import AppKit
import ApplicationServices
import CoreGraphics
import Observation
import UnmouseCore

@Observable
@MainActor
final class NavigationModel {
    unowned let app: AppModel

    var mode: AppMode = .idle
    var gridState: GridState?
    var hintState = HintState()
    var hintBubbles: [HintBubble] = []
    /// Cached once on enterHint — overlay body must not re-query AX each redraw.
    var hintScreenFrame: CGRect = .zero
    /// Button held down for a drag. Nil when nothing is held.
    var dragButton: MouseButton?
    /// Modifiers captured when the hold started, so the drag stays a ⌘-click and the like.
    var dragFlags: CGEventFlags = []
    var dragging: Bool { dragButton != nil }
    var bindings = BindingTable.empty
    let motion = FreeMotion()
    var onTutorial: ((TutorialEvent) -> Void)?

    var karabinerStatus: KarabinerStatus = .eventTapOnly

    enum KarabinerStatus: String {
        case usingKarabiner = "Using Karabiner"
        case waitingForKarabiner = "Waiting for Karabiner, using Event Tap"
        case eventTapOnly = "Event tap only"
    }

    // MARK: Private

    private let eventTap = EventTapController()
    private let karabiner = KarabinerListener()
    private let displayLink = DisplayLinkDriver()
    private let focusFollow = FocusFollow()
    private var lastFlags: CGEventFlags = []
    private var consumeFreeExitUp = false
    /// Action key (space, esc, …) whose key-down already ran and left the mode.
    /// Held until release so the key-up, repeats, and the other input source cannot reach the focused app.
    private var swallowUpToken: String?
    private var leftClicks = LeftClickChain()
    private var lastModeActivityNanos: UInt64 = 0
    private var modeWatchTimer: DispatchSourceTimer?
    /// Free movement is one burst. A gap shorter than this stays one move.
    private var freeMoveOpen = false
    private var freeMoveIdle: TimeInterval = 0
    private let freeMoveGap: TimeInterval = 0.2
    private var hintLoadGeneration: UInt64 = 0

    init(app: AppModel) {
        self.app = app
    }

    // MARK: - Public API

    @discardableResult
    func startInput() -> Bool {
        let ok = eventTap.start()
        eventTap.setMaxTapMilliseconds(UInt64(max(50, app.config.input.tapMaxMs)))
        wireInput()
        updateKarabiner()
        return ok
    }

    func stopInput() {
        eventTap.stop()
        karabiner.stop()
        stopDisplayLink()
    }

    func applyBindings(_ config: AppConfig) {
        bindings = BindingTable(bindings: config.bindings)
        eventTap.setMaxTapMilliseconds(UInt64(max(50, config.input.tapMaxMs)))
    }

    func setCenterOnFocus(_ enabled: Bool) {
        focusFollow.setEnabled(enabled) { [weak self] in
            self?.centerOnFocusedWindow()
        }
    }

    /// Re-attach after Accessibility is granted. Observers created while untrusted never fire.
    func refreshCenterOnFocus() {
        focusFollow.rewatchIfEnabled()
    }

    func updateKarabiner() {
        guard app.config.input.karabiner else {
            setKarabinerStatus(.eventTapOnly)
            karabiner.stop()
            return
        }
        if !karabiner.isRunning {
            _ = karabiner.startIfAvailable()
        }
        // The virtual keyboard, not the installed karabiner_cli binary.
        setKarabinerStatus(karabiner.isActive ? .usingKarabiner : .waitingForKarabiner)
    }

    private func setKarabinerStatus(_ status: KarabinerStatus) {
        guard status != karabinerStatus else { return }
        karabinerStatus = status
        InputTrace.log("karabiner status \(status.rawValue)")
    }

    func releaseStaleHolds() {
        motion.releaseStaleMoveHolds(bindings: bindings.free)
    }

    func screenForCursor() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Screen that holds the focused window. Falls back to the cursor screen.
    func screenForFocusedWindow() -> NSScreen {
        if let frame = Self.focusedWindowAppKitFrame(primaryHeight: NSScreen.screens.first?.frame.height ?? 0) {
            let mid = CGPoint(x: frame.midX, y: frame.midY)
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mid, $0.frame, false) }) {
                return screen
            }
            // Prefer the screen with the largest intersection if the midpoint is in a gap.
            let best = NSScreen.screens.max { a, b in
                let aa = a.frame.intersection(frame)
                let bb = b.frame.intersection(frame)
                return aa.width * aa.height < bb.width * bb.height
            }
            if let best, best.frame.intersects(frame) { return best }
        }
        return screenForCursor()
    }

    /// Pointer to the center of the focused window. Skips a click that is already inside it,
    /// and skips grid / free / hint so a mode keeps the point it is aiming at.
    private func centerOnFocusedWindow() {
        guard mode == .idle, !dragging else { return }
        guard AXIsProcessTrusted() else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard let frame = Self.focusedWindowAppKitFrame(primaryHeight: NSScreen.screens.first?.frame.height ?? 0),
              frame.width >= 8, frame.height >= 8 else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cursor = CoordinateSpace.cgEventToAppKit(PointerController.location, primaryHeight: primaryH)
        if frame.contains(cursor) { return }
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        let point: CGPoint
        if NSScreen.screens.contains(where: { $0.frame.contains(mid) }) {
            point = mid
        } else {
            let visible = NSScreen.screens
                .map { $0.frame.intersection(frame) }
                .max { $0.width * $0.height < $1.width * $1.height }
            guard let visible, visible.width >= 8, visible.height >= 8 else { return }
            point = CGPoint(x: visible.midX, y: visible.midY)
        }
        PointerController.move(toAppKit: point)
    }

    /// Focused window frame in AppKit screen coords (bottom-left origin).
    /// Each element has its own 0.15s timeout. The timeout is not inherited, and the default waits on the other app.
    nonisolated private static func focusedWindowAppKitFrame(primaryHeight: CGFloat) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let focusedApp
        else { return nil }
        let appEl = unsafeDowncast(focusedApp as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(appEl, 0.15)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef
        else { return nil }
        let win = unsafeDowncast(windowRef as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(win, 0.15)
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        let appKitOrigin = CoordinateSpace.cgEventToAppKit(pos, primaryHeight: primaryHeight)
        return CGRect(x: appKitOrigin.x, y: appKitOrigin.y - size.height, width: size.width, height: size.height)
    }

    // MARK: - Mode transitions

    func enterGrid() {
        InputTrace.log("mode → grid")
        let screen = screenForCursor()
        let idx = NSScreen.screens.firstIndex(of: screen) ?? 0
        gridState = GridState(
            rows: app.config.grid.rows,
            cols: app.config.grid.cols,
            chars: app.config.grid.chars,
            depth: app.config.grid.depth,
            subRows: app.config.grid.subRows,
            subCols: app.config.grid.subCols,
            screenIndex: idx,
            screenOrigin: screen.frame.origin,
            screenSize: screen.frame.size
        )
        stopDisplayLink()
        hintState = HintState()
        hintBubbles = []
        app.overlayController?.hideHints()
        app.overlayController?.hideFreeDot()
        mode = .grid
        bumpModeActivity()
        startModeWatch()
        app.overlayController?.showGrid()
        app.overlayController?.updateCoach()
        onTutorial?(.enteredGrid)
    }

    func enterFree(fromGrid: Bool) {
        InputTrace.log("mode → free fromGrid=\(fromGrid)")
        motion.resetMotionClocks()
        motion.resetSpeedDemo()
        motion.releaseStaleMoveHolds(bindings: bindings.free)
        mode = .free
        hintState = HintState()
        hintBubbles = []
        bumpModeActivity()
        startModeWatch()
        app.overlayController?.hideGrid()
        app.overlayController?.hideHints()
        app.overlayController?.revealSystemCursor()
        app.overlayController?.showFreeDot()
        app.overlayController?.updateCoach()
        startDisplayLink()
        onTutorial?(fromGrid ? .gridToFree : .enteredFree)
    }

    func enterHint() {
        InputTrace.log("mode → hint")
        hintLoadGeneration &+= 1
        let generation = hintLoadGeneration
        stopDisplayLink()
        gridState = nil
        hintState = HintState()
        hintBubbles = []
        // Cursor screen first. The focused-window query waits on that app's main thread,
        // so it must not run here or a busy window freezes the palette.
        hintScreenFrame = screenForCursor().frame
        InputTrace.log(
            "hint screen frame \(Int(hintScreenFrame.width))x\(Int(hintScreenFrame.height))@\(Int(hintScreenFrame.minX)),\(Int(hintScreenFrame.minY))"
        )
        mode = .hint
        bumpModeActivity()
        startModeWatch()
        app.overlayController?.hideGrid()
        app.overlayController?.hideFreeDot()
        app.overlayController?.showHints()
        app.overlayController?.updateCoach()
        onTutorial?(.enteredHint)
        syncHintCommandHeld()
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        Task { await loadHints(generation: generation, primaryHeight: primaryH) }
    }

    func exitToIdle(keepDrag: Bool = false) {
        InputTrace.log("mode → idle keepDrag=\(keepDrag)")
        if !keepDrag, dragging { endDrag(notifyTutorial: false) }
        mode = .idle
        gridState = nil
        hintState = HintState()
        hintBubbles = []
        hintScreenFrame = .zero
        app.overlayController?.hideAllOverlays(keepDrag: keepDrag)
        stopDisplayLink()
        stopModeWatch()
        motion.resetAll()
    }

    // MARK: - Wire Input

    private enum InputSource { case tap, karabiner }

    private func wireInput() {
        eventTap.onKey = { [weak self] kind, flags, down, alone, nanos in
            guard let self else { return false }
            return self.handleKey(kind: kind, flags: flags, down: down, alone: alone, source: .tap, eventNanos: nanos)
        }
        eventTap.onFlags = { [weak self] flags in
            self?.lastFlags = flags
        }
        karabiner.onKey = { [weak self] kind, down, nanos in
            guard let self else { return }
            InputTrace.log("karabiner \(KeyCodes.token(for: kind)) \(down ? "down" : "up") t=\(nanos)")
            _ = self.handleKey(kind: kind, flags: self.lastFlags, down: down, alone: false, source: .karabiner, eventNanos: nanos)
        }
        karabiner.onActiveChange = { [weak self] active in
            guard let self, self.app.config.input.karabiner else { return }
            self.setKarabinerStatus(active ? .usingKarabiner : .waitingForKarabiner)
        }
        eventTap.onMouseDown = { [weak self] in
            InputTrace.log("nav mouseDown → endFreeModeIfNeeded mode=\(self?.mode.rawValue ?? "?")")
            self?.endFreeModeIfNeeded()
        }
        eventTap.onTapReset = { [weak self] in
            InputTrace.log("nav tapReset → motion.resetAll() held was \(self?.motion.heldKeys.heldTokens() ?? [])")
            self?.swallowUpToken = nil
            self?.motion.resetAll()
        }
    }

    private func handleKey(
        kind: KeyKind, flags: CGEventFlags, down: Bool, alone: Bool,
        source: InputSource, eventNanos: UInt64
    ) -> Bool {
        let token = KeyCodes.token(for: kind)
        let src = source == .tap ? "tap" : "kar"
        InputTrace.log(
            "nav \(src) \(token) \(down ? "↓" : "↑") alone=\(alone) mode=\(mode.rawValue) flags=\(InputTrace.flags(flags))"
        )
        lastFlags = flags
        if mode != .idle { bumpModeActivity() }

        if kind.isModifier {
            if source == .karabiner {
                InputTrace.log("nav ignore kar modifier \(token)")
                return false
            }
            let applied = motion.heldKeys.setHeld(token, down: down, at: eventNanos)
            InputTrace.log(
                "nav held \(token)=\(down) applied=\(applied) now=\(motion.heldKeys.heldTokens())"
            )
            let swallow: Bool
            if !down {
                swallow = handleKeyUp(kind: kind, flags: flags, alone: alone)
            } else {
                swallow = handleKeyDown(kind: kind, flags: flags)
            }
            syncHintCommandHeld()
            InputTrace.log("nav result \(token) \(down ? "↓" : "↑") swallow=\(swallow) mode=\(mode.rawValue)")
            return swallow
        }

        // Hint's shortcut is usually a chord (⌘⇧Space). Do not hand that key to the focused app.
        let hintShortcut = bindings.global.hintMode.matches(key: kind, flags: flags, alone: false)
        // ⌘ + a scroll key stays here. The wheel event keeps ⌘ so the app zooms.
        // Z/X stay here too, including under ⌘, so they scale that scroll.
        let keepSpeed = mode == .free && isFreeSpeedKey(kind)
        // Hint keeps ⌘T / ⌘0–9; other ⌘⌥⌃ chords pass through and leave hint (⌘Tab, etc.).
        let keepHintChord = mode == .hint && Self.isHintOwnedChord(kind: kind, flags: flags)
        let keepHintRight = mode == .hint && bindings.hint.rightClick.matches(key: kind, flags: flags, alone: false)
        if !hintShortcut, !keepHintChord, !keepHintRight, !capturesClickChord(kind: kind, flags: flags),
            !capturesCommandScroll(kind: kind, flags: flags), !keepSpeed,
            passSystemChord(token: token, flags: flags, down: down, source: source) {
            InputTrace.log("nav chord passthrough \(token) \(down ? "↓" : "↑")")
            return false
        }

        if down {
            let applied = motion.heldKeys.setHeld(token, down: true, at: eventNanos)
            InputTrace.log("nav held \(token)=true applied=\(applied) now=\(motion.heldKeys.heldTokens())")
        } else if source == .tap || mode != .free {
            let applied = motion.heldKeys.setHeld(token, down: false, at: eventNanos)
            InputTrace.log("nav held \(token)=false applied=\(applied) now=\(motion.heldKeys.heldTokens())")
        } else {
            InputTrace.log("nav skip clear \(token) (kar up in free) still=\(motion.heldKeys.isHeld(token))")
        }
        updateSpeedModifierFlags(kind: kind, down: down, source: source, nowNanos: eventNanos)
        if motion.speedLatch.releasePending {
            motion.speedLatch.sync(
                arrowHeld: motion.speedKeyHeld(bindings: bindings.free),
                fasterHID: motion.hidDown(bindings.free.fasterRaw),
                slowerHID: motion.hidDown(bindings.free.slowerRaw),
                nowNanos: eventNanos
            )
        }
        let holdAction = swallowUpToken == token
        if holdAction, !down { swallowUpToken = nil }
        guard motion.deduper.shouldHandle(token: token, down: down, nowNanos: eventNanos) else {
            let swallow = holdAction || motion.deduper.swallowed(token: token, down: down) || mode != .idle
            InputTrace.log("nav dedupe skip \(token) \(down ? "↓" : "↑") swallow=\(swallow)")
            return swallow
        }
        if mode != .idle {
            // Handler may return to idle before the event-tap copy of this key is delivered.
            motion.deduper.setSwallow(token: token, down: down, swallow: true)
        }
        let swallow: Bool
        if holdAction {
            swallow = true
        } else if !down {
            swallow = handleKeyUp(kind: kind, flags: flags, alone: alone)
        } else {
            swallow = handleKeyDown(kind: kind, flags: flags)
            if swallow, mode == .idle {
                swallowUpToken = token
            }
        }
        motion.deduper.setSwallow(token: token, down: down, swallow: swallow)
        InputTrace.log("nav result \(token) \(down ? "↓" : "↑") swallow=\(swallow) mode=\(mode.rawValue)")
        return swallow
    }

    private func updateSpeedModifierFlags(kind: KeyKind, down: Bool, source: InputSource, nowNanos: UInt64) {
        let faster = bindings.free.faster.matches(key: kind, flags: [], alone: false)
        let slower = bindings.free.slower.matches(key: kind, flags: [], alone: false)
        guard faster || slower else { return }
        if down {
            motion.speedLatch.keyDown(faster: faster, slower: slower)
            return
        }
        guard source == .tap || mode != .free else { return }
        motion.speedLatch.keyUp(
            faster: faster, slower: slower,
            arrowHeld: motion.speedKeyHeld(bindings: bindings.free),
            hidDown: motion.hidDown(kind),
            nowNanos: nowNanos
        )
    }

    private func handleKeyDown(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard app.accessibilityTrusted else { return false }
        let global = bindings.global
        // Chord form of the hint shortcut (not a bare modifier). Works from every mode.
        // The same shortcut leaves hint, matching grid and free.
        if global.hintMode.matches(key: kind, flags: flags, alone: false) {
            if mode == .hint {
                InputTrace.log("nav → leave hint")
                exitToIdle(keepDrag: dragging)
                onTutorial?(.cancelled)
            } else {
                InputTrace.log("nav → enterHint from \(mode.rawValue)")
                enterHint()
            }
            return true
        }
        switch mode {
        case .idle:
            if global.gridMode.matches(key: kind, flags: flags, alone: false), kind.isModifier { return false }
            if global.freeMode.matches(key: kind, flags: flags, alone: false), kind.isModifier { return false }
            if isLeftClickKey(kind, flags: flags), performLeftClick(repeatOnly: true) { return true }
            return false
        case .grid:
            return handleGridKey(kind: kind, flags: flags)
        case .free:
            return handleFreeKeyDown(kind: kind, flags: flags)
        case .hint:
            return handleHintKey(kind: kind, flags: flags)
        }
    }

    private func handleKeyUp(kind: KeyKind, flags: CGEventFlags, alone: Bool) -> Bool {
        let global = bindings.global
        let token = KeyCodes.token(for: kind)
        if consumeFreeExitUp, kind.isModifier {
            consumeFreeExitUp = false
            InputTrace.log("nav consumeFreeExitUp \(token)")
            if mode == .free, global.freeMode.matches(key: kind, flags: [], alone: true) { return false }
        }
        if alone {
            let gridTap = global.gridMode.matches(key: kind, flags: [], alone: true)
            let freeTap = global.freeMode.matches(key: kind, flags: [], alone: true)
            let hintTap = global.hintMode.matches(key: kind, flags: [], alone: true)
            InputTrace.log(
                "nav alone-up \(token) gridTap=\(gridTap) freeTap=\(freeTap) hintTap=\(hintTap) mode=\(mode.rawValue)"
            )
            if gridTap {
                if mode == .grid {
                    InputTrace.log("nav → cancelGrid")
                    cancelGrid()
                    return false
                }
                InputTrace.log("nav → enterGrid")
                enterGrid()
                return false
            }
            if freeTap {
                if mode == .hint {
                    InputTrace.log("nav → hint to free")
                    if hintState.selectedTarget != nil {
                        onTutorial?(.hintArmed)
                        finalizeHintToFree()
                    } else {
                        enterFree(fromGrid: false)
                    }
                    return false
                }
                if mode == .grid, let center = gridState?.prospectiveCenter {
                    InputTrace.log("nav → gridToFree at \(center)")
                    PointerController.move(toAppKit: center)
                    InputTrace.log("grid move \(InputTrace.point(PointerController.location))")
                    enterFree(fromGrid: true)
                    return false
                }
                if mode == .free {
                    InputTrace.log("nav → exitToIdle")
                    exitToIdle()
                    return false
                }
                InputTrace.log("nav → enterFree")
                enterFree(fromGrid: false)
                return false
            }
            if hintTap {
                if mode == .hint {
                    InputTrace.log("nav → leave hint")
                    exitToIdle(keepDrag: dragging)
                    onTutorial?(.cancelled)
                } else {
                    InputTrace.log("nav → enterHint")
                    enterHint()
                }
                return false
            }
        }
        return mode != .idle && !kind.isModifier
    }

    // MARK: - Grid

    private func cancelGrid() {
        if dragging { enterFree(fromGrid: false) } else { exitToIdle() }
        onTutorial?(.cancelled)
    }

    private func handleGridKey(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard var state = gridState else { return false }
        let b = bindings.grid
        if b.cancel.matches(key: kind, flags: flags, alone: false) { cancelGrid(); return true }
        if b.back.matches(key: kind, flags: flags, alone: false) {
            _ = state.backspace(); gridState = state; app.overlayController?.refreshGrid(); return true
        }
        if b.nextScreen.matches(key: kind, flags: flags, alone: false) {
            cycleScreen(&state); gridState = state; app.overlayController?.refreshGrid(); return true
        }
        if let matched = clickMatch(b.toggleDrag, key: kind, flags: flags) {
            performGridHold(.left, flags: matched, state: state); return true
        }
        if let matched = clickMatch(b.toggleRightDrag, key: kind, flags: flags) {
            performGridHold(.right, flags: matched, state: state); return true
        }
        if let matched = clickMatch(b.toggleMiddleDrag, key: kind, flags: flags) {
            performGridHold(.middle, flags: matched, state: state); return true
        }
        var finalize: GridFinalizeAction?
        var clickFlags = CGEventFlags()
        if let matched = clickMatch(b.leftClick, key: kind, flags: flags) {
            finalize = .leftClick; clickFlags = matched
        } else if let matched = clickMatch(b.rightClick, key: kind, flags: flags) {
            finalize = .rightClick; clickFlags = matched
        } else if let matched = clickMatch(b.middleClick, key: kind, flags: flags) {
            finalize = .middleClick; clickFlags = matched
        } else if b.moveOnly.matches(key: kind, flags: flags, alone: false) {
            finalize = .moveOnly
        } else if b.toFree.matches(key: kind, flags: flags, alone: kind.isModifier) {
            finalize = .toFree
        }
        let ch = kind.character
        let decision = GridInputRouter.decide(
            character: ch,
            matchesFinalize: (finalize == .toFree || state.hasClickTarget) ? finalize : nil,
            matchesBack: false, matchesCancel: false, matchesNextScreen: false,
            state: state
        )
        switch decision {
        case .typeCoordinate(let c):
            commitGridCharacter(c, state: &state); return true
        case .finalize(let action):
            if action == .toFree, kind.isModifier { consumeFreeExitUp = true }
            performGridFinalize(action, state: state, clickFlags: clickFlags); return true
        case .descend(let c):
            if state.descend() { commitGridCharacter(c, state: &state) }
            return true
        case .ignore:
            return true
        default:
            return true
        }
    }

    private func commitGridCharacter(_ c: Character, state: inout GridState) {
        let result = state.typeCharacter(c)
        switch result {
        case .selected:
            moveCursorToSelectedCell(state); onTutorial?(.typedGridCell)
        case .openedSubgrid:
            moveCursor(to: state.levelCenter); onTutorial?(.typedGridCell)
        case .typing where state.prospectiveCenter != nil:
            moveCursorToSelectedCell(state)
        default:
            break
        }
        gridState = state
        app.overlayController?.refreshGrid()
    }

    private func moveCursorToSelectedCell(_ state: GridState) {
        guard let center = state.prospectiveCenter else { return }
        moveCursor(to: center)
    }

    private func moveCursor(to center: CGPoint) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CoordinateSpace.appKitToCGEvent(center, primaryHeight: primaryH)
        InputTrace.log("grid move \(InputTrace.point(cg))")
        if let button = dragButton {
            let current = PointerController.location
            PointerController.moveBy(dx: cg.x - current.x, dy: cg.y - current.y, drag: button, flags: dragFlags)
        } else {
            PointerController.move(to: cg)
        }
        app.overlayController?.revealSystemCursor()
    }

    private func performGridFinalize(_ action: GridFinalizeAction, state: GridState, clickFlags: CGEventFlags = []) {
        guard let point = state.prospectiveCenter else {
            if action == .toFree { enterFree(fromGrid: true) } else { exitToIdle(keepDrag: dragging) }
            return
        }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        PointerController.move(to: CoordinateSpace.appKitToCGEvent(point, primaryHeight: primaryH))
        switch action {
        case .leftClick:
            if dragging { endDrag(notifyTutorial: true) } else { performLeftClick(flags: clickFlags) }
            exitToIdle()
        case .rightClick:
            if dragButton == .right { endDrag(notifyTutorial: true) }
            else { PointerController.click(.right, flags: clickFlags); onTutorial?(.rightClick) }
            exitToIdle()
        case .middleClick:
            if dragButton == .middle { endDrag(notifyTutorial: true) }
            else { PointerController.click(.middle, flags: clickFlags) }
            exitToIdle()
        case .moveOnly:
            exitToIdle(keepDrag: dragging)
            if dragging { enterFree(fromGrid: false) }
        case .toFree:
            enterFree(fromGrid: true)
        }
    }

    private func cycleScreen(_ state: inout GridState) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let next = (state.screenIndex + 1) % screens.count
        let s = screens[next]
        state.resetScreen(origin: s.frame.origin, size: s.frame.size, index: next)
    }

    // MARK: - Free

    private func handleFreeKeyDown(kind: KeyKind, flags: CGEventFlags) -> Bool {
        let b = bindings.free
        let global = bindings.global
        if global.gridMode.matches(key: kind, flags: flags, alone: false), kind.isModifier { return false }
        if b.cancel.matches(key: kind, flags: flags, alone: false) {
            if dragging { endDrag(notifyTutorial: false) }
            exitToIdle(); onTutorial?(.cancelled); return true
        }
        if let matched = clickMatch(b.toggleDrag, key: kind, flags: flags) {
            toggleHold(.left, flags: matched); return true
        }
        if let matched = clickMatch(b.toggleRightDrag, key: kind, flags: flags) {
            toggleHold(.right, flags: matched); return true
        }
        if let matched = clickMatch(b.toggleMiddleDrag, key: kind, flags: flags) {
            toggleHold(.middle, flags: matched); return true
        }
        if let matched = clickMatch(b.leftClick, key: kind, flags: flags) {
            if dragging { endDrag(notifyTutorial: true) } else { performLeftClick(flags: matched) }
            endFreeModeIfNeeded(); return true
        }
        if let matched = clickMatch(b.rightClick, key: kind, flags: flags) {
            if dragButton == .right { endDrag(notifyTutorial: true) }
            else { PointerController.click(.right, flags: matched); onTutorial?(.rightClick) }
            endFreeModeIfNeeded(); return true
        }
        if let matched = clickMatch(b.middleClick, key: kind, flags: flags) {
            if dragButton == .middle { endDrag(notifyTutorial: true) }
            else { PointerController.click(.middle, flags: matched) }
            endFreeModeIfNeeded(); return true
        }
        // Movement/scroll: tick handles motion; fire tutorial events on key-down.
        var steered = false
        for direction in MoveDirection.allCases {
            if bindings.matchesMove(direction, key: kind, flags: flags) {
                onTutorial?(.steered(direction)); steered = true
            }
        }
        if steered { onTutorial?(.moved); return true }
        var didScroll = false
        for direction in MoveDirection.allCases {
            if matchesFreeScroll(direction, key: kind, flags: flags) {
                onTutorial?(.scrolled(direction)); didScroll = true
            }
        }
        if didScroll { return true }
        if isFreeSpeedKey(kind) { return true }
        if kind.isModifier { return false }
        if app.config.free.exitOnAction { endFreeModeIfNeeded(); return false }
        return true
    }

    /// Faster/slower ignore held modifiers. ⌘Z would otherwise type Undo instead of speeding the scroll.
    private func isFreeSpeedKey(_ kind: KeyKind) -> Bool {
        bindings.free.faster.matches(key: kind, flags: [], alone: false)
            || bindings.free.slower.matches(key: kind, flags: [], alone: false)
    }

    /// Scroll bindings ignore a held ⌘, so ⌘-scroll is captured instead of typed into the app.
    private func matchesFreeScroll(_ direction: MoveDirection, key: KeyKind, flags: CGEventFlags) -> Bool {
        if bindings.matchesScroll(direction, key: key, flags: flags) { return true }
        guard flags.contains(.maskCommand) else { return false }
        let bare = CGEventFlags(rawValue: flags.rawValue & ~CGEventFlags.maskCommand.rawValue)
        return bindings.matchesScroll(direction, key: key, flags: bare)
    }

    /// ⌘ ⌥ ⌃ ⇧ plus a click or hold key stays here and is posted as that modified click.
    private func capturesClickChord(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard mode == .free || mode == .grid, ClickModifiers.carried(flags).rawValue != 0 else { return false }
        let matchers: [BindingMatcher] = mode == .free
            ? [
                bindings.free.toggleDrag, bindings.free.toggleRightDrag, bindings.free.toggleMiddleDrag,
                bindings.free.leftClick, bindings.free.rightClick, bindings.free.middleClick,
            ]
            : [
                bindings.grid.toggleDrag, bindings.grid.toggleRightDrag, bindings.grid.toggleMiddleDrag,
                bindings.grid.leftClick, bindings.grid.rightClick, bindings.grid.middleClick,
            ]
        return matchers.contains { $0.matchesIgnoringClickModifiers(key: kind, flags: flags) }
    }

    private func clickMatch(_ matcher: BindingMatcher, key: KeyKind, flags: CGEventFlags) -> CGEventFlags? {
        guard matcher.matchesIgnoringClickModifiers(key: key, flags: flags) else { return nil }
        return ClickModifiers.carried(flags)
    }

    private func capturesCommandScroll(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard mode == .free, flags.contains(.maskCommand) else { return false }
        return MoveDirection.allCases.contains { matchesFreeScroll($0, key: kind, flags: flags) }
    }

    /// Command/Option/Control plus a non-held key: let it through, and pass that source's key-up.
    /// Karabiner and the event tap are separate sources. Consuming the up on the first one
    /// leaves the tap to swallow Tab, which sticks the key in macOS.
    /// Free exits only when `exit_on_action` is on. Hint always exits (⌘Tab and friends).
    private func passSystemChord(token: String, flags: CGEventFlags, down: Bool, source: InputSource) -> Bool {
        let fromTap = source == .tap
        if !down {
            return motion.chordPass.end(token: token, fromTap: fromTap)
        }
        guard mode == .free || mode == .hint,
              !motion.heldKeys.isHeld(token),
              motion.chordModifierDown(flags) else { return false }
        motion.chordPass.begin(token: token, fromTap: fromTap)
        if mode == .hint {
            exitToIdle(keepDrag: dragging)
            onTutorial?(.cancelled)
        } else {
            endFreeModeIfNeeded()
        }
        return true
    }

    private func endFreeModeIfNeeded() {
        guard mode == .free, app.config.free.exitOnAction else { return }
        exitToIdle(); onTutorial?(.cancelled)
    }

    /// Hint-owned ⌘ chords stay in mode: palette cycle and ⌘1–9 / ⌘0 picks.
    private static func isHintOwnedChord(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskCommand) else { return false }
        if kind == .letter("t") { return true }
        if case .digit = kind { return true }
        return false
    }

    // MARK: - Hint

    /// ⌘ held → stamp ⌘1–9 onto palette + window bubbles even with a short query.
    private func syncHintCommandHeld() {
        guard mode == .hint else { return }
        let held = lastFlags.contains(.maskCommand)
            || motion.heldKeys.isHeld("commandLeft")
            || motion.heldKeys.isHeld("commandRight")
            || motion.heldKeys.isHeld("command")
        let before = hintState.commandHeld
        hintState.setCommandHeld(held)
        if hintState.commandHeld != before {
            rebuildHintBubbles()
            app.overlayController?.refreshHints()
        }
    }

    private func handleHintKey(kind: KeyKind, flags: CGEventFlags) -> Bool {
        let b = bindings.hint
        if b.cancel.matches(key: kind, flags: flags, alone: false) {
            exitToIdle(keepDrag: dragging); onTutorial?(.cancelled); return true
        }
        if b.back.matches(key: kind, flags: flags, alone: false) {
            hintState.backspace()
            rebuildHintBubbles()
            app.overlayController?.refreshHints()
            return true
        }
        // Tab/arrows only when no ⌘⌥⌃ — otherwise system chords already passed through above.
        let chordMods = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
        if chordMods.isEmpty {
            if kind == .up || (kind == .tab && flags.contains(.maskShift)) {
                hintState.moveSelection(-1); app.overlayController?.refreshHints(); return true
            }
            if kind == .down || kind == .tab {
                hintState.moveSelection(1); app.overlayController?.refreshHints(); return true
            }
        }
        // ⌘T cycles freestanding slots (leaves attach on first press).
        if flags.contains(.maskCommand), kind == .letter("t") {
            hintState.cyclePalette()
            app.overlayController?.refreshHints()
            return true
        }
        // ⌘1…⌘9 / ⌘0 after enough query characters.
        if flags.contains(.maskCommand), case .digit(let d) = kind, let n = Int(String(d)) {
            if let target = hintState.selectCmdNumber(n) {
                onTutorial?(.hintArmed)
                activateHint(target, button: .left)
            }
            return true
        }
        // Bare typable keys always search — never treat them as click even if config says so.
        let bareTypable = Self.isHintBareTypable(kind: kind, flags: flags)
        if !bareTypable, b.leftClick.matches(key: kind, flags: flags, alone: false) {
            // Empty query + no Tab/↑↓ selection → cancel. Otherwise activate the row.
            if hintState.armExactMatch() {
                onTutorial?(.hintArmed)
                activateHint(hintState.selectedTarget, button: .left)
            } else if hintState.typed.isEmpty {
                exitToIdle(keepDrag: dragging)
                onTutorial?(.cancelled)
            }
            return true
        }
        if !bareTypable, b.rightClick.matches(key: kind, flags: flags, alone: false) {
            if hintState.armExactMatch() {
                onTutorial?(.hintArmed)
                activateHint(hintState.selectedTarget, button: .right)
            } else if hintState.typed.isEmpty {
                exitToIdle(keepDrag: dragging)
                onTutorial?(.cancelled)
            }
            return true
        }
        // Option alone is handled on key-up. Ignore Option key-down here so it is not swallowed as typing.
        if b.toFree.matches(key: kind, flags: flags, alone: kind.isModifier), kind.isModifier {
            return false
        }
        if let ch = kind.character {
            guard !hintState.targets.isEmpty else { return true }
            let result = hintState.typeCharacter(ch)
            rebuildHintBubbles()
            app.overlayController?.refreshHints()
            if case .armed = result { onTutorial?(.hintArmed) }
            return true
        }
        return true
    }

    /// Letter/digit/punct with no ⌘⌥⌃⇧ — reserved for hint typing/search.
    private static func isHintBareTypable(kind: KeyKind, flags: CGEventFlags) -> Bool {
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return mods.isEmpty && kind.character != nil
    }

    /// Relayout yellow labels: mnemonic controls + framed search hits (text) when relevant.
    private func rebuildHintBubbles() {
        let screen = hintScreenFrame
        guard !screen.isEmpty else { return }
        hintBubbles = HintLayout.layout(targets: hintState.bubbleTargets, screenBounds: screen)
    }

    private func activateHint(_ target: HintTarget?, button: MouseButton?) {
        guard let target else { return }
        if case .click = target.action {
            if button == nil {
                HintActivator.moveTo(target.frame)
            } else if dragging, button == .left {
                HintActivator.moveTo(target.frame)
                endDrag(notifyTutorial: true)
            } else if button == .left {
                HintActivator.perform(target, button: .left)
                onTutorial?(.leftClick)
            } else if let button {
                HintActivator.perform(target, button: button)
                if button == .right { onTutorial?(.rightClick) }
            }
        } else {
            HintActivator.perform(target, button: button)
        }
        exitToIdle()
    }

    private func finalizeHintToFree() {
        guard let target = hintState.selectedTarget else {
            enterFree(fromGrid: false)
            return
        }
        if case .click = target.action, !target.frame.isEmpty {
            HintActivator.moveTo(target.frame)
        }
        enterFree(fromGrid: false)
    }

    private func loadHints(generation: UInt64, primaryHeight: CGFloat) async {
        InputTrace.log("hint load start gen=\(generation)")
        let t0 = DispatchTime.now().uptimeNanoseconds
        let source = AccessibilityHintSource()
        let windowTask = Task.detached {
            Self.focusedWindowAppKitFrame(primaryHeight: primaryHeight)
        }
        let launches = await source.launchTargets()
        guard mode == .hint, generation == hintLoadGeneration else { return }
        if !launches.isEmpty {
            publishHints(launches, generation: generation, since: t0, phase: "launches")
        }
        if let win = await windowTask.value, mode == .hint, generation == hintLoadGeneration {
            hintState.paletteLayout = HintPalettePlacement.resolve(window: win, screen: hintScreenFrame)
            InputTrace.log("hint palette layout \(hintState.paletteLayout) win=\(Int(win.width))x\(Int(win.height))")
            app.overlayController?.refreshHints()
        }
        let controls = await source.collect()
        let scanMs = (DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        guard mode == .hint, generation == hintLoadGeneration else {
            InputTrace.log("hint load stale gen=\(generation) current=\(hintLoadGeneration) mode=\(mode.rawValue) scanMs=\(scanMs) n=\(controls.count)")
            return
        }
        InputTrace.log("hint load scan done n=\(controls.count) launches=\(launches.count) scanMs=\(scanMs)")
        var seen = Set<String>()
        var merged: [HintTarget] = []
        for target in controls where seen.insert(target.id).inserted {
            merged.append(target)
        }
        for target in launches where seen.insert(target.id).inserted {
            merged.append(target)
        }
        publishHints(merged, generation: generation, since: t0, phase: "ready")
    }

    /// Codes the rows and keeps the query already typed. Safe to call again when the control walk finishes.
    private func publishHints(_ targets: [HintTarget], generation: UInt64, since t0: UInt64, phase: String) {
        guard mode == .hint, generation == hintLoadGeneration else { return }
        let coded = HintCoder.assignCodes(targets: targets)
        let layout = hintState.paletteLayout
        let cmdHeld = hintState.commandHeld
        hintState.replaceTargets(coded)
        hintState.paletteLayout = layout
        hintState.setCommandHeld(cmdHeld)
        rebuildHintBubbles()
        let labeled = coded.filter(\.showsLabel).count
        InputTrace.log(
            "hint load \(phase) labeled=\(labeled) bubbles=\(hintBubbles.count) n=\(coded.count) totalMs=\((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)"
        )
        app.overlayController?.showHints()
        app.overlayController?.refreshHints()
    }

    // MARK: - Click helpers

    /// `repeatOnly` swallows the key only when it continues a click still inside the system interval.
    /// Idle uses that so a second press double-clicks and a third triple-clicks, then the key types again.
    @discardableResult
    private func performLeftClick(repeatOnly: Bool = false, flags: CGEventFlags = []) -> Bool {
        let window = UInt64(NSEvent.doubleClickInterval * 1_000_000_000)
        guard let state = leftClicks.press(
            now: DispatchTime.now().uptimeNanoseconds,
            window: window,
            repeatOnly: repeatOnly
        ) else { return false }
        PointerController.click(.left, from: state, flags: flags)
        onTutorial?(.leftClick)
        return true
    }

    private func isLeftClickKey(_ kind: KeyKind, flags: CGEventFlags) -> Bool {
        [bindings.free.leftClick, bindings.grid.leftClick, bindings.hint.leftClick]
            .contains { $0.matches(key: kind, flags: flags, alone: false) }
    }

    private func endDrag(notifyTutorial: Bool) {
        if let button = dragButton {
            PointerController.mouseUp(button, flags: dragFlags)
        }
        dragButton = nil
        dragFlags = []
        motion.heldKeys.setDragging(false)
        if notifyTutorial { onTutorial?(.dragDropped) }
    }

    private func toggleHold(_ button: MouseButton, flags: CGEventFlags) {
        if dragButton == button {
            endDrag(notifyTutorial: true)
            return
        }
        if dragButton != nil { endDrag(notifyTutorial: false) }
        PointerController.mouseDown(button, flags: flags)
        dragButton = button
        dragFlags = flags
        motion.heldKeys.setDragging(true)
        onTutorial?(.dragStarted)
    }

    /// Move onto the aimed cell when there is one, hold the button, and drop into free mode so the drag can move.
    private func performGridHold(_ button: MouseButton, flags: CGEventFlags, state: GridState) {
        if dragButton != nil, dragButton != button {
            endDrag(notifyTutorial: false)
        }
        if dragButton == button {
            toggleHold(button, flags: flags)
            return
        }
        if let center = state.prospectiveCenter {
            moveCursor(to: center)
        }
        toggleHold(button, flags: flags)
        enterFree(fromGrid: true)
    }

    // MARK: - Display link

    private func startDisplayLink() {
        displayLink.onTick = { [weak self] dt in
            self?.tickFreeMode(dt: dt)
        }
        displayLink.start()
    }

    private func stopDisplayLink() {
        endFreeMoveLog()
        displayLink.stop()
    }

    private func tickFreeMode(dt: TimeInterval) {
        guard mode == .free else { return }
        let origin = PointerController.location
        let result = motion.tick(
            dt: dt, free: app.config.free, bindings: bindings.free, drag: dragButton, dragFlags: dragFlags
        )
        if dragging, app.tutorial?.progress?.arenaFocus == .drag {
            let next = PointerController.location
            // CGEvent +y is down, same direction as the puck's SwiftUI offset.
            app.tutorial?.nudgePuck(dx: next.x - origin.x, dy: next.y - origin.y)
        }
        if result.moved {
            if !freeMoveOpen {
                InputTrace.log("free move start \(InputTrace.point(origin))")
                freeMoveOpen = true
            }
            freeMoveIdle = 0
        } else if freeMoveOpen {
            freeMoveIdle += dt
            if freeMoveIdle >= freeMoveGap { endFreeMoveLog() }
        }
        if result.moved || result.scrolled { bumpModeActivity() }
        // Speed demo: credit Z/X tutorial steps that require sustained motion.
        if let ev = motion.creditSpeedDemo(
            required: app.tutorial?.progress?.current?.required,
            faster: result.faster, slower: result.slower,
            moved: result.moved, dt: min(dt, 0.05)
        ) {
            InputTrace.log("speedDemo done → \(ev)")
            onTutorial?(ev)
        }
        app.tutorial?.showSpeedTenthsLeft(motion.speedTenthsLeft)
        app.overlayController?.syncFreeDot(dragging: dragging)
    }

    private func endFreeMoveLog() {
        guard freeMoveOpen else { return }
        InputTrace.log("free move end \(InputTrace.point(PointerController.location))")
        freeMoveOpen = false
        freeMoveIdle = 0
    }

    // MARK: - Mode timeout watch

    private func bumpModeActivity() {
        lastModeActivityNanos = DispatchTime.now().uptimeNanoseconds
    }

    private func startModeWatch() {
        app.overlayController?.revealSystemCursor()
        if modeWatchTimer != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in self?.checkModeTimeout() }
        timer.resume()
        modeWatchTimer = timer
    }

    private func stopModeWatch() {
        modeWatchTimer?.cancel()
        modeWatchTimer = nil
    }

    private func checkModeTimeout() {
        guard mode != .idle else { stopModeWatch(); return }
        let limit = app.config.input.modeTimeoutS
        guard limit > 0 else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- lastModeActivityNanos) / 1_000_000_000
        if elapsed >= limit {
            exitToIdle(keepDrag: dragging)
            onTutorial?(.cancelled)
        }
    }
}

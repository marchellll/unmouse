import AppKit
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
    var dragging = false
    var bindings = BindingTable.empty
    let motion = FreeMotion()
    var onTutorial: ((TutorialEvent) -> Void)?

    var karabinerStatus: KarabinerStatus = .eventTapOnly

    enum KarabinerStatus: String {
        case usingKarabiner = "Using Karabiner"
        case waitingForKarabiner = "Waiting for Karabiner"
        case eventTapOnly = "Event tap only"
    }

    // MARK: Private

    private let eventTap = EventTapController()
    private let karabiner = KarabinerListener()
    private let displayLink = DisplayLinkDriver()
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

    func updateKarabiner() {
        guard app.config.input.karabiner else {
            karabinerStatus = .eventTapOnly
            karabiner.stop()
            return
        }
        if !karabiner.isRunning {
            _ = karabiner.startIfAvailable()
        }
        if karabiner.isActive || KarabinerPresence.cliPresent() {
            karabinerStatus = .usingKarabiner
        } else {
            karabinerStatus = .waitingForKarabiner
        }
    }

    func releaseStaleHolds() {
        motion.releaseStaleMoveHolds(bindings: bindings.free)
    }

    func screenForCursor() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
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
        mode = .hint
        bumpModeActivity()
        startModeWatch()
        app.overlayController?.hideGrid()
        app.overlayController?.hideFreeDot()
        app.overlayController?.showHints()
        app.overlayController?.updateCoach()
        onTutorial?(.enteredHint)
        Task { await loadHints(generation: generation) }
    }

    func exitToIdle(keepDrag: Bool = false) {
        InputTrace.log("mode → idle keepDrag=\(keepDrag)")
        if !keepDrag, dragging { endDrag(notifyTutorial: false) }
        mode = .idle
        gridState = nil
        hintState = HintState()
        hintBubbles = []
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
        karabiner.onKey = { [weak self] kind, down, nanos in
            guard let self else { return }
            InputTrace.log("karabiner \(KeyCodes.token(for: kind)) \(down ? "down" : "up") t=\(nanos)")
            _ = self.handleKey(kind: kind, flags: self.lastFlags, down: down, alone: false, source: .karabiner, eventNanos: nanos)
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
            InputTrace.log("nav result \(token) \(down ? "↓" : "↑") swallow=\(swallow) mode=\(mode.rawValue)")
            return swallow
        }

        // Hint's shortcut is usually a chord (⌘⇧Space). Do not hand that key to the focused app.
        let hintShortcut = bindings.global.hintMode.matches(key: kind, flags: flags, alone: false)
        // ⌘ + a scroll key stays here. The wheel event keeps ⌘ so the app zooms.
        // Z/X stay here too, including under ⌘, so they scale that scroll.
        let keepSpeed = mode == .free && isFreeSpeedKey(kind)
        if !hintShortcut, !capturesCommandScroll(kind: kind, flags: flags), !keepSpeed,
            passFreeChord(token: token, flags: flags, down: down, source: source) {
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
        var finalize: GridFinalizeAction?
        if b.leftClick.matches(key: kind, flags: flags, alone: false)        { finalize = .leftClick }
        else if b.rightClick.matches(key: kind, flags: flags, alone: false)  { finalize = .rightClick }
        else if b.middleClick.matches(key: kind, flags: flags, alone: false) { finalize = .middleClick }
        else if b.moveOnly.matches(key: kind, flags: flags, alone: false)    { finalize = .moveOnly }
        else if b.toFree.matches(key: kind, flags: flags, alone: kind.isModifier) { finalize = .toFree }
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
            performGridFinalize(action, state: state); return true
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
        if dragging {
            let current = PointerController.location
            PointerController.moveBy(dx: cg.x - current.x, dy: cg.y - current.y, dragging: true)
        } else {
            PointerController.move(to: cg)
        }
        app.overlayController?.revealSystemCursor()
    }

    private func performGridFinalize(_ action: GridFinalizeAction, state: GridState) {
        guard let point = state.prospectiveCenter else {
            if action == .toFree { enterFree(fromGrid: true) } else { exitToIdle(keepDrag: dragging) }
            return
        }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        PointerController.move(to: CoordinateSpace.appKitToCGEvent(point, primaryHeight: primaryH))
        switch action {
        case .leftClick:
            if dragging { endDrag(notifyTutorial: true) } else { performLeftClick() }
            exitToIdle()
        case .rightClick:
            PointerController.click(.right); onTutorial?(.rightClick); exitToIdle()
        case .middleClick:
            PointerController.click(.middle); exitToIdle()
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
        if b.toggleDrag.matches(key: kind, flags: flags, alone: false) {
            if dragging {
                endDrag(notifyTutorial: true)
            } else {
                PointerController.mouseDown(.left)
                dragging = true
                motion.heldKeys.setDragging(true)
                onTutorial?(.dragStarted)
            }
            return true
        }
        if b.leftClick.matches(key: kind, flags: flags, alone: false) {
            if dragging { endDrag(notifyTutorial: true) } else { performLeftClick() }
            endFreeModeIfNeeded(); return true
        }
        if b.rightClick.matches(key: kind, flags: flags, alone: false) {
            PointerController.click(.right); onTutorial?(.rightClick); endFreeModeIfNeeded(); return true
        }
        if b.middleClick.matches(key: kind, flags: flags, alone: false) {
            PointerController.click(.middle); endFreeModeIfNeeded(); return true
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

    private func capturesCommandScroll(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard mode == .free, flags.contains(.maskCommand) else { return false }
        return MoveDirection.allCases.contains { matchesFreeScroll($0, key: kind, flags: flags) }
    }

    /// Command/Option/Control plus a non-held key: let it through, and pass that source's key-up.
    /// Karabiner and the event tap are separate sources. Consuming the up on the first one
    /// leaves the tap to swallow Tab, which sticks the key in macOS.
    private func passFreeChord(token: String, flags: CGEventFlags, down: Bool, source: InputSource) -> Bool {
        let fromTap = source == .tap
        if !down {
            return motion.chordPass.end(token: token, fromTap: fromTap)
        }
        guard mode == .free, !motion.heldKeys.isHeld(token), motion.chordModifierDown(flags) else { return false }
        motion.chordPass.begin(token: token, fromTap: fromTap)
        endFreeModeIfNeeded()
        return true
    }

    private func endFreeModeIfNeeded() {
        guard mode == .free, app.config.free.exitOnAction else { return }
        exitToIdle(); onTutorial?(.cancelled)
    }

    // MARK: - Hint

    private func handleHintKey(kind: KeyKind, flags: CGEventFlags) -> Bool {
        let b = bindings.hint
        if b.cancel.matches(key: kind, flags: flags, alone: false) {
            exitToIdle(keepDrag: dragging); onTutorial?(.cancelled); return true
        }
        if b.back.matches(key: kind, flags: flags, alone: false) {
            hintState.backspace(); app.overlayController?.refreshHints(); return true
        }
        if b.leftClick.matches(key: kind, flags: flags, alone: false) {
            if hintState.armExactMatch() { onTutorial?(.hintArmed); finalizeHint(.left) }
            return true
        }
        if b.rightClick.matches(key: kind, flags: flags, alone: false) {
            if hintState.armExactMatch() { onTutorial?(.hintArmed); finalizeHint(.right) }
            return true
        }
        if b.moveNoAction.matches(key: kind, flags: flags, alone: false) {
            if hintState.armExactMatch() { onTutorial?(.hintArmed); finalizeHint(nil) }
            return true
        }
        if b.toFree.matches(key: kind, flags: flags, alone: kind.isModifier) {
            if hintState.armExactMatch() {
                onTutorial?(.hintArmed)
                if kind.isModifier { consumeFreeExitUp = true }
                finalizeHintToFree()
            }
            return true
        }
        if let ch = kind.character {
            guard !hintState.targets.isEmpty else { return true }
            let result = hintState.typeCharacter(ch)
            app.overlayController?.refreshHints()
            if case .armed = result { onTutorial?(.hintArmed) }
            return true
        }
        return true
    }

    private func finalizeHint(_ button: MouseButton?) {
        guard let target = hintState.armedTarget else { return }
        moveToHint(target)
        if let button {
            if dragging, button == .left {
                endDrag(notifyTutorial: true)
            } else if button == .left {
                performLeftClick()
            } else {
                PointerController.click(button); onTutorial?(.rightClick)
            }
        }
        exitToIdle()
    }

    private func finalizeHintToFree() {
        guard let target = hintState.armedTarget else { return }
        moveToHint(target)
        enterFree(fromGrid: false)
    }

    private func moveToHint(_ target: HintTarget) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CoordinateSpace.appKitToCGEvent(
            CGPoint(x: target.frame.midX, y: target.frame.midY),
            primaryHeight: primaryH
        )
        InputTrace.log("hint move \(InputTrace.point(cg))")
        PointerController.move(to: cg)
    }

    private func loadHints(generation: UInt64) async {
        let source = AccessibilityHintSource()
        let targets = await source.collect()
        guard mode == .hint, generation == hintLoadGeneration else { return }
        let coded = HintCoder.assignCodes(targets: targets, chars: app.config.hint.chars)
        hintState = HintState(targets: coded)
        let screen = screenForCursor().frame
        hintBubbles = HintLayout.layout(targets: coded, screenBounds: screen)
        app.overlayController?.refreshHints()
    }

    // MARK: - Click helpers

    /// `repeatOnly` swallows the key only when it continues a click still inside the system interval.
    /// Idle uses that so a second press double-clicks and a third triple-clicks, then the key types again.
    @discardableResult
    private func performLeftClick(repeatOnly: Bool = false) -> Bool {
        let window = UInt64(NSEvent.doubleClickInterval * 1_000_000_000)
        guard let state = leftClicks.press(
            now: DispatchTime.now().uptimeNanoseconds,
            window: window,
            repeatOnly: repeatOnly
        ) else { return false }
        PointerController.click(.left, from: state)
        onTutorial?(.leftClick)
        return true
    }

    private func isLeftClickKey(_ kind: KeyKind, flags: CGEventFlags) -> Bool {
        [bindings.free.leftClick, bindings.grid.leftClick, bindings.hint.leftClick]
            .contains { $0.matches(key: kind, flags: flags, alone: false) }
    }

    private func endDrag(notifyTutorial: Bool) {
        PointerController.mouseUp(.left)
        dragging = false
        motion.heldKeys.setDragging(false)
        if notifyTutorial { onTutorial?(.dragDropped) }
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
        let result = motion.tick(dt: dt, free: app.config.free, bindings: bindings.free, dragging: dragging)
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

import AppKit
import ApplicationServices
import Observation
import UnmouseCore

@Observable
@MainActor
final class AppModel {
    var config: AppConfig = .default
    var configError: String?
    var mode: AppMode = .idle
    var gridState: GridState?
    var hintState = HintState()
    var hintBubbles: [HintBubble] = []
    var dragging = false
    var coachEnabled = false
    var tutorial: TutorialProgress?
    var showWalkthrough = false
    var accessibilityTrusted = false
    var inputMonitoringOK = false
    var karabinerStatus: KarabinerStatus = .eventTapOnly
    var presets: [PresetItem] = []

    let heldKeys = HeldKeyStore()
    let deduper = KeyDeduper()

    private let eventTap = EventTapController()
    private let karabiner = KarabinerListener()
    private let displayLink = DisplayLinkDriver()
    private var configWatcher: DispatchSourceFileSystemObject?
    private var configFD: Int32 = -1
    private(set) var overlayController: OverlayController?
    private var lastFlags: CGEventFlags = []

    enum KarabinerStatus: String {
        case usingKarabiner = "Using Karabiner"
        case waitingForKarabiner = "Waiting for Karabiner"
        case eventTapOnly = "Event tap only"
    }

    struct PresetItem: Identifiable {
        var id: String { name }
        var name: String
        var url: URL
    }

    func start() {
        loadPresets()
        reloadConfig()
        watchConfig()
        overlayController = OverlayController(model: self)
        accessibilityTrusted = AXIsProcessTrusted()
        inputMonitoringOK = eventTap.start()
        if !inputMonitoringOK {
            // still try; may need permission
        }
        wireInput()
        updateKarabiner()
        refreshPermissions()

        if !accessibilityTrusted {
            showWalkthrough = true
        } else if !UserDefaults.standard.bool(forKey: "didCompleteWalkthrough") {
            showWalkthrough = true
        } else if !completedSessions().contains(.aimAndHit) {
            startTutorial(.aimAndHit)
        }
    }

    func refreshPermissions() {
        accessibilityTrusted = AXIsProcessTrusted()
        if accessibilityTrusted, inputMonitoringOK, showWalkthrough == false {
            // ok
        }
        if !inputMonitoringOK {
            inputMonitoringOK = eventTap.start()
            wireInput()
        }
        updateKarabiner()
    }

    func requestAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func finishWalkthrough() {
        UserDefaults.standard.set(true, forKey: "didCompleteWalkthrough")
        showWalkthrough = false
        startTutorial(.aimAndHit)
    }

    func skipWalkthrough() {
        showWalkthrough = false
    }

    // MARK: - Config

    func reloadConfig() {
        do {
            let defaultText = try loadBundledDefault()
            let url = try ConfigIO.ensureConfig(defaultText: defaultText)
            let loaded = try ConfigIO.decodeFile(at: url)
            let errors = ConfigValidator.validate(loaded)
            if errors.isEmpty {
                config = loaded
                configError = nil
            } else {
                configError = errors.map(\.description).joined(separator: "; ")
            }
        } catch {
            configError = String(describing: error)
        }
        updateKarabiner()
    }

    func applyPreset(_ item: PresetItem) {
        guard let text = try? String(contentsOf: item.url, encoding: .utf8) else { return }
        try? ConfigIO.replaceConfig(with: text)
        reloadConfig()
    }

    func editConfig() {
        NSWorkspace.shared.open(ConfigIO.configURL())
    }

    private func loadBundledDefault() throws -> String {
        let url =
            Bundle.module.url(forResource: "default.config", withExtension: "toml", subdirectory: "configs-example")
            ?? Bundle.main.url(forResource: "default.config", withExtension: "toml", subdirectory: "configs-example")
        guard let url else { throw ConfigError.parse("missing default.config.toml") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func loadPresets() {
        let urls =
            Bundle.module.urls(forResourcesWithExtension: "toml", subdirectory: "configs-example")
            ?? Bundle.main.urls(forResourcesWithExtension: "toml", subdirectory: "configs-example")
            ?? []
        presets = urls.map {
            PresetItem(name: $0.deletingPathExtension().lastPathComponent, url: $0)
        }.sorted { $0.name < $1.name }
    }

    private func watchConfig() {
        let url = ConfigIO.configURL()
        configFD = open(url.path, O_EVTONLY)
        guard configFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: configFD,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reloadConfig()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.configFD, fd >= 0 { close(fd) }
            self?.configFD = -1
        }
        configWatcher = source
        source.resume()
    }

    private func updateKarabiner() {
        let present = KarabinerPresence.virtualKeyboardPresent() || KarabinerPresence.cliPresent()
        if config.input.karabiner {
            if present {
                karabinerStatus = .usingKarabiner
                _ = karabiner.startIfAvailable()
            } else {
                karabinerStatus = .waitingForKarabiner
                karabiner.stop()
            }
        } else {
            karabinerStatus = .eventTapOnly
            karabiner.stop()
        }
    }

    private func wireInput() {
        eventTap.onKey = { [weak self] kind, flags, down, alone in
            guard let self else { return false }
            return self.handleKey(kind: kind, flags: flags, down: down, alone: alone, source: .tap)
        }
        karabiner.onKey = { [weak self] kind, down in
            guard let self else { return }
            _ = self.handleKey(kind: kind, flags: self.lastFlags, down: down, alone: false, source: .karabiner)
        }
    }

    private enum InputSource { case tap, karabiner }

    private func handleKey(kind: KeyKind, flags: CGEventFlags, down: Bool, alone: Bool, source: InputSource) -> Bool {
        lastFlags = flags
        let token = KeyCodes.token(for: kind)
        let now = DispatchTime.now().uptimeNanoseconds
        guard deduper.shouldHandle(token: token, down: down, nowNanos: now) else {
            return mode != .idle
        }

        heldKeys.setHeld(token, down: down)

        if !down {
            return handleKeyUp(kind: kind, flags: flags, alone: alone)
        }
        return handleKeyDown(kind: kind, flags: flags)
    }

    private func handleKeyDown(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard accessibilityTrusted else { return false }

        let global = config.bindings.global
        switch mode {
        case .idle:
            if BindingMatcher(global.gridMode).matches(key: kind, flags: flags, alone: false), kind.isModifier {
                return false // wait for alone on key up
            }
            if BindingMatcher(global.freeMode).matches(key: kind, flags: flags, alone: false), kind.isModifier {
                return false
            }
            if BindingMatcher(global.hintMode).matches(key: kind, flags: flags, alone: false) {
                enterHint()
                return true
            }
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
        let global = config.bindings.global
        if alone {
            if BindingMatcher(global.gridMode).matches(key: kind, flags: [], alone: true) {
                if mode == .free || mode == .idle || (mode == .grid) {
                    enterGrid()
                    return true
                }
            }
            if BindingMatcher(global.freeMode).matches(key: kind, flags: [], alone: true) {
                if mode == .grid, let center = gridState?.prospectiveCenter {
                    let primaryH = NSScreen.screens.first?.frame.height ?? 0
                    PointerController.move(to: CoordinateSpace.appKitToCGEvent(center, primaryHeight: primaryH))
                    enterFree(fromGrid: true)
                    return true
                }
                if mode == .idle {
                    enterFree(fromGrid: false)
                    return true
                }
                if mode == .free {
                    exitToIdle()
                    return true
                }
            }
        }
        return mode != .idle && !kind.isModifier
    }

    // MARK: Modes

    func enterGrid() {
        let screen = screenForCursor()
        let idx = NSScreen.screens.firstIndex(of: screen) ?? 0
        gridState = GridState(
            rows: config.grid.rows,
            cols: config.grid.cols,
            chars: config.grid.chars,
            depth: config.grid.depth,
            screenIndex: idx,
            screenOrigin: screen.frame.origin,
            screenSize: screen.frame.size
        )
        mode = .grid
        overlayController?.showGrid()
        note(.enteredGrid)
    }

    func enterFree(fromGrid: Bool) {
        mode = .free
        overlayController?.hideGrid()
        overlayController?.showFreeDot()
        startDisplayLink()
        note(fromGrid ? .gridToFree : .enteredFree)
    }

    func enterHint() {
        Task { await loadHints() }
        mode = .hint
        overlayController?.hideGrid()
        overlayController?.showHints()
        note(.enteredHint)
    }

    func exitToIdle(keepDrag: Bool = false) {
        if !keepDrag, dragging {
            PointerController.mouseUp(.left)
            dragging = false
            heldKeys.setDragging(false)
        }
        mode = .idle
        gridState = nil
        hintState = HintState()
        hintBubbles = []
        overlayController?.hideAllOverlays(keepDrag: keepDrag)
        stopDisplayLink()
        heldKeys.clearHeld()
    }

    private func handleGridKey(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard var state = gridState else { return false }
        let b = config.bindings.grid

        if BindingMatcher(b.cancel).matches(key: kind, flags: flags, alone: false) {
            if dragging {
                enterFree(fromGrid: false)
            } else {
                exitToIdle()
            }
            note(.cancelled)
            return true
        }
        if BindingMatcher(b.back).matches(key: kind, flags: flags, alone: false) {
            _ = state.backspace()
            gridState = state
            overlayController?.refreshGrid()
            return true
        }
        if BindingMatcher(b.nextScreen).matches(key: kind, flags: flags, alone: false) {
            cycleScreen(&state)
            gridState = state
            overlayController?.refreshGrid()
            return true
        }

        var finalize: GridFinalizeAction?
        if BindingMatcher(b.leftClick).matches(key: kind, flags: flags, alone: false) { finalize = .leftClick }
        else if BindingMatcher(b.rightClick).matches(key: kind, flags: flags, alone: false) { finalize = .rightClick }
        else if BindingMatcher(b.middleClick).matches(key: kind, flags: flags, alone: false) { finalize = .middleClick }
        else if BindingMatcher(b.moveOnly).matches(key: kind, flags: flags, alone: false) { finalize = .moveOnly }
        else if BindingMatcher(b.toFree).matches(key: kind, flags: flags, alone: true) || BindingMatcher(b.toFree).matches(key: kind, flags: flags, alone: false) {
            finalize = .toFree
        }

        let ch = kind.character
        let decision = GridInputRouter.decide(
            character: ch,
            matchesFinalize: state.isCellSelected ? finalize : nil,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: state
        )

        switch decision {
        case .typeCoordinate(let c):
            let result = state.typeCharacter(c)
            gridState = state
            overlayController?.refreshGrid()
            if case .selected = result { note(.typedGridCell) }
            return true
        case .finalize(let action):
            performGridFinalize(action, state: state)
            return true
        case .descend(let c):
            if state.descend() {
                _ = state.typeCharacter(c)
                gridState = state
                overlayController?.refreshGrid()
            }
            return true
        case .ignore:
            // option_left alone handled on key up; if finalize while selected via letter before selected, type as coord
            if !state.isCellSelected, let c = ch, config.grid.chars.lowercased().contains(c) {
                let result = state.typeCharacter(c)
                gridState = state
                overlayController?.refreshGrid()
                if case .selected = result { note(.typedGridCell) }
                return true
            }
            return true
        default:
            return true
        }
    }

    private func performGridFinalize(_ action: GridFinalizeAction, state: GridState) {
        guard let center = state.prospectiveCenter else {
            exitToIdle(keepDrag: dragging)
            return
        }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CoordinateSpace.appKitToCGEvent(center, primaryHeight: primaryH)
        PointerController.move(to: cg)

        switch action {
        case .leftClick:
            if dragging {
                PointerController.mouseUp(.left)
                dragging = false
                heldKeys.setDragging(false)
                note(.dragDropped)
            } else {
                PointerController.click(.left)
                note(.leftClick)
            }
            exitToIdle()
        case .rightClick:
            PointerController.click(.right)
            note(.rightClick)
            exitToIdle()
        case .middleClick:
            PointerController.click(.middle)
            exitToIdle()
        case .moveOnly:
            exitToIdle(keepDrag: dragging)
            if dragging { enterFree(fromGrid: false) }
        case .toFree:
            enterFree(fromGrid: true)
        }
    }

    private func handleFreeKeyDown(kind: KeyKind, flags: CGEventFlags) -> Bool {
        let b = config.bindings.free
        let global = config.bindings.global

        if BindingMatcher(global.gridMode).matches(key: kind, flags: flags, alone: false), kind.isModifier {
            return false // alone on up opens grid while dragging
        }
        if BindingMatcher(b.cancel).matches(key: kind, flags: flags, alone: false) {
            if dragging {
                PointerController.mouseUp(.left)
                dragging = false
                heldKeys.setDragging(false)
            }
            exitToIdle()
            note(.cancelled)
            return true
        }
        if BindingMatcher(b.toggleDrag).matches(key: kind, flags: flags, alone: false) {
            if dragging {
                PointerController.mouseUp(.left)
                dragging = false
                heldKeys.setDragging(false)
                note(.dragDropped)
            } else {
                PointerController.mouseDown(.left)
                dragging = true
                heldKeys.setDragging(true)
                note(.dragStarted)
            }
            return true
        }
        if BindingMatcher(b.leftClick).matches(key: kind, flags: flags, alone: false) {
            if dragging {
                PointerController.mouseUp(.left)
                dragging = false
                heldKeys.setDragging(false)
                note(.dragDropped)
            } else {
                PointerController.click(.left)
                note(.leftClick)
            }
            return true
        }
        if BindingMatcher(b.rightClick).matches(key: kind, flags: flags, alone: false) {
            PointerController.click(.right)
            note(.rightClick)
            return true
        }
        if BindingMatcher(b.middleClick).matches(key: kind, flags: flags, alone: false) {
            PointerController.click(.middle)
            return true
        }
        // movement / scroll / speed are held — handled by display link
        if BindingMatcher(b.moveLeft).matches(key: kind, flags: flags, alone: false)
            || BindingMatcher(b.moveRight).matches(key: kind, flags: flags, alone: false)
            || BindingMatcher(b.moveUp).matches(key: kind, flags: flags, alone: false)
            || BindingMatcher(b.moveDown).matches(key: kind, flags: flags, alone: false)
        {
            note(.moved)
            return true
        }
        if BindingMatcher(b.scrollUp).matches(key: kind, flags: flags, alone: false)
            || BindingMatcher(b.scrollDown).matches(key: kind, flags: flags, alone: false)
            || BindingMatcher(b.scrollLeft).matches(key: kind, flags: flags, alone: false)
            || BindingMatcher(b.scrollRight).matches(key: kind, flags: flags, alone: false)
        {
            note(.scrolled)
            return true
        }
        if BindingMatcher(b.faster).matches(key: kind, flags: flags, alone: false) {
            note(.heldFaster)
            return true
        }
        if BindingMatcher(b.slower).matches(key: kind, flags: flags, alone: false) {
            note(.heldSlower)
            return true
        }
        return true
    }

    private func handleHintKey(kind: KeyKind, flags: CGEventFlags) -> Bool {
        let b = config.bindings.hint
        if BindingMatcher(b.cancel).matches(key: kind, flags: flags, alone: false) {
            exitToIdle(keepDrag: dragging)
            note(.cancelled)
            return true
        }
        if BindingMatcher(b.back).matches(key: kind, flags: flags, alone: false) {
            hintState.backspace()
            overlayController?.refreshHints()
            return true
        }

        if hintState.armedID != nil {
            if BindingMatcher(b.leftClick).matches(key: kind, flags: flags, alone: false) {
                finalizeHint(.left)
                return true
            }
            if BindingMatcher(b.rightClick).matches(key: kind, flags: flags, alone: false) {
                finalizeHint(.right)
                return true
            }
            if BindingMatcher(b.moveNoAction).matches(key: kind, flags: flags, alone: false) {
                finalizeHint(nil)
                return true
            }
        }

        if let ch = kind.character {
            let result = hintState.typeCharacter(ch)
            overlayController?.refreshHints()
            if case .armed = result { note(.hintArmed) }
            return true
        }
        return true
    }

    private func finalizeHint(_ button: MouseButton?) {
        guard let target = hintState.armedTarget else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CoordinateSpace.appKitToCGEvent(
            CGPoint(x: target.frame.midX, y: target.frame.midY),
            primaryHeight: primaryH
        )
        PointerController.move(to: cg)
        if let button {
            if dragging, button == .left {
                PointerController.mouseUp(.left)
                dragging = false
                heldKeys.setDragging(false)
                note(.dragDropped)
            } else {
                PointerController.click(button)
                note(button == .left ? .leftClick : .rightClick)
            }
        }
        exitToIdle()
    }

    private func loadHints() async {
        let source = AccessibilityHintSource()
        let targets = await source.collect()
        let coded = HintCoder.assignCodes(targets: targets, chars: config.hint.chars)
        hintState = HintState(targets: coded)
        let screen = screenForCursor().frame
        hintBubbles = HintLayout.layout(targets: coded, screenBounds: screen)
        overlayController?.refreshHints()
    }

    private func cycleScreen(_ state: inout GridState) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let next = (state.screenIndex + 1) % screens.count
        let s = screens[next]
        state.resetScreen(origin: s.frame.origin, size: s.frame.size, index: next)
    }

    private func screenForCursor() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: Display link

    private func startDisplayLink() {
        displayLink.onTick = { [weak self] dt in
            self?.tickFreeMode(dt: dt)
        }
        displayLink.start()
    }

    private func stopDisplayLink() {
        displayLink.stop()
    }

    private func tickFreeMode(dt: TimeInterval) {
        guard mode == .free else { return }
        let snap = heldKeys.snapshot()
        var speed = config.free.speed
        let b = config.bindings.free
        let fasterTokens = Set((try? ShortcutParser.parseAll(b.faster))?.map { KeyCodes.token(for: $0.key) } ?? [])
        let slowerTokens = Set((try? ShortcutParser.parseAll(b.slower))?.map { KeyCodes.token(for: $0.key) } ?? [])
        if !snap.held.isDisjoint(with: fasterTokens) {
            speed *= config.free.fastMultiplier
            note(.heldFaster)
        }
        if !snap.held.isDisjoint(with: slowerTokens) {
            speed *= config.free.slowMultiplier
            note(.heldSlower)
        }
        let step = CGFloat(speed * dt)

        func held(_ raw: [String]) -> Bool {
            let tokens = Set((try? ShortcutParser.parseAll(raw))?.map { KeyCodes.token(for: $0.key) } ?? [])
            return !snap.held.isDisjoint(with: tokens)
        }

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        // CGEvent y: down is positive
        if held(b.moveLeft) { dx -= step }
        if held(b.moveRight) { dx += step }
        if held(b.moveUp) { dy -= step }
        if held(b.moveDown) { dy += step }
        if dx != 0 || dy != 0 {
            PointerController.moveBy(dx: dx, dy: dy)
            if dragging { PointerController.dragMove() }
            note(.moved)
        }

        let scroll = Int32(config.free.scrollSpeed)
        var sdx: Int32 = 0
        var sdy: Int32 = 0
        if held(b.scrollUp) { sdy += scroll }
        if held(b.scrollDown) { sdy -= scroll }
        if held(b.scrollLeft) { sdx -= scroll }
        if held(b.scrollRight) { sdx += scroll }
        if sdx != 0 || sdy != 0 {
            PointerController.scroll(dx: sdx, dy: sdy)
            note(.scrolled)
        }

        overlayController?.moveFreeDot()
    }

    // MARK: Tutorial

    func startTutorial(_ session: TutorialSessionID) {
        tutorial = TutorialProgress(session: session)
        coachEnabled = true
    }

    func skipTutorial() {
        tutorial?.handle(.skipped)
        finishTutorialSession()
    }

    private func note(_ event: TutorialEvent) {
        guard var t = tutorial else { return }
        if t.handle(event) {
            tutorial = t
            if t.completed {
                finishTutorialSession()
            }
        } else {
            tutorial = t
        }
    }

    private func finishTutorialSession() {
        guard let t = tutorial else { return }
        var done = completedSessions()
        done.insert(t.session)
        saveCompletedSessions(done)
        if let next = t.session.next {
            tutorial = TutorialProgress(session: next)
        } else {
            tutorial = nil
            coachEnabled = false
        }
    }

    private func completedSessions() -> Set<TutorialSessionID> {
        let raw = UserDefaults.standard.stringArray(forKey: "tutorialCompleted") ?? []
        return Set(raw.compactMap(TutorialSessionID.init(rawValue:)))
    }

    private func saveCompletedSessions(_ set: Set<TutorialSessionID>) {
        UserDefaults.standard.set(set.map(\.rawValue), forKey: "tutorialCompleted")
    }
}

extension KeyKind {
    var isModifier: Bool {
        switch self {
        case .command, .commandLeft, .commandRight,
             .option, .optionLeft, .optionRight,
             .shift, .shiftLeft, .shiftRight,
             .control, .controlLeft, .controlRight, .fn:
            true
        default:
            false
        }
    }
}

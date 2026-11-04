import AppKit
import ApplicationServices
import Observation
import ServiceManagement
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
    /// Mirrors `SMAppService.mainApp`. The system stores this, not config.toml, so a preset cannot toggle it.
    var launchAtLogin = false
    var launchAtLoginNote: String?
    var presets: [PresetItem] = []

    let heldKeys = HeldKeyStore()
    let deduper = KeyDeduper()

    private let eventTap = EventTapController()
    private let karabiner = KarabinerListener()
    private let displayLink = DisplayLinkDriver()
    private var configWatcher: DispatchSourceFileSystemObject?
    private var configFD: Int32 = -1
    private var configWatchRearming = false
    private(set) var overlayController: OverlayController?
    private var lastFlags: CGEventFlags = []
    /// Fractional scroll leftover so scroll_speed is lines/sec, not lines/frame.
    private var scrollFracX: Double = 0
    private var scrollFracY: Double = 0
    /// How long the current direction hold has lasted. Drives the speed curve.
    private var moveHeld: TimeInterval = 0
    /// How long the current scroll hold has lasted. Same curve as pointer movement.
    private var scrollHeld: TimeInterval = 0
    private var saveWorkItem: DispatchWorkItem?
    private var suppressConfigReload = false
    /// Currently applied preset name (for Settings picker).
    var selectedPresetName: String = "default.config"
    /// Z/X stay down across the key-up arrow reports emit for other held keys.
    /// Not observed: the display link settles it every frame while a release is pending.
    @ObservationIgnored
    private var speedLatch = SpeedModifierLatch()
    /// Option enters free on key-down. The matching key-up must not immediately leave.
    private var consumeFreeExitUp = false
    private var lastLeftClickNanos: UInt64 = 0
    /// Last user input while a mode is active (for mode_timeout_s).
    private var lastModeActivityNanos: UInt64 = 0
    private var modeWatchTimer: DispatchSourceTimer?
    /// Drops stale AX scans when hint mode is re-entered before the prior collect finishes.
    private var hintLoadGeneration: UInt64 = 0

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
        eventTap.setMaxTapMilliseconds(UInt64(max(50, config.input.tapMaxMs)))
        if !inputMonitoringOK {
            // still try; may need permission
        }
        wireInput()
        updateKarabiner()
        refreshPermissions()
        refreshLaunchAtLogin()

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

    /// ponytail: registers this app bundle as a login item. `swift run` has no bundle, so the toggle fails until Unmouse.app is what launches.
    func refreshLaunchAtLogin() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            launchAtLoginNote = nil
        case .requiresApproval:
            launchAtLogin = true
            launchAtLoginNote = "Approve Unmouse in System Settings → General → Login Items."
        case .notRegistered, .notFound:
            launchAtLogin = false
            launchAtLoginNote = nil
        @unknown default:
            launchAtLogin = false
            launchAtLoginNote = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()
        } catch {
            refreshLaunchAtLogin()
            launchAtLoginNote = error.localizedDescription
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
            let configURL = ConfigIO.configURL()
            let isFirstRun = !FileManager.default.fileExists(atPath: configURL.path)
            let url = try ConfigIO.ensureConfig(defaultText: defaultText)
            var loaded = try ConfigIO.decodeFile(at: url)
            if isFirstRun {
                let size = screenForCursor().frame.size
                let dimensions = GridSizing.dimensions(for: size)
                loaded.grid.rows = dimensions.rows
                loaded.grid.cols = dimensions.cols
                loaded.grid.subRows = dimensions.rows
                loaded.grid.subCols = dimensions.cols
                try ConfigIO.save(loaded)
            }
            // Black contributes no visible change with exclusion blending, so the
            // old default made the attention animation invisible.
            if loaded.colors.freeDotBlend == .exclusion,
               loaded.colors.freeDotHalo.uppercased() == "#000000",
               loaded.free.haloAttention != .none
            {
                loaded.colors.freeDotHalo = "#FFFFFF99"
                try ConfigIO.save(loaded)
            }
            let errors = ConfigValidator.validate(loaded)
            configError = errors.isEmpty ? nil : errors.map(\.description).joined(separator: "; ")
            // A shortcut that repeats a grid letter is flagged, and the rest of the config still loads.
            let blocking = errors.filter(\.blocksApply)
            if blocking.isEmpty {
                config = loaded
                UnmouseLog.setLevel(loaded.log.level)
                if errors.isEmpty {
                    UnmouseLog.info("config loaded")
                } else {
                    UnmouseLog.error("config invalid: \(configError ?? "")")
                }
                eventTap.setMaxTapMilliseconds(UInt64(max(50, loaded.input.tapMaxMs)))
            } else {
                UnmouseLog.error("config invalid: \(configError ?? "")")
            }
        } catch {
            configError = String(describing: error)
            UnmouseLog.error("config load failed: \(configError ?? "")")
        }
        updateKarabiner()
        overlayController?.refreshAppearance()
    }

    /// Drop a pending settings write and read config.toml again.
    func reloadConfigFromDisk() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        suppressConfigReload = false
        reloadConfig()
        watchConfig()
    }

    func applyPreset(_ item: PresetItem) {
        guard let text = try? String(contentsOf: item.url, encoding: .utf8) else { return }
        suppressConfigReload = true
        try? ConfigIO.replaceConfig(with: text)
        selectedPresetName = item.name
        reloadConfig()
        suppressConfigReload = false
        overlayController?.refreshAppearance()
    }

    /// Fit the grid and the subgrid to the display under the pointer. Both use the same count, so two passes land on a cell small enough to hit.
    func recalculateGridDimensions() {
        let dimensions = GridSizing.dimensions(for: screenForCursor().frame.size)
        config.grid.rows = dimensions.rows
        config.grid.cols = dimensions.cols
        config.grid.subRows = dimensions.rows
        config.grid.subCols = dimensions.cols
        commitConfigEdits()
    }

    /// Persist in-memory settings edits to config.toml (debounced).
    func commitConfigEdits() {
        let errors = ConfigValidator.validate(config)
        configError = errors.isEmpty ? nil : errors.map(\.description).joined(separator: "; ")
        if errors.contains(where: \.blocksApply) {
            return
        }
        UnmouseLog.setLevel(config.log.level)
        eventTap.setMaxTapMilliseconds(UInt64(max(50, config.input.tapMaxMs)))
        updateKarabiner()
        overlayController?.refreshAppearance()

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suppressConfigReload = true
            do {
                try ConfigIO.save(self.config)
            } catch {
                self.configError = String(describing: error)
            }
            // Allow watcher to settle before accepting external reloads.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.suppressConfigReload = false
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func editConfig() {
        NSWorkspace.shared.open(ConfigIO.configURL())
    }

    private func loadBundledDefault() throws -> String {
        // Prefer Bundle.main — SPM's Bundle.module fatalErrors if the resource
        // bundle was not copied into Unmouse.app/Contents/Resources.
        let url =
            Bundle.main.url(forResource: "default.config", withExtension: "toml", subdirectory: "configs-example")
            ?? Bundle.main.url(forResource: "default.config", withExtension: "toml")
        guard let url else { throw ConfigError.parse("missing default.config.toml in app Resources") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func loadPresets() {
        let urls =
            Bundle.main.urls(forResourcesWithExtension: "toml", subdirectory: "configs-example")
            ?? Bundle.main.urls(forResourcesWithExtension: "toml", subdirectory: nil)
            ?? []
        presets = urls.map {
            PresetItem(name: $0.deletingPathExtension().lastPathComponent, url: $0)
        }.sorted { $0.name < $1.name }
    }

    private func watchConfig() {
        // Atomic saves (TextEdit, VS Code, our own write) replace the file.
        // The old vnode never sees the next write, so re-open after every event.
        if configWatchRearming { return }
        configWatchRearming = true
        defer { configWatchRearming = false }
        configWatcher?.cancel()
        configWatcher = nil
        let url = ConfigIO.configURL()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        configFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.watchConfig()
            guard !self.suppressConfigReload else { return }
            self.reloadConfig()
        }
        source.setCancelHandler {
            if fd >= 0 { close(fd) }
        }
        configWatcher = source
        source.resume()
    }

    private func updateKarabiner() {
        guard config.input.karabiner else {
            karabinerStatus = .eventTapOnly
            karabiner.stop()
            return
        }
        // Opening an IOHIDManager scans every device and leaks Mach ports if repeated.
        if !karabiner.isRunning {
            _ = karabiner.startIfAvailable()
        }
        if karabiner.isActive || KarabinerPresence.cliPresent() {
            karabinerStatus = .usingKarabiner
        } else {
            karabinerStatus = .waitingForKarabiner
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

        // Modifiers are EventTap-only (see KarabinerListener). Never dedupe them —
        // a duplicate key-up with alone=false was swallowing real alone-taps.
        if mode != .idle {
            bumpModeActivity()
        }

        if kind.isModifier {
            if source == .karabiner { return false }
            let token = KeyCodes.token(for: kind)
            heldKeys.setHeld(token, down: down)
            if !down {
                return handleKeyUp(kind: kind, flags: flags, alone: alone)
            }
            return handleKeyDown(kind: kind, flags: flags)
        }

        let token = KeyCodes.token(for: kind)
        // Mirror every event into held set before dedupe. Swallowing CGEvents makes
        // CGEventSource.keyState unreliable, so our set is the source of truth.
        // Karabiner key-ups in free mode are ignored: its virtual keyboard drops Z/X
        // while an arrow is held. The event tap sees that same ghost up; the latch
        // below keeps the modifier until the arrow is actually released.
        if down {
            heldKeys.setHeld(token, down: true)
        } else if source == .tap || mode != .free {
            heldKeys.setHeld(token, down: false)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        updateSpeedModifierFlags(kind: kind, down: down, source: source, nowNanos: now)
        if speedLatch.releasePending {
            let free = config.bindings.free
            speedLatch.sync(
                arrowHeld: arrowMoveHeld(),
                fasterHID: hidDown(free.faster),
                slowerHID: hidDown(free.slower),
                nowNanos: now
            )
        }

        guard deduper.shouldHandle(token: token, down: down, nowNanos: now) else {
            return mode != .idle
        }

        if !down {
            return handleKeyUp(kind: kind, flags: flags, alone: alone)
        }
        return handleKeyDown(kind: kind, flags: flags)
    }

    private func updateSpeedModifierFlags(kind: KeyKind, down: Bool, source: InputSource, nowNanos: UInt64) {
        let b = config.bindings.free
        let faster = BindingMatcher(b.faster).matches(key: kind, flags: [], alone: false)
        let slower = BindingMatcher(b.slower).matches(key: kind, flags: [], alone: false)
        guard faster || slower else { return }
        if down {
            speedLatch.keyDown(faster: faster, slower: slower)
            return
        }
        // Karabiner's ghost up is ignored. The tap's copy is deferred across the arrow report.
        guard source == .tap || mode != .free else { return }
        speedLatch.keyUp(
            faster: faster,
            slower: slower,
            arrowHeld: arrowMoveHeld(),
            hidDown: hidDown(kind),
            nowNanos: nowNanos
        )
    }

    /// Arrow keys bound to free-mode movement. Letter aliases (hjkl) are not included.
    private func arrowMoveHeld() -> Bool {
        let move = [
            config.bindings.free.moveLeft,
            config.bindings.free.moveRight,
            config.bindings.free.moveUp,
            config.bindings.free.moveDown,
        ]
        for raw in move {
            for shortcut in (try? ShortcutParser.parseAll(raw)) ?? [] {
                switch shortcut.key {
                case .left, .right, .up, .down:
                    if heldKeys.isHeld(KeyCodes.token(for: shortcut.key)) { return true }
                default:
                    break
                }
            }
        }
        return false
    }

    private func hidDown(_ kind: KeyKind) -> Bool {
        guard let code = KeyCodes.keyCode(for: kind) else { return false }
        return CGEventSource.keyState(.hidSystemState, key: code)
    }

    private func hidDown(_ raw: [String]) -> Bool {
        for shortcut in (try? ShortcutParser.parseAll(raw)) ?? [] {
            if hidDown(shortcut.key) { return true }
        }
        return false
    }

    private func bindingHeld(_ raw: [String]) -> Bool {
        for shortcut in (try? ShortcutParser.parseAll(raw)) ?? [] {
            if heldKeys.isHeld(KeyCodes.token(for: shortcut.key)) { return true }
            // HID fallback when the tap missed a down during an arrow chord.
            if let code = KeyCodes.keyCode(for: shortcut.key),
               CGEventSource.keyState(.combinedSessionState, key: code)
            {
                return true
            }
        }
        return false
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
            if isLeftClickKey(kind, flags: flags), performLeftClick(secondOnly: true) {
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
        if consumeFreeExitUp && kind.isModifier {
            consumeFreeExitUp = false
            if mode == .free, BindingMatcher(global.freeMode).matches(key: kind, flags: [], alone: true) {
                return false
            }
        }
        if alone {
            if BindingMatcher(global.gridMode).matches(key: kind, flags: [], alone: true) {
                if mode == .grid {
                    cancelGrid()
                    return false
                }
                if mode == .free || mode == .idle {
                    enterGrid()
                    return false
                }
            }
            if BindingMatcher(global.freeMode).matches(key: kind, flags: [], alone: true) {
                if mode == .grid, let center = gridState?.prospectiveCenter {
                    let primaryH = NSScreen.screens.first?.frame.height ?? 0
                    PointerController.move(to: CoordinateSpace.appKitToCGEvent(center, primaryHeight: primaryH))
                    enterFree(fromGrid: true)
                    return false
                }
                if mode == .idle {
                    enterFree(fromGrid: false)
                    return false
                }
                if mode == .free {
                    exitToIdle()
                    return false
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
            subRows: config.grid.subRows,
            subCols: config.grid.subCols,
            screenIndex: idx,
            screenOrigin: screen.frame.origin,
            screenSize: screen.frame.size
        )
        mode = .grid
        bumpModeActivity()
        startModeWatch()
        overlayController?.showGrid()
        overlayController?.updateCoach()
        note(.enteredGrid)
    }

    func enterFree(fromGrid: Bool) {
        moveHeld = 0
        scrollHeld = 0
        mode = .free
        hintState = HintState()
        hintBubbles = []
        bumpModeActivity()
        startModeWatch()
        overlayController?.hideGrid()
        overlayController?.hideHints()
        overlayController?.revealSystemCursor()
        overlayController?.showFreeDot()
        overlayController?.updateCoach()
        startDisplayLink()
        note(fromGrid ? .gridToFree : .enteredFree)
    }

    func enterHint() {
        hintLoadGeneration &+= 1
        let generation = hintLoadGeneration
        hintState = HintState()
        hintBubbles = []
        mode = .hint
        bumpModeActivity()
        startModeWatch()
        overlayController?.hideGrid()
        overlayController?.showHints()
        overlayController?.updateCoach()
        note(.enteredHint)
        Task { await loadHints(generation: generation) }
    }

    /// Same path as the grid Cancel binding. A held drag returns to free mode.
    private func cancelGrid() {
        if dragging {
            enterFree(fromGrid: false)
        } else {
            exitToIdle()
        }
        note(.cancelled)
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
        stopModeWatch()
        heldKeys.clearHeld()
        speedLatch.reset()
        scrollFracX = 0
        scrollFracY = 0
        moveHeld = 0
        scrollHeld = 0
    }

    private func bumpModeActivity() {
        lastModeActivityNanos = DispatchTime.now().uptimeNanoseconds
    }

    private func startModeWatch() {
        overlayController?.revealSystemCursor()
        if modeWatchTimer != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.checkModeTimeout()
        }
        timer.resume()
        modeWatchTimer = timer
    }

    private func stopModeWatch() {
        modeWatchTimer?.cancel()
        modeWatchTimer = nil
    }

    private func checkModeTimeout() {
        guard mode != .idle else {
            stopModeWatch()
            return
        }
        let limit = config.input.modeTimeoutS
        guard limit > 0 else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- lastModeActivityNanos) / 1_000_000_000
        if elapsed >= limit {
            exitToIdle(keepDrag: dragging)
            note(.cancelled)
        }
    }

    private func handleGridKey(kind: KeyKind, flags: CGEventFlags) -> Bool {
        guard var state = gridState else { return false }
        let b = config.bindings.grid

        if BindingMatcher(b.cancel).matches(key: kind, flags: flags, alone: false) {
            cancelGrid()
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
        else if BindingMatcher(b.toFree).matches(key: kind, flags: flags, alone: kind.isModifier) {
            finalize = .toFree
        }

        let ch = kind.character
        let decision = GridInputRouter.decide(
            character: ch,
            matchesFinalize: (finalize == .toFree || state.hasClickTarget) ? finalize : nil,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: state
        )

        switch decision {
        case .typeCoordinate(let c):
            commitGridCharacter(c, state: &state)
            return true
        case .finalize(let action):
            if action == .toFree, kind.isModifier {
                consumeFreeExitUp = true
            }
            performGridFinalize(action, state: state)
            return true
        case .descend(let c):
            // Already selected; this key both descends and starts typing the nested cell.
            if state.descend() {
                commitGridCharacter(c, state: &state)
            }
            return true
        case .ignore:
            if !state.isCellSelected, let c = ch, config.grid.chars.lowercased().contains(c) {
                commitGridCharacter(c, state: &state)
                return true
            }
            return true
        default:
            return true
        }
    }

    /// One key selects that rectangle. Space clicks it. The last character of a cell opens the next grid.
    private func commitGridCharacter(_ c: Character, state: inout GridState) {
        let result = state.typeCharacter(c)
        switch result {
        case .selected:
            moveCursorToSelectedCell(state)
            note(.typedGridCell)
        case .openedSubgrid:
            moveCursor(to: state.levelCenter)
            note(.typedGridCell)
        case .typing where state.prospectiveCenter != nil:
            moveCursorToSelectedCell(state)
        default:
            break
        }
        gridState = state
        overlayController?.refreshGrid()
    }

    private func moveCursorToSelectedCell(_ state: GridState) {
        guard let center = state.prospectiveCenter else { return }
        moveCursor(to: center)
    }

    private func moveCursor(to center: CGPoint) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CoordinateSpace.appKitToCGEvent(center, primaryHeight: primaryH)
        if dragging {
            let current = PointerController.location
            PointerController.moveBy(dx: cg.x - current.x, dy: cg.y - current.y, dragging: true)
        } else {
            PointerController.move(to: cg)
        }
        overlayController?.revealSystemCursor()
    }

    private func performGridFinalize(_ action: GridFinalizeAction, state: GridState) {
        guard let point = state.prospectiveCenter else {
            if action == .toFree {
                enterFree(fromGrid: true)
            } else {
                exitToIdle(keepDrag: dragging)
            }
            return
        }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CoordinateSpace.appKitToCGEvent(point, primaryHeight: primaryH)
        PointerController.move(to: cg)

        switch action {
        case .leftClick:
            if dragging {
                PointerController.mouseUp(.left)
                dragging = false
                heldKeys.setDragging(false)
                note(.dragDropped)
            } else {
                performLeftClick()
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
                performLeftClick()
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

        // Space / click bindings confirm an exact typed code even when longer
        // codes still share that prefix (single-char would otherwise be stuck).
        if BindingMatcher(b.leftClick).matches(key: kind, flags: flags, alone: false) {
            if hintState.armExactMatch() {
                note(.hintArmed)
                finalizeHint(.left)
            }
            return true
        }
        if BindingMatcher(b.rightClick).matches(key: kind, flags: flags, alone: false) {
            if hintState.armExactMatch() {
                note(.hintArmed)
                finalizeHint(.right)
            }
            return true
        }
        if BindingMatcher(b.moveNoAction).matches(key: kind, flags: flags, alone: false) {
            if hintState.armExactMatch() {
                note(.hintArmed)
                finalizeHint(nil)
            }
            return true
        }
        if BindingMatcher(b.toFree).matches(key: kind, flags: flags, alone: kind.isModifier) {
            if hintState.armExactMatch() {
                note(.hintArmed)
                if kind.isModifier { consumeFreeExitUp = true }
                finalizeHintToFree()
            }
            return true
        }

        if let ch = kind.character {
            // Ignore typing until the AX scan has published targets (empty collect
            // would drop the key; a late loadHints must not wipe a partial code).
            guard !hintState.targets.isEmpty else { return true }
            let result = hintState.typeCharacter(ch)
            overlayController?.refreshHints()
            if case .armed = result { note(.hintArmed) }
            return true
        }
        return true
    }

    private func finalizeHint(_ button: MouseButton?) {
        guard let target = hintState.armedTarget else { return }
        moveToHint(target)
        if let button {
            if dragging, button == .left {
                PointerController.mouseUp(.left)
                dragging = false
                heldKeys.setDragging(false)
                note(.dragDropped)
            } else if button == .left {
                performLeftClick()
            } else {
                PointerController.click(button)
                note(.rightClick)
            }
        }
        exitToIdle()
    }

    /// Jump onto the armed control and continue in free mode (no click).
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
        PointerController.move(to: cg)
    }

    /// A second left-click key inside the system double-click interval sends click 2. The first click is immediate.
    @discardableResult
    private func performLeftClick(secondOnly: Bool = false) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        let window = UInt64(NSEvent.doubleClickInterval * 1_000_000_000)
        let second = lastLeftClickNanos != 0 && now &- lastLeftClickNanos <= window
        if secondOnly && !second { return false }
        if second {
            PointerController.click(.left, from: 2)
            lastLeftClickNanos = 0
        } else {
            PointerController.click(.left)
            lastLeftClickNanos = now
        }
        note(.leftClick)
        return true
    }

    private func isLeftClickKey(_ kind: KeyKind, flags: CGEventFlags) -> Bool {
        let keys = [
            config.bindings.free.leftClick,
            config.bindings.grid.leftClick,
            config.bindings.hint.leftClick,
        ]
        return keys.contains { BindingMatcher($0).matches(key: kind, flags: flags, alone: false) }
    }

    private func loadHints(generation: UInt64) async {
        let source = AccessibilityHintSource()
        let targets = await source.collect()
        // A newer enterHint (or leaving hint) invalidates this scan — applying it
        // would wipe keys the user already typed against the live target list.
        guard mode == .hint, generation == hintLoadGeneration else { return }
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
        // Do not publish per-frame state. Redrawing the blended free-dot view
        // leaked a Mach port every frame (Activity Monitor "Ports" climbs into the thousands).
        let b = config.bindings.free
        if speedLatch.releasePending {
            speedLatch.sync(
                arrowHeld: arrowMoveHeld(),
                fasterHID: hidDown(b.faster),
                slowerHID: hidDown(b.slower),
                nowNanos: DispatchTime.now().uptimeNanoseconds
            )
        }
        var speedMult = 1.0
        if speedLatch.faster || hidDown(b.faster) || bindingHeld(b.faster) {
            speedMult *= config.free.fastMultiplier
            note(.heldFaster)
        }
        if speedLatch.slower || hidDown(b.slower) || bindingHeld(b.slower) {
            speedMult *= config.free.slowMultiplier
            note(.heldSlower)
        }
        let left = bindingHeld(b.moveLeft)
        let right = bindingHeld(b.moveRight)
        let up = bindingHeld(b.moveUp)
        let down = bindingHeld(b.moveDown)
        if left || right || up || down {
            moveHeld += min(dt, 0.05)
        } else {
            moveHeld = 0
        }
        let pace = AccelCurve.fraction(knots: config.free.accelKnots, at: moveHeld)
        let step = CGFloat(config.free.speed * pace * speedMult * dt)

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        // CGEvent y: down is positive
        if left { dx -= step }
        if right { dx += step }
        if up { dy -= step }
        if down { dy += step }
        if dx != 0 || dy != 0 {
            // While dragging, only post dragged events — mouseMoved drops the button.
            PointerController.moveBy(dx: dx, dy: dy, dragging: dragging)
            bumpModeActivity()
            note(.moved)
        }

        let scrollUp = bindingHeld(b.scrollUp)
        let scrollDown = bindingHeld(b.scrollDown)
        let scrollLeft = bindingHeld(b.scrollLeft)
        let scrollRight = bindingHeld(b.scrollRight)
        if scrollUp || scrollDown || scrollLeft || scrollRight {
            scrollHeld += min(dt, 0.05)
        } else {
            scrollHeld = 0
        }
        // scroll_speed is the top lines per second. The speed curve ramps it, same as pointer movement.
        // 16pt is one line, posted as pixels every frame.
        let scrollPace = AccelCurve.fraction(knots: config.free.accelKnots, at: scrollHeld)
        let scrollRate = config.free.scrollSpeed * scrollPace * speedMult * 16
        if scrollUp { scrollFracY += scrollRate * dt }
        if scrollDown { scrollFracY -= scrollRate * dt }
        if scrollLeft { scrollFracX -= scrollRate * dt }
        if scrollRight { scrollFracX += scrollRate * dt }
        let sdx = scrollFracX.rounded(.towardZero)
        let sdy = scrollFracY.rounded(.towardZero)
        if sdx != 0 || sdy != 0 {
            scrollFracX -= sdx
            scrollFracY -= sdy
            let xSign = config.free.scrollReverseX ? -1.0 : 1.0
            let ySign = config.free.scrollReverseY ? -1.0 : 1.0
            PointerController.scroll(dx: sdx * xSign, dy: sdy * ySign)
            bumpModeActivity()
            note(.scrolled)
        }

        overlayController?.syncFreeDot(dragging: dragging)
    }

    // MARK: Tutorial

    func startTutorial(_ session: TutorialSessionID) {
        tutorial = TutorialProgress(session: session)
        // Practice window owns the tutorial UI; don't also open the corner coach.
        coachEnabled = false
        TutorialArenaController.shared.show(model: self)
        overlayController?.updateCoach()
    }

    func skipTutorial() {
        _ = tutorial?.handle(.skipped)
        finishTutorialSession()
    }

    func noteArena(_ event: TutorialEvent) {
        note(event)
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
            TutorialArenaController.shared.show(model: self)
        } else {
            tutorial = nil
            coachEnabled = false
            TutorialArenaController.shared.close()
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

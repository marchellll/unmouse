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
    var showWalkthrough = false
    var accessibilityTrusted = false
    var inputMonitoringOK = false
    /// Mirrors `SMAppService.mainApp`. The system stores this, not config.toml, so a preset cannot toggle it.
    var launchAtLogin = false
    var launchAtLoginNote: String?
    var presets: [PresetItem] = []
    var selectedPresetName: String = "default.config"

    private(set) var overlayController: OverlayController?
    var nav: NavigationModel!
    var tutorial: TutorialModel!

    private var configWatcher: DispatchSourceFileSystemObject?
    private var configFD: Int32 = -1
    private var configWatchRearming = false
    private var saveWorkItem: DispatchWorkItem?
    private var suppressConfigReload = false

    /// Forwarded from NavigationModel for Settings.
    var karabinerStatus: NavigationModel.KarabinerStatus {
        nav?.karabinerStatus ?? .eventTapOnly
    }

    /// Forwards navigation state so views can read it from AppModel.
    var mode: AppMode { nav?.mode ?? .idle }
    var gridState: GridState? { nav?.gridState }
    var hintState: HintState { nav?.hintState ?? HintState() }
    var hintBubbles: [HintBubble] { nav?.hintBubbles ?? [] }
    var dragging: Bool { nav?.dragging ?? false }
    var coachEnabled: Bool {
        get { tutorial?.coachEnabled ?? false }
        set { tutorial?.coachEnabled = newValue }
    }

    struct PresetItem: Identifiable {
        var id: String { name }
        var name: String
        var url: URL
    }

    func start() {
        nav = NavigationModel(app: self)
        tutorial = TutorialModel()
        tutorial.app = self
        nav.onTutorial = { [weak self] event in
            self?.tutorial.note(event)
        }

        loadPresets()
        reloadConfig()
        watchConfig()
        // InputTrace always prints; also open UnmouseLog.debug for the same lines.
        UnmouseLog.setLevel(.debug)
        InputTrace.log("Unmouse start — input trace ON (stderr + Console.app category input)")
        overlayController = OverlayController(model: self)
        accessibilityTrusted = AXIsProcessTrusted()
        inputMonitoringOK = nav.startInput()
        refreshPermissions()
        refreshLaunchAtLogin()

        if !accessibilityTrusted {
            showWalkthrough = true
        } else if !UserDefaults.standard.bool(forKey: "didCompleteWalkthrough") {
            showWalkthrough = true
        } else if !tutorial.completedSessions().contains(.freeOnly) {
            tutorial.start(.freeOnly)
        }
    }

    func refreshPermissions() {
        accessibilityTrusted = AXIsProcessTrusted()
        if !inputMonitoringOK {
            inputMonitoringOK = nav.startInput()
        }
        nav.updateKarabiner()
        nav.refreshCenterOnFocus()
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
        tutorial.start(.freeOnly)
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
                fitGrid(to: nav.screenForCursor().frame.size, into: &loaded)
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
            // Return matches Space for left click in every mode (older configs had Space only).
            var migratedClicks = false
            if Self.ensureReturnAlongsideSpace(&loaded.bindings.grid.leftClick) { migratedClicks = true }
            if Self.ensureReturnAlongsideSpace(&loaded.bindings.free.leftClick) { migratedClicks = true }
            if Self.ensureReturnAlongsideSpace(&loaded.bindings.hint.leftClick) { migratedClicks = true }
            if migratedClicks {
                try ConfigIO.save(loaded)
            }
            let errors = ConfigValidator.validate(loaded)
            applyRuntimeConfig(loaded, errors: errors, replaceConfig: true)
        } catch {
            configError = String(describing: error)
            UnmouseLog.error("config load failed: \(configError ?? "")")
        }
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
    }

    /// Fit the grid and the subgrid to the display under the pointer. Both use the same count, so two passes land on a cell small enough to hit.
    func recalculateGridDimensions() {
        fitGrid(to: nav.screenForCursor().frame.size, into: &config)
        commitConfigEdits()
    }

    /// Persist in-memory settings edits to config.toml (debounced).
    func commitConfigEdits() {
        let errors = ConfigValidator.validate(config)
        applyRuntimeConfig(config, errors: errors, replaceConfig: false)
        if errors.contains(where: \.blocksApply) { return }

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suppressConfigReload = true
            do {
                try ConfigIO.save(self.config)
            } catch {
                self.configError = String(describing: error)
            }
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

    // MARK: Tutorial facade (Settings / Walkthrough)

    func skipTutorial() {
        tutorial.skip()
    }

    func moveTutorial(by delta: Int) {
        tutorial.move(by: delta)
    }

    func noteArena(_ event: TutorialEvent) {
        tutorial.note(event)
    }

    // MARK: Private helpers

    private func applyRuntimeConfig(_ loaded: AppConfig, errors: [ConfigError], replaceConfig: Bool) {
        configError = errors.isEmpty ? nil : errors.map(\.description).joined(separator: "; ")
        let blocking = errors.filter(\.blocksApply)
        if blocking.isEmpty {
            if replaceConfig {
                config = loaded
                if errors.isEmpty {
                    UnmouseLog.info("config loaded")
                } else {
                    UnmouseLog.error("config invalid: \(configError ?? "")")
                }
            }
            UnmouseLog.setLevel(config.log.level)
            nav?.applyBindings(config)
            nav?.updateKarabiner()
            nav?.setCenterOnFocus(config.input.centerOnFocus)
            overlayController?.refreshAppearance()
        } else if replaceConfig {
            UnmouseLog.error("config invalid: \(configError ?? "")")
        }
    }

    private func fitGrid(to size: CGSize, into config: inout AppConfig) {
        let dimensions = GridSizing.dimensions(for: size)
        config.grid.rows = dimensions.rows
        config.grid.cols = dimensions.cols
        config.grid.subRows = dimensions.rows
        config.grid.subCols = dimensions.cols
    }

    /// If Space is a left-click binding, Return is too (unless already listed).
    @discardableResult
    private static func ensureReturnAlongsideSpace(_ keys: inout [String]) -> Bool {
        let lower = Set(keys.map { $0.lowercased() })
        guard lower.contains("space"),
              !lower.contains("return"),
              !lower.contains("enter")
        else { return false }
        keys.append("return")
        return true
    }

    private func loadBundledDefault() throws -> String {
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
}

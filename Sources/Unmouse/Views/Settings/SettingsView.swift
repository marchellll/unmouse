import AppKit
import SwiftUI
import UnmouseCore

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case global = "Global"
    case grid = "Grid"
    case free = "Free"
    case hint = "Hint"
    case presets = "Presets"

    var id: String { rawValue }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var pane: SettingsPane = .global

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { item in
                Text(item.rawValue).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
        } detail: {
            Form {
                switch pane {
                case .global: globalPane
                case .grid: gridPane
                case .free: freePane
                case .hint: hintPane
                case .presets: presetsPane
                }
                if let err = model.configError {
                    Section("Validation") {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(8)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            model.refreshPermissions()
            model.refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
            model.refreshLaunchAtLogin()
        }
    }

    private func commit() {
        model.commitConfigEdits()
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        )
    }

    private func permissionRow(title: String, ok: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            if !ok {
                Button(actionTitle, action: action)
            }
        }
    }

    private func bind(_ title: String, _ binding: Binding<[String]>, hint: String? = nil, conflicts: Bool = false) -> some View {
        KeystrokeCaptureRow(title: title, hint: hint, shortcuts: binding, conflicts: conflicts, onChange: commit)
    }

    /// A bare grid shortcut whose key is also a cell letter. That key cannot both type and act.
    private func overlapsGridChars(_ shortcuts: [String]) -> Bool {
        let chars = Set(model.config.grid.chars.lowercased())
        return shortcuts.contains { raw in
            guard let sc = try? ShortcutParser.parse(raw),
                  sc.modifiers.isEmpty,
                  let c = sc.key.character
            else { return false }
            return chars.contains(c)
        }
    }

    // MARK: Panes

    @ViewBuilder private var globalPane: some View {
        Section {
            permissionRow(
                title: "Accessibility",
                ok: model.accessibilityTrusted,
                actionTitle: "Grant",
                action: { model.requestAccessibility() }
            )
            permissionRow(
                title: "Input Monitoring",
                ok: model.inputMonitoringOK,
                actionTitle: "Open Settings",
                action: { model.openInputMonitoringSettings() }
            )
        }

        Section {
            Toggle("Coach", isOn: $model.tutorial.coachEnabled)
                .help("While a mode is on, shows what you can do next.")
                .onChange(of: model.tutorial.coachEnabled) { _, _ in
                    model.overlayController?.updateCoach()
                }
            Menu("Tutorial") {
                Button("Install walkthrough") { model.showWalkthrough = true }
                Divider()
                ForEach(TutorialSessionID.allCases, id: \.self) { session in
                    Button(session.title) { model.tutorial.start(session) }
                }
            }
            Toggle("Open at login", isOn: launchAtLoginBinding)
                .help("Launches Unmouse when you log in.")
            optionHint(
                "Center on focus",
                hint: "When the focused window changes and the pointer is outside it, moves the pointer to that window's center. A click inside the window stays where it landed. Grid, free, and hint keep the pointer where it is."
            ) {
                Toggle("", isOn: configBind(\.input.centerOnFocus)).labelsHidden()
            }
            if let note = model.launchAtLoginNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Mode shortcuts") {
            bind("Grid mode", global(\.gridMode), hint: "Tap to open the grid on the screen under the pointer. Tap again to cancel. From free or hint mode, the same tap switches to the grid. While dragging, the tap keeps the drag.")
            bind("Free mode", global(\.freeMode), hint: "Tap to drive the pointer from the keyboard. Tap again to leave. From grid or hint mode, the same tap switches to free mode. On a finished grid cell, this jumps there first.")
            bind("Hint mode", global(\.hintMode), hint: "Labels clickable controls on screen. Type a label to arm it, then confirm. From grid or free mode, this shortcut switches here. Press it again to leave.")
        }
        Section("Input") {
            SteppedIntRow(
                "Alone-tap max",
                unit: "ms",
                value: tapMaxMsBinding,
                range: 50...800,
                hint: "How long a bare ⌘ or ⌥ can be held and still count as a tap that opens grid or free mode. A longer hold is left for the app underneath."
            )
            SteppedDoubleRow(
                "Mode idle timeout",
                unit: "s",
                value: modeTimeoutBinding,
                step: 1,
                hint: "Leaves grid, free, or hint after this many seconds without a key. 0 stays until you cancel."
            )
            optionHint("Log level", hint: "How much Unmouse writes to the log. None writes nothing.") {
                menuPicker(logLevelBinding) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
            }
            optionHint(
                "Karabiner",
                hint: "Keys still arrive while another app has Secure Input, such as a password field. Off listens with the event tap only."
            ) {
                menuPicker(karabinerBinding) {
                    Text("On").tag(true)
                    Text("Off").tag(false)
                }
            }
            optionHint("Status", hint: "Where key events are coming from right now.") {
                Text(model.karabinerStatus.rawValue)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var gridPane: some View {
        Section("Live preview") {
            GridPreview(config: model.config)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .background(Checkerboard().clipShape(RoundedRectangle(cornerRadius: 8)))
        }
        Section("Layout") {
            SteppedIntRow("Rows", value: gridInt(\.rows, 1...16), hint: "Rows and columns stay equal so every nested cell keeps the screen's shape. Edit either one to override.")
            SteppedIntRow("Cols", value: gridInt(\.cols, 1...16), hint: "Rows and columns stay equal so every nested cell keeps the screen's shape. Edit either one to override.")
            optionHint(
                "Fit display",
                hint: "Sets the grid and the subgrid from the display under the pointer. Both get the same count, so two passes leave a cell small enough to hit."
            ) {
                Button("Recalculate") { model.recalculateGridDimensions() }
            }
            SteppedIntRow(
                "Depth",
                value: gridInt(\.depth, 1...3),
                hint: "How many finer grids a finished cell can open. The last character of a cell draws the next grid immediately. Space clicks the rectangle chosen so far."
            )
            optionHint(
                "Chars",
                hint: "Each cell shows two characters, or three when the alphabet is too small to name every cell in two. Cells that share a first character form one rectangle. That key selects it, and space clicks its center. Later characters narrow to one cell."
            ) {
                trailingField(gridString(\.chars))
            }
        }
        Section("Subgrid") {
            SteppedIntRow(
                "Rows",
                value: gridInt(\.subRows, 1...16),
                hint: "Rows of the second grid, and of the third when depth is 3."
            )
            SteppedIntRow(
                "Cols",
                value: gridInt(\.subCols, 1...16),
                hint: "Columns of those deeper grids. When the alphabet has a character for every cell, each cell is one key."
            )
            SteppedDoubleRow(
                "Font size",
                unit: "pt",
                value: gridDouble(\.subFontSize, 8...48),
                step: 1,
                hint: "Point size of the letters on those deeper grids."
            )
            HexColorPicker(
                title: "Font color",
                hint: "Color of the letters on the second and third grids.",
                hex: gridString(\.subLabel),
                onChange: commit
            )
            HexColorPicker(
                title: "Glow",
                hint: "Soft light around the letters on the second and third grids. A fully clear color, or a radius of 0, turns it off.",
                hex: gridString(\.subGlow),
                onChange: commit
            )
            SteppedDoubleRow(
                "Glow radius",
                unit: "pt",
                value: gridDouble(\.subGlowRadius, 0...32),
                step: 0.5,
                hint: "How far that light spreads. 0 turns the glow off."
            )
        }
        Section("Text") {
            optionHint(
                "Font",
                hint: "Typeface of the cell letters. system is a monospaced system font. Each other name is drawn in that face."
            ) {
                FontFacePicker(name: gridString(\.font))
            }
        }
        Section("Colors") {
            optionHint(
                "Blend",
                hint: "How grid lines and letters mix with the desktop. Exclusion and difference stay readable on light and dark backgrounds. Normal paints the color as itself."
            ) {
                menuPicker(blendBinding(\.gridBlend)) {
                    ForEach(GridBlend.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
            }
            HexColorPicker(title: "Background", hint: "Kept in the config. The grid overlay stays clear so the desktop shows through.", hex: colorHex(\.background), onChange: commit)
            HexColorPicker(title: "Line", hex: colorHex(\.line), onChange: commit)
            HexColorPicker(title: "Label", hex: colorHex(\.label), onChange: commit)
            HexColorPicker(
                title: "Label outline",
                hint: "Stroke around the cell letters. A fully clear color, or a width of 0, turns it off. The stroke uses the same blend as the letters.",
                hex: gridString(\.labelOutline),
                onChange: commit
            )
            SteppedDoubleRow(
                "Outline width",
                unit: "pt",
                value: gridDouble(\.labelOutlineWidth, 0...12),
                step: 0.5,
                hint: "Thickness of that stroke, in points. 0 turns the outline off."
            )
            HexColorPicker(title: "Highlight", hint: "Stroke drawn around the selected grid cell.", hex: colorHex(\.highlight), onChange: commit)
            HexColorPicker(
                title: "Selection dim",
                hint: "Darkens everything except the chosen cell. A fully clear color, #00000000, turns the darken off.",
                hex: gridString(\.selectionDim),
                onChange: commit
            )
            SteppedIntRow(
                "Selection blur",
                unit: "pt",
                value: gridInt(\.selectionBlur, 0...40),
                hint: "Blurs the desktop under that darkened area. 0 turns the blur off. The chosen cell stays sharp."
            )
        }
        Section("Shortcuts") {
            bind("Back", gridBind(\.back), hint: "Undoes one step: clears a selected cell, then one typed character, then one nested level.", conflicts: overlapsGridChars(model.config.bindings.grid.back))
            bind("Left click", gridBind(\.leftClick), hint: "Clicks the selected rectangle and leaves the grid. Press it again within the system double-click time to double-click, and once more to triple-click. A held drag is released there instead of a new click. Command, Option, Control, or Shift held with the key is sent with the click.", conflicts: overlapsGridChars(model.config.bindings.grid.leftClick))
            bind("Right click", gridBind(\.rightClick), hint: "With a cell selected, moves there, right-clicks, and leaves the grid. Command, Option, Control, or Shift held with the key is sent with the click.", conflicts: overlapsGridChars(model.config.bindings.grid.rightClick))
            bind("Middle click", gridBind(\.middleClick), hint: "With a cell selected, moves there, middle-clicks, and leaves the grid. Command, Option, Control, or Shift held with the key is sent with the click.", conflicts: overlapsGridChars(model.config.bindings.grid.middleClick))
            bind("Hold click", gridBind(\.toggleDrag), hint: "Presses the left button and holds it, then switches to free mode so the pointer can drag. Press again to release. Command, Option, Control, or Shift held with the key is sent with the click.", conflicts: overlapsGridChars(model.config.bindings.grid.toggleDrag))
            bind("Hold right click", gridBind(\.toggleRightDrag), hint: "Holds the right button, then switches to free mode. Press again to release. Modifiers held with the key are sent with the click.", conflicts: overlapsGridChars(model.config.bindings.grid.toggleRightDrag))
            bind("Hold middle click", gridBind(\.toggleMiddleDrag), hint: "Holds the middle button, then switches to free mode. Press again to release. Modifiers held with the key are sent with the click.", conflicts: overlapsGridChars(model.config.bindings.grid.toggleMiddleDrag))
            bind("Move only", gridBind(\.moveOnly), hint: "Moves the pointer to the selected cell and leaves without clicking.", conflicts: overlapsGridChars(model.config.bindings.grid.moveOnly))
            bind("To free", gridBind(\.toFree), hint: "Moves to the selected cell and switches into free mode.", conflicts: overlapsGridChars(model.config.bindings.grid.toFree))
            bind("Cancel", gridBind(\.cancel), hint: "Leaves the grid. If a drag is held, stays in free mode and keeps the drag.", conflicts: overlapsGridChars(model.config.bindings.grid.cancel))
            bind("Next screen", gridBind(\.nextScreen), hint: "Moves the grid to the next display.", conflicts: overlapsGridChars(model.config.bindings.grid.nextScreen))
        }
    }

    private var speedCurveRow: some View {
        let hint = "The pt/s number is the top pointer speed. The seconds number is how long the curve runs. Pointer movement and scroll both follow it. Glide starts slower, levels off, then reaches the top just after 3 seconds. Drag a point to change the shape."
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                OptionLabel(title: "Speed curve", hint: hint)
                    .frame(maxWidth: 280, alignment: .leading)
                Spacer(minLength: 8)
                menuPicker(accelPresetBinding) {
                    ForEach(AccelPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
            }
            AccelCurveEditor(knots: accelKnotsBinding, duration: model.config.free.accelSeconds, onCommit: commit)
            HStack(spacing: 8) {
                TypedNumber(value: freeDouble(\.speed), range: 1...50_000, maxFraction: 2)
                Text("pt/s")
                    .foregroundStyle(.secondary)
                Stepper("", value: freeDouble(\.speed), in: 1...50_000, step: 20)
                    .labelsHidden()
                Spacer(minLength: 8)
                TypedNumber(value: accelSecondsBinding, range: 1...30, maxFraction: 1, width: 56)
                Text("s")
                    .foregroundStyle(.secondary)
                Stepper("", value: accelSecondsBinding, in: 1...30, step: 0.5)
                    .labelsHidden()
            }
        }
        .help(hint)
    }

    @ViewBuilder private var freePane: some View {
        Section("Motion") {
            speedCurveRow
            SteppedDoubleRow("Fast multiplier", unit: "×", value: freeDouble(\.fastMultiplier), step: 0.25, hint: "Multiplies pointer and scroll speed while Faster is held.")
            SteppedDoubleRow("Slow multiplier", unit: "×", value: freeDouble(\.slowMultiplier), step: 0.05, hint: "Multiplies pointer and scroll speed while Slower is held.")
            SteppedDoubleRow("Scroll speed", unit: "lines/s", value: freeDouble(\.scrollSpeed), step: 1, hint: "Top scroll rate while a scroll key is held. The speed curve ramps it over the same seconds as pointer movement. One line is 16 points.")
            optionHint("Reverse scroll", hint: "Flips that scroll axis. X swaps left and right. Y swaps up and down.") {
                HStack(spacing: 16) {
                    Toggle("X", isOn: freeBool(\.scrollReverseX))
                    Toggle("Y", isOn: freeBool(\.scrollReverseY))
                }
            }
            optionHint(
                "Leave on action",
                hint: "A Command, Option, or Control chord, a mouse click, or any other key leaves free mode. Off keeps free mode up. Chords still reach the app. ⌘ plus a scroll key is sent as ⌘-scroll so the app can zoom. Faster and Slower stay here and scale pointer and scroll speed."
            ) {
                Toggle("", isOn: freeBool(\.exitOnAction)).labelsHidden()
            }
        }
        Section("Halo") {
            optionHint(
                "Attention",
                hint: "None holds the halo still. Pulse and breathe grow and shrink. Ping expands and fades out, then repeats."
            ) {
                menuPicker(freeAttention) {
                    ForEach(HaloAttention.allCases, id: \.self) { a in
                        Text(a.rawValue).tag(a)
                    }
                }
            }
            SteppedDoubleRow("Attention period", unit: "s", value: freeDouble(\.haloAttentionPeriod), step: 0.1, hint: "Seconds for one halo animation cycle. Lower is faster.")
            SteppedDoubleRow("Attention scale", unit: "×", value: freeDouble(\.haloAttentionScale), step: 0.1, hint: "How large the halo grows compared with the dot.")
            CartesianRow(
                "Offset (x, y)",
                x: haloOffsetX,
                y: haloOffsetY,
                hint: "Where the halo sits relative to the pointer, in points. Cartesian: +x is right, +y is up."
            )
        }
        Section("Colors") {
            optionHint(
                "Blend",
                hint: "How the free-mode dot and halo mix with the desktop. Exclusion and difference stay readable on light and dark backgrounds. Normal paints the color as itself."
            ) {
                menuPicker(blendBinding(\.freeDotBlend)) {
                    ForEach(GridBlend.allCases, id: \.self) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
            }
            HexColorPicker(title: "Dot", hex: colorHex(\.freeDot), onChange: commit)
            HexColorPicker(title: "Halo", hint: "Color of the ring around the free-mode dot.", hex: colorHex(\.freeDotHalo), onChange: commit)
        }
        Section("Shortcuts") {
            bind("Move left", freeBind(\.moveLeft))
            bind("Move down", freeBind(\.moveDown))
            bind("Move up", freeBind(\.moveUp))
            bind("Move right", freeBind(\.moveRight))
            bind("Faster", freeBind(\.faster), hint: "Hold to multiply pointer and scroll speed. Releasing returns to normal.")
            bind("Slower", freeBind(\.slower), hint: "Hold to multiply pointer and scroll speed. Releasing returns to normal.")
            bind("Scroll up", freeBind(\.scrollUp))
            bind("Scroll down", freeBind(\.scrollDown))
            bind("Scroll left", freeBind(\.scrollLeft))
            bind("Scroll right", freeBind(\.scrollRight))
            bind("Hold click", freeBind(\.toggleDrag), hint: "Presses the left button and holds it, so the pointer drags. Press again to release. Command, Option, Control, or Shift held with the key is sent with the click.")
            bind("Hold right click", freeBind(\.toggleRightDrag), hint: "Holds the right button. Press again to release. Modifiers held with the key are sent with the click.")
            bind("Hold middle click", freeBind(\.toggleMiddleDrag), hint: "Holds the middle button. Press again to release. Modifiers held with the key are sent with the click.")
            bind("Left click", freeBind(\.leftClick), hint: "Left-clicks and stays in free mode. Press it again within the system double-click time to double-click, and once more to triple-click. A held drag is released instead of a new click. Command, Option, Control, or Shift held with the key is sent with the click.")
            bind("Right click", freeBind(\.rightClick), hint: "Right-clicks and stays in free mode. Modifiers held with the key are sent with the click.")
            bind("Middle click", freeBind(\.middleClick), hint: "Middle-clicks and stays in free mode. Modifiers held with the key are sent with the click.")
            bind("Cancel", freeBind(\.cancel), hint: "Leaves free mode. A held drag is released first.")
        }
    }

    @ViewBuilder private var hintPane: some View {
        Section("Colors") {
            HexColorPicker(title: "Fill", hint: "Fill of each hint bubble.", hex: colorHex(\.hintFill), onChange: commit)
            HexColorPicker(title: "Text", hex: colorHex(\.hintText), onChange: commit)
            HexColorPicker(title: "Line", hint: "Border of each hint bubble.", hex: colorHex(\.hintLine), onChange: commit)
        }
        Section("Shortcuts") {
            bind("Left click", hintBind(\.leftClick), hint: "Activates the selected result (left click, menu, window, or app) and leaves hint mode. Space and Return both work.")
            bind("Right click", hintBind(\.rightClick), hint: "Right-clicks an on-screen result and leaves hint mode. Control+Space and Control+Return by default. Control-click is the Mac right-click.")
            bind("To free", hintBind(\.toFree), hint: "Alone tap moves onto the selected on-screen control and switches into free mode.")
            bind("Cancel", hintBind(\.cancel), hint: "Closes hint mode without moving the pointer. Escape by default. ⌘⌥⌃ chords such as ⌘Tab also leave and reach the system; ⌘T and ⌘1–9 stay in hint.")
            bind("Back", hintBind(\.back), hint: "Deletes the last character of the query.")
        }
    }

    @ViewBuilder private var presetsPane: some View {
        Section("Layout preset") {
            optionHint(
                "Preset",
                hint: "Replaces your config, including shortcuts and colors, with that example."
            ) {
                menuPicker(Binding(
                    get: { model.selectedPresetName },
                    set: { name in
                        model.selectedPresetName = name
                        if let preset = model.presets.first(where: { $0.name == name }) {
                            model.applyPreset(preset)
                        }
                    }
                )) {
                    ForEach(model.presets) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
            }
            HStack {
                Button("Open config.toml") { model.editConfig() }
                Button("Reload config") { model.reloadConfigFromDisk() }
            }
        }
    }

    // MARK: Bindings into model.config

    private func configBind<T>(
        _ keyPath: WritableKeyPath<AppConfig, T>,
        clamp: ((T) -> T)? = nil
    ) -> Binding<T> {
        Binding(
            get: { model.config[keyPath: keyPath] },
            set: {
                model.config[keyPath: keyPath] = clamp?($0) ?? $0
                commit()
            }
        )
    }

    private var karabinerBinding: Binding<Bool> {
        configBind(\.input.karabiner)
    }

    private var tapMaxMsBinding: Binding<Int> {
        configBind(\.input.tapMaxMs) { $0.clamped(to: 50...800) }
    }

    private var modeTimeoutBinding: Binding<Double> {
        configBind(\.input.modeTimeoutS) { $0.clamped(to: 0...600) }
    }

    private var logLevelBinding: Binding<LogLevel> {
        Binding(
            get: { model.config.log.level },
            set: { model.config.log.level = $0; commit() }
        )
    }

    private var freeAttention: Binding<HaloAttention> {
        Binding(
            get: { model.config.free.haloAttention },
            set: { model.config.free.haloAttention = $0; commit() }
        )
    }

    private func blendBinding(_ keyPath: WritableKeyPath<ColorsConfig, GridBlend>) -> Binding<GridBlend> {
        Binding(
            get: { model.config.colors[keyPath: keyPath] },
            set: { model.config.colors[keyPath: keyPath] = $0; commit() }
        )
    }

    private func colorHex(_ keyPath: WritableKeyPath<ColorsConfig, String>) -> Binding<String> {
        Binding(
            get: { model.config.colors[keyPath: keyPath] },
            set: { model.config.colors[keyPath: keyPath] = $0 }
        )
    }

    private func gridString(_ keyPath: WritableKeyPath<GridConfig, String>) -> Binding<String> {
        Binding(
            get: { model.config.grid[keyPath: keyPath] },
            set: { model.config.grid[keyPath: keyPath] = $0; commit() }
        )
    }

    private func gridInt(_ keyPath: WritableKeyPath<GridConfig, Int>, _ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { model.config.grid[keyPath: keyPath] },
            set: {
                model.config.grid[keyPath: keyPath] = $0.clamped(to: range)
                commit()
            }
        )
    }

    private func gridDouble(_ keyPath: WritableKeyPath<GridConfig, Double>, _ range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { model.config.grid[keyPath: keyPath] },
            set: {
                model.config.grid[keyPath: keyPath] = $0.clamped(to: range)
                commit()
            }
        )
    }

    private var accelPresetBinding: Binding<AccelPreset> {
        Binding(
            get: { model.config.free.accel },
            set: { preset in
                if preset == .glide {
                    model.config.free.accelSeconds = AccelCurve.defaultDuration
                }
                model.config.free.accel = preset
                if preset != .custom {
                    model.config.free.accelKnots = AccelCurve.knots(for: preset, duration: model.config.free.accelSeconds)
                }
                commit()
            }
        )
    }

    private var accelSecondsBinding: Binding<Double> {
        Binding(
            get: { model.config.free.accelSeconds },
            set: { raw in
                let next = raw.clamped(to: 1...30)
                let current = model.config.free.accelSeconds
                guard next != current, current > 0 else { return }
                model.config.free.accelSeconds = next
                if model.config.free.accel != .custom {
                    model.config.free.accelKnots = AccelCurve.knots(for: model.config.free.accel, duration: next)
                } else {
                    let scale = next / current
                    let scaled = model.config.free.accelKnots.map { SpeedKnot(t: $0.t * scale, y: $0.y) }
                    model.config.free.accelKnots = AccelCurve.normalized(scaled, duration: next)
                }
                commit()
            }
        )
    }

    private var accelKnotsBinding: Binding<[SpeedKnot]> {
        Binding(
            get: { model.config.free.accelKnots },
            set: {
                model.config.free.accelKnots = $0
                model.config.free.accel = AccelCurve.matching($0, duration: model.config.free.accelSeconds)
            }
        )
    }

    private func freeBool(_ keyPath: WritableKeyPath<FreeConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.config.free[keyPath: keyPath] },
            set: { model.config.free[keyPath: keyPath] = $0; commit() }
        )
    }

    private func freeDouble(_ keyPath: WritableKeyPath<FreeConfig, Double>) -> Binding<Double> {
        Binding(
            get: { model.config.free[keyPath: keyPath] },
            set: { model.config.free[keyPath: keyPath] = $0; commit() }
        )
    }

    private var haloOffsetX: Binding<Double> {
        Binding(
            get: { model.config.free.haloOffset.x },
            set: { model.config.free.haloOffset.x = $0; commit() }
        )
    }

    private var haloOffsetY: Binding<Double> {
        Binding(
            get: { model.config.free.haloOffset.y },
            set: { model.config.free.haloOffset.y = $0; commit() }
        )
    }

    /// Title and hint on the left. The control stays vertically centered on the right.
    private func optionHint<Control: View>(
        _ title: String,
        hint: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            OptionLabel(title: title, hint: hint)
                .frame(maxWidth: 280, alignment: .leading)
            Spacer(minLength: 8)
            control()
        }
        .help(hint)
    }

    private func menuPicker<Selection: Hashable, Content: View>(
        _ selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Picker("", selection: selection, content: content)
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
    }

    private func trailingField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
    }

    private func global(_ keyPath: WritableKeyPath<GlobalBindings, [String]>) -> Binding<[String]> {
        Binding(
            get: { model.config.bindings.global[keyPath: keyPath] },
            set: { model.config.bindings.global[keyPath: keyPath] = $0 }
        )
    }

    private func gridBind(_ keyPath: WritableKeyPath<GridBindings, [String]>) -> Binding<[String]> {
        Binding(
            get: { model.config.bindings.grid[keyPath: keyPath] },
            set: { model.config.bindings.grid[keyPath: keyPath] = $0 }
        )
    }

    private func freeBind(_ keyPath: WritableKeyPath<FreeBindings, [String]>) -> Binding<[String]> {
        Binding(
            get: { model.config.bindings.free[keyPath: keyPath] },
            set: { model.config.bindings.free[keyPath: keyPath] = $0 }
        )
    }

    private func hintBind(_ keyPath: WritableKeyPath<HintBindings, [String]>) -> Binding<[String]> {
        Binding(
            get: { model.config.bindings.hint[keyPath: keyPath] },
            set: { model.config.bindings.hint[keyPath: keyPath] = $0 }
        )
    }
}

private struct SteppedIntRow: View {
    let title: String
    var unit: String?
    @Binding var value: Int
    var range: ClosedRange<Int>?
    var hint: String?

    init(_ title: String, unit: String? = nil, value: Binding<Int>, range: ClosedRange<Int>? = nil, hint: String? = nil) {
        self.title = title
        self.unit = unit
        self._value = value
        self.range = range
        self.hint = hint
    }

    var body: some View {
        Group {
            if let hint, !hint.isEmpty {
                HStack(alignment: .center, spacing: 12) {
                    OptionLabel(title: title, hint: hint)
                        .frame(maxWidth: 280, alignment: .leading)
                    Spacer(minLength: 8)
                    numberField
                    Stepper("", value: $value, in: range ?? 0...10_000)
                        .labelsHidden()
                }
            } else {
                HStack {
                    Text(title)
                    Spacer(minLength: 8)
                    numberField
                    Stepper("", value: $value, in: range ?? 0...10_000)
                        .labelsHidden()
                }
            }
        }
        .modifier(OptionalHelp(hint: hint))
    }

    private var numberField: some View {
        HStack(spacing: 6) {
            let span = range ?? 0...10_000
            TypedNumber(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                range: Double(span.lowerBound)...Double(span.upperBound),
                maxFraction: 0,
                width: 64
            )
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SteppedDoubleRow: View {
    let title: String
    var unit: String?
    @Binding var value: Double
    var step: Double
    var hint: String?

    init(_ title: String, unit: String? = nil, value: Binding<Double>, step: Double, hint: String? = nil) {
        self.title = title
        self.unit = unit
        self._value = value
        self.step = step
        self.hint = hint
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let hint, !hint.isEmpty {
                OptionLabel(title: title, hint: hint)
                    .frame(maxWidth: 280, alignment: .leading)
            } else {
                Text(title)
            }
            Spacer(minLength: 8)
            TypedNumber(value: $value, minFraction: 2, maxFraction: 2)
            if let unit {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
            }
            Stepper("", value: $value, step: step)
                .labelsHidden()
        }
        .modifier(OptionalHelp(hint: hint))
    }
}

/// Number you can type or step. Commits when you leave the field or press Return.
private struct TypedNumber: View {
    @Binding var value: Double
    var range: ClosedRange<Double>?
    var minFraction: Int = 0
    var maxFraction: Int = 2
    var width: CGFloat = 76
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .onAppear { text = format(value) }
            .onChange(of: value) { _, new in
                if focused, let parsed = parse(text), abs(parsed - new) < 0.000_001 { return }
                text = format(new)
            }
            .onSubmit { apply() }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { apply() }
            }
    }

    private func apply() {
        guard var next = parse(text) else {
            text = format(value)
            return
        }
        if let range {
            next = min(range.upperBound, max(range.lowerBound, next))
        }
        text = format(next)
        if abs(next - value) > 0.000_001 {
            value = next
        }
    }

    private func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minFraction
        formatter.maximumFractionDigits = maxFraction
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

private struct CartesianRow: View {
    let title: String
    @Binding var x: Double
    @Binding var y: Double
    var hint: String?

    init(_ title: String, x: Binding<Double>, y: Binding<Double>, hint: String? = nil) {
        self.title = title
        self._x = x
        self._y = y
        self.hint = hint
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            OptionLabel(title: title, hint: hint)
                .frame(maxWidth: 280, alignment: .leading)
            Spacer(minLength: 8)
            Text("x")
                .foregroundStyle(.secondary)
            TypedNumber(value: $x, maxFraction: 0, width: 64)
            Stepper("", value: $x, step: 1)
                .labelsHidden()
            Text("y")
                .foregroundStyle(.secondary)
            TypedNumber(value: $y, maxFraction: 0, width: 64)
            Stepper("", value: $y, step: 1)
                .labelsHidden()
        }
        .modifier(OptionalHelp(hint: hint))
    }
}

/// Menu of installed faces. Each row is drawn in that face. `system` stays first.
private struct FontFacePicker: View {
    @Binding var name: String

    private struct Face: Identifiable, Hashable {
        var postScript: String
        var label: String
        var id: String { postScript }
    }

    private static let installed: [Face] = {
        var seen = Set<String>(["system"])
        var faces = [Face(postScript: "system", label: "system")]
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        for family in families {
            for member in manager.availableMembers(ofFontFamily: family) ?? [] {
                guard member.count >= 2,
                      let postScript = member[0] as? String,
                      let label = member[1] as? String,
                      seen.insert(postScript).inserted
                else { continue }
                faces.append(Face(postScript: postScript, label: label))
            }
        }
        return faces
    }()

    private var selection: Binding<String> {
        Binding(
            get: {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "system" : trimmed
            },
            set: { name = $0 }
        )
    }

    private var faces: [Face] {
        let current = selection.wrappedValue
        if Self.installed.contains(where: { $0.postScript == current }) {
            return Self.installed
        }
        return [Face(postScript: current, label: current)] + Self.installed
    }

    var body: some View {
        Picker("", selection: selection) {
            ForEach(faces) { face in
                Text(face.label)
                    .font(GridOverlayView.labelFont(name: face.postScript, size: 13))
                    .tag(face.postScript)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let n: CGFloat = 10
            for y in stride(from: 0, to: size.height, by: n) {
                for x in stride(from: 0, to: size.width, by: n) {
                    let odd = Int((x + y) / n) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: n, height: n)),
                        with: .color(odd ? Color(white: 0.25) : Color(white: 0.35))
                    )
                }
            }
        }
    }
}

struct GridPreview: View {
    let config: AppConfig

    var body: some View {
        Canvas { context, size in
            let rows = config.grid.rows
            let cols = config.grid.cols
            let cellW = size.width / CGFloat(cols)
            let cellH = size.height / CGFloat(rows)
            let labels = GridLabels.labels(chars: config.grid.chars, rows: rows, cols: cols)
            let line = Color(hex: config.colors.line) ?? .white
            let label = Color(hex: config.colors.label) ?? .white
            let outlineWidth = CGFloat(config.grid.labelOutlineWidth)
            for r in 0...rows {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: CGFloat(r) * cellH))
                p.addLine(to: CGPoint(x: size.width, y: CGFloat(r) * cellH))
                context.stroke(p, with: .color(line.opacity(0.5)), lineWidth: 1)
            }
            for c in 0...cols {
                var p = Path()
                p.move(to: CGPoint(x: CGFloat(c) * cellW, y: 0))
                p.addLine(to: CGPoint(x: CGFloat(c) * cellW, y: size.height))
                context.stroke(p, with: .color(line.opacity(0.5)), lineWidth: 1)
            }
            for (i, text) in labels.enumerated() {
                let row = i / cols
                let col = i % cols
                let shown = GridLabels.clumpText(text)
                let font = GridLinesView.nsFont(name: config.grid.font, size: 10)
                let fill = NSColor(label).usingColorSpace(.sRGB) ?? NSColor(label)
                let attr = GridLinesView.labelString(
                    shown,
                    font: font,
                    fill: fill,
                    outlineHex: config.grid.labelOutline,
                    outlineWidth: outlineWidth
                )
                context.draw(
                    Text(AttributedString(attr)),
                    at: CGPoint(x: CGFloat(col) * cellW + cellW / 2, y: CGFloat(row) * cellH + cellH / 2),
                    anchor: .center
                )
            }
        }
        .blendMode({
            switch config.colors.gridBlend {
            case .exclusion: .exclusion
            case .difference: .difference
            case .normal: .normal
            case .colorBurn: .colorBurn
            case .plusLighter: .plusLighter
            }
        }())
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private let host = HostingWindowController<SettingsView>(
        title: "Unmouse Settings",
        contentSize: NSSize(width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable, .miniaturizable]
    )

    func show(model: AppModel) {
        host.show(rootView: SettingsView(model: model))
    }
}

@MainActor
final class WalkthroughWindowController {
    static let shared = WalkthroughWindowController()
    private let host = HostingWindowController<WalkthroughView>(
        title: "Unmouse Setup",
        contentSize: NSSize(width: 420, height: 280),
        styleMask: [.titled, .closable]
    )

    func show(model: AppModel) {
        if host.isVisible { return }
        host.show(rootView: WalkthroughView(model: model))
    }

    func close() {
        host.close()
    }
}

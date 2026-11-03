import AppKit
import SwiftUI
import UnmouseCore

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Grid preview") {
                GridPreview(config: model.config)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Section("Colors") {
                LabeledContent("Blend", value: model.config.colors.gridBlend.rawValue)
                LabeledContent("Line", value: model.config.colors.line)
                LabeledContent("Label", value: model.config.colors.label)
            }
            Section("Bindings") {
                bindingGroup("Global", model.config.bindings.global.gridMode + model.config.bindings.global.freeMode + model.config.bindings.global.hintMode)
                bindingGroup("Grid left click", model.config.bindings.grid.leftClick)
                bindingGroup("Free move left", model.config.bindings.free.moveLeft)
            }
            Section("Input") {
                LabeledContent("Karabiner", value: model.config.input.karabiner ? "on" : "off")
                LabeledContent("Status", value: model.karabinerStatus.rawValue)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 420)
        .padding()
    }

    private func bindingGroup(_ title: String, _ keys: [String]) -> some View {
        LabeledContent(title, value: keys.joined(separator: ", "))
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
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.35)))
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
                context.draw(
                    Text(text).font(.system(size: 10, design: .monospaced)).foregroundColor(label),
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
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Unmouse Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 480))
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class WalkthroughWindowController {
    static let shared = WalkthroughWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        let hosting = NSHostingController(rootView: WalkthroughView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Unmouse Setup"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 280))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

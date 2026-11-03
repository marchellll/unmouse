import SwiftUI
import UnmouseCore

struct GridOverlayView: View {
    @Bindable var model: AppModel

    var body: some View {
        Canvas { context, size in
            guard let state = model.gridState else { return }
            let colors = model.config.colors
            let rows = state.rows
            let cols = state.cols
            let level = state.currentLevel
            // Drawing in panel-local coords: panel covers screen frame
            let origin = CGPoint.zero
            let cellW = size.width / CGFloat(cols)
            let cellH = size.height / CGFloat(rows)

            // selection dim: darken everything except selected cell
            if let selected = state.selectedCell, model.config.grid.selectionBlur > 0 || model.config.grid.selectionDim != "#00000000" {
                let dim = Color(hex: model.config.grid.selectionDim) ?? Color.black.opacity(0.5)
                var path = Path(CGRect(origin: origin, size: size))
                let hole = CGRect(
                    x: CGFloat(selected.col) * cellW,
                    y: CGFloat(selected.row) * cellH,
                    width: cellW,
                    height: cellH
                )
                path.addRect(hole)
                context.fill(path, with: .color(dim), style: FillStyle(eoFill: true))
            }

            let line = Color(hex: colors.line) ?? .white
            for r in 0...rows {
                let y = CGFloat(r) * cellH
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(p, with: .color(line.opacity(0.5)), lineWidth: 1)
            }
            for c in 0...cols {
                let x = CGFloat(c) * cellW
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(p, with: .color(line.opacity(0.5)), lineWidth: 1)
            }

            let labels = state.labels
            let labelColor = Color(hex: colors.label) ?? .white
            for (i, label) in labels.enumerated() {
                let row = i / cols
                let col = i % cols
                let rect = CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH, width: cellW, height: cellH)
                if !state.currentLevel.typed.isEmpty, !label.hasPrefix(state.currentLevel.typed) {
                    continue
                }
                let font = Font.system(size: min(cellW, cellH) * 0.28, weight: .semibold, design: .monospaced)
                context.draw(
                    Text(label).font(font).foregroundColor(labelColor),
                    at: CGPoint(x: rect.midX, y: rect.midY),
                    anchor: .center
                )
            }

            if let selected = state.selectedCell {
                let rect = CGRect(
                    x: CGFloat(selected.col) * cellW,
                    y: CGFloat(selected.row) * cellH,
                    width: cellW,
                    height: cellH
                )
                let hi = Color(hex: colors.highlight) ?? .white
                context.stroke(Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 4), with: .color(hi), lineWidth: 2)
            }
        }
        .blendMode(blendMode(for: model.config.colors.gridBlend))
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blendMode(for blend: GridBlend) -> BlendMode {
        switch blend {
        case .exclusion: .exclusion
        case .difference: .difference
        case .normal: .normal
        case .colorBurn: .colorBurn
        case .plusLighter: .plusLighter
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let a, r, g, b: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xff) / 255
            g = Double((v >> 16) & 0xff) / 255
            b = Double((v >> 8) & 0xff) / 255
            a = Double(v & 0xff) / 255
        } else {
            r = Double((v >> 16) & 0xff) / 255
            g = Double((v >> 8) & 0xff) / 255
            b = Double(v & 0xff) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

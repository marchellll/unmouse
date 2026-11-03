import AppKit
import SwiftUI
import UnmouseCore

/// AppKit layers, not SwiftUI. The panel's default content view is never nil, and NSHostingView
/// was left at zero size behind the backdrop, so the grid never appeared.
final class GridLinesView: NSView {
    /// Groups the lines and letters. The blend stays on this view's layer so it mixes with the desktop.
    private let content = CALayer()
    private let lines = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private var texts: [CATextLayer] = []
    private var pinnedBlend: String?
    private var didPin = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Without this, AppKit drops compositingFilter on the next layer update (~1s, when the text commits).
        layerUsesCoreImageFilters = true
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.actions = ["compositingFilter": NSNull()]
        content.backgroundColor = NSColor.clear.cgColor
        content.isOpaque = false
        content.actions = [
            "bounds": NSNull(), "position": NSNull(), "contents": NSNull(), "hidden": NSNull(),
            "opacity": NSNull(), "sublayers": NSNull(), "compositingFilter": NSNull(),
        ]
        lines.fillColor = nil
        lines.lineWidth = 1
        highlight.fillColor = nil
        highlight.lineWidth = 2
        let freeze: [String: any CAAction] = [
            "bounds": NSNull(), "position": NSNull(), "path": NSNull(), "hidden": NSNull(), "contents": NSNull(),
        ]
        lines.actions = freeze
        highlight.actions = freeze
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layerUsesCoreImageFilters = true
        guard let root = layer else { return }
        if content.superlayer !== root {
            content.removeFromSuperlayer()
            content.frame = bounds
            content.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            root.addSublayer(content)
        }
        if lines.superlayer !== content {
            content.addSublayer(lines)
            content.addSublayer(highlight)
        }
        restoreBlendIfCleared()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.frame = bounds
        CATransaction.commit()
        restoreBlendIfCleared()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        restoreBlendIfCleared()
    }

    func applyBlend(_ blend: GridBlend) {
        wantsLayer = true
        layerUsesCoreImageFilters = true
        let name = blend.layerFilterName
        if didPin, pinnedBlend == name {
            restoreBlendIfCleared()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.actions = ["compositingFilter": NSNull()]
        layer?.compositingFilter = name
        CATransaction.commit()
        pinnedBlend = name
        didPin = true
    }

    /// Assigning `compositingFilter` allocates a Mach port. Only write it again after AppKit clears it.
    /// AppKit also turns off layerUsesCoreImageFilters about a second after the letters update, which hides the blend while the filter object is still set.
    private func restoreBlendIfCleared() {
        layerUsesCoreImageFilters = true
        guard didPin, let pinnedBlend else { return }
        if let current = layer?.compositingFilter as? String, current == pinnedBlend { return }
        if layer?.compositingFilter != nil, !(layer?.compositingFilter is String) { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.actions = ["compositingFilter": NSNull()]
        layer?.compositingFilter = pinnedBlend
        CATransaction.commit()
    }

    func update(
        state: GridState,
        lineHex: String,
        labelHex: String,
        highlightHex: String,
        fontName: String,
        fontSize: CGFloat?,
        outlineHex: String,
        outlineWidth: CGFloat,
        glowHex: String,
        glowRadius: CGFloat
    ) {
        wantsLayer = true
        if lines.superlayer == nil { viewDidMoveToWindow() }
        let screen = state.levels[0]
        let level = state.currentLevel
        let local = CGRect(
            x: level.origin.x - screen.origin.x,
            y: level.origin.y - screen.origin.y,
            width: level.size.width,
            height: level.size.height
        )
        let cellW = local.width / CGFloat(max(state.cols, 1))
        let cellH = local.height / CGFloat(max(state.rows, 1))
        let path = CGMutablePath()
        for r in 0...state.rows {
            let y = local.maxY - CGFloat(r) * cellH
            path.move(to: CGPoint(x: local.minX, y: y))
            path.addLine(to: CGPoint(x: local.maxX, y: y))
        }
        for c in 0...state.cols {
            let x = local.minX + CGFloat(c) * cellW
            path.move(to: CGPoint(x: x, y: local.minY))
            path.addLine(to: CGPoint(x: x, y: local.maxY))
        }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let labels = state.labels
        let labelColor = Self.cgColor(labelHex) ?? NSColor.white.cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lines.path = path
        lines.strokeColor = (Self.cgColor(lineHex) ?? NSColor.white.cgColor).copy(alpha: 0.5)
        lines.frame = bounds
        content.frame = bounds
        while texts.count < labels.count {
            let text = CATextLayer()
            text.alignmentMode = .center
            text.truncationMode = .none
            text.isOpaque = false
            text.actions = [
                "bounds": NSNull(), "position": NSNull(), "hidden": NSNull(),
                "shadowColor": NSNull(), "shadowRadius": NSNull(), "shadowOpacity": NSNull(), "shadowOffset": NSNull(),
            ]
            content.addSublayer(text)
            texts.append(text)
        }
        for (i, text) in texts.enumerated() {
            guard i < labels.count else {
                text.isHidden = true
                continue
            }
            let label = labels[i]
            if label.isEmpty
                || (!state.currentLevel.typed.isEmpty && !label.hasPrefix(state.currentLevel.typed))
            {
                text.isHidden = true
                continue
            }
            let row = i / state.cols
            let col = i % state.cols
            let cell = CoordinateSpace.cellFrame(
                screenOrigin: level.origin,
                screenSize: level.size,
                rows: state.rows,
                cols: state.cols,
                row: row,
                col: col
            )
            let shown = GridLabels.clumpText(label)
            let lineCount = max(1, shown.split(separator: "\n", omittingEmptySubsequences: false).count)
            let lineLen = shown.split(separator: "\n").map(\.count).max() ?? 1
            let fitted = min(cell.width / CGFloat(max(lineLen, 1)) * 0.9, cell.height / CGFloat(lineCount) * 0.8)
            let preferred = fontSize ?? min(cellW, cellH) * 0.32
            let size = max(1, min(preferred, fitted))
            let stroke = min(max(0, outlineWidth), size * 0.18)
            let height = size * 1.35 * CGFloat(lineCount)
            let pad = max(stroke, glowRadius)
            let font = Self.nsFont(name: fontName, size: size)
            text.isHidden = false
            text.masksToBounds = false
            text.isWrapped = lineCount > 1
            text.contentsScale = scale
            text.string = Self.labelString(
                shown,
                font: font,
                fill: NSColor(cgColor: labelColor) ?? .white,
                outlineHex: outlineHex,
                outlineWidth: stroke
            )
            if glowRadius > 0.05, let glow = Self.cgColor(glowHex), glow.alpha > 0.01 {
                text.shadowColor = glow
                text.shadowRadius = glowRadius
                text.shadowOpacity = 1
                text.shadowOffset = .zero
            } else {
                text.shadowOpacity = 0
                text.shadowRadius = 0
            }
            text.setNeedsDisplay()
            text.frame = CGRect(
                x: cell.minX - screen.origin.x - pad,
                y: cell.midY - screen.origin.y - height / 2 - pad,
                width: cell.width + pad * 2,
                height: height + pad * 2
            )
        }
        if let cell = state.targetFrame {
            let rect = CGRect(
                x: cell.minX - screen.origin.x,
                y: cell.minY - screen.origin.y,
                width: cell.width,
                height: cell.height
            ).insetBy(dx: 2, dy: 2)
            highlight.isHidden = false
            highlight.path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            highlight.strokeColor = Self.cgColor(highlightHex) ?? NSColor.white.cgColor
            highlight.frame = bounds
        } else {
            highlight.isHidden = true
        }
        CATransaction.commit()
        restoreBlendIfCleared()
    }

    static func labelString(
        _ string: String,
        font: NSFont,
        fill: NSColor,
        outlineHex: String,
        outlineWidth: CGFloat
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fill,
            .paragraphStyle: style,
        ]
        // Negative stroke width draws the fill and a centered stroke. The fill covers the inner half.
        if outlineWidth > 0.05, let outline = nsColor(outlineHex), outline.alphaComponent > 0.01 {
            attrs[.strokeColor] = outline
            attrs[.strokeWidth] = -outlineWidth / max(font.pointSize, 1) * 100
        }
        return NSAttributedString(string: string, attributes: attrs)
    }

    static func nsFont(name: String, size: CGFloat) -> NSFont {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "system" {
            return .monospacedSystemFont(ofSize: size, weight: .semibold)
        }
        return NSFont(name: trimmed, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .semibold)
    }

    private static func nsColor(_ hex: String) -> NSColor? {
        guard let color = Color(hex: hex) else { return nil }
        return NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    }

    private static func cgColor(_ hex: String) -> CGColor? {
        nsColor(hex)?.cgColor
    }
}

struct GridOverlayView: View {
    @Bindable var model: AppModel

    var body: some View {
        // Read grid state here. Canvas runs its closure later, so a read inside
        // it never subscribes — the overlay skipped updates unless we rebuilt the
        // hosting view, and each rebuild leaked Mach ports.
        let state = model.gridState
        let colors = model.config.colors
        let fontName = model.config.grid.font
        Canvas { context, _ in
            guard let state else { return }
            let rows = state.rows
            let cols = state.cols

            let screen = CGRect(origin: state.levels[0].origin, size: state.levels[0].size)
            let levelAppKit = CGRect(origin: state.currentLevel.origin, size: state.currentLevel.size)
            let level = Self.appKitRectToPanel(levelAppKit, screen: screen)

            let cellW = level.width / CGFloat(cols)
            let cellH = level.height / CGFloat(rows)

            let line = Color(hex: colors.line) ?? .white
            for r in 0...rows {
                let y = level.minY + CGFloat(r) * cellH
                var p = Path()
                p.move(to: CGPoint(x: level.minX, y: y))
                p.addLine(to: CGPoint(x: level.maxX, y: y))
                context.stroke(p, with: .color(line.opacity(0.5)), lineWidth: 1)
            }
            for c in 0...cols {
                let x = level.minX + CGFloat(c) * cellW
                var p = Path()
                p.move(to: CGPoint(x: x, y: level.minY))
                p.addLine(to: CGPoint(x: x, y: level.maxY))
                context.stroke(p, with: .color(line.opacity(0.5)), lineWidth: 1)
            }

            let labels = state.labels
            let labelColor = Color(hex: colors.label) ?? .white
            // Floor so nested (small) cells still show readable labels.
            let fontSize = max(11, min(cellW, cellH) * 0.32)
            let font = Self.labelFont(name: fontName, size: fontSize)
            for (i, label) in labels.enumerated() {
                let row = i / cols
                let col = i % cols
                let rect = CGRect(
                    x: level.minX + CGFloat(col) * cellW,
                    y: level.minY + CGFloat(row) * cellH,
                    width: cellW,
                    height: cellH
                )
                if !state.currentLevel.typed.isEmpty, !label.hasPrefix(state.currentLevel.typed) {
                    continue
                }
                context.draw(
                    Text(label).font(font).foregroundColor(labelColor),
                    at: CGPoint(x: rect.midX, y: rect.midY),
                    anchor: .center
                )
            }

            if let selected = state.selectedCell {
                let rect = CGRect(
                    x: level.minX + CGFloat(selected.col) * cellW,
                    y: level.minY + CGFloat(selected.row) * cellH,
                    width: cellW,
                    height: cellH
                )
                let hi = Color(hex: colors.highlight) ?? .white
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 4),
                    with: .color(hi),
                    lineWidth: 2
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private static func appKitRectToPanel(_ rect: CGRect, screen: CGRect) -> CGRect {
        let topLeft = CGPoint(x: rect.minX, y: rect.maxY)
        return CGRect(
            x: topLeft.x - screen.minX,
            y: screen.maxY - topLeft.y,
            width: rect.width,
            height: rect.height
        )
    }

    static func labelFont(name: String, size: CGFloat) -> Font {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "system" {
            return .system(size: size, weight: .semibold, design: .monospaced)
        }
        if let ns = NSFont(name: trimmed, size: size) {
            return Font(ns)
        }
        return .system(size: size, weight: .semibold, design: .monospaced)
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

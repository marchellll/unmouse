import AppKit
import UnmouseCore

/// Tutorial card and chromatic stroke. A sibling of the grid lines, so the exclusion blend does not eat the type.
final class GridGuideView: NSView {
    private let aura = CALayer()
    private var strokes: [(red: CAShapeLayer, green: CAShapeLayer, blue: CAShapeLayer, core: CAShapeLayer)] = []
    private let card = GuideCardView()
    private var cue: GridGuideCue?
    private var screenOrigin: CGPoint = .zero
    private var avoid: CGRect = .null

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        aura.actions = ["sublayers": NSNull(), "bounds": NSNull(), "position": NSNull(), "opacity": NSNull()]
        card.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let root = layer else { return }
        if aura.superlayer !== root {
            aura.frame = bounds
            root.addSublayer(aura)
        }
        if card.superview !== self {
            addSubview(card)
            card.layer?.zPosition = 20
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        aura.frame = bounds
        CATransaction.commit()
        redraw()
    }

    func clear() {
        cue = nil
        isHidden = true
        card.isHidden = true
    }

    func apply(cue: GridGuideCue?, screenOrigin: CGPoint, avoid: CGRect) {
        self.cue = cue
        self.screenOrigin = screenOrigin
        self.avoid = avoid
        isHidden = cue == nil
        redraw()
    }

    private func redraw() {
        guard let cue, bounds.width > 1 else {
            card.isHidden = true
            aura.sublayers?.forEach { $0.isHidden = true }
            return
        }
        viewDidMoveToWindow()
        let localFrames = cue.frames.map { local($0) }
        let anchor = local(cue.anchor)
        let focus = CGPoint(x: cue.focus.x - screenOrigin.x, y: cue.focus.y - screenOrigin.y)
        let avoidLocal = avoid.isNull ? CGRect.null : local(avoid)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while strokes.count < localFrames.count {
            strokes.append(makeStroke())
        }
        for (i, stroke) in strokes.enumerated() {
            let hidden = i >= localFrames.count
            stroke.core.isHidden = hidden
            stroke.red.isHidden = hidden
            stroke.green.isHidden = hidden
            stroke.blue.isHidden = hidden
            guard !hidden else { continue }
            let path = CGPath(
                roundedRect: localFrames[i].insetBy(dx: 1.5, dy: 1.5),
                cornerWidth: 5,
                cornerHeight: 5,
                transform: nil
            )
            for layer in [stroke.core, stroke.red, stroke.green, stroke.blue] {
                layer.frame = bounds
                layer.path = path
            }
        }
        CATransaction.commit()

        card.set(title: cue.title, detail: cue.detail)
        let size = card.measuredSize()
        card.frame = GridGuideLayout.cardFrame(
            card: size,
            around: anchor,
            near: focus,
            in: bounds.insetBy(dx: 8, dy: 8),
            avoid: avoidLocal
        )
        card.isHidden = false
        card.needsDisplay = true
    }

    private func local(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenOrigin.x,
            y: rect.minY - screenOrigin.y,
            width: rect.width,
            height: rect.height
        )
    }

    private func makeStroke() -> (red: CAShapeLayer, green: CAShapeLayer, blue: CAShapeLayer, core: CAShapeLayer) {
        let core = shape(NSColor.white.withAlphaComponent(0.85), width: 1.25)
        let red = shape(NSColor(srgbRed: 1, green: 0.18, blue: 0.28, alpha: 0.95), width: 2)
        let green = shape(NSColor(srgbRed: 0.25, green: 1, blue: 0.45, alpha: 0.8), width: 2)
        let blue = shape(NSColor(srgbRed: 0.2, green: 0.45, blue: 1, alpha: 0.95), width: 2)
        shimmer(red, keyPath: "transform.translation.x", from: -2.2, to: 2.2, phase: 0)
        shimmer(blue, keyPath: "transform.translation.x", from: 2.2, to: -2.2, phase: 0.15)
        shimmer(green, keyPath: "transform.translation.y", from: -1.4, to: 1.4, phase: 0.45)
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.45
        breathe.toValue = 1
        breathe.duration = 1.15
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        core.add(breathe, forKey: "breathe")
        for layer in [core, red, green, blue] {
            aura.addSublayer(layer)
        }
        return (red, green, blue, core)
    }

    private func shape(_ color: NSColor, width: CGFloat) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = color.cgColor
        layer.lineWidth = width
        layer.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
        return layer
    }

    private func shimmer(_ layer: CALayer, keyPath: String, from: CGFloat, to: CGFloat, phase: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: keyPath)
        anim.fromValue = from
        anim.toValue = to
        anim.duration = 1.35
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timeOffset = phase
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "shimmer")
    }
}

private final class GuideCardView: NSView {
    private var title = NSAttributedString()
    private var detail = NSAttributedString()
    private var titleHeight: CGFloat = 0
    private var detailHeight: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    func set(title: String, detail: String) {
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byWordWrapping
        let detailStyle = NSMutableParagraphStyle()
        detailStyle.lineBreakMode = .byWordWrapping
        self.title = keycaps(
            title,
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .white,
            style: titleStyle
        )
        self.detail = keycaps(
            detail,
            font: .systemFont(ofSize: 12, weight: .regular),
            color: .white.withAlphaComponent(0.82),
            style: detailStyle
        )
        let width = Self.textWidth
        titleHeight = ceil(self.title.boundingRect(
            with: CGSize(width: width, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        detailHeight = detail.isEmpty ? 0 : ceil(self.detail.boundingRect(
            with: CGSize(width: width, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        needsDisplay = true
    }

    func measuredSize() -> CGSize {
        let gap: CGFloat = detailHeight > 0 ? 4 : 0
        let text = max(titleWidth(), detailWidth())
        return CGSize(width: ceil(text) + 24, height: titleHeight + detailHeight + gap + 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.86).setFill()
        box.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        box.lineWidth = 1
        box.stroke()
        let text = bounds.insetBy(dx: 12, dy: 10)
        let gap: CGFloat = detailHeight > 0 ? 4 : 0
        title.draw(in: CGRect(x: text.minX, y: text.maxY - titleHeight, width: text.width, height: titleHeight))
        if detailHeight > 0 {
            detail.draw(in: CGRect(
                x: text.minX,
                y: text.maxY - titleHeight - gap - detailHeight,
                width: text.width,
                height: detailHeight
            ))
        }
    }

    private static let textWidth: CGFloat = 248

    private func keycaps(_ markup: String, font: NSFont, color: NSColor, style: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let keyFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)
        for run in KeycapMarkup.parse(markup) {
            if run.isKey {
                result.append(NSAttributedString(string: "\u{00a0}\(run.text)\u{00a0}", attributes: [
                    .font: keyFont,
                    .foregroundColor: color,
                    .backgroundColor: NSColor.white.withAlphaComponent(0.16),
                    .paragraphStyle: style,
                ]))
            } else {
                result.append(NSAttributedString(string: run.text, attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: style,
                ]))
            }
        }
        return result
    }

    private func titleWidth() -> CGFloat {
        min(Self.textWidth, ceil(title.boundingRect(
            with: CGSize(width: Self.textWidth, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width))
    }

    private func detailWidth() -> CGFloat {
        guard detail.length > 0 else { return 0 }
        return min(Self.textWidth, ceil(detail.boundingRect(
            with: CGSize(width: Self.textWidth, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width))
    }
}

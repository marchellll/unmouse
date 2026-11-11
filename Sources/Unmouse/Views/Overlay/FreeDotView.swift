import AppKit
import QuartzCore
import SwiftUI
import UnmouseCore

/// Halo scale is written onto the layer itself each frame.
/// A parent compositing filter draws the model layer, so a Core Animation
/// presentation (CABasicAnimation) stays frozen at the start scale.
final class FreeDotView: NSView {
    private let halo = CAShapeLayer()
    private let ring = CAShapeLayer()
    /// Dragging replaces the circular halo — same color + attention, diamond silhouette.
    private let dragHalo = CAShapeLayer()
    private let dragRing = CAShapeLayer()
    private let core = CAShapeLayer()
    private var signature: Signature?

    private struct Signature: Equatable {
        var attention: HaloAttention
        var period: Double
        var scale: Double
        var fill: String
        var halo: String
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(free: FreeConfig, fillHex: String, haloHex: String, dragging: Bool) {
        let next = Signature(
            attention: free.haloAttention,
            period: free.haloAttentionPeriod,
            scale: free.haloAttentionScale,
            fill: fillHex,
            halo: haloHex
        )
        if next != signature {
            signature = next
            install(next)
        }
        pose(next, time: CACurrentMediaTime(), dragging: dragging)
    }

    private func install(_ sig: Signature) {
        let fill = Self.cgColor(sig.fill)
        let haloColor = Self.cgColor(sig.halo)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let diameter: CGFloat = 6

        circle(halo, diameter: diameter, fill: haloColor, center: center)
        circle(ring, diameter: diameter * 1.15, fill: nil, center: center)
        ring.strokeColor = haloColor
        ring.lineWidth = 1.5

        diamond(dragHalo, diameter: diameter, fill: haloColor, center: center)
        diamond(dragRing, diameter: diameter * 1.15, fill: nil, center: center)
        dragRing.strokeColor = haloColor
        dragRing.lineWidth = 1.5
        dragRing.fillColor = nil

        circle(core, diameter: diameter, fill: fill, center: center)

        guard let root = layer else { return }
        if halo.superlayer == nil {
            root.addSublayer(halo)
            root.addSublayer(ring)
            root.addSublayer(dragHalo)
            root.addSublayer(dragRing)
            root.addSublayer(core)
        }
    }

    override func layout() {
        super.layout()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [halo, ring, dragHalo, dragRing, core] {
            layer.position = center
        }
        CATransaction.commit()
    }

    private func circle(_ layer: CAShapeLayer, diameter: CGFloat, fill: CGColor?, center: CGPoint) {
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.position = center
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.path = CGPath(ellipseIn: layer.bounds, transform: nil)
        layer.fillColor = fill
        layer.strokeColor = nil
        layer.lineWidth = 0
    }

    private func diamond(_ layer: CAShapeLayer, diameter: CGFloat, fill: CGColor?, center: CGPoint) {
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.position = center
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let b = layer.bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: b.midX, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX, y: b.midY))
        path.addLine(to: CGPoint(x: b.midX, y: b.maxY))
        path.addLine(to: CGPoint(x: b.minX, y: b.midY))
        path.closeSubpath()
        layer.path = path
        layer.fillColor = fill
        layer.strokeColor = nil
        layer.lineWidth = 0
    }

    /// ponytail: sampled on the free-mode display link. Upgrade path is a keyframe if the cosine looks wrong.
    private func pose(_ sig: Signature, time: CFTimeInterval, dragging: Bool) {
        let period = max(0.2, sig.period)
        let peak = CGFloat(max(1.2, sig.scale))
        let phase = time.truncatingRemainder(dividingBy: period) / period
        let cosine = CGFloat(0.5 - 0.5 * cos(phase * 2 * .pi))
        let body = dragging ? dragHalo : halo
        let outline = dragging ? dragRing : ring

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.isHidden = dragging
        ring.isHidden = dragging
        dragHalo.isHidden = !dragging
        dragRing.isHidden = !dragging

        switch sig.attention {
        case .none:
            outline.isHidden = true
            pin(body, scale: 1.6, opacity: 0.55)
        case .pulse:
            outline.isHidden = false
            pin(body, scale: lerp(1.4, peak, cosine), opacity: lerp(0.75, 0.35, cosine))
            pin(outline, scale: lerp(1.4, peak, cosine), opacity: lerp(0.525, 0.245, cosine))
        case .ping:
            outline.isHidden = false
            let saw = CGFloat(phase)
            pin(body, scale: lerp(1.2, peak, saw), opacity: lerp(0.7, 0, saw))
            pin(outline, scale: lerp(1.2, peak, saw), opacity: lerp(0.49, 0, saw))
        case .breathe:
            outline.isHidden = true
            pin(body, scale: lerp(1.5, 1.85, cosine), opacity: lerp(0.3, 0.75, cosine))
        }
        CATransaction.commit()
        superview?.layer?.setNeedsDisplay()
    }

    private func pin(_ layer: CALayer, scale: CGFloat, opacity: Float) {
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        layer.opacity = opacity
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }

    private func lerp(_ from: Float, _ to: Float, _ t: CGFloat) -> Float {
        from + (to - from) * Float(t)
    }

    private static func cgColor(_ hex: String) -> CGColor {
        let color = NSColor(Color(hex: hex) ?? .white)
        return (color.usingColorSpace(.sRGB) ?? color).cgColor
    }
}

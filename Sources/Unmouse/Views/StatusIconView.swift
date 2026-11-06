import SwiftUI
import UnmouseCore

/// Draws the menu-bar icon without eating the click, so the status item's menu opens.
final class StatusIconHost: NSHostingView<StatusIconView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct StatusIconView: View {
    @Bindable var model: AppModel
    @State private var pulse = false

    var body: some View {
        Canvas { context, size in
            let color = Color.primary.opacity(model.nav.mode == .idle ? 1.0 : (pulse ? 1.0 : 0.7))
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            switch model.nav.mode {
            case .idle:
                drawMouse(context: context, in: rect, color: color)
            case .grid:
                drawGrid(context: context, in: rect, color: color)
            case .free:
                drawCrosshair(context: context, in: rect, color: color, dragging: model.nav.dragging)
            case .hint:
                drawBubble(context: context, in: rect, color: color)
            }
        }
        .frame(width: 18, height: 18)
        .onChange(of: model.nav.mode) { _, mode in
            pulse = false
            guard mode != .idle else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func drawMouse(context: GraphicsContext, in rect: CGRect, color: Color) {
        let body = Path(roundedRect: CGRect(x: rect.midX - 4, y: rect.minY + 2, width: 8, height: 12), cornerRadius: 3)
        context.stroke(body, with: .color(color), lineWidth: 1.2)
        var mid = Path()
        mid.move(to: CGPoint(x: rect.midX, y: rect.minY + 2))
        mid.addLine(to: CGPoint(x: rect.midX, y: rect.minY + 7))
        context.stroke(mid, with: .color(color), lineWidth: 1)
    }

    private func drawGrid(context: GraphicsContext, in rect: CGRect, color: Color) {
        let s = rect.insetBy(dx: 1, dy: 1)
        context.stroke(Path(s), with: .color(color), lineWidth: 1.2)
        var h = Path(); h.move(to: CGPoint(x: s.minX, y: s.midY)); h.addLine(to: CGPoint(x: s.maxX, y: s.midY))
        var v = Path(); v.move(to: CGPoint(x: s.midX, y: s.minY)); v.addLine(to: CGPoint(x: s.midX, y: s.maxY))
        context.stroke(h, with: .color(color), lineWidth: 1)
        context.stroke(v, with: .color(color), lineWidth: 1)
    }

    private func drawCrosshair(context: GraphicsContext, in rect: CGRect, color: Color, dragging: Bool) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var h = Path(); h.move(to: CGPoint(x: rect.minX, y: c.y)); h.addLine(to: CGPoint(x: rect.maxX, y: c.y))
        var v = Path(); v.move(to: CGPoint(x: c.x, y: rect.minY)); v.addLine(to: CGPoint(x: c.x, y: rect.maxY))
        context.stroke(h, with: .color(color), lineWidth: 1.2)
        context.stroke(v, with: .color(color), lineWidth: 1.2)
        context.stroke(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(color), lineWidth: 1)
        if dragging {
            context.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)), with: .color(color))
        }
    }

    private func drawBubble(context: GraphicsContext, in rect: CGRect, color: Color) {
        let bubble = Path(roundedRect: CGRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 2, height: rect.height - 5), cornerRadius: 3)
        context.stroke(bubble, with: .color(color), lineWidth: 1.2)
        var tail = Path()
        tail.move(to: CGPoint(x: rect.midX - 2, y: rect.maxY - 5))
        tail.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 1))
        tail.addLine(to: CGPoint(x: rect.midX + 2, y: rect.maxY - 5))
        context.stroke(tail, with: .color(color), lineWidth: 1)
    }
}

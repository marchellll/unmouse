import AppKit
import SwiftUI
import UnmouseCore

struct HintOverlayView: View {
    @Bindable var model: AppModel

    var body: some View {
        Canvas { context, size in
            let fill = Color(hex: model.config.colors.hintFill) ?? .black.opacity(0.9)
            let text = Color(hex: model.config.colors.hintText) ?? .white
            let line = Color(hex: model.config.colors.hintLine) ?? .white.opacity(0.8)
            let screen = NSScreen.main?.frame ?? .zero

            for bubble in model.nav.hintBubbles {
                guard model.nav.hintState.visibleTargets.contains(where: { $0.id == bubble.id }) else { continue }
                // AppKit screen → panel-local (SwiftUI y is top-down).
                let localBubble = Self.toLocal(bubble.bubbleFrame, screen: screen)
                if bubble.needsLeader, bubble.leaderPath.count >= 2 {
                    var p = Path()
                    let pts = bubble.leaderPath.map { Self.toLocal($0, screen: screen) }
                    p.move(to: pts[0])
                    for pt in pts.dropFirst() {
                        p.addLine(to: pt)
                    }
                    context.stroke(p, with: .color(line), lineWidth: 1)
                }
                let rounded = Path(roundedRect: localBubble, cornerRadius: 6)
                context.fill(rounded, with: .color(fill))
                if model.nav.hintState.armedID == bubble.id {
                    context.stroke(rounded, with: .color(line), lineWidth: 2)
                }
                context.draw(
                    Text(bubble.code).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(text),
                    at: CGPoint(x: localBubble.midX, y: localBubble.midY),
                    anchor: .center
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private static func toLocal(_ r: CGRect, screen: CGRect) -> CGRect {
        CGRect(
            x: r.minX - screen.minX,
            y: screen.maxY - r.maxY,
            width: r.width,
            height: r.height
        )
    }

    private static func toLocal(_ p: CGPoint, screen: CGRect) -> CGPoint {
        CGPoint(x: p.x - screen.minX, y: screen.maxY - p.y)
    }
}

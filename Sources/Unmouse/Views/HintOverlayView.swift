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

            for bubble in model.hintBubbles {
                guard model.hintState.visibleTargets.contains(where: { $0.id == bubble.id }) else { continue }
                // Convert AppKit screen coords to panel-local (panel = screen.frame)
                let localBubble = CGRect(
                    x: bubble.bubbleFrame.minX - screen.minX,
                    // SwiftUI Canvas y is top-down; AppKit y is bottom-up
                    y: screen.maxY - bubble.bubbleFrame.maxY,
                    width: bubble.bubbleFrame.width,
                    height: bubble.bubbleFrame.height
                )
                let localTarget = CGPoint(
                    x: bubble.targetPoint.x - screen.minX,
                    y: screen.maxY - bubble.targetPoint.y
                )
                if bubble.needsLeader {
                    var p = Path()
                    p.move(to: CGPoint(x: localBubble.midX, y: localBubble.midY))
                    p.addLine(to: localTarget)
                    context.stroke(p, with: .color(line), lineWidth: 1)
                }
                let rounded = Path(roundedRect: localBubble, cornerRadius: 6)
                context.fill(rounded, with: .color(fill))
                if model.hintState.armedID == bubble.id {
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
}

import AppKit

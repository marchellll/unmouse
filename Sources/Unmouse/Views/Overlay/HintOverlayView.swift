import AppKit
import SwiftUI
import UnmouseCore

struct HintOverlayView: View {
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { geo in
            // Cached on enterHint — never call AX from a SwiftUI body.
            let screen = model.nav.hintScreenFrame.isEmpty ? geo.frame(in: .global) : model.nav.hintScreenFrame
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let fill = Color(hex: model.config.colors.hintFill) ?? .black.opacity(0.9)
                    let text = Color(hex: model.config.colors.hintText) ?? .white
                    let line = Color(hex: model.config.colors.hintLine) ?? .white.opacity(0.8)

                    if let highlight = model.nav.hintState.highlightFrame {
                        let local = Self.toLocal(highlight, screen: screen)
                        let path = Path(roundedRect: local, cornerRadius: 3)
                        let mark = Color(hex: model.config.colors.hintHighlight) ?? Color(red: 0.204, green: 0.780, blue: 0.349)
                        context.fill(path, with: .color(mark.opacity(0.35)))
                        context.stroke(path, with: .color(mark.opacity(0.9)), lineWidth: 2)
                    }

                    let hint = model.nav.hintState
                    for bubble in model.nav.hintBubbles {
                        guard hint.visibleTargets.contains(where: { $0.id == bubble.id }) else { continue }
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
                        let style = hint.style(for: bubble.code)
                        if style.highlighted {
                            context.stroke(rounded, with: .color(line), lineWidth: 2)
                        }
                        // ⌘N on the bubble when palette would show it (long query or ⌘ held).
                        let label: String
                        if let n = hint.cmdNumber(forTargetID: bubble.id) {
                            label = "⌘\(n)"
                        } else {
                            label = bubble.code
                        }
                        context.draw(
                            Self.codeText(label, style: style, text: text),
                            at: CGPoint(x: localBubble.midX, y: localBubble.midY),
                            anchor: .center
                        )
                    }
                }
                .allowsHitTesting(false)

                // ponytail: fixed half-size for clamp — real height varies a bit with row count.
                HintPaletteView(model: model)
                    .frame(width: HintPalettePlacement.paletteSize.width)
                    .position(Self.paletteCenter(state: model.nav.hintState, screen: screen, geo: geo.size))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Overlay-local center for the palette; attached points convert from AppKit.
    private static func paletteCenter(state: HintState, screen: CGRect, geo: CGSize) -> CGPoint {
        let halfW = HintPalettePlacement.paletteSize.width / 2
        let halfH = HintPalettePlacement.paletteSize.height / 2
        let raw: CGPoint
        switch state.paletteLayout {
        case .attached(let appKit):
            raw = toLocal(appKit, screen: screen)
        case .freestanding(let anchor):
            raw = CGPoint(x: geo.width / 2, y: geo.height * anchor.yFraction)
        }
        return HintPalettePlacement.clampCenter(
            x: raw.x, y: raw.y,
            halfWidth: halfW, halfHeight: halfH,
            in: geo
        )
    }

    /// ponytail: typed letters shift toward amber off the text color. No extra config key.
    private static func codeText(_ code: String, style: HintCodeStyle, text: Color) -> Text {
        var attr = AttributedString(code)
        attr.foregroundColor = text
        if style.tintedCount > 0 {
            let end = attr.index(attr.startIndex, offsetByCharacters: min(style.tintedCount, code.count))
            attr[attr.startIndex..<end].foregroundColor = text.mix(
                with: Color(red: 1, green: 0.72, blue: 0.15),
                by: 0.45,
                in: .perceptual
            )
        }
        return Text(attr).font(.system(size: 12, weight: .bold, design: .monospaced))
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

private struct HintPaletteView: View {
    @Bindable var model: AppModel

    var body: some View {
        let state = model.nav.hintState
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(state.typed.isEmpty ? "Type to search…" : state.typed)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(state.typed.isEmpty ? Color.white.opacity(0.35) : Color.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().overlay(Color.white.opacity(0.12))

            if !state.scanned {
                Text("Scanning…")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(12)
            } else if state.targets.isEmpty {
                Text("Nothing found")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(12)
            } else {
                let rows = Array(state.matches.prefix(8))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, match in
                    let selected = state.selectedIndex >= 0 && index == state.selectedIndex
                    HStack(spacing: 10) {
                        if !match.target.code.isEmpty {
                            Text(match.target.code)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.95), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text(match.target.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(Self.actionLabel(match.target))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.45))
                        if let n = match.cmdNumber {
                            Text("⌘\(n)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(selected ? Color.white.opacity(0.12) : Color.clear)
                }
            }

            Divider().overlay(Color.white.opacity(0.12))
            Text(model.hintLegend)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private static func actionLabel(_ t: HintTarget) -> String {
        switch t.action {
        case .click: return t.showsLabel ? "Click" : "Click"
        case .menu: return "Menu"
        case .window: return "Raise"
        case .app: return "Launch"
        }
    }
}

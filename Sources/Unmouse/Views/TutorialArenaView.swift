import AppKit
import SwiftUI
import UnmouseCore

struct TutorialArenaView: View {
    @Bindable var model: AppModel
    @State private var puckOffset: CGSize = .zero

    private var focus: TutorialArenaFocus {
        model.tutorial.progress?.arenaFocus ?? .none
    }

    private var prompt: String {
        model.tutorial.progress?.current?.prompt ?? "Session clear — next up."
    }

    private var sessionTitle: String {
        model.tutorial.progress?.session.title ?? "Tutorial"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            practiceStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 480, minHeight: 360)
        .onChange(of: model.tutorial.progress?.stepIndex) { _, _ in
            puckOffset = .zero
        }
        .onChange(of: model.tutorial.progress?.session) { _, _ in
            puckOffset = .zero
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sessionTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let t = model.tutorial.progress, !t.steps.isEmpty {
                    Text("\(min(t.stepIndex + 1, t.steps.count)) / \(t.steps.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(prompt)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = model.tutorial.progress?.current?.detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var practiceStage: some View {
        Group {
            switch focus {
            case .none:
                Text("Use your keyboard on the desktop.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            case .leftTarget:
                leftTarget
            case .rightTarget:
                rightTarget
            case .drag:
                dragStage
            case .scroll:
                scrollPlane
                    .frame(width: 360, height: 180)
            case .hintButton:
                hintButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: focus)
    }

    private var leftTarget: some View {
        Button(action: { hit(.hitLeftTarget) }) {
            Text("Hit")
                .font(.headline)
                .foregroundStyle(Color.green)
                .frame(width: 96, height: 96)
                .background {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .overlay(Circle().strokeBorder(Color.green, lineWidth: 1.5))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hit")
    }

    private var rightTarget: some View {
        Button(action: {}) {
            Text("Menu")
                .font(.headline)
                .foregroundStyle(Color.orange)
                .frame(width: 112, height: 72)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.orange, lineWidth: 1.5)
                        )
                }
        }
        .buttonStyle(.plain)
        .background { RightClickCatcher { hit(.hitRightTarget) } }
        .contextMenu { Button("Right-click OK") { hit(.hitRightTarget) } }
        .accessibilityLabel("Menu")
    }

    private var dragStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 88, height: 88)
                .overlay {
                    Text("Drop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .offset(x: 80)

            Circle()
                .strokeBorder(.primary, lineWidth: 1.5)
                .frame(width: 48, height: 48)
                .overlay {
                    Text("Q")
                        .font(.subheadline.weight(.medium))
                }
                .offset(x: -80 + puckOffset.width, y: puckOffset.height)
                .gesture(
                    DragGesture()
                        .onChanged { puckOffset = $0.translation }
                        .onEnded { value in
                            let endX = -80 + value.translation.width
                            let endY = value.translation.height
                            if hypot(endX - 80, endY) < 50 {
                                hit(.hitDragDrop)
                                withAnimation(.easeOut(duration: 0.15)) {
                                    puckOffset = CGSize(width: 160, height: 0)
                                }
                            } else {
                                withAnimation(.easeOut(duration: 0.15)) { puckOffset = .zero }
                            }
                        }
                )
                .accessibilityLabel("Puck")
        }
    }

    private var scrollPlane: some View {
        TwoAxisScrollPad()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.8), lineWidth: 1)
            }
            .accessibilityLabel("Scroll pad")
    }

    private var hintButton: some View {
        Button("Archive") { hit(.hitLeftTarget) }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityLabel("Archive")
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Skip session") { model.skipTutorial() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func hit(_ event: TutorialEvent) {
        model.noteArena(event)
    }
}

/// Both scroll axes. A SwiftUI ScrollView is one axis, and a horizontal one turns vertical scroll into a sideways slide.
private struct TwoAxisScrollPad: NSViewRepresentable {
    func makeNSView(context: Context) -> PadView { PadView() }

    func updateNSView(_ nsView: PadView, context: Context) {}

    final class PadView: NSView {
        /// Inset from the top-left of the grid so left, right, up, and down all have room.
        private var origin = CGPoint(x: 120, y: 80)

        override var isFlipped: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            origin.x = min(480, max(0, origin.x - event.scrollingDeltaX))
            origin.y = min(280, max(0, origin.y - event.scrollingDeltaY))
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let cell: CGFloat = 36
            let gap: CGFloat = 8
            let step = cell + gap
            let cols = 16
            let rows = 10
            let blue = NSColor.systemBlue.withAlphaComponent(0.85)
            let fill = NSColor.systemBlue.withAlphaComponent(0.16)
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = NSRect(
                        x: CGFloat(col) * step - origin.x,
                        y: CGFloat(row) * step - origin.y,
                        width: cell,
                        height: cell
                    )
                    guard bounds.intersects(rect) else { continue }
                    fill.setFill()
                    blue.setStroke()
                    let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
                    path.lineWidth = 1
                    path.fill()
                    path.stroke()
                    let title = "\(col)" as NSString
                    let size = title.size(withAttributes: labelAttrs)
                    title.draw(
                        at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                        withAttributes: labelAttrs
                    )
                }
            }
        }
    }
}

private struct RightClickCatcher: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let v = RightClickView()
        v.onRightClick = onRightClick
        return v
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class RightClickView: NSView {
        var onRightClick: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }

        override func otherMouseDown(with event: NSEvent) {
            if event.buttonNumber == 1 { onRightClick?() }
        }
    }
}

@MainActor
final class TutorialArenaController {
    static let shared = TutorialArenaController()
    private let host = HostingWindowController<TutorialArenaView>(
        title: "Unmouse Practice",
        contentSize: NSSize(width: 520, height: 380),
        styleMask: [.titled, .closable, .resizable],
        activate: false,
        place: { window in
            window.level = .floating
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                ?? NSScreen.main
                ?? NSScreen.screens[0]
            let size = window.frame.size
            let visible = screen.visibleFrame
            let x = visible.midX - size.width / 2
            let y = visible.midY - size.height / 2 - 20
            window.setFrame(
                NSRect(
                    x: max(visible.minX + 12, min(x, visible.maxX - size.width - 12)),
                    y: max(visible.minY + 12, min(y, visible.maxY - size.height - 12)),
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
    )

    func show(model: AppModel) {
        host.show(rootView: TutorialArenaView(model: model))
        host.nsWindow?.level = .floating
        model.overlayController?.updateCoach()
    }

    func close() {
        host.close()
    }

    var frame: NSRect? { host.frame }
    var isVisible: Bool { host.isVisible }
}

import AppKit
import SwiftUI
import UnmouseCore

struct TutorialArenaView: View {
    @Bindable var model: AppModel
    @State private var puckOffset: CGSize = .zero
    @State private var scrollOffset: CGFloat = 0

    private var focus: TutorialArenaFocus {
        model.tutorial?.arenaFocus ?? .none
    }

    private var prompt: String {
        model.tutorial?.current?.prompt ?? "Session clear — next up."
    }

    private var sessionTitle: String {
        model.tutorial?.session.title ?? "Tutorial"
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
        .onChange(of: model.tutorial?.stepIndex) { _, _ in
            puckOffset = .zero
            scrollOffset = 0
        }
        .onChange(of: model.tutorial?.session) { _, _ in
            puckOffset = .zero
            scrollOffset = 0
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sessionTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let t = model.tutorial, !t.steps.isEmpty {
                    Text("\(min(t.stepIndex + 1, t.steps.count)) / \(t.steps.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(prompt)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
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
                scrollStrip
                    .frame(maxWidth: 360, maxHeight: 64)
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
                .foregroundStyle(.primary)
                .frame(width: 96, height: 96)
                .background(Circle().strokeBorder(.primary, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hit")
    }

    private var rightTarget: some View {
        Button(action: {}) {
            Text("Menu")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: 112, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary, lineWidth: 1.5)
                )
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

    private var scrollStrip: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(0..<16, id: \.self) { i in
                    Text("\(i)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )
                }
            }
            .padding(4)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minX
                    )
                }
            )
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetKey.self) { x in
            if abs(x - scrollOffset) > 20 {
                scrollOffset = x
                hit(.hitScroll)
            }
        }
        .padding(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.35), lineWidth: 1)
        }
        .accessibilityLabel("Scroll strip")
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

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: TutorialArenaView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Unmouse Practice"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 380))
            window.isReleasedWhenClosed = false
            window.level = .floating
            self.window = window
        }
        placeNearVisibleCenter()
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
        model.overlayController?.updateCoach()
    }

    func close() {
        window?.orderOut(nil)
    }

    var frame: NSRect? { window?.frame }
    var isVisible: Bool { window?.isVisible == true }

    private func placeNearVisibleCenter() {
        guard let window else { return }
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
}

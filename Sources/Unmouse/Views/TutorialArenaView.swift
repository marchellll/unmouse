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
        model.tutorial.progress?.prompt ?? "Session clear — next up."
    }

    /// The grid card is carrying this step's words. The window only speaks while that card is up.
    private var instructionOnGrid: Bool {
        guard model.nav.mode == .grid,
              let click = model.tutorial.progress?.current?.gridGuide,
              let anchor = model.tutorial.guideAnchor,
              let state = model.gridState
        else { return false }
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        return state.guide(at: point, click: click) != nil
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
            model.tutorial.resetPuckNudge()
        }
        .onChange(of: model.tutorial.progress?.session) { _, _ in
            puckOffset = .zero
            model.tutorial.resetPuckNudge()
        }
        .onChange(of: model.dragging) { _, dragging in
            guard model.tutorial.progress?.arenaFocus == .drag else { return }
            if dragging {
                model.tutorial.resetPuckNudge()
                puckOffset = .zero
                return
            }
            if model.tutorial.puckNudge != .zero {
                puckOffset = model.tutorial.puckNudge
            }
            settlePuck()
        }
        .onChange(of: model.tutorial.puckNudge) { _, nudge in
            guard model.dragging, model.tutorial.progress?.arenaFocus == .drag else { return }
            puckOffset = nudge
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
            if !instructionOnGrid {
                Text(keycaps(prompt, text: .title3, key: .system(.title3, design: .monospaced).weight(.semibold), color: .primary))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = model.tutorial.progress?.current?.detail {
                    Text(keycaps(detail, text: .body, key: .system(.body, design: .monospaced).weight(.semibold), color: .secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Backticks in tutorial copy become a key chip. The font lives on the runs, so a view font would wipe it.
    private func keycaps(_ markup: String, text: Font, key: Font, color: Color) -> AttributedString {
        var out = AttributedString()
        for run in KeycapMarkup.parse(markup) {
            if run.isKey {
                var piece = AttributedString("\u{00a0}\(run.text)\u{00a0}")
                piece.font = key
                piece.foregroundColor = color
                piece.backgroundColor = color.opacity(0.16)
                out += piece
            } else {
                var piece = AttributedString(run.text)
                piece.font = text
                piece.foregroundColor = color
                out += piece
            }
        }
        return out
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
        .background { ScreenFrameReader { model.tutorial.setGuideAnchor($0) } }
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
        .background { ScreenFrameReader { model.tutorial.setGuideAnchor($0) } }
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
                .offset(x: PuckDrop.dropX)

            // Q holds the button wherever the pointer is. A drag gesture only
            // tracked a hit on this circle, and the old 48pt stroke missed.
            Circle()
                .fill(Color.primary.opacity(0.12))
                .overlay { Circle().strokeBorder(.primary, lineWidth: 1.5) }
                .overlay {
                    Text("Q")
                        .font(.subheadline.weight(.medium))
                }
                .frame(width: 72, height: 72)
                .offset(x: PuckDrop.homeX + puckOffset.width, y: puckOffset.height)
                .accessibilityLabel("Puck")
        }
    }

    private var scrollPlane: some View {
        TwoAxisScrollPad(captureZoom: model.tutorial.progress?.current?.required == .zoomedAll) {
            hit(.zoomed($0))
        }
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
            Button("Previous") { model.moveTutorial(by: -1) }
                .disabled(!(model.tutorial.progress?.canMoveBack ?? false))
            Button("Next") { model.moveTutorial(by: 1) }
                .disabled(!(model.tutorial.progress?.canMoveForward ?? false))
            Spacer()
            Button("Skip session") { model.skipTutorial() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func hit(_ event: TutorialEvent) {
        model.noteArena(event)
    }

    /// Space or Q released the button. Count a drop only while the puck step is up.
    private func settlePuck() {
        let hitDrop = PuckDrop.contains(offset: puckOffset)
        InputTrace.log(
            "tutorial puck release hit=\(hitDrop) offset=\(Int(puckOffset.width.rounded())),\(Int(puckOffset.height.rounded()))"
        )
        if hitDrop {
            hit(.hitDragDrop)
            withAnimation(.easeOut(duration: 0.15)) {
                puckOffset = CGSize(width: PuckDrop.dropX - PuckDrop.homeX, height: 0)
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) { puckOffset = .zero }
        }
        model.tutorial.resetPuckNudge()
    }
}

/// Both scroll axes. A SwiftUI ScrollView is one axis, and a horizontal one turns vertical scroll into a sideways slide.
/// ⌘-scroll and pinch zoom the grid. Plain scroll still pans.
private struct TwoAxisScrollPad: NSViewRepresentable {
    var captureZoom: Bool
    var onZoom: (ZoomDirection) -> Void

    func makeNSView(context: Context) -> PadView {
        let view = PadView()
        view.onZoom = onZoom
        view.setCapture(captureZoom)
        return view
    }

    func updateNSView(_ nsView: PadView, context: Context) {
        nsView.onZoom = onZoom
        nsView.setCapture(captureZoom)
    }

    final class PadView: NSView {
        var onZoom: ((ZoomDirection) -> Void)?
        /// Inset from the top-left of the grid so left, right, up, and down all have room.
        private var origin = CGPoint(x: 120, y: 80)
        private var scale: CGFloat = 1
        private var credit = ZoomCredit()
        private var capturing = false

        private enum Grid {
            static let cols = 16
            static let rows = 10
            static let cell: CGFloat = 36
            static let gap: CGFloat = 8
            static var step: CGFloat { cell + gap }

            static func contentSize(scale: CGFloat) -> CGSize {
                let step = Self.step * scale
                let gap = Self.gap * scale
                return CGSize(
                    width: CGFloat(cols) * step - gap,
                    height: CGFloat(rows) * step - gap
                )
            }
        }

        override var isFlipped: Bool { true }

        func setCapture(_ on: Bool) {
            guard on != capturing else { return }
            capturing = on
            guard on else { return }
            let adjusted = CGFloat(credit.arm(scale: Double(scale)))
            guard abs(adjusted - scale) > 0.001 else { return }
            applyScale(adjusted, anchor: CGPoint(x: bounds.midX, y: bounds.midY), report: false)
        }

        override func scrollWheel(with event: NSEvent) {
            if event.modifierFlags.contains(.command), event.scrollingDeltaY != 0 {
                let proposed = scale * CGFloat(exp(Double(event.scrollingDeltaY) * 0.01))
                applyScale(proposed, anchor: convert(event.locationInWindow, from: nil))
                return
            }
            origin.x -= event.scrollingDeltaX
            origin.y -= event.scrollingDeltaY
            clampOrigin()
            needsDisplay = true
        }

        override func magnify(with event: NSEvent) {
            let factor = 1 + event.magnification
            guard factor > 0 else { return }
            applyScale(scale * factor, anchor: convert(event.locationInWindow, from: nil))
        }

        private func applyScale(_ proposed: CGFloat, anchor: CGPoint, report: Bool = true) {
            let old = scale
            let next = CGFloat(ZoomCredit.clamped(Double(proposed)))
            guard old > 0, abs(next - old) > 0.0001 else { return }
            let ux = (anchor.x + origin.x) / old
            let uy = (anchor.y + origin.y) / old
            scale = next
            origin.x = ux * scale - anchor.x
            origin.y = uy * scale - anchor.y
            clampOrigin()
            needsDisplay = true
            guard report, capturing, let direction = credit.credit(scale: Double(scale)) else { return }
            onZoom?(direction)
        }

        private func clampOrigin() {
            let content = Grid.contentSize(scale: scale)
            origin.x = clamped(origin.x, view: bounds.width, content: content.width)
            origin.y = clamped(origin.y, view: bounds.height, content: content.height)
        }

        private func clamped(_ origin: CGFloat, view: CGFloat, content: CGFloat) -> CGFloat {
            guard view > 0 else { return origin }
            if content <= view { return (content - view) / 2 }
            return min(content - view, max(0, origin))
        }

        override func draw(_ dirtyRect: NSRect) {
            let cell = Grid.cell * scale
            let gap = Grid.gap * scale
            let step = cell + gap
            let blue = NSColor.systemBlue.withAlphaComponent(0.85)
            let fill = NSColor.systemBlue.withAlphaComponent(0.16)
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: max(9, min(22, 11 * scale)), weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            for row in 0..<Grid.rows {
                for col in 0..<Grid.cols {
                    let rect = NSRect(
                        x: CGFloat(col) * step - origin.x,
                        y: CGFloat(row) * step - origin.y,
                        width: cell,
                        height: cell
                    )
                    guard bounds.intersects(rect) else { continue }
                    fill.setFill()
                    blue.setStroke()
                    let path = NSBezierPath(roundedRect: rect, xRadius: 6 * scale, yRadius: 6 * scale)
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

/// Reports a view's screen rectangle. AppKit's origin is the bottom left, same as the grid.
private struct ScreenFrameReader: NSViewRepresentable {
    var onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> Reporter {
        let view = Reporter()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: Reporter, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }

    final class Reporter: NSView {
        var onChange: ((CGRect) -> Void)?
        private var last: CGRect = .null

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(report), name: NSWindow.didMoveNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(report), name: NSWindow.didResizeNotification, object: window)
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        @objc func report() {
            guard let window, bounds.width > 1, bounds.height > 1 else { return }
            let rect = window.convertToScreen(convert(bounds, to: nil))
            guard rect != last else { return }
            last = rect
            onChange?(rect)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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

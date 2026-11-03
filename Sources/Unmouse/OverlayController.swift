import AppKit
import SwiftUI
import UnmouseCore

@MainActor
final class OverlayController {
    private weak var model: AppModel?
    private var gridPanels: [NSPanel] = []
    private var freeDotPanel: NSPanel?
    private var hintPanel: NSPanel?
    private var coachPanel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func showGrid() {
        hideGrid()
        guard let model, let state = model.gridState else { return }
        let screens = NSScreen.screens
        guard screens.indices.contains(state.screenIndex) else { return }
        let screen = screens[state.screenIndex]
        let panel = makeOverlayPanel(frame: screen.frame)
        let view = GridOverlayView(model: model)
        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        gridPanels = [panel]
        applySelectionBlur(state: state, screen: screen)
    }

    func refreshGrid() {
        showGrid()
    }

    func hideGrid() {
        gridPanels.forEach { $0.orderOut(nil) }
        gridPanels = []
    }

    func showFreeDot() {
        if freeDotPanel == nil {
            let panel = makeOverlayPanel(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
            panel.contentView = NSHostingView(rootView: FreeDotView(model: model!))
            freeDotPanel = panel
        }
        moveFreeDot()
        freeDotPanel?.orderFrontRegardless()
    }

    func moveFreeDot() {
        guard let panel = freeDotPanel else { return }
        let mouse = NSEvent.mouseLocation
        let size: CGFloat = 40
        let offset: CGFloat = 14
        let frame = NSRect(x: mouse.x + offset, y: mouse.y - offset - 6, width: size, height: size)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func showHints() {
        hideHints()
        guard let model else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panel = makeOverlayPanel(frame: screen.frame)
        panel.contentView = NSHostingView(rootView: HintOverlayView(model: model))
        panel.orderFrontRegardless()
        hintPanel = panel
    }

    func refreshHints() {
        showHints()
    }

    func hideHints() {
        hintPanel?.orderOut(nil)
        hintPanel = nil
    }

    func updateCoach() {
        guard let model else { return }
        if model.coachEnabled || model.tutorial != nil {
            if coachPanel == nil {
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let frame = NSRect(x: screen.frame.minX + 16, y: screen.frame.minY + 16, width: 320, height: 160)
                let panel = makeOverlayPanel(frame: frame)
                panel.contentView = NSHostingView(rootView: CoachView(model: model))
                coachPanel = panel
            }
            coachPanel?.orderFrontRegardless()
        } else {
            coachPanel?.orderOut(nil)
            coachPanel = nil
        }
    }

    func hideAllOverlays(keepDrag: Bool) {
        hideGrid()
        hideHints()
        freeDotPanel?.orderOut(nil)
        if model?.mode != .free {
            freeDotPanel = nil
        }
        updateCoach()
    }

    private func makeOverlayPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        return panel
    }

    private func applySelectionBlur(state: GridState, screen: NSScreen) {
        // Visual dim/blur handled inside GridOverlayView via Canvas + material hole.
        _ = state
        _ = screen
    }
}

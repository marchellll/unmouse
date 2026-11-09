import AppKit
import ObjectiveC
import QuartzCore
import SwiftUI
import UnmouseCore

@MainActor
final class OverlayController {
    private weak var model: AppModel?
    private var gridPanels: [NSPanel] = []
    private var freeDotPanel: NSPanel?
    private var freeDotView: FreeDotView?
    private var hintPanel: NSPanel?
    private var coachPanel: NSPanel?
    private var gridShade: SelectionShadeView?
    private var gridLines: GridLinesView?
    private var gridGuide: GridGuideView?
    /// Re-pin CALayer compositingFilter — AppKit/SwiftUI clears it after a couple seconds.
    private var blendKeepalive: DispatchSourceTimer?

    init(model: AppModel) {
        self.model = model
    }

    func showGrid() {
        guard let model, let state = model.gridState else { return }
        let screens = NSScreen.screens
        guard screens.indices.contains(state.screenIndex) else { return }
        let screen = screens[state.screenIndex]

        let panel: NSPanel
        if let existing = gridPanels.first {
            panel = existing
            if panel.frame != screen.frame {
                panel.setFrame(screen.frame, display: true)
            }
        } else {
            panel = makeOverlayPanel(frame: screen.frame)
            gridPanels = [panel]
        }
        // NSPanel init always installs a content view, so a nil check never installs the grid.
        let bounds = NSRect(origin: .zero, size: panel.frame.size)
        let lines: GridLinesView
        if let existing = gridLines, existing.window === panel {
            lines = existing
        } else {
            let container = NSView(frame: bounds)
            container.wantsLayer = true
            container.layerUsesCoreImageFilters = true
            container.layer?.backgroundColor = NSColor.clear.cgColor
            container.autoresizingMask = [.width, .height]
            let shade = SelectionShadeView(frame: bounds)
            shade.autoresizingMask = [.width, .height]
            let created = GridLinesView(frame: bounds)
            created.autoresizingMask = [.width, .height]
            let guide = GridGuideView(frame: bounds)
            guide.autoresizingMask = [.width, .height]
            container.addSubview(shade)
            container.addSubview(created)
            container.addSubview(guide)
            panel.contentView = container
            gridShade = shade
            gridLines = created
            gridGuide = guide
            lines = created
        }
        gridShade?.frame = bounds
        lines.frame = bounds
        gridGuide?.frame = bounds
        panel.contentView?.layerUsesCoreImageFilters = true
        gridShade?.apply(
            state: model.gridState,
            dimHex: model.config.grid.selectionDim,
            blur: CGFloat(model.config.grid.selectionBlur)
        )
        syncGridContents()
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        startBlendKeepalive()
    }

    func refreshGrid() {
        showGrid()
    }

    func hideGrid() {
        gridShade = nil
        gridLines = nil
        gridGuide = nil
        gridPanels.forEach { $0.orderOut(nil) }
        gridPanels = []
        if freeDotPanel == nil || freeDotPanel?.isVisible != true {
            stopBlendKeepalive()
        }
    }

    func showFreeDot() {
        guard let model else { return }
        let size: CGFloat = 96
        if freeDotPanel == nil {
            let panel = makeOverlayPanel(frame: NSRect(x: 0, y: 0, width: size, height: size))
            let dot = FreeDotView(frame: NSRect(x: 0, y: 0, width: size, height: size))
            dot.autoresizingMask = [.width, .height]
            let wrapper = BlendHostView(frame: NSRect(x: 0, y: 0, width: size, height: size))
            wrapper.autoresizingMask = [.width, .height]
            dot.frame = wrapper.bounds
            wrapper.addSubview(dot)
            panel.contentView = wrapper
            freeDotView = dot
            freeDotPanel = panel
        }
        syncFreeDot(dragging: model.dragging)
        pinBlend(on: freeDotPanel, blend: model.config.colors.freeDotBlend)
        revealSystemCursor()
        if freeDotPanel?.isVisible != true {
            freeDotPanel?.orderFrontRegardless()
        }
        startBlendKeepalive()
    }

    /// Move the dot only when the pointer moved. No per-frame orderFront or redisplay.
    func syncFreeDot(dragging: Bool) {
        guard let model else { return }
        freeDotView?.apply(
            free: model.config.free,
            fillHex: model.config.colors.freeDot,
            haloHex: model.config.colors.freeDotHalo,
            dragging: dragging
        )
        moveFreeDot()
    }

    func moveFreeDot() {
        guard let panel = freeDotPanel, let model else { return }
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        // Dot is centered in a panel big enough for the pulse. Offset is Cartesian: +x right, +y up.
        let dx = CGFloat(model.config.free.haloOffset.x)
        let dy = CGFloat(model.config.free.haloOffset.y)
        let origin = NSPoint(
            x: mouse.x + dx - size.width / 2,
            y: mouse.y + dy - size.height / 2
        )
        let current = panel.frame.origin
        if abs(current.x - origin.x) < 0.5, abs(current.y - origin.y) < 0.5 { return }
        panel.setFrameOrigin(origin)
    }

    func showHints() {
        guard let model else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        if let panel = hintPanel {
            panel.setFrame(screen.frame, display: true)
            if panel.contentView == nil {
                panel.contentView = NSHostingView(rootView: HintOverlayView(model: model))
            }
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            return
        }
        let panel = makeOverlayPanel(frame: screen.frame)
        panel.contentView = NSHostingView(rootView: HintOverlayView(model: model))
        panel.orderFrontRegardless()
        hintPanel = panel
    }

    /// HintOverlayView observes model.nav — keep the panel and let SwiftUI redraw.
    func refreshHints() {
        guard hintPanel != nil else {
            showHints()
            return
        }
        // No panel rebuild: @Observable HintState / hintBubbles already drive the canvas.
    }

    func hideHints() {
        hintPanel?.orderOut(nil)
        hintPanel = nil
    }

    func hideFreeDot() {
        freeDotPanel?.orderOut(nil)
        freeDotPanel = nil
        freeDotView = nil
        if gridPanels.isEmpty {
            stopBlendKeepalive()
        }
    }

    func updateCoach() {
        guard let model else { return }

        // Tutorial lives on the practice window — don't park a second coach in the corner.
        // Coach only appears while a mode is active (shows what you can do next).
        let show = model.coachEnabled && model.tutorial.progress == nil && model.mode != .idle
        if show {
            if coachPanel == nil {
                let screen = NSScreen.main ?? NSScreen.screens[0]
                let frame = NSRect(x: screen.frame.minX + 16, y: screen.frame.minY + 16, width: 320, height: 120)
                let panel = makeOverlayPanel(frame: frame)
                panel.contentView = NSHostingView(rootView: CoachView(model: model))
                coachPanel = panel
            }
            if coachPanel?.isVisible != true {
                coachPanel?.orderFrontRegardless()
            }
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
            freeDotView = nil
        }
        stopBlendKeepalive()
        updateCoach()
    }

    /// Typing hides the cursor until the pointer moves. NSCursor only clears this app's hide count.
    /// A mouse-moved event clears the window-server flag. Do not CGWarp: that disables the event tap.
    func revealSystemCursor() {
        NSCursor.setHiddenUntilMouseMoves(false)
        PointerController.showCursor()
        DispatchQueue.main.async {
            NSCursor.setHiddenUntilMouseMoves(false)
            PointerController.showCursor()
        }
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
        panel.animationBehavior = .none
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.setFrame(frame, display: true)
        }
        return panel
    }

    private func blendHost(in panel: NSPanel) -> BlendHostView? {
        if let host = panel.contentView as? BlendHostView { return host }
        return panel.contentView?.subviews.first { $0 is BlendHostView } as? BlendHostView
    }

    /// Re-apply blend filters after settings edits (live grid / free-dot).
    func refreshAppearance() {
        guard model != nil else { return }
        syncGridContents()
        pinBlend(on: freeDotPanel, blend: model?.config.colors.freeDotBlend ?? .exclusion)
    }

    private func syncGridContents() {
        guard let model, let lines = gridLines, let state = model.gridState else { return }
        let nested = state.levels.count > 1
        let grid = model.config.grid
        lines.update(
            state: state,
            lineHex: model.config.colors.line,
            labelHex: nested ? grid.subLabel : model.config.colors.label,
            highlightHex: model.config.colors.highlight,
            fontName: grid.font,
            fontSize: nested ? CGFloat(grid.subFontSize) : nil,
            outlineHex: nested ? "#00000000" : grid.labelOutline,
            outlineWidth: nested ? 0 : CGFloat(grid.labelOutlineWidth),
            glowHex: nested ? grid.subGlow : "#00000000",
            glowRadius: nested ? CGFloat(grid.subGlowRadius) : 0
        )
        lines.applyBlend(model.config.colors.gridBlend)
        refreshGuide()
    }

    /// Aim-and-hit card. Sits above the grid lines and outside their blend, so the words stay readable.
    func refreshGuide() {
        guard let guide = gridGuide, let model, let state = model.gridState else {
            gridGuide?.clear()
            return
        }
        guard let click = model.tutorial.progress?.current?.gridGuide,
              let anchor = model.tutorial.guideAnchor, anchor.width > 1, anchor.height > 1
        else {
            guide.clear()
            return
        }
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        let screen = state.levels[0].origin
        guide.apply(cue: state.guide(at: point, click: click), screenOrigin: screen, avoid: anchor)
    }

    /// Keep compositingFilter forever — SwiftUI / AppKit clears it after ~2s otherwise.
    private func pinBlend(on panel: NSPanel?, blend: GridBlend) {
        guard let panel else { return }
        let filter = blend.layerFilterName
        if let wrapper = blendHost(in: panel) {
            wrapper.blendFilterName = filter
            wrapper.applyBlend()
            return
        }
        guard let view = panel.contentView else { return }
        view.wantsLayer = true
        view.layer?.compositingFilter = filter
    }

    private func startBlendKeepalive() {
        if blendKeepalive != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.35, repeating: 0.35)
        timer.setEventHandler { [weak self] in
            guard let self, let model = self.model else { return }
            // Full redraw would re-rasterize the letters. Only put the filter back if AppKit cleared it.
            self.gridLines?.applyBlend(model.config.colors.gridBlend)
            if self.freeDotPanel?.isVisible == true {
                self.pinBlend(on: self.freeDotPanel, blend: model.config.colors.freeDotBlend)
            }
        }
        timer.resume()
        blendKeepalive = timer
    }

    private func stopBlendKeepalive() {
        blendKeepalive?.cancel()
        blendKeepalive = nil
    }
}

/// Owns the desktop compositing filter so replacing the SwiftUI hosting view never drops it.
private final class BlendHostView: NSView {
    var blendFilterName: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var pinnedFilter: String?
    private var didPin = false

    func applyBlend() {
        wantsLayer = true
        layerUsesCoreImageFilters = true
        let desired = blendFilterName
        if didPin, pinnedFilter == desired {
            if desired == nil || layer?.compositingFilter != nil { return }
        }
        layer?.actions = ["compositingFilter": NSNull()]
        layer?.compositingFilter = desired
        pinnedFilter = desired
        didPin = true
    }

    override func layout() {
        super.layout()
        for sub in subviews {
            sub.frame = bounds
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyBlend()
    }
}

/// Dim + desktop blur with a sharp hole on the selected cell.
/// Lives outside the grid's exclusion blend, and updates as a layer so it shows on the same turn as the key.
private final class SelectionShadeView: NSView {
    private let backdrop: CALayer?
    private let dimLayer = CALayer()
    private let maskLayer = CAShapeLayer()
    private var hole: CGRect?
    private var appliedBlur: CGFloat = -1
    private var appliedDim = ""
    private var shadeOn = false

    override init(frame frameRect: NSRect) {
        if let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type {
            backdrop = cls.init()
        } else {
            backdrop = nil
        }
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        let freeze: [String: any CAAction] = [
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull(),
            "filters": NSNull(),
            "hidden": NSNull(),
            "backgroundColor": NSNull(),
            "path": NSNull(),
            "opacity": NSNull(),
        ]
        backdrop?.frame = bounds
        backdrop?.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backdrop?.actions = freeze
        backdrop?.setValue(true, forKey: "windowServerAware")
        backdrop?.setValue(false, forKey: "enabled")
        dimLayer.frame = bounds
        dimLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        dimLayer.actions = freeze
        maskLayer.actions = freeze
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = NSColor.white.cgColor
        layer?.mask = maskLayer
        if let backdrop {
            layer?.addSublayer(backdrop)
        }
        layer?.addSublayer(dimLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func apply(state: GridState?, dimHex: String, blur: CGFloat) {
        let nextHole = Self.hole(in: state)
        let dim = Self.cgColor(dimHex)
        let show = nextHole != nil && (blur > 0.5 || dim != nil)
        if show == shadeOn, nextHole == hole, dimHex == appliedDim, abs(blur - appliedBlur) < 0.1 {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadeOn = show
        hole = nextHole
        appliedDim = dimHex
        appliedBlur = blur

        if show, blur > 0.5, let filter = Self.blurFilter(radius: blur) {
            backdrop?.setValue(true, forKey: "enabled")
            backdrop?.filters = [filter]
        } else {
            backdrop?.setValue(false, forKey: "enabled")
            backdrop?.filters = nil
        }
        dimLayer.isHidden = !show || dim == nil
        dimLayer.backgroundColor = dim
        updateMask()
        CATransaction.commit()
        CATransaction.flush()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateMask()
        CATransaction.commit()
    }

    private func updateMask() {
        guard shadeOn, let hole, bounds.width > 1, bounds.height > 1 else {
            maskLayer.path = nil
            return
        }
        maskLayer.frame = CGRect(origin: .zero, size: bounds.size)
        let path = CGMutablePath()
        path.addRect(maskLayer.bounds)
        path.addRect(hole)
        maskLayer.path = path
    }

    private static func hole(in state: GridState?) -> CGRect? {
        guard let state else { return nil }
        let screen = state.levels[0]
        let target: CGRect
        if let frame = state.targetFrame {
            target = frame
        } else if state.levels.count > 1 {
            let level = state.currentLevel
            target = CGRect(origin: level.origin, size: level.size)
        } else {
            return nil
        }
        return CGRect(
            x: target.minX - screen.origin.x,
            y: target.minY - screen.origin.y,
            width: target.width,
            height: target.height
        )
    }

    private static func cgColor(_ hex: String) -> CGColor? {
        guard let color = Color(hex: hex) else { return nil }
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        guard ns.alphaComponent > 0.001 else { return nil }
        return ns.cgColor
    }

    /// ponytail: CABackdropLayer + CAFilter are private. Ceiling: a future OS drops them and only the dim remains. Upgrade path is NSVisualEffectView if a public blur-radius API appears.
    private static func blurFilter(radius: CGFloat) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") else { return nil }
        let sel = NSSelectorFromString("filterWithType:")
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector, NSString) -> NSObject
        let imp = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let filter = imp(cls, sel, "gaussianBlur")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }
}

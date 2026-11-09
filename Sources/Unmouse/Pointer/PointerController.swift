import AppKit
import CoreGraphics
import UnmouseCore

enum PointerController {
    /// Private source so a swallowed key or a previous delta is not inherited.
    /// Quartz fills delta Y from the position change and leaves delta X at 0, which drops left/right.
    private static let source: CGEventSource = {
        let source = CGEventSource(stateID: .privateState) ?? CGEventSource(stateID: .hidSystemState)!
        source.localEventsSuppressionInterval = 0
        return source
    }()

    /// Sub-pixel remainder. A frame under 1px must not vanish, and must not stick as a later delta.
    private static var pendingX: Double = 0
    private static var pendingY: Double = 0
    /// Last point we posted. mouseLocation lags, and a nudge or click that reads it puts the pointer back.
    private static var aim = PointerAim()

    static var location: CGPoint {
        aim.resolve(live: systemLocation)
    }

    private static var systemLocation: CGPoint {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CoordinateSpace.appKitToCGEvent(NSEvent.mouseLocation, primaryHeight: primaryH)
    }

    /// Clears "hidden until mouse moves" without warping. A lone +1 delta walks the pointer, so the nudge is paired.
    static func showCursor() {
        var p = location
        p.x += 1
        postMove(to: p, dx: 1, dy: 0, dragging: false)
        p.x -= 1
        postMove(to: p, dx: -1, dy: 0, dragging: false)
    }

    static func move(to point: CGPoint) {
        pendingX = 0
        pendingY = 0
        let here = location
        postMove(
            to: point,
            dx: Int64((point.x - here.x).rounded()),
            dy: Int64((point.y - here.y).rounded()),
            dragging: false
        )
    }

    /// AppKit screen point (origin bottom-left) → CGEvent global.
    static func move(toAppKit point: CGPoint) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        move(to: CoordinateSpace.appKitToCGEvent(point, primaryHeight: primaryH))
    }

    static func moveBy(dx: CGFloat, dy: CGFloat, dragging: Bool = false) {
        pendingX += Double(dx)
        pendingY += Double(dy)
        let ix = Int64(pendingX.rounded(.towardZero))
        let iy = Int64(pendingY.rounded(.towardZero))
        guard ix != 0 || iy != 0 else { return }
        pendingX -= Double(ix)
        pendingY -= Double(iy)
        var p = location
        p.x += CGFloat(ix)
        p.y += CGFloat(iy)
        postMove(to: p, dx: ix, dy: iy, dragging: dragging)
    }

    private static func postMove(to point: CGPoint, dx: Int64, dy: Int64, dragging: Bool) {
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: dx)
        event.setIntegerValueField(.mouseEventDeltaY, value: dy)
        send(event)
        aim.remember(live: systemLocation, point: point)
    }

    static func click(_ button: MouseButton, count: Int = 1, from: Int = 1) {
        let (downType, upType, cgButton) = mapping(button)
        let p = location
        InputTrace.log("click \(button.rawValue) at \(InputTrace.point(p))")
        let start = max(1, from)
        for i in start...max(start, count) {
            let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: p, mouseButton: cgButton)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            stampStill(down)
            send(down)
            let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: p, mouseButton: cgButton)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            stampStill(up)
            send(up)
        }
    }

    static func mouseDown(_ button: MouseButton = .left) {
        let (downType, _, cgButton) = mapping(button)
        let p = location
        InputTrace.log("drag down \(button.rawValue) at \(InputTrace.point(p))")
        let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: p, mouseButton: cgButton)
        stampStill(down)
        send(down)
    }

    static func mouseUp(_ button: MouseButton = .left) {
        let (_, upType, cgButton) = mapping(button)
        let p = location
        InputTrace.log("drag up \(button.rawValue) at \(InputTrace.point(p))")
        let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: p, mouseButton: cgButton)
        stampStill(up)
        send(up)
    }

    /// A click or a still drag must not replay the last move delta.
    private static func stampStill(_ event: CGEvent?) {
        event?.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event?.setIntegerValueField(.mouseEventDeltaY, value: 0)
    }

    /// Continuous pixel scroll. Line units only move after a whole line, which feels stuck.
    /// `command` keeps ⌘ on the event so the app treats a vertical scroll as zoom.
    static func scroll(dx: Double, dy: Double, command: Bool = false) {
        let ix = Int32(dx.rounded())
        let iy = Int32(dy.rounded())
        guard ix != 0 || iy != 0 else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: iy,
            wheel2: ix,
            wheel3: 0
        ) else { return }
        event.location = location
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(iy))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(ix))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(iy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(ix))
        // An unplaced scroll event carries a mouse delta and walks the cursor.
        event.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        send(event, flags: command ? .maskCommand : [])
    }

    /// Drop keyboard modifiers. The free-mode Option tap otherwise sticks, and an Option-click hides the app underneath.
    /// Scroll may keep Command so the focused app zooms.
    private static func send(_ event: CGEvent?, flags: CGEventFlags = []) {
        guard let event else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    static let marker: Int64 = 0x554E_4D53 // 'UNMS'

    static func isOurs(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    private static func mapping(_ button: MouseButton) -> (CGEventType, CGEventType, CGMouseButton) {
        switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        case .middle: (.otherMouseDown, .otherMouseUp, .center)
        }
    }
}

import AppKit
import CoreGraphics
import UnmouseCore

enum PointerController {
    private static let source = CGEventSource(stateID: .combinedSessionState)

    static var location: CGPoint {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CoordinateSpace.appKitToCGEvent(NSEvent.mouseLocation, primaryHeight: primaryH)
    }

    /// Clears "hidden until mouse moves" without warping. Absolute position stays put; the delta is what the window server notices.
    static func showCursor() {
        let point = location
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: 1)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
        send(event)
    }

    static func move(to point: CGPoint) {
        send(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    }

    static func moveBy(dx: CGFloat, dy: CGFloat, dragging: Bool = false) {
        var p = location
        p.x += dx
        p.y += dy
        if dragging {
            let event = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: p,
                mouseButton: .left
            )
            send(event)
        } else {
            move(to: p)
        }
    }

    static func click(_ button: MouseButton, count: Int = 1, from: Int = 1) {
        let (downType, upType, cgButton) = mapping(button)
        let p = location
        let start = max(1, from)
        for i in start...max(start, count) {
            let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: p, mouseButton: cgButton)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            send(down)
            let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: p, mouseButton: cgButton)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            send(up)
        }
    }

    static func mouseDown(_ button: MouseButton = .left) {
        let (downType, _, cgButton) = mapping(button)
        let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: location, mouseButton: cgButton)
        send(down)
    }

    static func mouseUp(_ button: MouseButton = .left) {
        let (_, upType, cgButton) = mapping(button)
        send(CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: location, mouseButton: cgButton))
    }

    static func dragMove() {
        send(CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: location, mouseButton: .left))
    }

    /// Continuous pixel scroll. Line units only move after a whole line, which feels stuck.
    static func scroll(dx: Double, dy: Double) {
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
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(iy))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(ix))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(iy))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(ix))
        send(event)
    }

    /// Drop keyboard modifiers. The free-mode Option tap otherwise sticks, and an Option-click hides the app underneath.
    private static func send(_ event: CGEvent?) {
        guard let event else { return }
        event.flags = []
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

extension CGPoint {
    func cgEventGlobal(primaryHeight: CGFloat) -> CGPoint {
        CoordinateSpace.appKitToCGEvent(self, primaryHeight: primaryHeight)
    }

    func appKit(primaryHeight: CGFloat) -> CGPoint {
        CoordinateSpace.cgEventToAppKit(self, primaryHeight: primaryHeight)
    }
}

extension NSEvent {
    var cgGlobalLocation: CGPoint {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return locationInWindow.appKitToCG(primary: h) // mouseLocation is AppKit already at screen
    }
}

private extension CGPoint {
    func appKitToCG(primary: CGFloat) -> CGPoint {
        CoordinateSpace.appKitToCGEvent(self, primaryHeight: primary)
    }
}

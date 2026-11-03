import AppKit
import CoreGraphics
import UnmouseCore

enum PointerController {
    private static let source = CGEventSource(stateID: .combinedSessionState)

    static var location: CGPoint {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        return CoordinateSpace.appKitToCGEvent(NSEvent.mouseLocation, primaryHeight: primaryH)
    }

    static func move(to point: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event?.post(tap: .cghidEventTap)
    }

    static func moveBy(dx: CGFloat, dy: CGFloat) {
        var p = location
        p.x += dx
        p.y += dy
        move(to: p)
    }

    static func click(_ button: MouseButton, count: Int = 1) {
        let (downType, upType, cgButton) = mapping(button)
        let p = location
        for i in 1...count {
            let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: p, mouseButton: cgButton)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            down?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: p, mouseButton: cgButton)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            up?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            up?.post(tap: .cghidEventTap)
        }
    }

    static func mouseDown(_ button: MouseButton = .left) {
        let (downType, _, cgButton) = mapping(button)
        let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: location, mouseButton: cgButton)
        down?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        down?.post(tap: .cghidEventTap)
    }

    static func mouseUp(_ button: MouseButton = .left) {
        let (_, upType, cgButton) = mapping(button)
        let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: location, mouseButton: cgButton)
        up?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        up?.post(tap: .cghidEventTap)
    }

    static func dragMove() {
        let event = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: location, mouseButton: .left)
        event?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event?.post(tap: .cghidEventTap)
    }

    static func scroll(dx: Int32, dy: Int32) {
        let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        event?.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event?.post(tap: .cghidEventTap)
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

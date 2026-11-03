import AppKit
import ApplicationServices
import UnmouseCore

struct AccessibilityHintSource: HintSource {
    func collect() async -> [HintTarget] {
        await Task.detached(priority: .userInitiated) {
            Self.collectSync()
        }.value
    }

    nonisolated private static func collectSync() -> [HintTarget] {
        guard AXIsProcessTrusted() else { return [] }
        let system = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let focusedApp
        else { return [] }

        let appEl = unsafeBitCast(focusedApp, to: AXUIElement.self)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        var window: CFTypeRef?
        let root: AXUIElement
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let window
        {
            root = unsafeBitCast(window, to: AXUIElement.self)
        } else {
            root = appEl
        }

        var results: [HintTarget] = []
        var count = 0
        walk(root, into: &results, count: &count, limit: 400)
        return results
    }

    nonisolated private static func walk(_ el: AXUIElement, into results: inout [HintTarget], count: inout Int, limit: Int) {
        guard count < limit else { return }
        if isPressable(el), let frame = frame(of: el), frame.width > 1, frame.height > 1 {
            let title = stringAttr(el, kAXTitleAttribute as CFString)
                ?? stringAttr(el, kAXDescriptionAttribute as CFString)
                ?? stringAttr(el, kAXRoleDescriptionAttribute as CFString)
                ?? ""
            let role = stringAttr(el, kAXRoleAttribute as CFString) ?? "el"
            let id = "\(role)-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(count)"
            results.append(HintTarget(id: id, title: title, frame: frame))
            count += 1
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
              let arr = children as? [AXUIElement]
        else { return }
        for child in arr {
            walk(child, into: &results, count: &count, limit: limit)
        }
    }

    nonisolated private static func isPressable(_ el: AXUIElement) -> Bool {
        var actions: CFArray?
        if AXUIElementCopyActionNames(el, &actions) == .success,
           let names = actions as? [String],
           names.contains(kAXPressAction as String)
        {
            return true
        }
        let role = stringAttr(el, kAXRoleAttribute as CFString) ?? ""
        let roles: Set<String> = [
            kAXButtonRole as String,
            "AXLink",
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
            kAXPopUpButtonRole as String,
            kAXComboBoxRole as String,
            kAXMenuItemRole as String,
            kAXTabGroupRole as String,
        ]
        return roles.contains(role)
    }

    nonisolated private static func frame(of el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        let posOK = AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        let sizeOK = AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard posOK, sizeOK else { return nil }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let appKitOrigin = CoordinateSpace.cgEventToAppKit(pos, primaryHeight: primaryH)
        let appKitY = appKitOrigin.y - size.height
        return CGRect(x: appKitOrigin.x, y: appKitY, width: size.width, height: size.height)
    }

    nonisolated private static func stringAttr(_ el: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return ref as? String
    }
}

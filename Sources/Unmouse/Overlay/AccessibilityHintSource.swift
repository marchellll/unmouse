import AppKit
import ApplicationServices
import UnmouseCore

struct AccessibilityHintSource: HintSource {
    func collect() async -> [HintTarget] {
        // Another app answers on its own threads, whoever asks. The wait stays off our main thread.
        let outside = await Task.detached(priority: .userInitiated) { Self.scanOtherApp() }.value
        switch outside {
        case .targets(let targets): return targets
        // Our own windows cannot be read through the system API: SwiftUI evaluates its bindings
        // on the calling thread, which trapped in `launchAtLoginBinding`. Read them in-process, on main.
        case .ownApp: return await MainActor.run { Self.scanOwnWindow() }
        }
    }

    private enum Scan: Sendable {
        case targets([HintTarget])
        case ownApp
    }

    nonisolated private static func scanOtherApp() -> Scan {
        guard AXIsProcessTrusted() else { return .targets([]) }
        let system = AXUIElementCreateSystemWide()
        prime(system)
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let focusedApp
        else { return .targets([]) }

        let appEl = unsafeDowncast(focusedApp as AnyObject, to: AXUIElement.self)
        var pid: pid_t = 0
        if AXUIElementGetPid(appEl, &pid) == .success, pid == ProcessInfo.processInfo.processIdentifier {
            return .ownApp
        }
        prime(appEl)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        var window: CFTypeRef?
        let root: AXUIElement
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let window
        {
            root = unsafeDowncast(window as AnyObject, to: AXUIElement.self)
        } else {
            root = appEl
        }

        var results: [HintTarget] = []
        var count = 0
        walk(root, into: &results, count: &count, limit: 400)
        return .targets(results)
    }

    /// ponytail: one timeout per element, not inherited. A stuck control costs 0.25s and is skipped. Ceiling is a 400-node tree of hung elements.
    nonisolated private static func prime(_ el: AXUIElement) {
        AXUIElementSetMessagingTimeout(el, 0.25)
    }

    nonisolated private static func walk(_ el: AXUIElement, into results: inout [HintTarget], count: inout Int, limit: Int) {
        guard count < limit else { return }
        prime(el)
        if isActionable(el), let frame = frame(of: el), isHintSized(frame) {
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

    // MARK: Own windows

    /// Frames from NSAccessibility are already screen points with a bottom-left origin, the same as `walk`.
    /// ponytail: roles only, no press-action fallback. Unmouse's own controls all carry a role from `actionableRoles`.
    @MainActor private static func scanOwnWindow() -> [HintTarget] {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return [] }
        var results: [HintTarget] = []
        var visited = 0
        walkOwn(window, into: &results, visited: &visited, limit: 400)
        return results
    }

    @MainActor private static func walkOwn(_ node: Any, into results: inout [HintTarget], visited: inout Int, limit: Int) {
        guard results.count < limit, visited < 4_000 else { return }
        visited += 1
        guard let element = node as? NSAccessibilityProtocol else { return }
        let role = element.accessibilityRole()?.rawValue ?? ""
        if actionableRoles.contains(role), !deniedRoles.contains(role),
           let owner = node as? NSAccessibilityElementProtocol
        {
            let frame = owner.accessibilityFrame()
            if isHintSized(frame) {
                let title = element.accessibilityTitle()
                    ?? element.accessibilityLabel()
                    ?? element.accessibilityRoleDescription()
                    ?? ""
                let id = "\(role)-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(results.count)"
                results.append(HintTarget(id: id, title: title, frame: frame))
            }
        }
        for child in element.accessibilityChildren() ?? [] {
            walkOwn(child, into: &results, visited: &visited, limit: limit)
        }
    }

    /// Buttons / tabs / links / menus — not every Electron text line.
    nonisolated private static let actionableRoles: Set<String> = [
        kAXButtonRole as String,
        "AXLink",
        kAXCheckBoxRole as String,
        kAXRadioButtonRole as String,
        kAXPopUpButtonRole as String,
        kAXComboBoxRole as String,
        kAXMenuItemRole as String,
        kAXMenuBarItemRole as String,
        kAXMenuButtonRole as String,
        "AXTab",
        "AXTabButton",
        kAXTabGroupRole as String,
        "AXToolbar",
        "AXToolbarButton",
        kAXDisclosureTriangleRole as String,
        "AXDecrementArrow",
        "AXIncrementArrow",
        kAXSliderRole as String,
        kAXColorWellRole as String,
        "AXSearchField",
        kAXTextFieldRole as String, // single-line fields only (sized below)
    ]

    nonisolated private static let deniedRoles: Set<String> = [
        kAXStaticTextRole as String,
        kAXTextAreaRole as String, // editor body / code lines
        "AXWebArea",
        kAXScrollAreaRole as String,
        kAXGroupRole as String,
        "AXSplitGroup",
        "AXList",
        "AXOutline",
        "AXTable",
        "AXRow",
        "AXCell",
        "AXLayoutArea",
        "AXLayoutItem",
        "AXParagraph",
        "AXInlineText",
        "AXText",
    ]

    nonisolated private static func isActionable(_ el: AXUIElement) -> Bool {
        let role = stringAttr(el, kAXRoleAttribute as CFString) ?? ""
        if deniedRoles.contains(role) { return false }
        if actionableRoles.contains(role) { return true }

        // Fallback: pressable + not a skinny full-width line (VS Code AX quirk).
        var actions: CFArray?
        guard AXUIElementCopyActionNames(el, &actions) == .success,
              let names = actions as? [String],
              names.contains(kAXPressAction as String)
        else { return false }
        return true
    }

    /// Drop code-line shaped rects and tiny noise; keep compact controls.
    nonisolated private static func isHintSized(_ frame: CGRect) -> Bool {
        guard frame.width > 4, frame.height > 4 else { return false }
        // Editor lines: short height, very wide.
        if frame.height <= 28, frame.width > 160 { return false }
        // Giant panes / whole editor surfaces.
        if frame.width > 800, frame.height > 200 { return false }
        return true
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

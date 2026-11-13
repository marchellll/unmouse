import AppKit
import ApplicationServices
import CoreGraphics
import UnmouseCore

struct AccessibilityHintSource: HintSource {
    /// Wait after `AXManualAccessibility` before walking the focused window.
    var scanSettleMs: Int

    init(scanSettleMs: Int = 200) {
        self.scanSettleMs = scanSettleMs
    }

    /// Installed and running apps. No accessibility calls, so a busy front app cannot delay launching WhatsApp.
    func launchTargets() async -> [HintTarget] {
        let snap = await MainActor.run { Self.snapshot() }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let targets = await Task.detached(priority: .userInitiated) {
            var results: [HintTarget] = []
            var seen = Set<String>()
            Self.collectApps(
                runningPaths: snap.apps.compactMap(\.path),
                into: &results,
                seen: &seen,
                deadline: .max
            )
            return results
        }.value
        InputTrace.log(
            "hint launches n=\(targets.count) ms=\((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)"
        )
        return targets
    }

    func collect() async -> [HintTarget] {
        // Snapshot AppKit on main — NSWorkspace / NSScreen are not safe in Task.detached.
        let settleMs = min(2_000, max(0, scanSettleMs))
        let deadline = Self.scanDeadline(extraMs: settleMs)
        let snap = await MainActor.run { Self.snapshot() }
        InputTrace.log("hint scan snap apps=\(snap.apps.count) primaryH=\(Int(snap.primaryHeight))")
        let outside = await Task.detached(priority: .userInitiated) {
            Self.scanOtherApp(snap: snap, deadline: deadline, settleMs: settleMs)
        }.value
        switch outside {
        case .targets(let targets):
            return targets
        case .ownApp:
            let own = await MainActor.run { Self.scanOwnWindow(primaryHeight: snap.primaryHeight, deadline: deadline) }
            return await Task.detached(priority: .userInitiated) {
                var results = own
                results.sort {
                    if $0.frame.maxY != $1.frame.maxY { return $0.frame.maxY > $1.frame.maxY }
                    return $0.frame.minX < $1.frame.minX
                }
                var seen = Set(own.map(\.id))
                let before = results.count
                let t0 = DispatchTime.now().uptimeNanoseconds
                Self.collectWindows(snap.apps, primaryHeight: snap.primaryHeight, into: &results, seen: &seen, deadline: deadline)
                InputTrace.log(
                    "hint scan windows +\(results.count - before) ms=\((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)"
                )
                if Self.timedOut(deadline) {
                    InputTrace.log("hint scan timeout n=\(results.count)")
                }
                return results
            }.value
        }
    }

    /// Stop the walk after this and keep whatever was collected.
    /// ponytail: checked between elements. One AX call can still spend its 0.25s messaging timeout past the budget.
    private static let scanBudgetNanos: UInt64 = 1_000_000_000

    private static func scanDeadline(extraMs: Int = 0) -> UInt64 {
        let extra = UInt64(max(0, extraMs)) * 1_000_000
        return DispatchTime.now().uptimeNanoseconds &+ scanBudgetNanos &+ extra
    }

    private static func timedOut(_ deadline: UInt64) -> Bool {
        DispatchTime.now().uptimeNanoseconds >= deadline
    }

    private enum Scan: Sendable {
        case targets([HintTarget])
        case ownApp
    }

    /// Running-app facts gathered on the main actor before the detached AX walk.
    private struct AppSnap: Sendable {
        let pid: pid_t
        let name: String
        let path: String?
    }

    private struct Snapshot: Sendable {
        let primaryHeight: CGFloat
        let apps: [AppSnap]
    }

    @MainActor private static func snapshot() -> Snapshot {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
        let byPid = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })

        // Front-to-back on-screen windows ≈ last-active order.
        var apps: [AppSnap] = []
        var seen = Set<pid_t>()
        if let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] {
            for entry in info {
                // Layer 0 = normal app windows; skip overlays / status items first.
                if let layer = entry[kCGWindowLayer as String] as? Int, layer != 0 { continue }
                guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                      seen.insert(pid).inserted,
                      let app = byPid[pid]
                else { continue }
                apps.append(
                    AppSnap(pid: pid, name: app.localizedName ?? "", path: app.bundleURL?.path)
                )
            }
        }
        // Running but no on-screen window yet — keep after the z-ordered ones.
        for app in running where seen.insert(app.processIdentifier).inserted {
            apps.append(
                AppSnap(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? "",
                    path: app.bundleURL?.path
                )
            )
        }
        return Snapshot(primaryHeight: primaryH, apps: apps)
    }

    nonisolated private static func scanOtherApp(snap: Snapshot, deadline: UInt64, settleMs: Int) -> Scan {
        let tAll = DispatchTime.now().uptimeNanoseconds
        guard AXIsProcessTrusted() else {
            InputTrace.log("hint scan abort — AX not trusted")
            return .targets([])
        }
        let system = AXUIElementCreateSystemWide()
        prime(system)
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let focusedApp
        else {
            InputTrace.log("hint scan abort — no focused app")
            return .targets([])
        }

        let appEl = unsafeDowncast(focusedApp as AnyObject, to: AXUIElement.self)
        var pid: pid_t = 0
        if AXUIElementGetPid(appEl, &pid) == .success, pid == ProcessInfo.processInfo.processIdentifier {
            InputTrace.log("hint scan own-app path")
            return .ownApp
        }
        prime(appEl)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // ponytail: Electron fills the AX tree after those flags. 200ms covers Obsidian's chrome; raise scan_settle_ms if a page is still thin.
        if settleMs > 0 {
            InputTrace.log("hint scan settle \(settleMs)ms")
            Thread.sleep(forTimeInterval: Double(settleMs) / 1000)
        }

        var windowRef: CFTypeRef?
        let window: AXUIElement?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowRef
        {
            window = unsafeDowncast(windowRef as AnyObject, to: AXUIElement.self)
        } else {
            window = nil
        }
        let windowFrame = window.flatMap { frame(of: $0, primaryHeight: snap.primaryHeight) } ?? .null

        var results: [HintTarget] = []
        var seen = Set<String>()
        var controlCount = 0
        var textCount = 0

        // Menu bar — separate budget so a large page cannot starve File/Edit.
        var t0 = DispatchTime.now().uptimeNanoseconds
        if let menuBar = copyElement(appEl, kAXMenuBarAttribute as CFString) {
            walkMenuBar(
                menuBar, primaryHeight: snap.primaryHeight,
                into: &results, seen: &seen, count: &controlCount, limit: 40, deadline: deadline
            )
        }
        InputTrace.log(
            "hint scan menubar n=\(controlCount) ms=\((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)"
        )

        if let window {
            t0 = DispatchTime.now().uptimeNanoseconds
            walkControls(
                window,
                windowFrame: windowFrame,
                primaryHeight: snap.primaryHeight,
                into: &results,
                seen: &seen,
                count: &controlCount,
                textCount: &textCount,
                limit: 500,
                textLimit: 300,
                deadline: deadline
            )
            collectLinks(
                window, windowFrame: windowFrame, primaryHeight: snap.primaryHeight,
                into: &results, seen: &seen, count: &controlCount, limit: 500, deadline: deadline
            )
            InputTrace.log(
                "hint scan window controls=\(controlCount) text=\(textCount) ms=\((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)"
            )
        } else {
            InputTrace.log("hint scan no focused window")
        }

        t0 = DispatchTime.now().uptimeNanoseconds
        let beforeMenus = results.count
        walkMenus(appEl, pid: pid, into: &results, seen: &seen, limit: 400, deadline: deadline)
        InputTrace.log(
            "hint scan menus +\(results.count - beforeMenus) ms=\((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)"
        )

        // Spatial sort for in-window UI only — windows/apps append in MRU order after.
        results.sort {
            if $0.frame.maxY != $1.frame.maxY { return $0.frame.maxY > $1.frame.maxY }
            return $0.frame.minX < $1.frame.minX
        }

        t0 = DispatchTime.now().uptimeNanoseconds
        let beforeWin = results.count
        collectWindows(snap.apps, primaryHeight: snap.primaryHeight, into: &results, seen: &seen, deadline: deadline)
        InputTrace.log(
            "hint scan windows +\(results.count - beforeWin) ms=\((DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)"
        )

        let totalMs = (DispatchTime.now().uptimeNanoseconds - tAll) / 1_000_000
        if timedOut(deadline) {
            InputTrace.log("hint scan timeout n=\(results.count) totalMs=\(totalMs)")
        } else {
            InputTrace.log("hint scan done n=\(results.count) totalMs=\(totalMs)")
        }
        return .targets(results)
    }

    /// ponytail: one timeout per element. A stuck control costs 0.25s and is skipped.
    nonisolated private static func prime(_ el: AXUIElement) {
        AXUIElementSetMessagingTimeout(el, 0.25)
    }

    nonisolated private static func walkControls(
        _ el: AXUIElement,
        windowFrame: CGRect,
        primaryHeight: CGFloat,
        into results: inout [HintTarget],
        seen: inout Set<String>,
        count: inout Int,
        textCount: inout Int,
        limit: Int,
        textLimit: Int,
        deadline: UInt64,
        depth: Int = 0
    ) {
        guard count < limit, depth < 40, !timedOut(deadline) else { return }
        prime(el)
        let role = stringAttr(el, kAXRoleAttribute as CFString) ?? ""

        if role == "AXWebArea" {
            ensureWebChildren(el)
        }

        if isActionable(el), let f = frame(of: el, primaryHeight: primaryHeight), isHintSized(f, windowFrame: windowFrame) {
            let title = resolveTitle(el)
            let subrole = stringAttr(el, kAXSubroleAttribute as CFString) ?? ""
            let id = dedupeKey(role: role, title: title, frame: f)
            if seen.insert(id).inserted {
                // Window AXDefaultButton is resolved separately; title heuristics cover common dialogs.
                let lower = title.lowercased()
                results.append(
                    HintTarget(
                        id: id,
                        title: title,
                        frame: f,
                        role: role,
                        action: .click,
                        showsLabel: true,
                        isDefault: lower == "ok" || lower == "yes",
                        isCancel: lower == "cancel" || lower == "no",
                        subrole: subrole
                    )
                )
                count += 1
            }
        } else if role == (kAXStaticTextRole as String) || role == "AXStaticText",
                  textCount < textLimit,
                  let f = frame(of: el, primaryHeight: primaryHeight),
                  isHintSized(f, windowFrame: windowFrame)
        {
            let title = resolveTitle(el)
            if !title.isEmpty, title.count <= 500 {
                let id = dedupeKey(role: "text", title: title, frame: f)
                if seen.insert(id).inserted {
                    results.append(
                        HintTarget(
                            id: id,
                            title: title,
                            frame: f,
                            role: role,
                            action: .click,
                            showsLabel: false
                        )
                    )
                    textCount += 1
                }
            }
        }

        guard !timedOut(deadline) else { return }
        var kids = children(of: el)
        if kids.isEmpty, role == "AXWebArea" {
            ensureWebChildren(el)
            kids = children(of: el)
        }
        for child in kids {
            walkControls(
                child, windowFrame: windowFrame, primaryHeight: primaryHeight, into: &results, seen: &seen,
                count: &count, textCount: &textCount, limit: limit, textLimit: textLimit,
                deadline: deadline, depth: depth + 1
            )
        }
    }

    nonisolated private static func collectLinks(
        _ root: AXUIElement,
        windowFrame: CGRect,
        primaryHeight: CGFloat,
        into results: inout [HintTarget],
        seen: inout Set<String>,
        count: inout Int,
        limit: Int,
        deadline: UInt64
    ) {
        func visit(_ el: AXUIElement, depth: Int) {
            guard count < limit, depth < 40, !timedOut(deadline) else { return }
            prime(el)
            if stringAttr(el, kAXRoleAttribute as CFString) == "AXWebArea" {
                ensureWebChildren(el)
                if let links = copyArray(el, "AXLinkUIElements" as CFString) {
                    for link in links {
                        guard count < limit, !timedOut(deadline) else { return }
                        prime(link)
                        guard let f = frame(of: link, primaryHeight: primaryHeight),
                              isHintSized(f, windowFrame: windowFrame) else { continue }
                        let title = resolveTitle(link)
                        let id = dedupeKey(role: "AXLink", title: title, frame: f)
                        if seen.insert(id).inserted {
                            results.append(
                                HintTarget(
                                    id: id,
                                    title: title,
                                    frame: f,
                                    role: "AXLink",
                                    action: .click,
                                    showsLabel: true
                                )
                            )
                            count += 1
                        }
                    }
                }
            }
            guard !timedOut(deadline) else { return }
            for child in children(of: el) {
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
    }

    nonisolated private static func walkMenuBar(
        _ el: AXUIElement,
        primaryHeight: CGFloat,
        into results: inout [HintTarget],
        seen: inout Set<String>,
        count: inout Int,
        limit: Int,
        deadline: UInt64
    ) {
        for child in children(of: el) {
            guard count < limit, !timedOut(deadline) else { return }
            prime(child)
            let role = stringAttr(child, kAXRoleAttribute as CFString) ?? ""
            guard role == (kAXMenuBarItemRole as String) else { continue }
            let title = resolveTitle(child)
            guard !title.isEmpty else { continue }
            let f = frame(of: child, primaryHeight: primaryHeight) ?? .zero
            let id = dedupeKey(role: role, title: title, frame: f)
            if seen.insert(id).inserted {
                results.append(
                    HintTarget(
                        id: id,
                        title: title,
                        frame: f,
                        role: role,
                        action: .click,
                        showsLabel: true
                    )
                )
                count += 1
            }
        }
    }

    nonisolated private static func walkMenus(
        _ appEl: AXUIElement,
        pid: pid_t,
        into results: inout [HintTarget],
        seen: inout Set<String>,
        limit: Int,
        deadline: UInt64
    ) {
        guard !timedOut(deadline), let menuBar = copyElement(appEl, kAXMenuBarAttribute as CFString) else { return }
        var count = 0
        func walk(_ el: AXUIElement, path: [String]) {
            guard count < limit, !timedOut(deadline) else { return }
            for child in children(of: el) {
                guard count < limit, !timedOut(deadline) else { return }
                prime(child)
                let role = stringAttr(child, kAXRoleAttribute as CFString) ?? ""
                let title = resolveTitle(child)
                if role == (kAXMenuItemRole as String), !title.isEmpty, !title.hasPrefix("–"), title != "-" {
                    let next = path + [title]
                    let id = "menu-\(pid)-\(next.joined(separator: "/"))"
                    if seen.insert(id).inserted {
                        results.append(
                            HintTarget(
                                id: id,
                                title: next.joined(separator: " › "),
                                frame: .zero,
                                role: role,
                                action: .menu(pid: pid, path: next),
                                showsLabel: false
                            )
                        )
                        count += 1
                    }
                    if let submenu = copyElement(child, kAXChildrenAttribute as CFString)
                        ?? children(of: child).first(where: {
                            stringAttr($0, kAXRoleAttribute as CFString) == (kAXMenuRole as String)
                        })
                    {
                        // Prefer walking child menus.
                        for m in children(of: child) where stringAttr(m, kAXRoleAttribute as CFString) == (kAXMenuRole as String) {
                            walk(m, path: next)
                        }
                        _ = submenu
                    } else {
                        for m in children(of: child) {
                            walk(m, path: next)
                        }
                    }
                } else if role == (kAXMenuBarItemRole as String) {
                    let next = title.isEmpty ? path : path + [title]
                    for m in children(of: child) {
                        walk(m, path: next)
                    }
                } else if role == (kAXMenuRole as String) {
                    walk(child, path: path)
                } else {
                    for m in children(of: child) {
                        walk(m, path: path)
                    }
                }
            }
        }
        walk(menuBar, path: [])
    }

    /// ponytail: backstop under the 1s scan budget. One stuck AX app is still 0.25s.
    private static let windowCap = 40
    /// ponytail: installed-app list is for fuzzy launch only; 150 is plenty.
    private static let appCap = 150

    /// `apps` must already be front-to-back (MRU). Emits one row per titled window in that order.
    nonisolated private static func collectWindows(
        _ apps: [AppSnap],
        primaryHeight: CGFloat,
        into results: inout [HintTarget],
        seen: inout Set<String>,
        deadline: UInt64
    ) {
        var added = 0
        for app in apps {
            guard added < windowCap, !timedOut(deadline) else { break }
            // Skip our own process — own windows are walked separately when needed.
            if app.pid == ProcessInfo.processInfo.processIdentifier { continue }
            let appEl = AXUIElementCreateApplication(app.pid)
            prime(appEl)
            guard let windows = copyArray(appEl, kAXWindowsAttribute as CFString) else { continue }
            for win in windows {
                guard added < windowCap, !timedOut(deadline) else { break }
                prime(win)
                let title = stringAttr(win, kAXTitleAttribute as CFString) ?? ""
                guard !title.isEmpty else { continue }
                let f = frame(of: win, primaryHeight: primaryHeight) ?? .zero
                let id = "window-\(app.pid)-\(title)"
                if seen.insert(id).inserted {
                    let appName = app.name
                    results.append(
                        HintTarget(
                            id: id,
                            title: appName.isEmpty ? title : "\(title) — \(appName)",
                            frame: f,
                            role: "AXWindow",
                            action: .window(pid: app.pid, title: title),
                            showsLabel: false
                        )
                    )
                    added += 1
                }
            }
        }
    }

    /// Running apps first (MRU paths), then installed-but-not-running A–Z.
    nonisolated private static func collectApps(
        runningPaths: [String],
        into results: inout [HintTarget],
        seen: inout Set<String>,
        deadline: UInt64
    ) {
        guard !timedOut(deadline) else { return }
        let dirs = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        var installed: [String] = []
        for dir in dirs {
            guard !timedOut(deadline) else { break }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                installed.append(dir + "/" + name)
            }
        }

        var paths: [String] = []
        var pathSeen = Set<String>()
        for path in runningPaths where pathSeen.insert(path).inserted {
            paths.append(path)
        }
        for path in installed.sorted() where pathSeen.insert(path).inserted {
            paths.append(path)
        }

        var added = 0
        for path in paths {
            guard added < appCap, !timedOut(deadline) else { break }
            let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let id = "app-\(path)"
            if seen.insert(id).inserted {
                results.append(
                    HintTarget(
                        id: id,
                        title: name,
                        frame: .zero,
                        role: "AXApplication",
                        action: .app(path: path),
                        showsLabel: false
                    )
                )
                added += 1
            }
        }
    }

    // MARK: Own windows

    /// Controls only — windows/apps merge happens off-main after this returns.
    @MainActor private static func scanOwnWindow(primaryHeight: CGFloat, deadline: UInt64) -> [HintTarget] {
        _ = primaryHeight
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return [] }
        var results: [HintTarget] = []
        var visited = 0
        var seen = Set<String>()
        walkOwn(window, into: &results, visited: &visited, seen: &seen, limit: 400, deadline: deadline)
        return results
    }

    @MainActor private static func walkOwn(
        _ node: Any,
        into results: inout [HintTarget],
        visited: inout Int,
        seen: inout Set<String>,
        limit: Int,
        deadline: UInt64
    ) {
        guard results.count < limit, visited < 4_000, !timedOut(deadline) else { return }
        visited += 1
        guard let element = node as? NSAccessibilityProtocol else { return }
        let role = element.accessibilityRole()?.rawValue ?? ""
        if actionableRoles.contains(role), !deniedRoles.contains(role),
           let owner = node as? NSAccessibilityElementProtocol
        {
            let frame = owner.accessibilityFrame()
            if isHintSized(frame, windowFrame: .null) {
                let title = element.accessibilityTitle()
                    ?? element.accessibilityLabel()
                    ?? element.accessibilityRoleDescription()
                    ?? ""
                let subrole = element.accessibilitySubrole()?.rawValue ?? ""
                let id = dedupeKey(role: role, title: title, frame: frame)
                if seen.insert(id).inserted {
                    results.append(
                        HintTarget(
                            id: id,
                            title: title,
                            frame: frame,
                            role: role,
                            action: .click,
                            showsLabel: true,
                            subrole: subrole
                        )
                    )
                }
            }
        }
        guard !timedOut(deadline) else { return }
        for child in element.accessibilityChildren() ?? [] {
            walkOwn(child, into: &results, visited: &visited, seen: &seen, limit: limit, deadline: deadline)
        }
    }

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
        kAXTextFieldRole as String,
    ]

    nonisolated private static let deniedRoles: Set<String> = [
        kAXStaticTextRole as String,
        kAXTextAreaRole as String,
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
        var actions: CFArray?
        guard AXUIElementCopyActionNames(el, &actions) == .success,
              let names = actions as? [String],
              names.contains(kAXPressAction as String)
        else { return false }
        // Skip containers that claim press.
        if role == kAXGroupRole as String || role == "AXWebArea" || role == kAXScrollAreaRole as String {
            return false
        }
        return true
    }

    nonisolated private static func isHintSized(_ frame: CGRect, windowFrame: CGRect) -> Bool {
        guard frame.width > 4, frame.height > 4 else { return false }
        if !windowFrame.isNull, !windowFrame.isEmpty {
            if !frame.intersects(windowFrame.insetBy(dx: -2, dy: -2)) { return false }
            // Drop frames that cover most of the window.
            if frame.width > windowFrame.width * 0.9, frame.height > windowFrame.height * 0.9 {
                return false
            }
        } else {
            if frame.width > 1200, frame.height > 800 { return false }
        }
        return true
    }

    nonisolated private static func ensureWebChildren(_ el: AXUIElement) {
        AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    nonisolated private static func resolveTitle(_ el: AXUIElement) -> String {
        if let t = stringAttr(el, kAXTitleAttribute as CFString), !t.isEmpty { return t }
        if let t = stringAttr(el, kAXDescriptionAttribute as CFString), !t.isEmpty { return t }
        if let t = stringAttr(el, kAXValueAttribute as CFString), !t.isEmpty { return t }
        // Link title often lives on a static-text child.
        for child in children(of: el) {
            let role = stringAttr(child, kAXRoleAttribute as CFString) ?? ""
            if role == (kAXStaticTextRole as String) {
                if let t = stringAttr(child, kAXValueAttribute as CFString) ?? stringAttr(child, kAXTitleAttribute as CFString),
                   !t.isEmpty
                {
                    return t
                }
            }
        }
        return stringAttr(el, kAXRoleDescriptionAttribute as CFString) ?? ""
    }

    nonisolated private static func dedupeKey(role: String, title: String, frame: CGRect) -> String {
        let qx = Int(frame.origin.x / 4) * 4
        let qy = Int(frame.origin.y / 4) * 4
        return "\(role)|\(title)|\(qx)|\(qy)|\(Int(frame.width))|\(Int(frame.height))"
    }

    nonisolated private static func frame(of el: AXUIElement, primaryHeight: CGFloat) -> CGRect? {
        prime(el)
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
        let appKitOrigin = CoordinateSpace.cgEventToAppKit(pos, primaryHeight: primaryHeight)
        let appKitY = appKitOrigin.y - size.height
        return CGRect(x: appKitOrigin.x, y: appKitY, width: size.width, height: size.height)
    }

    nonisolated private static func stringAttr(_ el: AXUIElement, _ attr: CFString) -> String? {
        prime(el)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return ref as? String
    }

    nonisolated private static func children(of el: AXUIElement) -> [AXUIElement] {
        prime(el)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
              let arr = children as? [AXUIElement]
        else { return [] }
        return arr
    }

    nonisolated private static func copyElement(_ el: AXUIElement, _ attr: CFString) -> AXUIElement? {
        prime(el)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success, let ref else { return nil }
        return unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
    }

    nonisolated private static func copyArray(_ el: AXUIElement, _ attr: CFString) -> [AXUIElement]? {
        prime(el)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return ref as? [AXUIElement]
    }
}

// MARK: - Hint activation helpers

enum HintActivator {
    static func perform(_ target: HintTarget, button: MouseButton?) {
        switch target.action {
        case .click:
            guard !target.frame.isEmpty else { return }
            moveTo(target.frame)
            if let button {
                PointerController.click(button)
            }
        case .menu(let pid, let path):
            pressMenu(pid: pid, path: path)
        case .window(let pid, let title):
            raiseWindow(pid: pid, title: title)
        case .app(let path):
            // Launch Services. `NSRunningApplication.activate()` waits on that app's main thread.
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    static func moveTo(_ frame: CGRect) {
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let cg = CoordinateSpace.appKitToCGEvent(
            CGPoint(x: frame.midX, y: frame.midY),
            primaryHeight: primaryH
        )
        PointerController.move(to: cg)
    }

    private static func pressMenu(pid: pid_t, path: [String]) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let menuBar = copyAttr(app, kAXMenuBarAttribute as CFString) else { return }
        var current: AXUIElement = menuBar
        for (i, title) in path.enumerated() {
            let kids = children(of: current)
            guard let item = kids.first(where: { resolveTitle($0) == title })
                    ?? kids.first(where: { resolveTitle($0).localizedCaseInsensitiveCompare(title) == .orderedSame })
            else { return }
            if i == path.count - 1 {
                AXUIElementPerformAction(item, kAXPressAction as CFString)
                return
            }
            // Open the submenu by pressing, then find the menu among children.
            AXUIElementPerformAction(item, kAXPressAction as CFString)
            if let menu = children(of: item).first(where: {
                stringAttr($0, kAXRoleAttribute as CFString) == (kAXMenuRole as String)
            }) {
                current = menu
            } else {
                current = item
            }
        }
    }

    private static func raiseWindow(pid: pid_t, title: String) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
        let appEl = AXUIElementCreateApplication(pid)
        guard let windows = copyArray(appEl, kAXWindowsAttribute as CFString) else { return }
        for win in windows {
            let t = stringAttr(win, kAXTitleAttribute as CFString) ?? ""
            if t == title {
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                return
            }
        }
    }

    private static func resolveTitle(_ el: AXUIElement) -> String {
        stringAttr(el, kAXTitleAttribute as CFString)
            ?? stringAttr(el, kAXDescriptionAttribute as CFString)
            ?? ""
    }

    private static func stringAttr(_ el: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func children(of el: AXUIElement) -> [AXUIElement] {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
              let arr = children as? [AXUIElement]
        else { return [] }
        return arr
    }

    private static func copyAttr(_ el: AXUIElement, _ attr: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success, let ref else { return nil }
        return unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
    }

    private static func copyArray(_ el: AXUIElement, _ attr: CFString) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success else { return nil }
        return ref as? [AXUIElement]
    }
}

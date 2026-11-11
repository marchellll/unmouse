import AppKit
import ApplicationServices

/// Moves the pointer when the focused window changes.
/// Listens for app activation, Space changes, and each app's focused-window notification.
/// ponytail: apps that never post those Accessibility notifications are missed. A CGWindow poll would catch them.
@MainActor
final class FocusFollow {
    private var enabled = false
    /// True after a start attempt made while Accessibility was already trusted.
    private var attached = false
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var onFocus: (() -> Void)?
    private var coalesce = false

    func setEnabled(_ on: Bool, handler: @escaping () -> Void) {
        onFocus = handler
        guard on != enabled else { return }
        enabled = on
        if on {
            attached = AXIsProcessTrusted()
            start()
        } else {
            attached = false
            stop()
        }
    }

    /// Observers created while Accessibility is off never fire. Attach once it is granted.
    func rewatchIfEnabled() {
        guard enabled, !attached, AXIsProcessTrusted() else { return }
        stop()
        start()
        attached = true
    }

    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let pid = Self.pid(from: note) else { return }
            Task { @MainActor in self?.watchPid(pid) }
        })
        tokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let pid = Self.pid(from: note) else { return }
            Task { @MainActor in self?.unwatch(pid) }
        })
        tokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.note()
        })
        tokens.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.note()
        })
        let selfPid = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != selfPid {
            watch(app)
        }
    }

    private func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
        for (pid, observer) in observers {
            let element = AXUIElementCreateApplication(pid)
            AXObserverRemoveNotification(observer, element, kAXFocusedWindowChangedNotification as CFString)
            AXObserverRemoveNotification(observer, element, kAXMainWindowChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
    }

    private nonisolated static func pid(from note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    private func watchPid(_ pid: pid_t) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) else { return }
        watch(app)
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        guard app.activationPolicy != .prohibited else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, Self.axCallback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notes = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]
        let added = notes.contains {
            AXObserverAddNotification(observer, element, $0 as CFString, refcon) == .success
        }
        guard added else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func unwatch(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        let element = AXUIElementCreateApplication(pid)
        AXObserverRemoveNotification(observer, element, kAXFocusedWindowChangedNotification as CFString)
        AXObserverRemoveNotification(observer, element, kAXMainWindowChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// C callback. Hops to the main actor; the class is isolated there.
    private nonisolated static let axCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        Unmanaged<FocusFollow>.fromOpaque(refcon).takeUnretainedValue().note()
    }

    nonisolated private func note() {
        Task { @MainActor [weak self] in
            self?.schedule()
        }
    }

    private func schedule() {
        guard enabled, !coalesce else { return }
        coalesce = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.coalesce = false
            guard self.enabled else { return }
            self.onFocus?()
        }
    }
}

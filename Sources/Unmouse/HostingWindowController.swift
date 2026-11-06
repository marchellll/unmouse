import AppKit
import SwiftUI

/// Shared singleton window host for Settings, Walkthrough, and Practice.
@MainActor
final class HostingWindowController<Content: View> {
    private var window: NSWindow?
    private let title: String
    private let styleMask: NSWindow.StyleMask
    private let contentSize: NSSize
    private let place: ((NSWindow) -> Void)?
    private let activate: Bool

    init(
        title: String,
        contentSize: NSSize,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable],
        activate: Bool = true,
        place: ((NSWindow) -> Void)? = nil
    ) {
        self.title = title
        self.contentSize = contentSize
        self.styleMask = styleMask
        self.activate = activate
        self.place = place
    }

    func show(rootView: Content) {
        if window == nil {
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.title = title
            window.styleMask = styleMask
            window.setContentSize(contentSize)
            window.isReleasedWhenClosed = false
            if place == nil {
                window.center()
            }
            self.window = window
        }
        if let place, let window {
            place(window)
        }
        window?.makeKeyAndOrderFront(nil)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func close() {
        window?.orderOut(nil)
    }

    var frame: NSRect? { window?.frame }
    var isVisible: Bool { window?.isVisible == true }
    var nsWindow: NSWindow? { window }
}

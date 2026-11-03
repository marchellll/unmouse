import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coachTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.start()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let hosting = NSHostingView(rootView: StatusIconView(model: model))
            hosting.frame = NSRect(x: 0, y: 0, width: 22, height: 22)
            button.addSubview(hosting)
            button.frame = hosting.frame
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 280, height: 420)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        popover = pop

        coachTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncWindows()
            }
        }

        syncWindows()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshPermissions()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func syncWindows() {
        if model.showWalkthrough {
            WalkthroughWindowController.shared.show(model: model)
        } else {
            WalkthroughWindowController.shared.close()
        }
        model.overlayController?.updateCoach()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

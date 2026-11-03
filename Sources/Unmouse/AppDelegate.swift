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

        // squareLength — never assign button.frame; that detaches the item from the
        // menu bar and makes the popover anchor float mid-screen.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in true }
            button.image?.isTemplate = true
            let hosting = NSHostingView(rootView: StatusIconView(model: model))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                hosting.widthAnchor.constraint(equalToConstant: 18),
                hosting.heightAnchor.constraint(equalToConstant: 18),
            ])
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        let host = NSHostingController(rootView: PopoverView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        pop.contentViewController = host
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
            // minY = below the status button (toward the desktop).
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

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem?
    private var coachTimer: Timer?
    private let statusTag = 1

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.start()

        // squareLength — never assign button.frame; that detaches the item from the menu bar.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in true }
            button.image?.isTemplate = true
            let hosting = StatusIconHost(rootView: StatusIconView(model: model))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                hosting.widthAnchor.constraint(equalToConstant: 18),
                hosting.heightAnchor.constraint(equalToConstant: 18),
            ])
        }
        item.menu = makeMenu()
        statusItem = item

        coachTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncWindows()
            }
        }

        syncWindows()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let name = NSMenuItem(title: "Unmouse", action: nil, keyEquivalent: "")
        name.isEnabled = false
        menu.addItem(name)

        let status = NSMenuItem(title: model.mode.rawValue.capitalized, action: nil, keyEquivalent: "")
        status.tag = statusTag
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: statusTag)?.title = model.mode.rawValue.capitalized
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.show(model: model)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
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

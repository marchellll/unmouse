import AppKit
import QuartzCore

@MainActor
final class DisplayLinkDriver: NSObject {
    private var link: CADisplayLink?
    var onTick: ((TimeInterval) -> Void)?

    func start() {
        stop()
        guard let screen = NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        onTick?(link.duration)
    }
}

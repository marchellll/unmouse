import AppKit
import Observation
import UnmouseCore

@Observable
@MainActor
final class TutorialModel {
    var progress: TutorialProgress?
    var coachEnabled = false
    /// Screen rect of the practice target the grid guide aims at. AppKit coordinates.
    var guideAnchor: CGRect?
    /// Puck travel while the hold-click key is down. The arena copies this into its offset.
    var puckNudge: CGSize = .zero
    /// Copied onto each session so prompts name the keys in the live config.
    var bindings: BindingsConfig = .init()

    /// Weak back-reference so the arena can still drive notes; AppModel owns overlays.
    weak var app: AppModel?

    func start(_ session: TutorialSessionID) {
        app?.nav.releaseStaleHolds()
        progress = TutorialProgress(session: session, bindings: bindings)
        coachEnabled = false
        guideAnchor = nil
        puckNudge = .zero
        InputTrace.log("tutorial start \(session.rawValue) step=\(progress?.current?.id ?? "-")")
        if let app {
            TutorialArenaController.shared.show(model: app)
        }
        app?.overlayController?.updateCoach()
        app?.overlayController?.refreshGuide()
    }

    func setGuideAnchor(_ rect: CGRect?) {
        let next = rect.flatMap { $0.width > 1 && $0.height > 1 ? $0 : nil }
        guard next != guideAnchor else { return }
        guideAnchor = next
        app?.overlayController?.refreshGuide()
    }

    func skip() {
        let session = progress?.session.rawValue ?? "-"
        let step = progress?.current?.id ?? "-"
        _ = progress?.handle(.skipped)
        InputTrace.log("tutorial skip \(session) at \(step)")
        finishSession()
    }

    func move(by delta: Int) {
        guard var t = progress else { return }
        let from = t.current?.id ?? "-"
        guard t.move(delta) else { return }
        progress = t
        InputTrace.log("tutorial move \(t.session.rawValue) \(from) → \(t.current?.id ?? "-")")
    }

    func resetPuckNudge() {
        guard puckNudge != .zero else { return }
        puckNudge = .zero
    }

    /// Pointer moved while the drag button is down on the puck step.
    func nudgePuck(dx: CGFloat, dy: CGFloat) {
        let next = PuckDrop.nudge(puckNudge, dx: dx, dy: dy, onDragStep: progress?.arenaFocus == .drag)
        guard next != puckNudge else { return }
        puckNudge = next
    }

    /// Called every free-mode frame. Writes only when the displayed tenth changes.
    func showSpeedTenthsLeft(_ tenths: Int?) {
        guard var t = progress, t.speedTenthsLeft != tenths else { return }
        t.setSpeedTenthsLeft(tenths)
        progress = t
    }

    func note(_ event: TutorialEvent) {
        guard var t = progress else { return }
        let step = t.current?.id ?? (t.completed ? "done" : "-")
        let before = t
        let advanced = t.handle(event)
        let changed = t != before
        if changed || !Self.quiet(event) {
            let next = t.completed ? "done" : (t.current?.id ?? "-")
            let how = changed ? (advanced ? "→ \(next)" : "partial") : "ignore"
            let credit = t.creditNote
            let extra = credit.isEmpty ? "" : " \(credit)"
            InputTrace.log("tutorial \(step) \(event.logLabel) \(how)\(extra)")
        }
        guard changed else { return }
        progress = t
        app?.overlayController?.refreshGuide()
        if advanced, t.completed {
            finishSession()
        }
    }

    /// Steer, move, and scroll fire on every key. Log them only when credit changes.
    private static func quiet(_ event: TutorialEvent) -> Bool {
        switch event {
        case .steered, .moved, .scrolled: true
        default: false
        }
    }

    func use(_ bindings: BindingsConfig) {
        self.bindings = bindings
        guard var t = progress else { return }
        t.bindings = bindings
        progress = t
    }

    func finishSession() {
        guard let t = progress else { return }
        InputTrace.log("tutorial done \(t.session.rawValue) next=\(t.session.next?.rawValue ?? "none")")
        var done = completedSessions()
        done.insert(t.session)
        saveCompletedSessions(done)
        if let next = t.session.next {
            progress = TutorialProgress(session: next, bindings: bindings)
            if let app {
                TutorialArenaController.shared.show(model: app)
            }
        } else {
            progress = nil
            coachEnabled = false
            guideAnchor = nil
            TutorialArenaController.shared.close()
            app?.overlayController?.updateCoach()
        }
        app?.overlayController?.refreshGuide()
    }

    func completedSessions() -> Set<TutorialSessionID> {
        let raw = UserDefaults.standard.stringArray(forKey: "tutorialCompleted") ?? []
        return Set(raw.compactMap(TutorialSessionID.init(rawValue:)))
    }

    private func saveCompletedSessions(_ set: Set<TutorialSessionID>) {
        UserDefaults.standard.set(set.map(\.rawValue), forKey: "tutorialCompleted")
    }
}

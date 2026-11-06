import AppKit
import Observation
import UnmouseCore

@Observable
@MainActor
final class TutorialModel {
    var progress: TutorialProgress?
    var coachEnabled = false

    /// Weak back-reference so the arena can still drive notes; AppModel owns overlays.
    weak var app: AppModel?

    func start(_ session: TutorialSessionID) {
        app?.nav.releaseStaleHolds()
        progress = TutorialProgress(session: session)
        coachEnabled = false
        if let app {
            TutorialArenaController.shared.show(model: app)
        }
        app?.overlayController?.updateCoach()
    }

    func skip() {
        _ = progress?.handle(.skipped)
        finishSession()
    }

    func note(_ event: TutorialEvent) {
        guard var t = progress else { return }
        let before = t
        let advanced = t.handle(event)
        guard t != before else { return }
        progress = t
        if advanced, t.completed {
            finishSession()
        }
    }

    func finishSession() {
        guard let t = progress else { return }
        var done = completedSessions()
        done.insert(t.session)
        saveCompletedSessions(done)
        if let next = t.session.next {
            progress = TutorialProgress(session: next)
            if let app {
                TutorialArenaController.shared.show(model: app)
            }
        } else {
            progress = nil
            coachEnabled = false
            TutorialArenaController.shared.close()
            app?.overlayController?.updateCoach()
        }
    }

    func completedSessions() -> Set<TutorialSessionID> {
        let raw = UserDefaults.standard.stringArray(forKey: "tutorialCompleted") ?? []
        return Set(raw.compactMap(TutorialSessionID.init(rawValue:)))
    }

    private func saveCompletedSessions(_ set: Set<TutorialSessionID>) {
        UserDefaults.standard.set(set.map(\.rawValue), forKey: "tutorialCompleted")
    }
}

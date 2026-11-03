import Testing
@testable import UnmouseCore

@Suite("Tutorial")
struct TutorialTests {
    @Test func advancesOnlyOnMatchingEvent() {
        var progress = TutorialProgress(session: .aimAndHit)
        var ok = progress.handle(.moved)
        #expect(!ok)
        ok = progress.handle(.enteredGrid)
        #expect(ok && progress.stepIndex == 1)
        ok = progress.handle(.typedGridCell)
        #expect(ok)
        ok = progress.handle(.leftClick)
        #expect(ok)
        ok = progress.handle(.typedGridCell)
        #expect(ok)
        ok = progress.handle(.rightClick)
        #expect(ok && progress.completed)
    }

    @Test func fourSessionsHaveSteps() {
        for session in TutorialSessionID.allCases {
            #expect(!TutorialCatalog.steps(for: session).isEmpty)
        }
    }

    @Test func skipCompletes() {
        var progress = TutorialProgress(session: .hintMode)
        let ok = progress.handle(.skipped)
        #expect(ok && progress.completed)
    }

    @Test func keyDeduper() {
        let deduper = KeyDeduper(windowMillis: 50)
        #expect(deduper.shouldHandle(token: "h", down: true, nowNanos: 1_000))
        #expect(!deduper.shouldHandle(token: "h", down: true, nowNanos: 2_000))
        #expect(deduper.shouldHandle(token: "h", down: true, nowNanos: 100_000_000))
    }
}

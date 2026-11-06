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
        ok = progress.handle(.hitLeftTarget)
        #expect(ok)
        ok = progress.handle(.typedGridCell)
        #expect(ok)
        ok = progress.handle(.hitRightTarget)
        #expect(ok && progress.completed)
    }

    @Test func steerStepNeedsEveryDirection() {
        var progress = TutorialProgress(session: .freeOnly)
        var ok = progress.handle(.enteredFree)
        #expect(ok && progress.stepIndex == 1)
        ok = progress.handle(.steered(.left))
        #expect(!ok)
        ok = progress.handle(.steered(.left))
        #expect(!ok)
        ok = progress.handle(.steered(.down))
        #expect(!ok)
        ok = progress.handle(.steered(.up))
        #expect(!ok && progress.stepIndex == 1)
        ok = progress.handle(.steered(.right))
        #expect(ok && progress.stepIndex == 2)
    }

    @Test func aimThenActKeepsOptionOnTheCellScreen() {
        var progress = TutorialProgress(session: .aimThenAct)
        var ok = progress.handle(.enteredGrid)
        #expect(ok && progress.stepIndex == 1)
        #expect(progress.current?.detail == "Then ⌥ — drop into free mode.")
        ok = progress.handle(.gridToFree)
        #expect(!ok && progress.stepIndex == 1)
        ok = progress.handle(.typedGridCell)
        #expect(!ok && progress.stepIndex == 1)
        ok = progress.handle(.gridToFree)
        #expect(ok && progress.stepIndex == 2)
        #expect(progress.current?.prompt == "Nudge onto the target with H J K L.")
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

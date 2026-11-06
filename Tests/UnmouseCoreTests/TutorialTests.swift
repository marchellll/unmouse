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

    @Test func scrollStepNeedsEveryDirection() {
        var progress = TutorialProgress(session: .freeOnly, stepIndex: 6)
        #expect(progress.current?.required == .scrolledAll)
        var ok = progress.handle(.scrolled(.left))
        #expect(!ok && progress.stepIndex == 6)
        ok = progress.handle(.scrolled(.left))
        #expect(!ok)
        ok = progress.handle(.scrolled(.down))
        #expect(!ok)
        ok = progress.handle(.scrolled(.up))
        #expect(!ok)
        ok = progress.handle(.hitLeftTarget)
        #expect(!ok && progress.stepIndex == 6)
        ok = progress.handle(.scrolled(.right))
        #expect(ok && progress.stepIndex == 7)
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

    @Test func speedStepsAdvanceOnlyAfterASecondOfMovement() {
        var progress = TutorialProgress(session: .freeOnly)
        var ok = progress.handle(.enteredFree)
        #expect(ok)
        for direction in MoveDirection.allCases {
            _ = progress.handle(.steered(direction))
        }
        #expect(progress.stepIndex == 2 && progress.current?.required == .heldFaster)

        ok = progress.observeSpeed(faster: true, slower: false, moved: false, dt: 1)
        #expect(!ok)
        ok = progress.observeSpeed(faster: false, slower: false, moved: true, dt: 1)
        #expect(!ok)
        ok = progress.observeSpeed(faster: true, slower: false, moved: true, dt: 0.5)
        #expect(!ok)
        ok = progress.observeSpeed(faster: true, slower: false, moved: false, dt: 1)
        #expect(!ok && progress.stepIndex == 2)
        ok = progress.observeSpeed(faster: true, slower: false, moved: true, dt: 0.5)
        #expect(!ok)
        ok = progress.observeSpeed(faster: true, slower: false, moved: true, dt: 0.5)
        #expect(ok && progress.stepIndex == 3 && progress.current?.required == .heldSlower)

        ok = progress.observeSpeed(faster: true, slower: false, moved: true, dt: 2)
        #expect(!ok)
        ok = progress.observeSpeed(faster: false, slower: true, moved: true, dt: 0.5)
        #expect(!ok)
        ok = progress.observeSpeed(faster: false, slower: true, moved: true, dt: 0.5)
        #expect(ok && progress.current?.required == .hitLeftTarget)
    }

    @Test func skipCompletes() {
        var progress = TutorialProgress(session: .hintMode)
        let ok = progress.handle(.skipped)
        #expect(ok && progress.completed)
    }

    @Test func movedOnSteerStepLeavesProgressEqual() {
        var progress = TutorialProgress(session: .freeOnly)
        _ = progress.handle(.enteredFree)
        #expect(progress.stepIndex == 1)
        let before = progress
        let advanced = progress.handle(.moved)
        #expect(!advanced)
        #expect(progress == before)
    }
}

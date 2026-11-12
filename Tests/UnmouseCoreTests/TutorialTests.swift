import CoreGraphics
import Testing
@testable import UnmouseCore

@Suite("Tutorial")
struct TutorialTests {
    @Test func advancesOnlyOnMatchingEvent() {
        var progress = TutorialProgress(session: .aimAndHit)
        #expect(progress.steps.count == 2)
        #expect(progress.current?.gridGuide == .left)
        var ok = progress.handle(.moved)
        #expect(!ok)
        ok = progress.handle(.enteredGrid)
        #expect(!ok && progress.stepIndex == 0)
        ok = progress.handle(.typedGridCell)
        #expect(!ok && progress.stepIndex == 0)
        ok = progress.handle(.hitLeftTarget)
        #expect(ok && progress.stepIndex == 1)
        #expect(progress.current?.gridGuide == .right)
        ok = progress.handle(.hitLeftTarget)
        #expect(!ok)
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
        #expect(progress.current?.required == .zoomedAll)
    }

    @Test func zoomStepNeedsBothDirections() {
        var progress = TutorialProgress(session: .freeOnly, stepIndex: 7)
        #expect(progress.current?.prompt == "Zoom the blue strip — `⌘` + `.` in, `⌘` + `,` out.")
        #expect(progress.current?.arenaFocus == .scroll)
        var ok = progress.handle(.zoomed(.in))
        #expect(!ok && progress.stepIndex == 7)
        ok = progress.handle(.zoomed(.in))
        #expect(!ok)
        ok = progress.handle(.scrolled(.up))
        #expect(!ok && progress.stepIndex == 7)
        ok = progress.handle(.zoomed(.out))
        #expect(ok && progress.stepIndex == 8)
        #expect(progress.current?.required == .dragStarted)
    }

    @Test func zoomCreditNeedsARealChangeBothWays() {
        var credit = ZoomCredit()
        let start = credit.arm(scale: 1)
        #expect(start == 1)
        #expect(credit.credit(scale: 1.2) == nil)
        #expect(credit.credit(scale: ZoomCredit.ratio) == .in)
        #expect(credit.credit(scale: ZoomCredit.maxScale) == nil)
        #expect(credit.credit(scale: 1) == nil)
        #expect(credit.credit(scale: 1 / ZoomCredit.ratio) == .out)
        #expect(credit.credit(scale: ZoomCredit.minScale) == nil)

        var pinned = ZoomCredit()
        let pulled = pinned.arm(scale: ZoomCredit.maxScale)
        #expect(abs(pulled - ZoomCredit.maxScale / ZoomCredit.ratio) < 0.0001)
        #expect(pinned.credit(scale: pulled * ZoomCredit.ratio) == .in)
        #expect(pinned.credit(scale: pulled / ZoomCredit.ratio) == .out)

        var shrunk = ZoomCredit()
        let raised = shrunk.arm(scale: ZoomCredit.minScale)
        #expect(abs(raised - ZoomCredit.minScale * ZoomCredit.ratio) < 0.0001)
        #expect(shrunk.credit(scale: raised / ZoomCredit.ratio) == .out)
    }

    @Test func previousAndNextMoveOneStep() {
        var progress = TutorialProgress(session: .freeOnly)
        #expect(!progress.canMoveBack)
        #expect(progress.canMoveForward)
        var ok = progress.move(-1)
        #expect(!ok && progress.stepIndex == 0)

        ok = progress.move(1)
        #expect(ok && progress.stepIndex == 1)
        #expect(progress.current?.required == .steeredAll)
        ok = progress.handle(.steered(.left))
        #expect(!ok)
        ok = progress.move(1)
        #expect(ok)
        ok = progress.move(-1)
        #expect(ok && progress.stepIndex == 1)
        ok = progress.handle(.steered(.right))
        #expect(!ok)
        ok = progress.handle(.steered(.down))
        #expect(!ok)
        ok = progress.handle(.steered(.up))
        #expect(!ok)
        ok = progress.handle(.steered(.left))
        #expect(ok && progress.stepIndex == 2)

        let last = progress.steps.count - 1
        ok = progress.move(last - progress.stepIndex)
        #expect(ok)
        #expect(progress.canMoveBack)
        #expect(!progress.canMoveForward)
        ok = progress.move(1)
        #expect(!ok && progress.stepIndex == last)
    }

    @Test func aimThenActKeepsOptionOnTheCellScreen() {
        var progress = TutorialProgress(session: .aimThenAct)
        var ok = progress.handle(.enteredGrid)
        #expect(ok && progress.stepIndex == 1)
        #expect(progress.current?.gridGuide == .toFree)
        #expect(progress.current?.detail == "Then `⌥` — drop into free mode.")
        ok = progress.handle(.gridToFree)
        #expect(!ok && progress.stepIndex == 1)
        ok = progress.handle(.typedGridCell)
        #expect(!ok && progress.stepIndex == 1)
        ok = progress.handle(.gridToFree)
        #expect(ok && progress.stepIndex == 2)
        #expect(progress.current?.prompt == "Nudge onto the target with `J` `K` `L` `;`.")
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
        #expect(ok && progress.stepIndex == 3 && progress.current?.required == .heldSlower)

        ok = progress.observeSpeed(faster: true, slower: false, moved: true, dt: 2)
        #expect(!ok)
        ok = progress.observeSpeed(faster: false, slower: true, moved: true, dt: 0.5)
        #expect(!ok)
        ok = progress.observeSpeed(faster: false, slower: true, moved: true, dt: 0.5)
        #expect(ok && progress.current?.required == .hitLeftTarget)
    }

    @Test func speedStepAddsBurstsUntilOneSecond() {
        var progress = TutorialProgress(session: .freeOnly, stepIndex: 2)
        #expect(progress.current?.required == .heldFaster)
        for _ in 0..<3 {
            let ok = progress.observeSpeed(faster: true, slower: false, moved: true, dt: 0.3)
            #expect(!ok && progress.stepIndex == 2)
            let paused = progress.observeSpeed(faster: false, slower: false, moved: false, dt: 2)
            #expect(!paused && progress.stepIndex == 2)
        }
        let ok = progress.observeSpeed(faster: true, slower: false, moved: true, dt: 0.1)
        #expect(ok && progress.stepIndex == 3)
    }

    @Test func speedPromptShowsRemainingHoldOnlyAfterStart() {
        var progress = TutorialProgress(session: .freeOnly, stepIndex: 2)
        #expect(progress.prompt == "Hold `Z` and move — go faster.")

        var clock = SpeedDemoClock()
        _ = clock.advance(active: true, dt: 0.3, goal: 1)
        #expect(clock.tenthsLeft(goal: 1) == 7)
        _ = clock.advance(active: true, dt: 0.6, goal: 1)
        #expect(clock.tenthsLeft(goal: 1) == 1)

        progress.setSpeedTenthsLeft(7)
        #expect(progress.prompt == "Hold `Z` and move — go faster. Keep holding `Z` and move for 0.7 more seconds.")
    }

    @Test func zoomPromptNamesTheMissingDirection() {
        var progress = TutorialProgress(session: .freeOnly, stepIndex: 7)
        #expect(progress.current?.required == .zoomedAll)
        #expect(progress.prompt == "Zoom the blue strip — `⌘` + `.` in, `⌘` + `,` out.")
        _ = progress.handle(.zoomed(.in))
        #expect(progress.prompt == "Zoom the blue strip — `⌘` + `.` in, `⌘` + `,` out. Keep zooming out `⌘` + `,`.")
        _ = progress.handle(.zoomed(.out))
        #expect(progress.stepIndex == 8)
    }

    @Test func keycapMarkupSplitsChords() {
        let runs = KeycapMarkup.parse("Keep zooming out `⌘` + `,`.")
        #expect(runs.map(\.isKey) == [false, true, false, true, false])
        #expect(runs.filter(\.isKey).map(\.text) == ["⌘", ","])
    }

    @Test func skipCompletes() {
        var progress = TutorialProgress(session: .hintMode)
        let ok = progress.handle(.skipped)
        #expect(ok && progress.completed)
    }

    @Test func puckDropCountsACenterInsideTheRing() {
        #expect(!PuckDrop.contains(offset: .zero))
        #expect(PuckDrop.contains(offset: CGSize(width: PuckDrop.dropX - PuckDrop.homeX, height: 0)))
        #expect(PuckDrop.contains(offset: CGSize(width: 160, height: 40)))
        #expect(!PuckDrop.contains(offset: CGSize(width: 160, height: 60)))
    }

    @Test func puckNudgeFollowsThePointerOnlyOnTheDragStep() {
        let home = CGSize(width: 10, height: -4)
        #expect(PuckDrop.nudge(home, dx: 0, dy: 0, onDragStep: true) == home)
        #expect(PuckDrop.nudge(home, dx: 30, dy: 8, onDragStep: false) == home)
        let stepped = PuckDrop.nudge(home, dx: 30, dy: 8, onDragStep: true)
        #expect(stepped == CGSize(width: 40, height: 4))
        let landed = PuckDrop.nudge(stepped, dx: 120, dy: -4, onDragStep: true)
        #expect(landed == CGSize(width: PuckDrop.dropX - PuckDrop.homeX, height: 0))
        #expect(PuckDrop.contains(offset: landed))
    }

    @Test func hintLegendFollowsTheBindings() {
        #expect(HintLegend.line(.init()) == "Space/↩ click · ⌃Space/⌃↩ right · ⌥ free · ⌘ grid · Esc cancel")
        var changed = BindingsConfig()
        changed.hint.rightClick = ["d"]
        changed.global.gridMode = ["g"]
        #expect(HintLegend.line(changed) == "Space/↩ click · D right · ⌥ free · G grid · Esc cancel")
        changed.hint.leftClick = []
        #expect(!HintLegend.line(changed).contains("click"))
    }

    @Test func guideKeysFollowTheGridBindings() {
        var grid = GridBindings()
        grid.leftClick = ["t"]
        grid.rightClick = ["s"]
        grid.toFree = ["a"]
        let keys = GridGuideKeys(grid: grid)
        #expect(GridGuideCopy.detail(opensFiner: false, click: .left, keys: keys) == "`T` hits this cell.")
        #expect(GridGuideCopy.detail(opensFiner: true, click: .right, keys: keys) == "Last key opens a finer grid. `S` right-clicks the rectangle so far.")
        #expect(GridGuideCopy.detail(opensFiner: false, click: .toFree, keys: keys) == "Then `A` — drop into free mode.")
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

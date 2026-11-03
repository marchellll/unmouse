import CoreGraphics
import Testing
@testable import UnmouseCore

@Suite("Grid")
struct GridTests {
    @Test func labelsOneCharWhenEnough() {
        let labels = GridLabels.labels(chars: "qwertyuiopasdfghjkl;", rows: 5, cols: 4)
        #expect(labels.count == 20)
        #expect(labels[0] == "q")
        #expect(labels[10] == "a")
        #expect(GridLabels.labelWidth(chars: "qwertyuiopasdfghjkl;", rows: 5, cols: 4) == 1)
    }

    @Test func labelsTwoCharsWhenNeeded() {
        let labels = GridLabels.labels(chars: "ab", rows: 2, cols: 2)
        #expect(labels == ["aa", "ab", "ba", "bb"])
        #expect(GridLabels.labelWidth(chars: "ab", rows: 2, cols: 2) == 2)
    }

    @Test func typeAndBackspace() {
        var state = GridState(
            rows: 5, cols: 4, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 100, height: 100)
        )
        let typed = state.typeCharacter("q")
        #expect(typed == .selected(row: 0, col: 0))
        #expect(state.isCellSelected)
        let back = state.backspace()
        #expect(back == .clearedSelection)
        #expect(!state.isCellSelected)
        _ = state.typeCharacter("q")
        let descended = state.descend()
        #expect(descended)
        #expect(state.levels.count == 2)
        let popped = state.backspace()
        #expect(popped == .poppedLevel)
        #expect(state.levels.count == 1)
    }

    @Test func finalizersOnlyWhenSelected() {
        let state = GridState(
            rows: 5, cols: 4, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 100, height: 100)
        )
        let before = GridInputRouter.decide(
            character: "a",
            matchesFinalize: .rightClick,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: state
        )
        #expect(before == .typeCoordinate("a"))

        var selected = state
        _ = selected.typeCharacter("q")
        let after = GridInputRouter.decide(
            character: "a",
            matchesFinalize: .rightClick,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: selected
        )
        #expect(after == .finalize(.rightClick))
    }

    @Test func coordinateFlip() {
        let primary: CGFloat = 1000
        let appKit = CGPoint(x: 10, y: 100)
        let cg = CoordinateSpace.appKitToCGEvent(appKit, primaryHeight: primary)
        #expect(cg.x == 10)
        #expect(cg.y == 900)
        let back = CoordinateSpace.cgEventToAppKit(cg, primaryHeight: primary)
        #expect(back == appKit)
    }
}

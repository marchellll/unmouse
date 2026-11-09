import CoreGraphics
import Testing
@testable import UnmouseCore

@Suite("Grid")
struct GridTests {
    @Test func labelsClumpByFirstCharacter() {
        let chars = "qwertyuiopasdfghjkl;"
        let labels = GridLabels.labels(chars: chars, rows: 5, cols: 6)
        #expect(labels.count == 30)
        #expect(GridLabels.labelWidth(chars: chars, rows: 5, cols: 6) == 2)
        #expect(GridLabels.clumpText("qw") == "qw")
        // 6×5 splits into quadrants: top-left is 3×3 and every cell starts with q.
        for row in 0..<3 {
            for col in 0..<3 {
                #expect(labels[row * 6 + col].hasPrefix("q"))
            }
        }
        #expect(labels[0] == "qq")
        #expect(labels[1] == "qw")
        #expect(!labels[3].hasPrefix("q"))
        #expect(labels[3].hasPrefix("w"))
    }

    @Test func firstCharacterClicksTheBlockCenter() {
        var state = GridState(
            rows: 5, cols: 6, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500)
        )
        #expect(state.typeCharacter("q") == .typing)
        let frame = state.targetFrame
        let centerCell = CoordinateSpace.cellFrame(
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500),
            rows: 5, cols: 6, row: 1, col: 1
        )
        #expect(frame?.width == 300)
        #expect(frame?.height == 300)
        #expect(state.prospectiveCenter == CGPoint(x: centerCell.midX, y: centerCell.midY))
        let click = GridInputRouter.decide(
            character: nil,
            matchesFinalize: .leftClick,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: state
        )
        #expect(click == .finalize(.leftClick))
    }

    @Test func shortAlphabetUsesThreeCharacters() {
        let chars = "abcde"
        #expect(GridLabels.labelWidth(chars: chars, rows: 10, cols: 10) == 3)
        let labels = GridLabels.labels(chars: chars, rows: 10, cols: 10)
        #expect(labels.count == 100)
        #expect(labels.allSatisfy { $0.count == 3 })
        #expect(Set(labels).count == labels.count)
        let first = labels[0].prefix(1)
        let block = labels.indices.filter { labels[$0].hasPrefix(first) }
        let blockRows = Set(block.map { $0 / 10 })
        let blockCols = Set(block.map { $0 % 10 })
        #expect(block.count == blockRows.count * blockCols.count)
        #expect(blockRows.count == 5)
        #expect(blockCols.count == 5)
        let pair = labels[0].prefix(2)
        let sub = block.filter { labels[$0].hasPrefix(pair) }
        let subRows = Set(sub.map { $0 / 10 })
        let subCols = Set(sub.map { $0 % 10 })
        #expect(sub.count == subRows.count * subCols.count)
        #expect(sub.count > 1)
        #expect(sub.count < block.count)
    }

    @Test func twoCharactersOpenTheSubgrid() {
        var state = GridState(
            rows: 5, cols: 6, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500)
        )
        #expect(state.typeCharacter("q") == .typing)
        #expect(state.levels.count == 1)
        // "qi" is one cell in the top-left block. Finishing it opens that cell's grid.
        #expect(state.typeCharacter("i") == .openedSubgrid)
        #expect(state.levels.count == 2)
        #expect(state.selectedCell == nil)
        #expect(state.currentLevel.typed.isEmpty)
        let cell = CoordinateSpace.cellFrame(
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500),
            rows: 5, cols: 6, row: 2, col: 1
        )
        let nested = CGRect(origin: state.currentLevel.origin, size: state.currentLevel.size)
        #expect(nested == cell)
        #expect(state.labels.count == 30)
        #expect(state.labels.allSatisfy { !$0.isEmpty })
    }

    @Test func finishedCellStaysSelectedOnTheLastLevel() {
        var state = GridState(
            rows: 5, cols: 6, chars: "qwertyuiopasdfghjkl;", depth: 1,
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500)
        )
        _ = state.typeCharacter("q")
        #expect(state.typeCharacter("i") == .selected(row: 2, col: 1))
        #expect(state.levels.count == 1)
        #expect(state.isCellSelected)
        let click = GridInputRouter.decide(
            character: nil,
            matchesFinalize: .leftClick,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: state
        )
        #expect(click == .finalize(.leftClick))
    }

    @Test func twoKeysSelectTheCell() {
        var state = GridState(
            rows: 2, cols: 2, chars: "abcdefghij", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 100, height: 100)
        )
        #expect(state.labels == ["aa", "ba", "ca", "da"])
        #expect(state.typeCharacter("b") == .typing)
        #expect(state.typeCharacter("a") == .openedSubgrid)
        #expect(state.levels.count == 2)
        #expect(state.chars == "abcdefghij")
        #expect(state.labels == ["a", "b", "c", "d"])
        #expect(state.labelWidth == 1)
        #expect(state.selectedCell == nil)
    }

    @Test func firstRunDimensionsKeepScreenShape() {
        let size = CGSize(width: 1_512, height: 982)
        let dimensions = GridSizing.dimensions(for: size)
        #expect(dimensions == (rows: 7, cols: 7))
        let n = CGFloat(dimensions.cols)
        let cellAspect = (size.width / n) / (size.height / n)
        #expect(abs(cellAspect - size.width / size.height) < 0.001)
        #expect(size.width / (n * n) <= GridSizing.targetHitSize * GridSizing.targetCoverage)
        #expect(size.height / (n * n) <= GridSizing.targetHitSize * GridSizing.targetCoverage)
    }

    @Test func typeAndBackspace() {
        var state = GridState(
            rows: 5, cols: 4, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 100, height: 100)
        )
        #expect(state.typeCharacter("q") == .typing)
        let opened = state.typeCharacter("q")
        #expect(opened == .openedSubgrid)
        #expect(state.levels.count == 2)
        let nested = CGRect(origin: state.currentLevel.origin, size: state.currentLevel.size)
        #expect(nested.width == 25)
        #expect(nested.height == 20)
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

    @Test func descendClearsSelectionForNestedLabels() {
        var state = GridState(
            rows: 5, cols: 4, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 400, height: 400)
        )
        #expect(state.typeCharacter("q") == .typing)
        let opened = state.typeCharacter("q")
        #expect(opened == .openedSubgrid)
        #expect(state.selectedCell == nil)
        #expect(state.currentLevel.typed.isEmpty)
        #expect(state.chars == "qwertyuiopasdfghjkl;")
        #expect(state.labels.count == 20)
        #expect(state.labels[0] == "q")
        #expect(state.labelWidth == 1)
        #expect(state.hasClickTarget)
        #expect(state.typeCharacter("w") == .selected(row: 0, col: 1))
        let space = GridInputRouter.decide(
            character: nil,
            matchesFinalize: .leftClick,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: state
        )
        #expect(space == .finalize(.leftClick))
        let option = GridInputRouter.decide(
            character: nil,
            matchesFinalize: .toFree,
            matchesBack: false,
            matchesCancel: false,
            matchesNextScreen: false,
            state: GridState(
                rows: 5, cols: 4, chars: "qwertyuiopasdfghjkl;", depth: 2,
                screenOrigin: .zero, screenSize: CGSize(width: 400, height: 400)
            )
        )
        #expect(option == .finalize(.toFree))
    }

    @Test func deeperGridsUseTheSubgridDivision() {
        var state = GridState(
            rows: 10, cols: 10, chars: "qwertyuiopasdfghjkl;", depth: 3,
            subRows: 3, subCols: 3,
            screenOrigin: .zero, screenSize: CGSize(width: 1000, height: 1000)
        )
        #expect(state.typeCharacter("q") == .typing)
        #expect(state.typeCharacter("q") == .openedSubgrid)
        #expect(state.levels.count == 2)
        #expect(state.rows == 3)
        #expect(state.cols == 3)
        #expect(state.labels.count == 9)
        #expect(state.labels == ["q", "w", "e", "r", "t", "y", "u", "i", "o"])
        #expect(state.labelWidth == 1)
        let parent = CGRect(origin: state.currentLevel.origin, size: state.currentLevel.size)
        #expect(parent.width == 100)
        #expect(parent.height == 100)
        #expect(state.typeCharacter("q") == .openedSubgrid)
        #expect(state.levels.count == 3)
        #expect(state.rows == 3)
        #expect(state.backspace() == .poppedLevel)
        #expect(state.levels.count == 2)
        #expect(state.rows == 3)
        #expect(state.backspace() == .poppedLevel)
        #expect(state.levels.count == 1)
        #expect(state.rows == 10)
        #expect(state.cols == 10)
    }

    @Test func backspaceUndoesAPartialLabelThenDoesNothing() {
        var state = GridState(
            rows: 5, cols: 4, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 100, height: 100)
        )
        #expect(state.backspace() == .noop)
        #expect(state.typeCharacter("q") == .typing)
        #expect(state.currentLevel.typed == "q")
        #expect(state.backspace() == .clearedChar)
        #expect(state.currentLevel.typed.isEmpty)
        #expect(state.selectedCell == nil)
        #expect(state.backspace() == .noop)
    }

    @Test func backspaceClearsAFinishedCellSoItCanBeRetyped() {
        var state = GridState(
            rows: 5, cols: 4, chars: "qwertyuiopasdfghjkl;", depth: 2,
            screenOrigin: .zero, screenSize: CGSize(width: 400, height: 400)
        )
        #expect(state.typeCharacter("q") == .typing)
        #expect(state.typeCharacter("q") == .openedSubgrid)
        #expect(state.typeCharacter("w") == .selected(row: 0, col: 1))
        #expect(state.isCellSelected)
        #expect(state.backspace() == .clearedSelection)
        #expect(state.selectedCell == nil)
        #expect(state.currentLevel.typed.isEmpty)
        #expect(!state.isCellSelected)
        #expect(state.typeCharacter("e") == .selected(row: 0, col: 2))

        state.selectedCell = GridCellIndex(row: 1, col: 1)
        state.levels[state.levels.count - 1].typed = ""
        #expect(state.backspace() == .clearedSelection)
        #expect(state.selectedCell == nil)
        #expect(state.currentLevel.typed.isEmpty)
    }
}

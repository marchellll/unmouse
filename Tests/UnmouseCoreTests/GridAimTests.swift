import CoreGraphics
import Testing
@testable import UnmouseCore

@Suite("Grid aim")
struct GridAimTests {
    private func state(depth: Int = 2) -> GridState {
        GridState(
            rows: 5, cols: 6, chars: "qwertyuiopasdfghjkl;", depth: depth,
            subRows: 3, subCols: 3,
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500)
        )
    }

    @Test func pathNamesTheRootCellAndTheSubcellUnderThePoint() {
        let grid = state()
        let cell = CoordinateSpace.cellFrame(
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500),
            rows: 5, cols: 6, row: 2, col: 1
        )
        let point = CGPoint(x: cell.midX, y: cell.midY)
        let path = grid.aimPath(containing: point)
        let labels = GridLabels.labels(chars: grid.chars, rows: 5, cols: 6)
        #expect(path.count == 2)
        #expect(path[0].row == 2 && path[0].col == 1)
        #expect(path[0].label == labels[2 * 6 + 1])
        #expect(path[0].frame == cell)
        #expect(path[1].row == 1 && path[1].col == 1)
        #expect(path[1].label == "t")
        #expect(path[0].frame.contains(path[1].frame))
        #expect(path[1].frame.contains(point))
    }

    @Test func pointOutsideTheScreenHasNoPath() {
        let path = state().aimPath(containing: CGPoint(x: -1, y: 10))
        #expect(path.isEmpty)
        #expect(state().guide(at: CGPoint(x: -1, y: 10), click: .left) == nil)
    }

    @Test func guideOnTheRootShowsTheKeysStillToType() {
        var grid = state()
        let cell = CoordinateSpace.cellFrame(
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500),
            rows: 5, cols: 6, row: 2, col: 1
        )
        let point = CGPoint(x: cell.midX, y: cell.midY)
        let cue = grid.guide(at: point, click: .left)
        #expect(cue?.frames.count == 2)
        #expect(cue?.frames.first == cell)
        #expect(cue?.title == KeycapMarkup.typeKeys(grid.aimPath(containing: point)[0].label))
        #expect(cue?.detail == "Last key opens a finer grid. `␣` clicks the rectangle so far.")
        let free = grid.guide(at: point, click: .toFree)
        #expect(free?.frames.count == 2)
        #expect(free?.detail == "Last key opens a finer grid. Then `⌥` — drop into free mode.")
        let first = grid.aimPath(containing: point)[0].label.first!
        #expect(grid.typeCharacter(first) == .typing)
        let next = grid.guide(at: point, click: .left)
        let rest = String(grid.aimPath(containing: point)[0].label.dropFirst())
        #expect(next?.title == KeycapMarkup.typeKeys(rest))
        #expect(next?.anchor == cell)
    }

    @Test func guideFollowsTheSubcellAfterThatCellOpens() {
        var grid = state()
        let cell = CoordinateSpace.cellFrame(
            screenOrigin: .zero, screenSize: CGSize(width: 600, height: 500),
            rows: 5, cols: 6, row: 2, col: 1
        )
        let point = CGPoint(x: cell.midX, y: cell.midY)
        let sub = grid.aimPath(containing: point)[1]
        let root = grid.aimPath(containing: point)[0]
        for ch in root.label { _ = grid.typeCharacter(ch) }
        #expect(grid.levels.count == 2)
        let cue = grid.guide(at: point, click: .right)
        #expect(cue?.frames == [sub.frame])
        #expect(cue?.title == KeycapMarkup.typeKeys(sub.label))
        #expect(cue?.detail == "`A` right-clicks this cell.")
    }

    @Test func wrongSubgridSaysToGoBack() {
        var grid = state()
        let size = CGSize(width: 600, height: 500)
        let target = CoordinateSpace.cellFrame(
            screenOrigin: .zero, screenSize: size, rows: 5, cols: 6, row: 4, col: 5
        )
        let point = CGPoint(x: target.midX, y: target.midY)
        let other = GridLabels.labels(chars: grid.chars, rows: 5, cols: 6)[0]
        for ch in other { _ = grid.typeCharacter(ch) }
        #expect(grid.levels.count == 2)
        let cue = grid.guide(at: point, click: .left)
        #expect(cue?.frames.isEmpty == true)
        #expect(cue?.title == "Not this cell")
        let free = grid.guide(at: point, click: .toFree)
        #expect(free?.title == "Then `⌥`")
        #expect(free?.detail == "Drop into free mode.")
    }

    @Test func cardSitsOnTheOpenSideNearestTheTarget() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let card = CGSize(width: 100, height: 48)
        let againstLeft = CGRect(x: 0, y: 200, width: 120, height: 120)
        let beside = GridGuideLayout.cardFrame(
            card: card, around: againstLeft, near: CGPoint(x: 20, y: 260), in: bounds
        )
        #expect(beside.intersection(againstLeft).width < 5)
        #expect(beside.intersection(againstLeft).height < 5)

        let openRight = CGRect(x: 200, y: 200, width: 120, height: 120)
        let right = GridGuideLayout.cardFrame(
            card: card, around: openRight, near: CGPoint(x: 310, y: 260), in: bounds
        )
        #expect(right.minX >= openRight.maxX - 1)

        let middle = CGRect(x: 300, y: 200, width: 200, height: 200)
        let above = GridGuideLayout.cardFrame(
            card: card, around: middle, near: CGPoint(x: 400, y: 370), in: bounds
        )
        #expect(above.minY >= middle.maxY - 1)
        #expect(abs(above.midX - 400) < 1)
    }
}

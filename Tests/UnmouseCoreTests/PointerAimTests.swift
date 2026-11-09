import CoreGraphics
import Testing
@testable import UnmouseCore

@Suite("Pointer aim")
struct PointerAimTests {
    private let previous = CGPoint(x: 3374, y: 62)
    private let cell = CGPoint(x: 3429, y: 15)
    private let elsewhere = CGPoint(x: 100, y: 800)

    @Test func staleSystemLocationStaysOnThePostedPoint() {
        var aim = PointerAim()
        aim.remember(live: previous, point: cell)
        #expect(aim.resolve(live: previous) == cell)
    }

    @Test func caughtUpLocationStaysOnThePostedPoint() {
        var aim = PointerAim()
        aim.remember(live: previous, point: cell)
        #expect(aim.resolve(live: cell) == cell)
    }

    @Test func aRealMoveDropsTheAim() {
        var aim = PointerAim()
        aim.remember(live: previous, point: cell)
        #expect(aim.resolve(live: elsewhere) == elsewhere)
        #expect(aim.resolve(live: elsewhere) == elsewhere)
        #expect(aim.posted == nil)
    }

    @Test func aSecondPostBeforeCatchUpReplacesThePoint() {
        var aim = PointerAim()
        aim.remember(live: previous, point: cell)
        let nudged = CGPoint(x: cell.x + 1, y: cell.y)
        aim.remember(live: previous, point: nudged)
        aim.remember(live: previous, point: cell)
        #expect(aim.resolve(live: previous) == cell)
    }

    @Test func moveAfterCatchUpUsesTheLandedPointAsAnchor() {
        var aim = PointerAim()
        aim.remember(live: previous, point: cell)
        let next = CGPoint(x: 3703, y: 15)
        aim.remember(live: cell, point: next)
        #expect(aim.resolve(live: cell) == next)
        #expect(aim.resolve(live: next) == next)
    }
}

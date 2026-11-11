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

    @Test func clampedPostBelowTheBottomDropsTheAim() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let edge = CGPoint(x: 960, y: 1080)
        var aim = PointerAim()
        aim.remember(live: edge, point: CGPoint(x: 960, y: 1200))
        #expect(aim.resolve(live: edge, displays: [display]) == edge)
        #expect(aim.posted == nil)

        aim.remember(live: edge, point: CGPoint(x: 960, y: 1400))
        #expect(aim.resolve(live: edge, displays: [display]) == edge)
        #expect(aim.posted == nil)
    }

    /// mouseLocation can track the virtual off-screen post; still snap back to the edge.
    @Test func virtualOffScreenLiveStillClampsToTheEdge() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let edge = CGPoint(x: 960, y: 1080)
        let debt = CGPoint(x: 960, y: 4526)
        var aim = PointerAim()
        aim.remember(live: edge, point: debt)
        #expect(aim.resolve(live: debt, displays: [display]) == edge)
        #expect(aim.posted == nil)
    }

    @Test func postOntoANeighborDisplayKeepsTheAim() {
        let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let onLeft = CGPoint(x: 1910, y: 540)
        let onRight = CGPoint(x: 1930, y: 540)
        var aim = PointerAim()
        aim.remember(live: onLeft, point: onRight)
        #expect(aim.resolve(live: onLeft, displays: [left, right]) == onRight)
        #expect(aim.posted == onRight)
    }
}

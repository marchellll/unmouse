import Testing
@testable import UnmouseCore

@Suite("Speed modifier latch")
struct SpeedModifierLatchTests {
    private let grace = SpeedModifierLatch.graceNanos

    @Test func letterChordReleasesAfterGrace() {
        var latch = SpeedModifierLatch()
        latch.keyDown(faster: true, slower: false)
        latch.keyUp(faster: true, slower: false, arrowHeld: false, hidDown: false, nowNanos: 1_000)
        latch.sync(arrowHeld: false, fasterHID: false, slowerHID: false, nowNanos: 1_000)
        #expect(latch.faster)
        latch.sync(arrowHeld: false, fasterHID: false, slowerHID: false, nowNanos: 1_000 + grace)
        #expect(!latch.faster)
        #expect(!latch.releasePending)
    }

    @Test func ghostUpBeforeArrowDownStillHolds() {
        var latch = SpeedModifierLatch()
        latch.keyDown(faster: true, slower: false)
        latch.keyUp(faster: true, slower: false, arrowHeld: false, hidDown: false, nowNanos: 5_000)
        latch.sync(arrowHeld: true, fasterHID: false, slowerHID: false, nowNanos: 5_000 + 1_000_000)
        #expect(latch.faster)
        latch.sync(arrowHeld: false, fasterHID: false, slowerHID: false, nowNanos: 5_000 + grace + 1)
        #expect(!latch.faster)
    }

    @Test func arrowChordKeepsFasterUntilArrowsRelease() {
        var latch = SpeedModifierLatch()
        latch.keyDown(faster: true, slower: false)
        latch.keyUp(faster: true, slower: false, arrowHeld: true, hidDown: false, nowNanos: 10)
        #expect(latch.faster)
        latch.sync(arrowHeld: true, fasterHID: false, slowerHID: false, nowNanos: 10 + grace + 1)
        #expect(latch.faster)
        latch.sync(arrowHeld: false, fasterHID: false, slowerHID: false, nowNanos: 10 + grace + 1)
        #expect(!latch.faster)
    }

    @Test func hidStillDownIgnoresArrowGhost() {
        var latch = SpeedModifierLatch()
        latch.keyDown(faster: true, slower: false)
        latch.keyUp(faster: true, slower: false, arrowHeld: false, hidDown: true, nowNanos: 10)
        #expect(latch.faster)
        #expect(!latch.releasePending)
        latch.sync(arrowHeld: false, fasterHID: false, slowerHID: false, nowNanos: 10 + grace)
        #expect(latch.faster)
    }

    @Test func deferredReleaseKeptWhenHIDStillDown() {
        var latch = SpeedModifierLatch()
        latch.keyDown(faster: false, slower: true)
        latch.keyUp(faster: false, slower: true, arrowHeld: true, hidDown: false, nowNanos: 10)
        latch.sync(arrowHeld: false, fasterHID: false, slowerHID: true, nowNanos: 99)
        #expect(latch.slower)
        #expect(!latch.faster)
    }

    @Test func slowerReleaseDoesNotClearFaster() {
        var latch = SpeedModifierLatch()
        latch.keyDown(faster: true, slower: true)
        latch.keyUp(faster: false, slower: true, arrowHeld: false, hidDown: false, nowNanos: 1_000)
        latch.sync(arrowHeld: false, fasterHID: false, slowerHID: false, nowNanos: 1_000 + grace)
        #expect(latch.faster)
        #expect(!latch.slower)
    }
}

import Testing
@testable import UnmouseCore

@Suite("AloneTap")
struct AloneTapTests {
    @Test func shortAloneTapFires() {
        var tap = AloneTapTracker(maxTapMilliseconds: 200)
        #expect(tap.handle(.modifier(token: "command_left", down: true, nowNanos: 1_000)) == .down)
        let up = tap.handle(.modifier(token: "command_left", down: false, nowNanos: 1_000 + 150_000_000))
        #expect(up == .up(alone: true))
    }

    @Test func longHoldDoesNotCountAsTap() {
        var tap = AloneTapTracker(maxTapMilliseconds: 200)
        #expect(tap.handle(.modifier(token: "command_left", down: true, nowNanos: 1_000)) == .down)
        // 250ms > 200ms max
        let up = tap.handle(.modifier(token: "command_left", down: false, nowNanos: 1_000 + 250_000_000))
        #expect(up == .up(alone: false))
    }

    @Test func interruptedByOtherKey() {
        var tap = AloneTapTracker(maxTapMilliseconds: 200)
        _ = tap.handle(.modifier(token: "command_left", down: true, nowNanos: 1_000))
        _ = tap.handle(.otherKey)
        let up = tap.handle(.modifier(token: "command_left", down: false, nowNanos: 1_000 + 50_000_000))
        #expect(up == .up(alone: false))
    }

    @Test func setMaxTapMillisecondsUpdatesThreshold() {
        var tap = AloneTapTracker(maxTapMilliseconds: 500)
        tap.setMaxTapMilliseconds(100)
        _ = tap.handle(.modifier(token: "option_left", down: true, nowNanos: 0))
        let up = tap.handle(.modifier(token: "option_left", down: false, nowNanos: 150_000_000))
        #expect(up == .up(alone: false))
    }
}

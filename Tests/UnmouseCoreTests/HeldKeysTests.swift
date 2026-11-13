import Testing
@testable import UnmouseCore

@Suite("HeldKeys")
struct HeldKeysTests {
    @Test func lateDownDoesNotResurrectReleasedKey() {
        let store = HeldKeyStore()
        store.setHeld("k", down: true, at: 1_000)
        store.setHeld("k", down: false, at: 3_000)
        // Late Karabiner down that was stamped earlier than the up.
        store.setHeld("k", down: true, at: 2_000)
        #expect(!store.isHeld("k"))
    }

    @Test func newerDownWinsAfterUp() {
        let store = HeldKeyStore()
        store.setHeld("j", down: true, at: 1_000)
        store.setHeld("j", down: false, at: 2_000)
        store.setHeld("j", down: true, at: 3_000)
        #expect(store.isHeld("j"))
    }

    @Test func clearHeldDropsTokensAndTimestamps() {
        let store = HeldKeyStore()
        store.setHeld("h", down: true, at: 5_000)
        store.clearHeld()
        #expect(!store.isHeld("h"))
        // After clear, an older stamp is allowed again.
        store.setHeld("h", down: true, at: 1_000)
        #expect(store.isHeld("h"))
    }

    @Test func keyDeduper() {
        let deduper = KeyDeduper(windowMillis: 50)
        #expect(deduper.shouldHandle(token: "h", down: true, nowNanos: 1_000))
        #expect(!deduper.shouldHandle(token: "h", down: true, nowNanos: 2_000))
        #expect(deduper.shouldHandle(token: "h", down: true, nowNanos: 100_000_000))
        // Fallback carries the original HID stamp, which is earlier than the tap.
        #expect(deduper.shouldHandle(token: "space", down: true, nowNanos: 5_000_000))
        #expect(!deduper.shouldHandle(token: "space", down: true, nowNanos: 4_000_000))
    }

    @Test func differentFlagsRetryUnlessTheFirstCopySwallowed() {
        let deduper = KeyDeduper(windowMillis: 50)
        #expect(deduper.shouldHandle(token: "space", down: true, nowNanos: 1_000, flags: 1))
        #expect(!deduper.shouldHandle(token: "space", down: true, nowNanos: 2_000, flags: 3))
        #expect(!deduper.shouldRetry(token: "space", down: true, flags: 1))
        #expect(deduper.shouldRetry(token: "space", down: true, flags: 3))
        #expect(!deduper.shouldRetry(token: "space", down: true, flags: 3))

        #expect(deduper.shouldHandle(token: "f", down: true, nowNanos: 1_000, flags: 1))
        deduper.setSwallow(token: "f", down: true, swallow: true)
        #expect(!deduper.shouldHandle(token: "f", down: true, nowNanos: 2_000, flags: 3))
        #expect(!deduper.shouldRetry(token: "f", down: true, flags: 3))
    }

    @Test func duplicateReplaysSwallowDecision() {
        let deduper = KeyDeduper(windowMillis: 50)
        #expect(deduper.shouldHandle(token: "escape", down: true, nowNanos: 1_000))
        deduper.setSwallow(token: "escape", down: true, swallow: true)
        #expect(!deduper.shouldHandle(token: "escape", down: true, nowNanos: 2_000))
        #expect(deduper.swallowed(token: "escape", down: true))
        #expect(!deduper.swallowed(token: "escape", down: false))

        #expect(deduper.shouldHandle(token: "a", down: true, nowNanos: 1_000))
        deduper.setSwallow(token: "a", down: true, swallow: false)
        #expect(!deduper.shouldHandle(token: "a", down: true, nowNanos: 2_000))
        #expect(!deduper.swallowed(token: "a", down: true))

        #expect(deduper.shouldHandle(token: "escape", down: true, nowNanos: 100_000_000))
        #expect(!deduper.swallowed(token: "escape", down: true))
    }

    @Test func chordUpFromKarabinerDoesNotEatTheTapUp() {
        var pass = ChordPassthrough()
        pass.begin(token: "tab", fromTap: false)
        pass.begin(token: "tab", fromTap: true)
        let karUp = pass.end(token: "tab", fromTap: false)
        let tapUp = pass.end(token: "tab", fromTap: true)
        let extra = pass.end(token: "tab", fromTap: true)
        #expect(karUp)
        #expect(tapUp)
        #expect(!extra)
    }

    @Test func chordUpOnlyMatchesTheSourceThatWentDown() {
        var pass = ChordPassthrough()
        pass.begin(token: "tab", fromTap: true)
        pass.begin(token: "tab", fromTap: true)
        let karUp = pass.end(token: "tab", fromTap: false)
        let tapUp = pass.end(token: "tab", fromTap: true)
        let extra = pass.end(token: "tab", fromTap: true)
        #expect(!karUp)
        #expect(tapUp)
        #expect(!extra)
    }
}

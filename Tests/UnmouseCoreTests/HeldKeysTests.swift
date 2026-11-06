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
    }
}

import Testing
@testable import UnmouseCore

@Suite("LeftClickChain")
struct LeftClickChainTests {
    private let window: UInt64 = 500_000_000

    @Test func chainsThroughTripleThenRestarts() {
        var chain = LeftClickChain()
        #expect(chain.press(now: 0, window: window) == 1)
        #expect(chain.press(now: window, window: window) == 2)
        #expect(chain.press(now: window * 2, window: window) == 3)
        #expect(chain.count == 0)
        #expect(chain.press(now: window * 2 + 1, window: window) == 1)
    }

    @Test func gapStartsANewClick() {
        var chain = LeftClickChain()
        #expect(chain.press(now: 0, window: window) == 1)
        #expect(chain.press(now: window + 1, window: window) == 1)
        #expect(chain.press(now: window + 1 + window, window: window) == 2)
    }

    @Test func repeatOnlyContinuesDoubleAndTriple() {
        var chain = LeftClickChain()
        #expect(chain.press(now: 0, window: window, repeatOnly: true) == nil)
        #expect(chain.press(now: 0, window: window) == 1)
        #expect(chain.press(now: 100, window: window, repeatOnly: true) == 2)
        #expect(chain.press(now: 200, window: window, repeatOnly: true) == 3)
        #expect(chain.press(now: 201, window: window, repeatOnly: true) == nil)
    }

    @Test func repeatOnlyIgnoresAnExpiredChain() {
        var chain = LeftClickChain()
        #expect(chain.press(now: 0, window: window) == 1)
        #expect(chain.press(now: window + 1, window: window, repeatOnly: true) == nil)
        #expect(chain.count == 1)
    }
}

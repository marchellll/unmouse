import Foundation

/// Chains a left-click key into a single, double, or triple click.
/// Each press must land within `window` nanoseconds of the previous one.
/// After a triple click the chain ends, so the next press starts at 1.
public struct LeftClickChain: Sendable, Equatable {
    public private(set) var count = 0
    private var atNanos: UInt64 = 0

    public init() {}

    /// Click state to post (1, 2, or 3).
    /// `nil` when `repeatOnly` and this press does not continue an open chain.
    public mutating func press(now: UInt64, window: UInt64, repeatOnly: Bool = false) -> Int? {
        let continuing = count > 0 && now &- atNanos <= window
        if repeatOnly && !continuing { return nil }
        let next = continuing ? count + 1 : 1
        if next >= 3 {
            count = 0
            atNanos = 0
        } else {
            count = next
            atNanos = now
        }
        return next
    }
}

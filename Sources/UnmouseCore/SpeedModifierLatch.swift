import Foundation

/// Hold state for free-mode faster/slower.
///
/// Arrow-key reports drop other held keys, so Z/X get a key-up while the arrow
/// is still down. That up often arrives before the arrow's own key-down. Letter
/// chords do not do this. The release is held for `graceNanos`, and longer
/// while an arrow move key stays down.
///
/// ponytail: a real Z release during an arrow hold stays active until the arrow
/// is up and HID agrees the key is up. HID still down cancels the pending
/// release. Upgrade path is the physical keyboard report.
public struct SpeedModifierLatch: Sendable {
    public private(set) var faster = false
    public private(set) var slower = false
    private var fasterRelease = false
    private var slowerRelease = false
    /// Nonzero when the release is waiting to see if an arrow key-down follows.
    private var fasterReleaseAt: UInt64 = 0
    private var slowerReleaseAt: UInt64 = 0

    public static let graceNanos: UInt64 = 50_000_000

    public var releasePending: Bool { fasterRelease || slowerRelease }

    public init() {}

    public mutating func reset() {
        self = .init()
    }

    public mutating func keyDown(faster: Bool, slower: Bool) {
        if faster {
            self.faster = true
            fasterRelease = false
            fasterReleaseAt = 0
        }
        if slower {
            self.slower = true
            slowerRelease = false
            slowerReleaseAt = 0
        }
    }

    /// `hidDown` means the hardware still reports this key down after the key-up.
    public mutating func keyUp(faster: Bool, slower: Bool, arrowHeld: Bool, hidDown: Bool, nowNanos: UInt64) {
        if faster {
            (self.faster, fasterRelease, fasterReleaseAt) = Self.release(
                held: self.faster,
                arrowHeld: arrowHeld,
                hidDown: hidDown,
                now: nowNanos
            )
        }
        if slower {
            (self.slower, slowerRelease, slowerReleaseAt) = Self.release(
                held: self.slower,
                arrowHeld: arrowHeld,
                hidDown: hidDown,
                now: nowNanos
            )
        }
    }

    /// Drop a deferred release once no arrow is held and the grace window is over.
    public mutating func sync(arrowHeld: Bool, fasterHID: Bool, slowerHID: Bool, nowNanos: UInt64) {
        guard !arrowHeld else { return }
        (faster, fasterRelease, fasterReleaseAt) = Self.settle(
            held: faster, pending: fasterRelease, at: fasterReleaseAt, hid: fasterHID, now: nowNanos
        )
        (slower, slowerRelease, slowerReleaseAt) = Self.settle(
            held: slower, pending: slowerRelease, at: slowerReleaseAt, hid: slowerHID, now: nowNanos
        )
    }

    private static func release(held: Bool, arrowHeld: Bool, hidDown: Bool, now: UInt64) -> (Bool, Bool, UInt64) {
        if hidDown { return (held, false, 0) }
        // Arrow already down: settle as soon as it comes up. No grace.
        if arrowHeld { return (held, true, 0) }
        // Arrow key-down may be the next event in this report.
        return (held, true, now)
    }

    private static func settle(held: Bool, pending: Bool, at: UInt64, hid: Bool, now: UInt64) -> (Bool, Bool, UInt64) {
        guard pending else { return (held, false, 0) }
        if hid { return (held, false, 0) }
        if at != 0, now &- at < graceNanos { return (held, true, at) }
        return (false, false, 0)
    }
}

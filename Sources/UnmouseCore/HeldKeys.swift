import Foundation
import Synchronization

struct KeySnapshot: Sendable, Equatable {
    var held: Set<String>
    var dragging: Bool

    init(held: Set<String> = [], dragging: Bool = false) {
        self.held = held
        self.dragging = dragging
    }
}

/// Shared between the event-tap callback and the main actor.
/// Applies key changes in event-time order so a late Karabiner down cannot
/// resurrect a key that the tap already released.
public final class HeldKeyStore: @unchecked Sendable {
    private struct State {
        var snap = KeySnapshot()
        /// Last applied event time per token. Older events are ignored.
        var lastNanos: [String: UInt64] = [:]
    }

    private let mutex: Mutex<State>

    public init() {
        mutex = Mutex(State())
    }

    /// Returns false when the event is older than the last applied stamp for this token.
    @discardableResult
    public func setHeld(_ token: String, down: Bool, at nanos: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        mutex.withLock { state in
            if let last = state.lastNanos[token], nanos < last {
                return false
            }
            state.lastNanos[token] = nanos
            if down {
                state.snap.held.insert(token)
            } else {
                state.snap.held.remove(token)
            }
            return true
        }
    }

    public func heldTokens() -> [String] {
        mutex.withLock { $0.snap.held.sorted() }
    }

    public func isHeld(_ token: String) -> Bool {
        mutex.withLock { $0.snap.held.contains(token) }
    }

    public func setDragging(_ value: Bool) {
        mutex.withLock { $0.snap.dragging = value }
    }

    func snapshot() -> KeySnapshot {
        mutex.withLock { $0.snap }
    }

    public func clearHeld() {
        mutex.withLock { state in
            state.snap.held.removeAll()
            state.lastNanos.removeAll()
        }
    }
}

/// Dedupes the same physical key arriving from both the event tap and Karabiner HID.
public final class KeyDeduper: @unchecked Sendable {
    private struct Seen {
        var nanos: UInt64
        var swallow: Bool
    }

    private let mutex: Mutex<[String: Seen]>
    private let windowNanos: UInt64

    public init(windowMillis: UInt64 = 30) {
        mutex = Mutex([:])
        windowNanos = windowMillis * 1_000_000
    }

    /// Returns true if this event should be handled (first of a pair).
    public func shouldHandle(token: String, down: Bool, nowNanos: UInt64) -> Bool {
        let key = "\(token):\(down)"
        return mutex.withLock { map in
            if let last = map[key], nowNanos &- last.nanos < windowNanos {
                return false
            }
            map[key] = Seen(nanos: nowNanos, swallow: false)
            return true
        }
    }

    /// Record whether the winning event was swallowed. The other source must replay that,
    /// because handling may already have left the mode by the time the copy arrives.
    public func setSwallow(token: String, down: Bool, swallow: Bool) {
        let key = "\(token):\(down)"
        mutex.withLock { map in
            map[key]?.swallow = swallow
        }
    }

    public func swallowed(token: String, down: Bool) -> Bool {
        let key = "\(token):\(down)"
        return mutex.withLock { $0[key]?.swallow ?? false }
    }
}

/// A free-mode chord is seen twice: Karabiner HID, then the event tap.
/// Each source that passed the key-down must pass its own key-up.
/// One shared slot lets the first up (Karabiner) consume it, and the tap
/// then swallows Tab. macOS keeps Tab down, so the next Cmd-Tab is ignored
/// until some later key-up finally arrives.
public struct ChordPassthrough: Equatable {
    private struct Pending: Equatable {
        var tap = false
        var kar = false
    }

    private var pending: [String: Pending] = [:]

    public init() {}

    public mutating func begin(token: String, fromTap: Bool) {
        var slot = pending[token] ?? Pending()
        if fromTap { slot.tap = true } else { slot.kar = true }
        pending[token] = slot
    }

    /// True when this source passed the matching key-down.
    public mutating func end(token: String, fromTap: Bool) -> Bool {
        guard var slot = pending[token] else { return false }
        if fromTap {
            guard slot.tap else { return false }
            slot.tap = false
        } else {
            guard slot.kar else { return false }
            slot.kar = false
        }
        if slot.tap || slot.kar {
            pending[token] = slot
        } else {
            pending[token] = nil
        }
        return true
    }

    public mutating func reset() {
        pending.removeAll()
    }
}

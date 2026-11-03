import Foundation
import Synchronization

public struct KeySnapshot: Sendable, Equatable {
    public var held: Set<String>
    public var dragging: Bool

    public init(held: Set<String> = [], dragging: Bool = false) {
        self.held = held
        self.dragging = dragging
    }
}

/// Shared between the event-tap callback and the main actor.
public final class HeldKeyStore: @unchecked Sendable {
    private let mutex: Mutex<KeySnapshot>

    public init() {
        mutex = Mutex(KeySnapshot())
    }

    public func setHeld(_ token: String, down: Bool) {
        mutex.withLock { snap in
            if down {
                snap.held.insert(token)
            } else {
                snap.held.remove(token)
            }
        }
    }

    public func isHeld(_ token: String) -> Bool {
        mutex.withLock { $0.held.contains(token) }
    }

    public func setDragging(_ value: Bool) {
        mutex.withLock { $0.dragging = value }
    }

    public func snapshot() -> KeySnapshot {
        mutex.withLock { $0 }
    }

    public func clearHeld() {
        mutex.withLock { $0.held.removeAll() }
    }
}

/// Dedupes the same physical key arriving from both the event tap and Karabiner HID.
public final class KeyDeduper: @unchecked Sendable {
    private let mutex: Mutex<[String: UInt64]>
    private let windowNanos: UInt64

    public init(windowMillis: UInt64 = 30) {
        mutex = Mutex([:])
        windowNanos = windowMillis * 1_000_000
    }

    /// Returns true if this event should be handled (first of a pair).
    public func shouldHandle(token: String, down: Bool, nowNanos: UInt64) -> Bool {
        let key = "\(token):\(down)"
        return mutex.withLock { map in
            if let last = map[key], nowNanos &- last < windowNanos {
                return false
            }
            map[key] = nowNanos
            return true
        }
    }
}

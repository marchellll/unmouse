import Foundation

/// Edge-triggered alone-modifier tap detector with max hold duration.
public struct AloneTapTracker: Sendable, Equatable {
    public private(set) var aloneCandidate: String?
    public private(set) var aloneInterrupted: Bool
    public private(set) var modifiersDown: Set<String>
    /// Nanoseconds since boot when the alone candidate went down.
    private var candidateDownNanos: UInt64?
    /// Max hold for a tap. Holds longer than this are ignored on release.
    public var maxTapNanos: UInt64

    public init(
        aloneCandidate: String? = nil,
        aloneInterrupted: Bool = false,
        modifiersDown: Set<String> = [],
        maxTapMilliseconds: UInt64 = 200
    ) {
        self.aloneCandidate = aloneCandidate
        self.aloneInterrupted = aloneInterrupted
        self.modifiersDown = modifiersDown
        self.candidateDownNanos = nil
        self.maxTapNanos = maxTapMilliseconds * 1_000_000
    }

    public enum Event: Sendable, Equatable {
        case modifier(token: String, down: Bool, nowNanos: UInt64)
        case otherKey
    }

    public enum Result: Sendable, Equatable {
        case ignored
        case down
        /// `alone` is true when this up completes an uninterrupted solo tap within max duration.
        case up(alone: Bool)
    }

    public mutating func setMaxTapMilliseconds(_ ms: UInt64) {
        maxTapNanos = max(1, ms) * 1_000_000
    }

    @discardableResult
    public mutating func handle(_ event: Event) -> Result {
        switch event {
        case .otherKey:
            aloneInterrupted = true
            aloneCandidate = nil
            candidateDownNanos = nil
            return .ignored

        case .modifier(let token, let down, let now):
            if down {
                if modifiersDown.contains(token) {
                    return .ignored
                }
                modifiersDown.insert(token)
                if let candidate = aloneCandidate, candidate != token {
                    aloneInterrupted = true
                } else if aloneCandidate == nil {
                    aloneCandidate = token
                    aloneInterrupted = false
                    candidateDownNanos = now
                }
                return .down
            }

            guard modifiersDown.contains(token) else {
                return .ignored
            }
            modifiersDown.remove(token)
            var wasAlone = aloneCandidate == token && !aloneInterrupted
            if wasAlone, let downAt = candidateDownNanos {
                let held = now &- downAt
                if held > maxTapNanos {
                    wasAlone = false
                }
            }
            if aloneCandidate == token {
                aloneCandidate = nil
                aloneInterrupted = false
                candidateDownNanos = nil
            }
            return .up(alone: wasAlone)
        }
    }
}

/// Whether one side of a modifier is down, from a flagsChanged event.
/// Karabiner sometimes sets only the other side's device bit on this key's event.
public enum ModifierSide {
    public static func isDown(ownSide: Bool, otherSide: Bool, generic: Bool, trackedDown: Bool) -> Bool {
        if ownSide { return true }
        if otherSide { return !trackedDown }
        return generic
    }
}

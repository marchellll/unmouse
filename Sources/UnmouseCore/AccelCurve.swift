import Foundation

/// One knot on the free-mode speed curve. `t` is seconds a direction has been held.
/// `y` is a fraction of top speed, 0...1.
public struct SpeedKnot: Codable, Sendable, Equatable {
    public var t: Double
    public var y: Double

    public init(t: Double, y: Double) {
        self.t = max(0, t)
        self.y = min(1, max(0, y))
    }
}

/// Shape of the free-mode speed curve. `linear` is a flat line at top speed.
public enum AccelPreset: String, Codable, Sendable, CaseIterable, Equatable {
    case linear
    case diagonal
    case glide
    case custom

    public var title: String {
        switch self {
        case .linear: "Linear"
        case .diagonal: "Diagonal"
        case .glide: "Glide"
        case .custom: "Custom"
        }
    }
}

/// Speed while a direction key is held, as a fraction of top speed.
public enum AccelCurve {
    /// Seconds Glide takes to reach and hold top speed.
    public static let defaultDuration: Double = 3.5

    public static func knots(for preset: AccelPreset, duration: Double = defaultDuration) -> [SpeedKnot] {
        let duration = max(0.5, duration)
        switch preset {
        case .linear:
            return [SpeedKnot(t: 0, y: 1), SpeedKnot(t: duration, y: 1)]
        case .diagonal:
            return [SpeedKnot(t: 0, y: 0), SpeedKnot(t: duration, y: 1)]
        case .glide, .custom:
            // Tuned shape at 3.5s: quick rise, a long shelf, then top speed just after 3s.
            let scale = duration / defaultDuration
            return [
                SpeedKnot(t: 0, y: 0.09),
                SpeedKnot(t: 0.40 * scale, y: 0.68),
                SpeedKnot(t: 2.72 * scale, y: 0.74),
                SpeedKnot(t: 3.20 * scale, y: 1),
                SpeedKnot(t: duration, y: 1),
            ]
        }
    }

    public static func matching(_ knots: [SpeedKnot], duration: Double = defaultDuration) -> AccelPreset {
        let span = knots.map(\.t).max() ?? duration
        let window = span > 0 ? span : duration
        for preset in [AccelPreset.linear, .diagonal, .glide] where close(knots, Self.knots(for: preset, duration: window)) {
            return preset
        }
        return .custom
    }

    /// Fraction of top speed after `seconds` of holding a direction.
    public static func fraction(knots: [SpeedKnot], at seconds: Double) -> Double {
        let knots = knots.sorted { $0.t < $1.t }
        guard let first = knots.first else { return 1 }
        if seconds <= first.t { return first.y }
        guard let last = knots.last else { return first.y }
        if seconds >= last.t { return last.y }
        var index = 0
        while index + 1 < knots.count, knots[index + 1].t < seconds {
            index += 1
        }
        let a = knots[index]
        let b = knots[min(index + 1, knots.count - 1)]
        let span = b.t - a.t
        if span <= 0 { return b.y }
        let u = (seconds - a.t) / span
        // Two knots stay straight (flat or diagonal). More knots ease between shoulders.
        let w = knots.count <= 2 ? u : smoothstep(u)
        return a.y + (b.y - a.y) * w
    }

    public static func normalized(_ knots: [SpeedKnot], duration: Double = defaultDuration) -> [SpeedKnot] {
        let duration = max(0.5, duration)
        let sorted = knots
            .map { SpeedKnot(t: $0.t, y: $0.y) }
            .sorted { $0.t < $1.t }
        guard sorted.count >= 2 else { return Self.knots(for: .glide, duration: duration) }
        var result: [SpeedKnot] = []
        result.reserveCapacity(min(8, sorted.count))
        for (index, knot) in sorted.enumerated() {
            if result.count == 8 { break }
            let isLast = index == sorted.count - 1
            if let previous = result.last, !isLast, knot.t - previous.t < 0.05 {
                continue
            }
            result.append(knot)
        }
        guard result.count >= 2 else { return Self.knots(for: .glide, duration: duration) }
        result[0].t = 0
        result[result.count - 1].t = duration
        return result
    }

    private static func close(_ knots: [SpeedKnot], _ preset: [SpeedKnot]) -> Bool {
        guard knots.count == preset.count else { return false }
        for (knot, expected) in zip(knots, preset) {
            if abs(knot.t - expected.t) > 0.001 || abs(knot.y - expected.y) > 0.001 {
                return false
            }
        }
        return true
    }

    private static func smoothstep(_ u: Double) -> Double {
        let u = min(1, max(0, u))
        return u * u * (3 - 2 * u)
    }
}

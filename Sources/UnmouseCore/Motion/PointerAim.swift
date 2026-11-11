import CoreGraphics
import Foundation

/// Where the pointer is after we post a move.
/// `NSEvent.mouseLocation` stays on the previous point until the window server applies the event.
/// A click or a cursor nudge that reads it in that gap lands on the old point and overwrites the move.
public struct PointerAim: Equatable, Sendable {
    public var posted: CGPoint?
    /// System location when `posted` was published. While the system still reports this, the post has not landed.
    public var anchor: CGPoint?

    public init() {}

    public mutating func remember(live: CGPoint, point: CGPoint) {
        if let posted {
            if Self.near(live, posted) {
                anchor = posted
            } else if let anchor, Self.near(live, anchor) {
                // System is still on the pre-post point. Keep the anchor so the new point stays in force.
            } else {
                anchor = live
            }
        } else {
            anchor = live
        }
        posted = point
    }

    /// Posted point while the system location is caught up or still on the anchor.
    /// Any other location is a real pointer move: drop the aim and use it.
    /// When `displays` is non-empty and the posted point is outside every display, drop the
    /// aim and clamp. A `live` still on the on-screen anchor clamps the posted point, so the
    /// next delta starts at the edge. Any other `live` is clamped itself: it followed the
    /// virtual post, or it is a real move. Empty `displays` keeps the lag-only path (tests).
    /// ponytail: a half-applied event queue could report a point between anchor and posted, and this trusts that point. Absolute positions land as the latest event, so the in-between read does not show up.
    public mutating func resolve(live: CGPoint, displays: [CGRect] = []) -> CGPoint {
        if !displays.isEmpty, let posted, !Self.onScreen(posted, displays: displays) {
            let edge = Self.clamp(posted, to: displays)
            let laggedAtAnchor = if let anchor {
                Self.onScreen(live, displays: displays) && Self.near(live, anchor)
            } else {
                false
            }
            self.posted = nil
            self.anchor = nil
            return laggedAtAnchor ? edge : Self.clamp(live, to: displays)
        }
        guard let posted, let anchor else {
            return displays.isEmpty ? live : Self.clamp(live, to: displays)
        }
        if Self.near(live, posted) || Self.near(live, anchor) { return posted }
        self.posted = nil
        self.anchor = nil
        return displays.isEmpty ? live : Self.clamp(live, to: displays)
    }

    /// Inclusive edges. `CGRect.contains` excludes maxX/maxY, which would treat a cursor on the bottom as off-screen.
    public static func onScreen(_ point: CGPoint, displays: [CGRect]) -> Bool {
        displays.contains { r in
            point.x >= r.minX && point.x <= r.maxX && point.y >= r.minY && point.y <= r.maxY
        }
    }

    /// Nearest point that still lies on some display. Identity when already on-screen or `displays` is empty.
    public static func clamp(_ point: CGPoint, to displays: [CGRect]) -> CGPoint {
        guard !displays.isEmpty else { return point }
        if onScreen(point, displays: displays) { return point }
        var best = point
        var bestDist = CGFloat.greatestFiniteMagnitude
        for r in displays {
            let c = CGPoint(
                x: min(max(point.x, r.minX), r.maxX),
                y: min(max(point.y, r.minY), r.maxY)
            )
            let dx = c.x - point.x
            let dy = c.y - point.y
            let d = dx * dx + dy * dy
            if d < bestDist {
                bestDist = d
                best = c
            }
        }
        return best
    }

    public static func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1.5 && abs(a.y - b.y) < 1.5
    }
}

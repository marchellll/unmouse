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
    /// ponytail: a half-applied event queue could report a point between anchor and posted, and this trusts that point. Absolute positions land as the latest event, so the in-between read does not show up.
    public mutating func resolve(live: CGPoint) -> CGPoint {
        guard let posted, let anchor else { return live }
        if Self.near(live, posted) || Self.near(live, anchor) { return posted }
        self.posted = nil
        self.anchor = nil
        return live
    }

    public static func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1.5 && abs(a.y - b.y) < 1.5
    }
}

import CoreGraphics
import Foundation

/// Converts between AppKit bottom-left coordinates and CGEvent global top-left coordinates.
public enum CoordinateSpace {
    /// AppKit point (origin bottom-left of primary, y up) → CGEvent global (origin top-left of primary, y down).
    public static func appKitToCGEvent(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// CGEvent global → AppKit.
    public static func cgEventToAppKit(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func cellFrame(
        screenOrigin: CGPoint,
        screenSize: CGSize,
        rows: Int,
        cols: Int,
        row: Int,
        col: Int
    ) -> CGRect {
        let cellW = screenSize.width / CGFloat(cols)
        let cellH = screenSize.height / CGFloat(rows)
        let x = screenOrigin.x + CGFloat(col) * cellW
        let y = screenOrigin.y + screenSize.height - CGFloat(row + 1) * cellH
        return CGRect(x: x, y: y, width: cellW, height: cellH)
    }
}

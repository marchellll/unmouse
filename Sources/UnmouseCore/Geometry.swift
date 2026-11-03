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

    /// Center of a cell in screen-local AppKit coordinates (origin bottom-left of that screen).
    public static func cellCenter(
        screenOrigin: CGPoint,
        screenSize: CGSize,
        rows: Int,
        cols: Int,
        row: Int,
        col: Int
    ) -> CGPoint {
        let cellW = screenSize.width / CGFloat(cols)
        let cellH = screenSize.height / CGFloat(rows)
        // row 0 is top of screen in grid labels
        let x = screenOrigin.x + (CGFloat(col) + 0.5) * cellW
        let y = screenOrigin.y + screenSize.height - (CGFloat(row) + 0.5) * cellH
        return CGPoint(x: x, y: y)
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

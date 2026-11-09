import CoreGraphics
import Foundation

public enum GridGuideClick: Equatable, Sendable {
    case left
    case right
    /// Finish a cell, then Option leaves the grid in free mode.
    case toFree
}

public struct AimedCell: Equatable, Sendable {
    public var row: Int
    public var col: Int
    public var label: String
    public var frame: CGRect

    public init(row: Int, col: Int, label: String, frame: CGRect) {
        self.row = row
        self.col = col
        self.label = label
        self.frame = frame
    }
}

/// What to draw in front of the grid for one tutorial beat.
public struct GridGuideCue: Equatable, Sendable {
    /// Cells to shimmer, outermost first. Empty when this grid does not contain the target.
    public var frames: [CGRect]
    /// Cell the card sits beside. The open grid, when the target is in another cell.
    public var anchor: CGRect
    /// The target. The card prefers the side of `anchor` closest to this point.
    public var focus: CGPoint
    public var title: String
    public var detail: String

    public init(frames: [CGRect], anchor: CGRect, focus: CGPoint, title: String, detail: String) {
        self.frames = frames
        self.anchor = anchor
        self.focus = focus
        self.title = title
        self.detail = detail
    }
}

extension GridState {
    /// Root cell, then each finer cell, for a point on this screen. Empty when the point is outside.
    /// ponytail: one point picks the cell. A target that straddles a line belongs to the cell under its center.
    public func aimPath(containing point: CGPoint) -> [AimedCell] {
        guard let root = levels.first else { return [] }
        var origin = root.origin
        var size = root.size
        var rows = rootRows
        var cols = rootCols
        var path: [AimedCell] = []
        for level in 0..<max(depth, 1) {
            guard let hit = Self.cellIndex(point: point, origin: origin, size: size, rows: rows, cols: cols) else { break }
            let labels = levelLabels(rows: rows, cols: cols, nested: level > 0)
            let index = hit.row * cols + hit.col
            let label = labels.indices.contains(index) ? labels[index] : ""
            let frame = CoordinateSpace.cellFrame(
                screenOrigin: origin,
                screenSize: size,
                rows: rows,
                cols: cols,
                row: hit.row,
                col: hit.col
            )
            path.append(AimedCell(row: hit.row, col: hit.col, label: label, frame: frame))
            if level + 1 >= depth { break }
            origin = frame.origin
            size = frame.size
            rows = subRows
            cols = subCols
        }
        return path
    }

    /// Cue for the grid currently on screen. Nil when `point` is off this screen.
    public func guide(at point: CGPoint, click: GridGuideClick) -> GridGuideCue? {
        let path = aimPath(containing: point)
        guard !path.isEmpty else { return nil }
        let level = CGRect(origin: currentLevel.origin, size: currentLevel.size)
        let index = levels.count - 1
        let aimed = index < path.count ? path[index] : nil
        let onTarget = aimed.map { level.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) } ?? false
        if !onTarget {
            if click == .toFree {
                return GridGuideCue(
                    frames: [],
                    anchor: level,
                    focus: CGPoint(x: level.midX, y: level.midY),
                    title: "Then `⌥`",
                    detail: "Drop into free mode."
                )
            }
            return GridGuideCue(
                frames: [],
                anchor: level,
                focus: CGPoint(x: level.midX, y: level.midY),
                title: "Not this cell",
                detail: "`⌫` — the target is outside this grid."
            )
        }
        let here = path[index]
        let typed = currentLevel.typed
        let rest = here.label.hasPrefix(typed) ? String(here.label.dropFirst(typed.count)) : here.label
        let title = KeycapMarkup.typeKeys(rest)
        return GridGuideCue(
            frames: path.dropFirst(index).map(\.frame),
            anchor: here.frame,
            focus: point,
            title: title,
            detail: GridGuideCopy.detail(opensFiner: levels.count < depth, click: click)
        )
    }

    private func levelLabels(rows: Int, cols: Int, nested: Bool) -> [String] {
        if nested, let single = GridLabels.singleLabels(chars: chars, rows: rows, cols: cols) {
            return single
        }
        return GridLabels.labels(chars: chars, rows: rows, cols: cols)
    }

    private static func cellIndex(
        point: CGPoint,
        origin: CGPoint,
        size: CGSize,
        rows: Int,
        cols: Int
    ) -> (row: Int, col: Int)? {
        let rect = CGRect(origin: origin, size: size)
        guard rect.contains(point), rows > 0, cols > 0 else { return nil }
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        guard cellW > 0, cellH > 0 else { return nil }
        let col = min(cols - 1, max(0, Int((point.x - origin.x) / cellW)))
        let row = min(rows - 1, max(0, Int((origin.y + size.height - point.y) / cellH)))
        return (row, col)
    }
}

public enum GridGuideCopy {
    public static func detail(opensFiner: Bool, click: GridGuideClick) -> String {
        switch (opensFiner, click) {
        case (true, .left): "Last key opens a finer grid. `␣` clicks the rectangle so far."
        case (true, .right): "Last key opens a finer grid. `A` right-clicks the rectangle so far."
        case (false, .left): "`␣` hits this cell."
        case (false, .right): "`A` right-clicks this cell."
        case (true, .toFree): "Last key opens a finer grid. Then `⌥` — drop into free mode."
        case (false, .toFree): "Then `⌥` — drop into free mode."
        }
    }
}

public enum GridGuideLayout {
    /// Card just outside `cell`, on the side closest to `point` that still fits in `bounds`.
    /// `avoid` is the target itself; the card steps aside when the target crosses the cell edge.
    public static func cardFrame(
        card: CGSize,
        around cell: CGRect,
        near point: CGPoint,
        in bounds: CGRect,
        avoid: CGRect = .null,
        gap: CGFloat = 12
    ) -> CGRect {
        let candidates = [
            CGRect(x: point.x - card.width / 2, y: cell.maxY + gap, width: card.width, height: card.height),
            CGRect(x: point.x - card.width / 2, y: cell.minY - gap - card.height, width: card.width, height: card.height),
            CGRect(x: cell.maxX + gap, y: point.y - card.height / 2, width: card.width, height: card.height),
            CGRect(x: cell.minX - gap - card.width, y: point.y - card.height / 2, width: card.width, height: card.height),
        ].map { clamp($0, in: bounds) }
        let clear = candidates.filter { !overlaps($0, cell: cell, avoid: avoid) }
        let pool = clear.isEmpty ? candidates : clear
        if let best = pool.min(by: { distance($0, to: point) < distance($1, to: point) }), !clear.isEmpty {
            return best
        }
        let corners = [
            CGPoint(x: bounds.minX + gap, y: bounds.maxY - card.height - gap),
            CGPoint(x: bounds.maxX - card.width - gap, y: bounds.maxY - card.height - gap),
            CGPoint(x: bounds.minX + gap, y: bounds.minY + gap),
            CGPoint(x: bounds.maxX - card.width - gap, y: bounds.minY + gap),
        ]
        let origin = corners.max { distance(CGRect(origin: $0, size: card), to: point) < distance(CGRect(origin: $1, size: card), to: point) }
            ?? CGPoint(x: bounds.minX + gap, y: bounds.minY + gap)
        return clamp(CGRect(origin: origin, size: card), in: bounds)
    }

    private static func clamp(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        var rect = rect
        if rect.minX < bounds.minX { rect.origin.x = bounds.minX }
        if rect.minY < bounds.minY { rect.origin.y = bounds.minY }
        if rect.maxX > bounds.maxX { rect.origin.x -= rect.maxX - bounds.maxX }
        if rect.maxY > bounds.maxY { rect.origin.y -= rect.maxY - bounds.maxY }
        if rect.minX < bounds.minX { rect.origin.x = bounds.minX }
        if rect.minY < bounds.minY { rect.origin.y = bounds.minY }
        return rect
    }

    private static func overlaps(_ rect: CGRect, cell: CGRect, avoid: CGRect) -> Bool {
        let hit = rect.intersection(cell)
        if hit.width > 4, hit.height > 4 { return true }
        guard !avoid.isNull, !avoid.isEmpty else { return false }
        let over = rect.intersection(avoid)
        return over.width > 4 && over.height > 4
    }

    private static func distance(_ rect: CGRect, to point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

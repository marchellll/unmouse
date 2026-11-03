import CoreGraphics
import Foundation

/// A point (and optional hit-box) that needs a label.
public struct LabelSite: Equatable, Sendable, Identifiable {
    public var id: String
    /// Preferred anchor — usually the target center.
    public var point: CGPoint
    /// Target hit-box used for in-situ placement.
    public var bounds: CGRect
    /// Opaque app data (hint code, title, …) echoed back on the placed label.
    public var tag: String

    public init(id: String, point: CGPoint, bounds: CGRect = .null, tag: String = "") {
        self.id = id
        self.point = point
        self.bounds = bounds
        self.tag = tag
    }
}

/// Placed label. `leader` is empty when the badge stays in-situ (no line).
public struct PlacedLabel: Equatable, Sendable, Identifiable {
    public var id: String
    public var tag: String
    public var frame: CGRect
    public var target: CGPoint
    /// Stem polyline, or empty when pinned on the element.
    public var leader: [CGPoint]

    public init(id: String, tag: String, frame: CGRect, target: CGPoint, leader: [CGPoint]) {
        self.id = id
        self.tag = tag
        self.frame = frame
        self.target = target
        self.leader = leader
    }
}

public enum LeaderStyle: String, Equatable, Sendable {
    case straight
    case elbow
    case comb
}

public struct BoundaryLabelConfig: Equatable, Sendable {
    public var labelSize: CGSize
    /// Gap between badges on a local rail.
    public var padding: CGFloat
    /// |Δy| tolerance for “same row” (kills vertical Katamari chaining).
    public var rowToleranceY: CGFloat
    /// Gap from row center to local baseline (AppKit Y-up).
    public var railGap: CGFloat
    /// Hard cap on badge↔target distance; beyond this → snap in-situ, no leader.
    public var maxLeashDistance: CGFloat
    public var stemLength: CGFloat
    public var leaderStyle: LeaderStyle
    /// Kept for call-site compatibility.
    public var tierGap: CGFloat
    public var bandThreshold: CGFloat
    public var nudgeDistance: CGFloat
    public var iterations: Int
    public var floatOffset: CGFloat
    public var clusterRadius: CGFloat
    public var ringPad: CGFloat
    public var marginInset: CGFloat
    public var gutter: CGFloat

    public init(
        labelSize: CGSize = CGSize(width: 28, height: 20),
        padding: CGFloat = 4,
        rowToleranceY: CGFloat = 10,
        railGap: CGFloat = 4,
        maxLeashDistance: CGFloat = 28,
        stemLength: CGFloat = 4,
        leaderStyle: LeaderStyle = .straight,
        tierGap: CGFloat = 6,
        bandThreshold: CGFloat = 10,
        nudgeDistance: CGFloat = 22,
        iterations: Int = 10,
        floatOffset: CGFloat = 0,
        clusterRadius: CGFloat = 72,
        ringPad: CGFloat = 36,
        marginInset: CGFloat = 10,
        gutter: CGFloat = 14
    ) {
        self.labelSize = labelSize
        self.padding = padding
        self.rowToleranceY = rowToleranceY
        self.railGap = railGap
        self.maxLeashDistance = maxLeashDistance
        self.stemLength = stemLength
        self.leaderStyle = leaderStyle
        self.tierGap = tierGap
        self.bandThreshold = bandThreshold
        self.nudgeDistance = nudgeDistance
        self.iterations = iterations
        self.floatOffset = floatOffset
        self.clusterRadius = clusterRadius
        self.ringPad = ringPad
        self.marginInset = marginInset
        self.gutter = gutter
    }

    public static let `default` = BoundaryLabelConfig()
}

/// Strict-row local labels with a hard distance leash.
///
/// 1. Place every badge in-situ on its element (no leader)
/// 2. Partition into strict horizontal rows (`|Δy| ≤ rowToleranceY`) — never
///    chain vertically across editor lines
/// 3. Within a row, collision-cluster only; isolates stay put
/// 4. Dense row neighbors get a local baseline; if X-relax pushes a badge
///    past `maxLeashDistance`, snap it back in-situ and drop the leader
public enum BoundaryLabeler {
    public static func layout(
        sites: [LabelSite],
        bounds: CGRect,
        config: BoundaryLabelConfig = .default
    ) -> [PlacedLabel] {
        guard !sites.isEmpty else { return [] }

        var frames = sites.map { inSituFrame(site: $0, size: config.labelSize) }
        clampAll(&frames, in: bounds)
        var leaders = Array(repeating: [CGPoint](), count: sites.count)

        let rows = strictRows(sites: sites, toleranceY: config.rowToleranceY)
        for row in rows {
            let clusters = collisionClusters(indices: row, frames: frames, padding: config.padding)
            for cluster in clusters {
                if cluster.count == 1 { continue }
                layoutLocalRow(
                    indices: cluster,
                    sites: sites,
                    frames: &frames,
                    leaders: &leaders,
                    bounds: bounds,
                    config: config
                )
            }
        }

        clampAll(&frames, in: bounds)

        return sites.indices.map { i in
            PlacedLabel(
                id: sites[i].id,
                tag: sites[i].tag,
                frame: frames[i],
                target: sites[i].point,
                leader: leaders[i]
            )
        }
    }

    public static func crossingCount(_ labels: [PlacedLabel]) -> Int {
        crossingPairs(labels).count
    }

    public static func crossingPairs(_ labels: [PlacedLabel]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        for i in 0..<labels.count {
            for j in (i + 1)..<labels.count {
                let a = labels[i]
                let b = labels[j]
                guard a.leader.count >= 2, b.leader.count >= 2 else { continue }
                if polylinesCross(a.leader, b.leader) {
                    pairs.append((a.id, b.id))
                }
            }
        }
        return pairs
    }
}

// MARK: - In-situ seed

/// Center the badge on the target point (true in-situ).
private func inSituFrame(site: LabelSite, size: CGSize) -> CGRect {
    CGRect(
        x: site.point.x - size.width / 2,
        y: site.point.y - size.height / 2,
        width: size.width,
        height: size.height
    )
}

// MARK: - Strict rows (no vertical chaining)

private func strictRows(sites: [LabelSite], toleranceY: CGFloat) -> [[Int]] {
    let sorted = sites.indices.sorted { sites[$0].point.y < sites[$1].point.y }
    var rows: [[Int]] = []
    var current: [Int] = []
    var anchorY: CGFloat = 0

    for idx in sorted {
        let y = sites[idx].point.y
        if current.isEmpty {
            current = [idx]
            anchorY = y
        } else if abs(y - anchorY) <= toleranceY {
            current.append(idx)
        } else {
            rows.append(current)
            current = [idx]
            anchorY = y
        }
    }
    if !current.isEmpty { rows.append(current) }
    return rows
}

// MARK: - Collision components (within a row)

private func collisionClusters(indices: [Int], frames: [CGRect], padding: CGFloat) -> [[Int]] {
    var visited = Set<Int>()
    var clusters: [[Int]] = []
    let indexSet = Set(indices)

    for start in indices {
        if visited.contains(start) { continue }
        var cluster: [Int] = []
        var queue = [start]
        visited.insert(start)
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            cluster.append(cur)
            let boxA = frames[cur].insetBy(dx: -padding, dy: -padding)
            for j in indices where !visited.contains(j) && indexSet.contains(j) {
                let boxB = frames[j].insetBy(dx: -padding, dy: -padding)
                if boxA.intersects(boxB) {
                    visited.insert(j)
                    queue.append(j)
                }
            }
        }
        clusters.append(cluster)
    }
    return clusters
}

// MARK: - Local row rail + leash

private func layoutLocalRow(
    indices: [Int],
    sites: [LabelSite],
    frames: inout [CGRect],
    leaders: inout [[CGPoint]],
    bounds: CGRect,
    config: BoundaryLabelConfig
) {
    let sorted = indices.sorted { sites[$0].point.x < sites[$1].point.x }
    let w = config.labelSize.width
    let h = config.labelSize.height
    let rowCenterY = sorted.map { sites[$0].point.y }.reduce(0, +) / CGFloat(sorted.count)

    // AppKit Y-up: prefer a baseline just above the row; flip below near the top.
    var baselineY = rowCenterY + config.railGap
    let topLimit = bounds.maxY - 2 - h
    if baselineY + h > topLimit {
        baselineY = rowCenterY - config.railGap - h
    }

    for idx in sorted {
        frames[idx] = CGRect(
            x: sites[idx].point.x - w / 2,
            y: baselineY,
            width: w,
            height: h
        )
    }

    // Forward X-relax along the row.
    for k in 1..<sorted.count {
        let prev = sorted[k - 1]
        let cur = sorted[k]
        let minX = frames[prev].maxX + config.padding
        if frames[cur].origin.x < minX {
            frames[cur].origin.x = minX
        }
    }

    // Leash: anything dragged farther than maxLeash snaps back in-situ.
    for idx in sorted {
        let d = hypot(frames[idx].midX - sites[idx].point.x, frames[idx].midY - sites[idx].point.y)
        if d > config.maxLeashDistance {
            frames[idx] = inSituFrame(site: sites[idx], size: config.labelSize)
            leaders[idx] = []
        } else {
            leaders[idx] = stemLeader(frame: frames[idx], target: sites[idx].point, config: config)
        }
    }
}

private func stemLeader(frame: CGRect, target: CGPoint, config: BoundaryLabelConfig) -> [CGPoint] {
    let above = frame.midY >= target.y
    let attach = above
        ? CGPoint(x: frame.midX, y: frame.minY)
        : CGPoint(x: frame.midX, y: frame.maxY)

    if abs(attach.x - target.x) < 1, abs(attach.y - target.y) < 1 {
        return []
    }

    switch config.leaderStyle {
    case .straight:
        return [attach, target]
    case .elbow:
        if abs(attach.x - target.x) < 1 { return [attach, target] }
        return [attach, CGPoint(x: frame.midX, y: target.y), target]
    case .comb:
        let stem = config.stemLength
        let joint = above
            ? CGPoint(x: frame.midX, y: frame.minY - stem)
            : CGPoint(x: frame.midX, y: frame.maxY + stem)
        if abs(attach.x - target.x) < 1 { return [attach, target] }
        return [attach, joint, target]
    }
}

private func polylinesCross(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
    guard a.count >= 2, b.count >= 2 else { return false }
    for i in 0..<(a.count - 1) {
        for j in 0..<(b.count - 1) {
            if segmentsCross(a[i], a[i + 1], b[j], b[j + 1]) {
                return true
            }
        }
    }
    return false
}

// MARK: - Geometry

private func clampAll(_ frames: inout [CGRect], in bounds: CGRect) {
    let inset = bounds.insetBy(dx: 2, dy: 2)
    for i in frames.indices {
        var r = frames[i]
        if r.minX < inset.minX { r.origin.x = inset.minX }
        if r.minY < inset.minY { r.origin.y = inset.minY }
        if r.maxX > inset.maxX { r.origin.x = inset.maxX - r.width }
        if r.maxY > inset.maxY { r.origin.y = inset.maxY - r.height }
        frames[i] = r
    }
}

private func segmentsCross(_ p1: CGPoint, _ q1: CGPoint, _ p2: CGPoint, _ q2: CGPoint) -> Bool {
    func orient(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    let o1 = orient(p1, q1, p2)
    let o2 = orient(p1, q1, q2)
    let o3 = orient(p2, q2, p1)
    let o4 = orient(p2, q2, q1)
    return o1 * o2 < 0 && o3 * o4 < 0
}

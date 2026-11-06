import CoreGraphics
import Foundation

public enum GridLabels {
    /// One character per cell, in string order, when the alphabet can give every cell its own key.
    public static func singleLabels(chars: String, rows: Int, cols: Int) -> [String]? {
        let cells = max(1, rows) * max(1, cols)
        var unique: [Character] = []
        var seen = Set<Character>()
        for ch in chars.lowercased() where seen.insert(ch).inserted {
            unique.append(ch)
            if unique.count == cells { break }
        }
        guard unique.count >= cells else { return nil }
        return (0..<cells).map { String(unique[$0]) }
    }

    /// Two characters per cell when every block fits in the alphabet. Otherwise three:
    /// the first character is still one rectangle, and the extra character names the cell inside it.
    public static func labels(chars: String, rows: Int, cols: Int) -> [String] {
        let alphabet = Array(chars)
        let rows = max(rows, 1)
        let cols = max(cols, 1)
        let cells = rows * cols
        guard !alphabet.isEmpty else { return Array(repeating: "", count: cells) }
        if let pairs = pairLabels(alphabet: alphabet, rows: rows, cols: cols) {
            return pairs
        }
        return tripleLabels(alphabet: alphabet, rows: rows, cols: cols, cells: cells)
    }

    public static func labelWidth(chars: String, rows: Int, cols: Int) -> Int {
        let count = chars.count
        guard count > 0 else { return 2 }
        let rows = max(rows, 1)
        let cols = max(cols, 1)
        return twoCharPlan(rows: rows, cols: cols, alphabetCount: count) == nil ? 3 : 2
    }

    private static func pairLabels(alphabet: [Character], rows: Int, cols: Int) -> [String]? {
        guard let plan = twoCharPlan(rows: rows, cols: cols, alphabetCount: alphabet.count) else { return nil }
        let rowSpans = split(rows, into: plan.blockRows)
        let colSpans = split(cols, into: plan.blockCols)
        var rowBlock = [Int](repeating: 0, count: rows)
        var rowLocal = [Int](repeating: 0, count: rows)
        var row = 0
        for (block, span) in rowSpans.enumerated() {
            for offset in 0..<span {
                rowBlock[row] = block
                rowLocal[row] = offset
                row += 1
            }
        }
        var colBlock = [Int](repeating: 0, count: cols)
        var colLocal = [Int](repeating: 0, count: cols)
        var col = 0
        for (block, span) in colSpans.enumerated() {
            for offset in 0..<span {
                colBlock[col] = block
                colLocal[col] = offset
                col += 1
            }
        }
        return (0..<(rows * cols)).map { index in
            let r = index / cols
            let c = index % cols
            let block = rowBlock[r] * plan.blockCols + colBlock[c]
            let second = rowLocal[r] * colSpans[colBlock[c]] + colLocal[c]
            return String(alphabet[block % alphabet.count]) + String(alphabet[second % alphabet.count])
        }
    }

    private static func tripleLabels(alphabet: [Character], rows: Int, cols: Int, cells: Int) -> [String] {
        let n = alphabet.count
        if let outer = plan(rows: rows, cols: cols, alphabetCount: n, accepts: { h, w in
            twoCharPlan(rows: h, cols: w, alphabetCount: n) != nil
        }) {
            var labels = Array(repeating: "", count: cells)
            let rowSpans = split(rows, into: outer.blockRows)
            let colSpans = split(cols, into: outer.blockCols)
            var row0 = 0
            for br in 0..<outer.blockRows {
                var col0 = 0
                for bc in 0..<outer.blockCols {
                    let h = rowSpans[br]
                    let w = colSpans[bc]
                    let first = alphabet[(br * outer.blockCols + bc) % n]
                    let inner = pairLabels(alphabet: alphabet, rows: h, cols: w) ?? []
                    for localRow in 0..<h {
                        for localCol in 0..<w {
                            labels[(row0 + localRow) * cols + (col0 + localCol)] = String(first) + inner[localRow * w + localCol]
                        }
                    }
                    col0 += w
                }
                row0 += rowSpans[br]
            }
            return labels
        }
        // ponytail: n³ is still smaller than the grid, so a unique rectangle tiling does not exist. Digits repeat modulo n.
        return (0..<cells).map { index in
            let first = alphabet[(index / (n * n)) % n]
            let second = alphabet[(index / n) % n]
            let third = alphabet[index % n]
            return String(first) + String(second) + String(third)
        }
    }

    private static func twoCharPlan(rows: Int, cols: Int, alphabetCount: Int) -> (blockRows: Int, blockCols: Int)? {
        plan(rows: rows, cols: cols, alphabetCount: alphabetCount) { h, w in
            h * w <= alphabetCount
        }
    }

    /// Squarer blocks first, then larger ones, so the first key is a clump rather than a row or a single cell.
    /// ponytail: scored by worst-block aspect plus 1/area. Ceiling: the search only considers an even block grid, not arbitrary rectangle partitions.
    private static func plan(
        rows: Int,
        cols: Int,
        alphabetCount: Int,
        accepts: (Int, Int) -> Bool
    ) -> (blockRows: Int, blockCols: Int)? {
        let n = max(alphabetCount, 1)
        var plans: [(blockRows: Int, blockCols: Int, penalty: Double)] = []
        for br in 1...rows {
            let maxBC = min(cols, n / br)
            guard maxBC >= 1 else { continue }
            for bc in 1...maxBC {
                let rowSpans = split(rows, into: br)
                let colSpans = split(cols, into: bc)
                var worst = 1.0
                var biggest = 1
                var ok = true
                for h in rowSpans {
                    for w in colSpans {
                        if !accepts(h, w) { ok = false }
                        let aspect = Double(max(h, w)) / Double(max(min(h, w), 1))
                        worst = max(worst, aspect)
                        biggest = max(biggest, h * w)
                    }
                }
                guard ok else { continue }
                plans.append((br, bc, worst + 1 / Double(biggest)))
            }
        }
        let multi = plans.filter { $0.blockRows * $0.blockCols > 1 }
        let pool = multi.isEmpty ? plans : multi
        return pool.min { $0.penalty < $1.penalty }.map { ($0.blockRows, $0.blockCols) }
    }

    private static func split(_ total: Int, into parts: Int) -> [Int] {
        let parts = max(parts, 1)
        let base = total / parts
        let extra = total % parts
        return (0..<parts).map { $0 < extra ? base + 1 : base }
    }

    /// Shown form of a clump: a compact block, still in string order. A 2- or 3-character key stays one line.
    public static func clumpText(_ clump: String) -> String {
        let count = clump.count
        guard count > 3 else { return clump }
        let across = Int(ceil(sqrt(Double(count))))
        var lines: [String] = []
        var rest = Substring(clump)
        while !rest.isEmpty {
            let take = min(across, rest.count)
            lines.append(String(rest.prefix(take)))
            rest = rest.dropFirst(take)
        }
        return lines.joined(separator: "\n")
    }
}

/// First-run grid dimensions. AppKit screen sizes are in points, so Retina scale is already accounted for.
public enum GridSizing {
    public static let targetHitSize: CGFloat = 44
    public static let targetCoverage: CGFloat = 0.9

    /// Same count both ways, so every nested cell keeps the screen's aspect ratio.
    /// The longer side after two refinements stays within 90% of a 44-point target.
    public static func dimensions(for screenSize: CGSize) -> (rows: Int, cols: Int) {
        let maxFinalCell = targetHitSize * targetCoverage
        let longest = max(screenSize.width, screenSize.height, 1)
        let count = max(1, Int(ceil(sqrt(longest / maxFinalCell))))
        return (rows: count, cols: count)
    }
}

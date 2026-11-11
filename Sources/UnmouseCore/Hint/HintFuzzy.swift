import CoreGraphics
import Foundation

/// Subsequence fuzzy ranker. Spaces and punctuation in the query are dropped.
public enum HintFuzzy {
    public struct Score: Equatable, Sendable, Comparable {
        public var value: Int
        public var matchRange: Range<Int>?

        public static func < (lhs: Score, rhs: Score) -> Bool { lhs.value < rhs.value }
    }

    /// Normalize a query: lowercase, drop spaces and punctuation.
    public static func normalizeQuery(_ raw: String) -> String {
        String(raw.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Score `label` for `query`. Exact `code` match always wins. Nil means no match.
    public static func score(query raw: String, label: String, code: String = "") -> Score? {
        let q = normalizeQuery(raw)
        if q.isEmpty { return Score(value: 0, matchRange: nil) }

        let rawLower = raw.lowercased()
        if !code.isEmpty {
            if code == rawLower || code == q {
                return Score(value: 1_000_000, matchRange: nil)
            }
            // Typing a hint code letter-by-letter must keep the bubble in the list.
            if code.hasPrefix(rawLower) || code.hasPrefix(q) {
                return Score(value: 900_000 - rawLower.count, matchRange: nil)
            }
        }

        let labelChars = Array(label.lowercased())
        let queryChars = Array(q)
        guard !queryChars.isEmpty else { return Score(value: 0, matchRange: nil) }

        var qi = 0
        var score = 0
        var consecutive = 0
        var firstMatch: Int?
        var lastMatch = -2
        var wordStart = true

        for (li, ch) in labelChars.enumerated() {
            if ch.isWhitespace || ch.isPunctuation {
                wordStart = true
                continue
            }
            guard qi < queryChars.count else { break }
            if ch == queryChars[qi] {
                if firstMatch == nil { firstMatch = li }
                var bonus = 10
                if wordStart { bonus += 40 }
                if li == lastMatch + 1 {
                    consecutive += 1
                    bonus += 15 * consecutive
                } else {
                    consecutive = 0
                }
                // Prefer earlier matches.
                bonus += max(0, 20 - li)
                score += bonus
                lastMatch = li
                qi += 1
                wordStart = false
            } else if ch.isLetter || ch.isNumber {
                wordStart = false
            }
        }

        guard qi == queryChars.count else { return nil }
        let end = lastMatch + 1
        let range = firstMatch.map { $0..<end }
        return Score(value: score, matchRange: range)
    }

    /// AppKit-ish highlight inside `frame` from a character range in `label`.
    public static func highlightFrame(label: String, range: Range<Int>?, frame: CGRect) -> CGRect {
        guard let range, !label.isEmpty, frame.width > 0 else { return frame }
        let n = CGFloat(label.count)
        let start = CGFloat(range.lowerBound) / n
        let end = CGFloat(min(range.upperBound, label.count)) / n
        let w = max(8, frame.width * (end - start))
        return CGRect(
            x: frame.minX + frame.width * start,
            y: frame.minY,
            width: w,
            height: frame.height
        )
    }
}

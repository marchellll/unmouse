import BoundaryLabeling
import CoreGraphics
import Foundation

public struct HintTarget: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var frame: CGRect
    public var code: String

    public init(id: String, title: String, frame: CGRect, code: String = "") {
        self.id = id
        self.title = title
        self.frame = frame
        self.code = code
    }
}

public struct HintBubble: Equatable, Sendable, Identifiable {
    public var id: String
    public var code: String
    public var bubbleFrame: CGRect
    public var targetPoint: CGPoint
    public var needsLeader: Bool
    /// Orthogonal dog-leg polyline in AppKit screen coords.
    public var leaderPath: [CGPoint]

    public init(
        id: String,
        code: String,
        bubbleFrame: CGRect,
        targetPoint: CGPoint,
        needsLeader: Bool,
        leaderPath: [CGPoint] = []
    ) {
        self.id = id
        self.code = code
        self.bubbleFrame = bubbleFrame
        self.targetPoint = targetPoint
        self.needsLeader = needsLeader
        self.leaderPath = leaderPath
    }
}

public enum HintCoder {
    /// Assign short codes from charset. Prefer title prefix when unique.
    public static func assignCodes(targets: [HintTarget], chars: String) -> [HintTarget] {
        let alphabet = Array(chars.lowercased())
        guard !alphabet.isEmpty else { return targets }

        var used: Set<String> = []
        var result: [HintTarget] = []

        func takeCode(preferred: String?) -> String? {
            if let preferred {
                let p = preferred.lowercased().filter { alphabet.contains($0) }
                if !p.isEmpty {
                    for len in 1...min(2, p.count) {
                        let candidate = String(p.prefix(len))
                        if !used.contains(candidate) {
                            used.insert(candidate)
                            return candidate
                        }
                    }
                }
            }
            for c in alphabet {
                let s = String(c)
                if !used.contains(s) {
                    used.insert(s)
                    return s
                }
            }
            for a in alphabet {
                for b in alphabet {
                    let s = String([a, b])
                    if !used.contains(s) {
                        used.insert(s)
                        return s
                    }
                }
            }
            return nil
        }

        for target in targets {
            var t = target
            // Full title (filtered to charset), not only the first glyph — so
            // "Save"/"Settings" can become "s"/"se" and Space can confirm "s".
            let pref = String(target.title.lowercased().filter { alphabet.contains($0) })
            if let code = takeCode(preferred: pref.isEmpty ? nil : pref) {
                t.code = code
                result.append(t)
            }
        }
        return result
    }
}

/// Thin Unmouse adapter over the publishable `BoundaryLabeling` package.
public enum HintLayout {
    public static let bubbleSize = BoundaryLabelConfig.default.labelSize
    public static let minTargetSize: CGFloat = 24
    public static let bubblePad = BoundaryLabelConfig.default.padding
    public static let marginInset = BoundaryLabelConfig.default.marginInset
    public static let gutter = BoundaryLabelConfig.default.gutter

    public static func layout(
        targets: [HintTarget],
        screenBounds: CGRect
    ) -> [HintBubble] {
        let sites = targets.map {
            LabelSite(
                id: $0.id,
                point: CGPoint(x: $0.frame.midX, y: $0.frame.midY),
                bounds: $0.frame,
                tag: $0.code
            )
        }
        let placed = BoundaryLabeler.layout(
            sites: sites,
            bounds: screenBounds,
            config: BoundaryLabelConfig(
                labelSize: bubbleSize,
                padding: bubblePad,
                marginInset: marginInset,
                gutter: gutter
            )
        )
        return placed.map {
            HintBubble(
                id: $0.id,
                code: $0.tag,
                bubbleFrame: $0.frame,
                targetPoint: $0.target,
                needsLeader: !$0.leader.isEmpty,
                leaderPath: $0.leader
            )
        }
    }

    static func crossingCount(_ bubbles: [HintBubble]) -> Int {
        BoundaryLabeler.crossingCount(bubbles.map(asPlaced))
    }

    static func crossingPairs(_ bubbles: [HintBubble]) -> [(String, String)] {
        BoundaryLabeler.crossingPairs(bubbles.map(asPlaced))
    }

    private static func asPlaced(_ b: HintBubble) -> PlacedLabel {
        PlacedLabel(
            id: b.id,
            tag: b.code,
            frame: b.bubbleFrame,
            target: b.targetPoint,
            leader: b.leaderPath
        )
    }
}

public struct HintState: Equatable, Sendable {
    public var targets: [HintTarget]
    public var typed: String
    public var armedID: String?

    public init(targets: [HintTarget] = []) {
        self.targets = targets
        self.typed = ""
        self.armedID = nil
    }

    public var visibleTargets: [HintTarget] {
        if typed.isEmpty { return targets }
        return targets.filter { $0.code.hasPrefix(typed) }
    }

    /// How to draw `code` for the keys typed so far.
    /// An exact code is highlighted even when a longer code still shares it —
    /// space can already fire that target. Longer codes tint only the typed prefix.
    public func style(for code: String) -> HintCodeStyle {
        guard !typed.isEmpty, code.hasPrefix(typed) else {
            return HintCodeStyle(highlighted: false, tintedCount: 0)
        }
        if code == typed {
            return HintCodeStyle(highlighted: true, tintedCount: 0)
        }
        return HintCodeStyle(highlighted: false, tintedCount: typed.count)
    }

    public mutating func typeCharacter(_ ch: Character) -> HintTypeResult {
        if armedID != nil { return .ignored }
        let next = typed + String(ch).lowercased()
        let matches = targets.filter { $0.code.hasPrefix(next) }
        if matches.isEmpty { return .ignored }
        typed = next
        if matches.count == 1, matches[0].code == next {
            armedID = matches[0].id
            return .armed(matches[0])
        }
        return .narrowed
    }

    /// Arm the target whose code equals `typed` exactly — needed when a
    /// single-char code shares a prefix with longer codes (space confirms it).
    @discardableResult
    public mutating func armExactMatch() -> Bool {
        if let armedID, targets.contains(where: { $0.id == armedID }) {
            return true
        }
        guard !typed.isEmpty else { return false }
        guard let match = targets.first(where: { $0.code == typed }) else { return false }
        armedID = match.id
        return true
    }

    public mutating func backspace() {
        armedID = nil
        if !typed.isEmpty {
            typed.removeLast()
        }
    }

    public var armedTarget: HintTarget? {
        guard let armedID else { return nil }
        return targets.first { $0.id == armedID }
    }
}

public enum HintTypeResult: Equatable, Sendable {
    case narrowed
    case armed(HintTarget)
    case ignored
}

public struct HintCodeStyle: Equatable, Sendable {
    /// Stroke the bubble. The typed code matches this label exactly, so it is actionable.
    public var highlighted: Bool
    /// Leading characters that match a still-open longer code. The rest stay the normal text color.
    public var tintedCount: Int

    public init(highlighted: Bool, tintedCount: Int) {
        self.highlighted = highlighted
        self.tintedCount = tintedCount
    }
}

/// Seam for future AI vision. Live source is accessibility.
public protocol HintSource: Sendable {
    func collect() async -> [HintTarget]
}

struct VisionHintSource: HintSource {
    init() {}
    func collect() async -> [HintTarget] { [] }
}

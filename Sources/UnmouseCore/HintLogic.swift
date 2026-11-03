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

    public init(id: String, code: String, bubbleFrame: CGRect, targetPoint: CGPoint, needsLeader: Bool) {
        self.id = id
        self.code = code
        self.bubbleFrame = bubbleFrame
        self.targetPoint = targetPoint
        self.needsLeader = needsLeader
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
            // generate sequential codes
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
            let pref = target.title.first.map(String.init)
            if let code = takeCode(preferred: pref) {
                t.code = code
                result.append(t)
            }
        }
        return result
    }
}

public enum HintLayout {
    public static let bubbleSize = CGSize(width: 28, height: 20)
    public static let minTargetSize: CGFloat = 24

    public static func layout(
        targets: [HintTarget],
        screenBounds: CGRect
    ) -> [HintBubble] {
        var placed: [CGRect] = []
        var bubbles: [HintBubble] = []

        for target in targets {
            let center = CGPoint(x: target.frame.midX, y: target.frame.midY)
            var bubble = CGRect(
                x: center.x - bubbleSize.width / 2,
                y: center.y - bubbleSize.height / 2,
                width: bubbleSize.width,
                height: bubbleSize.height
            )
            let tooSmall = target.frame.width < minTargetSize || target.frame.height < minTargetSize
            var needsLeader = tooSmall

            if placed.contains(where: { $0.intersects(bubble) }) || tooSmall {
                needsLeader = true
                bubble = findFreeSpot(near: center, avoiding: placed, in: screenBounds) ?? bubble
            }
            placed.append(bubble)
            bubbles.append(
                HintBubble(
                    id: target.id,
                    code: target.code,
                    bubbleFrame: bubble,
                    targetPoint: center,
                    needsLeader: needsLeader
                )
            )
        }
        return bubbles
    }

    static func findFreeSpot(near: CGPoint, avoiding: [CGRect], in bounds: CGRect) -> CGRect? {
        let offsets: [CGPoint] = [
            CGPoint(x: 20, y: 20),
            CGPoint(x: -20, y: 20),
            CGPoint(x: 20, y: -20),
            CGPoint(x: -20, y: -20),
            CGPoint(x: 40, y: 0),
            CGPoint(x: -40, y: 0),
            CGPoint(x: 0, y: 40),
            CGPoint(x: 0, y: -40),
            CGPoint(x: 40, y: 40),
            CGPoint(x: -40, y: -40),
        ]
        for off in offsets {
            var r = CGRect(
                x: near.x + off.x - bubbleSize.width / 2,
                y: near.y + off.y - bubbleSize.height / 2,
                width: bubbleSize.width,
                height: bubbleSize.height
            )
            r = r.intersection(bounds.insetBy(dx: 2, dy: 2))
            if r.width < bubbleSize.width * 0.5 { continue }
            if avoiding.contains(where: { $0.intersects(r) }) { continue }
            return CGRect(
                x: r.minX,
                y: r.minY,
                width: bubbleSize.width,
                height: bubbleSize.height
            )
        }
        return nil
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

/// Seam for future AI vision. Live source is accessibility.
public protocol HintSource: Sendable {
    func collect() async -> [HintTarget]
}

public struct VisionHintSource: HintSource {
    public init() {}
    public func collect() async -> [HintTarget] { [] }
}

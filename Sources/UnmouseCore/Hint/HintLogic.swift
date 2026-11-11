import BoundaryLabeling
import CoreGraphics
import Foundation

/// What happens when the selected hint row is activated.
public enum HintAction: Equatable, Sendable {
    case click
    case menu(pid: Int32, path: [String])
    case window(pid: Int32, title: String)
    case app(path: String)
}

public struct HintTarget: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var frame: CGRect
    public var code: String
    public var role: String
    public var action: HintAction
    /// Yellow letter bubble. False for text, nested menus, windows, apps.
    public var showsLabel: Bool
    public var isDefault: Bool
    public var isCancel: Bool
    /// AX subrole when known (`AXCloseButton`, …). Used to demote window chrome.
    public var subrole: String

    public init(
        id: String,
        title: String,
        frame: CGRect,
        code: String = "",
        role: String = "",
        action: HintAction = .click,
        showsLabel: Bool = true,
        isDefault: Bool = false,
        isCancel: Bool = false,
        subrole: String = ""
    ) {
        self.id = id
        self.title = title
        self.frame = frame
        self.code = code
        self.role = role
        self.action = action
        self.showsLabel = showsLabel
        self.isDefault = isDefault
        self.isCancel = isCancel
        self.subrole = subrole
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
    /// Cmd+N appears after this many typed query characters.
    public static let cmdNumberMinQuery = 3

    /// Fixed label alphabet. Digraphs cover hundreds of controls; no config knob.
    public static let alphabet = "abcdefghijklmnopqrstuvwxyz"

    /// Assign short codes from the fixed alphabet. Rank, then slice the title.
    public static func assignCodes(
        targets: [HintTarget],
        chars: String = alphabet,
        priorityWords: Set<String> = PriorityWords.load()
    ) -> [HintTarget] {
        let alphabet = Array(chars.lowercased())
        guard !alphabet.isEmpty else { return targets }

        var labeled = targets.enumerated().filter { $0.element.showsLabel }
        labeled.sort { a, b in
            let ra = rank(a.element, priority: priorityWords)
            let rb = rank(b.element, priority: priorityWords)
            if ra != rb { return ra < rb }
            if a.element.frame.maxY != b.element.frame.maxY {
                return a.element.frame.maxY > b.element.frame.maxY
            }
            if a.element.frame.minX != b.element.frame.minX {
                return a.element.frame.minX < b.element.frame.minX
            }
            return a.offset < b.offset
        }

        var used: Set<String> = []
        var codedByID: [String: String] = [:]

        for (_, target) in labeled {
            if let code = takeCode(for: target, alphabet: alphabet, used: &used, priority: priorityWords) {
                codedByID[target.id] = code
            }
        }

        return targets.map { t in
            var copy = t
            if let code = codedByID[t.id] {
                copy.code = code
            }
            return copy
        }
    }

    /// Lower is better. Focused-window controls beat menu bar / chrome so short codes land on real UI.
    private static func rank(_ t: HintTarget, priority: Set<String>) -> Int {
        if isDeprioritized(t) {
            // Menu bar last; window chrome / chevrons / sliders just above it.
            let base = t.role == roleMenuBarItem ? 50 : 40
            return priority.contains(t.title.lowercased()) ? base : base + 5
        }
        var base: Int
        if t.isDefault { base = 0 }
        else if t.isCancel { base = 1 }
        else if t.role == roleButton { base = 2 }
        else if t.role == "AXLink" { base = 3 }
        else if t.role == "AXCheckBox" || t.role == "AXRadioButton" || t.role == "AXTab"
            || t.role == "AXTabButton" || t.role == "AXPopUpButton" || t.role == "AXMenuButton"
        {
            base = 3
        } else { base = 4 }
        let title = t.title.lowercased()
        if priority.contains(title) { return base }
        return base + 10
    }

    /// No single-letter codes: menu bar, traffic lights, disclosure/arrows, sliders, empty chrome.
    static func isDeprioritized(_ t: HintTarget) -> Bool {
        if t.role == roleMenuBarItem { return true }
        if chromeSubroles.contains(t.subrole) { return true }
        if lowValueRoles.contains(t.role) { return true }
        return isWindowChromeTitle(t.title)
    }

    private static let chromeSubroles: Set<String> = [
        "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
    ]

    private static let lowValueRoles: Set<String> = [
        "AXDisclosureTriangle",
        "AXDecrementArrow",
        "AXIncrementArrow",
        "AXSlider",
        "AXColorWell",
        "AXToolbar",
        "AXSplitter",
        "AXGrowArea",
        "AXBusyIndicator",
    ]

    /// Traffic-light titles and common AX description forms.
    static func isWindowChromeTitle(_ title: String) -> Bool {
        let t = title.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        if chromeTitles.contains(t) { return true }
        // "close button", "minimise button", "enter full screen button"
        if t.hasSuffix(" button") {
            let stem = String(t.dropLast(" button".count))
            if chromeTitles.contains(stem) { return true }
        }
        return false
    }

    private static let chromeTitles: Set<String> = [
        "close", "minimize", "minimise", "zoom", "maximize", "maximise",
        "full screen", "fullscreen", "enter full screen", "exit full screen",
        "enter fullscreen", "exit fullscreen",
    ]

    private static func takeCode(
        for target: HintTarget,
        alphabet: [Character],
        used: inout Set<String>,
        priority: Set<String>
    ) -> String? {
        let alphaSet = Set(alphabet)
        let words = words(in: target.title, alphabet: alphaSet)
        let titleFlat = String(target.title.lowercased().filter { alphaSet.contains($0) })
        let deprioritized = isDeprioritized(target)
        // Single-char mnemonics stay on real in-window controls — not File/Close/chevrons.
        let allowSingle =
            !deprioritized
            && (target.isDefault || target.isCancel
                || target.role == roleButton
                || target.role == "AXLink"
                || target.role == "AXCheckBox"
                || target.role == "AXRadioButton"
                || target.role == "AXTab"
                || target.role == "AXTabButton"
                || target.role == "AXPopUpButton"
                || target.role == "AXMenuButton"
                || priority.contains(target.title.lowercased()))

        // Prefer ≤2 chars. 3-char only after every digraph is taken (n² is huge).
        var candidates: [String] = []
        if allowSingle, let first = words.first, let c = first.first {
            candidates.append(String(c))
        }
        if words.count >= 2, let first = words.first, first.count > 4 {
            let initials = String(words.compactMap(\.first).prefix(2))
            if initials.count == 2 { candidates.append(initials) }
        }
        if let first = words.first, first.count >= 2 {
            candidates.append(String(first.prefix(2)))
        }
        if titleFlat.count >= 2 { candidates.append(String(titleFlat.prefix(2))) }

        if let hit = claim(from: candidates, alphabet: alphaSet, used: &used) {
            return hit
        }

        // Leftover singles stay off deprioritized chrome / menu bar.
        if !deprioritized {
            for c in alphabet {
                let s = String(c)
                if !used.contains(s) {
                    used.insert(s)
                    return s
                }
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

        // Truly exhausted digraphs — mnemonic 3, then leftover triples.
        var long: [String] = []
        if let first = words.first, first.count >= 3 {
            long.append(String(first.prefix(3)))
        }
        if titleFlat.count >= 3 { long.append(String(titleFlat.prefix(3))) }
        if let hit = claim(from: long, alphabet: alphaSet, used: &used) {
            return hit
        }
        for a in alphabet {
            for b in alphabet {
                for c in alphabet {
                    let s = String([a, b, c])
                    if !used.contains(s) {
                        used.insert(s)
                        return s
                    }
                }
            }
        }
        return nil
    }

    private static func claim(
        from candidates: [String],
        alphabet: Set<Character>,
        used: inout Set<String>
    ) -> String? {
        for candidate in candidates where !candidate.isEmpty {
            if !used.contains(candidate), candidate.allSatisfy({ alphabet.contains($0) }) {
                used.insert(candidate)
                return candidate
            }
        }
        return nil
    }

    private static func words(in title: String, alphabet: Set<Character>) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in title.lowercased() {
            if alphabet.contains(ch) {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
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
        let sites = targets.filter { $0.showsLabel && !$0.code.isEmpty }.map {
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

public struct HintMatch: Equatable, Sendable, Identifiable {
    public var target: HintTarget
    public var score: Int
    public var matchRange: Range<Int>?
    public var cmdNumber: Int?

    public var id: String { target.id }
}

/// Freestanding vertical slot (screen-centered). ⌘T cycles these.
public enum HintPaletteAnchor: Int, CaseIterable, Equatable, Sendable {
    case semiBottom = 0
    case center = 1
    case semiTop = 2

    /// Fraction of overlay height for the palette center (top = 0).
    public var yFraction: CGFloat {
        switch self {
        case .semiTop: 0.28
        case .center: 0.50
        case .semiBottom: 0.72
        }
    }

    public mutating func toggle() {
        self = Self(rawValue: (rawValue + 1) % Self.allCases.count) ?? .semiBottom
    }
}

/// Where the hint palette sits. Attached points are AppKit screen coords (y up).
public enum HintPaletteLayout: Equatable, Sendable {
    /// Snapped against the focused window (below or beside).
    case attached(CGPoint)
    /// Screen-centered freestanding slot.
    case freestanding(HintPaletteAnchor)
}

/// Prefer nempel below → beside → freestanding center-below.
public enum HintPalettePlacement {
    public static let paletteSize = CGSize(width: 420, height: 320)
    public static let gap: CGFloat = 8

    /// Resolve layout for the focused window on its screen (both AppKit coords).
    public static func resolve(
        window: CGRect,
        screen: CGRect,
        paletteSize: CGSize = paletteSize,
        gap: CGFloat = gap
    ) -> HintPaletteLayout {
        guard screen.width > 8, screen.height > 8 else {
            return .freestanding(.semiBottom)
        }
        let visible = window.intersection(screen)
        guard !visible.isNull, !visible.isInfinite, visible.width > 8, visible.height > 8 else {
            return .freestanding(.semiBottom)
        }

        let halfW = paletteSize.width / 2
        let halfH = paletteSize.height / 2
        let needW = paletteSize.width + gap
        let needH = paletteSize.height + gap

        // 1) Below the window, centered on window midX, nempel to the bottom edge.
        let spaceBelow = visible.minY - screen.minY
        if spaceBelow >= needH {
            let x = clamp(visible.midX, screen.minX + halfW, screen.maxX - halfW)
            let y = visible.minY - gap - halfH
            return .attached(CGPoint(x: x, y: y))
        }

        // 2) Beside the window, centered on window midY, nempel to the side with room.
        let spaceRight = screen.maxX - visible.maxX
        let spaceLeft = visible.minX - screen.minX
        if spaceRight >= needW || spaceLeft >= needW {
            let y = clamp(visible.midY, screen.minY + halfH, screen.maxY - halfH)
            if spaceRight >= needW, spaceRight >= spaceLeft {
                let x = visible.maxX + gap + halfW
                return .attached(CGPoint(x: x, y: y))
            }
            if spaceLeft >= needW {
                let x = visible.minX - gap - halfW
                return .attached(CGPoint(x: x, y: y))
            }
            // Prefer the side that fits even if the other looked larger but was short.
            if spaceRight >= needW {
                let x = visible.maxX + gap + halfW
                return .attached(CGPoint(x: x, y: y))
            }
        }

        // 3) Give up — freestanding center-below; ⌘T cycles the rest.
        return .freestanding(.semiBottom)
    }

    public static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), max(lo, hi))
    }

    /// Keep the palette center on-screen in overlay-local points (y down).
    public static func clampCenter(
        x: CGFloat,
        y: CGFloat,
        halfWidth: CGFloat,
        halfHeight: CGFloat,
        in size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: clamp(x, min(halfWidth, size.width), max(min(halfWidth, size.width), size.width - halfWidth)),
            y: clamp(y, min(halfHeight, size.height), max(min(halfHeight, size.height), size.height - halfHeight))
        )
    }
}

public struct HintState: Equatable, Sendable {
    public var targets: [HintTarget]
    public var typed: String
    public var selectedIndex: Int
    public var matches: [HintMatch]
    /// Attached to the window, or a freestanding ⌘T slot.
    public var paletteLayout: HintPaletteLayout
    /// Holding ⌘ shows ⌘1–9 on bubbles/palette even before the query is long enough.
    public var commandHeld: Bool

    public init(targets: [HintTarget] = []) {
        self.targets = targets
        self.typed = ""
        // No auto-select on empty query — Tab/↑↓ pick a row; Space with none cancels.
        self.selectedIndex = -1
        self.matches = Self.rank(targets: targets, query: "")
        self.paletteLayout = .freestanding(.semiBottom)
        self.commandHeld = false
        applyCmdNumbers()
    }

    /// ⌘T: leave attach if needed, then cycle center-below → center → center-upper.
    public mutating func cyclePalette() {
        switch paletteLayout {
        case .attached:
            paletteLayout = .freestanding(.center)
        case .freestanding(var anchor):
            anchor.toggle()
            paletteLayout = .freestanding(anchor)
        }
    }

    /// Palette + window bubbles show ⌘N when the query is long enough, or while ⌘ is held.
    public var showsCmdNumbers: Bool {
        typed.count >= HintCoder.cmdNumberMinQuery || commandHeld
    }

    public func cmdNumber(forTargetID id: String) -> Int? {
        guard showsCmdNumbers else { return nil }
        return matches.first(where: { $0.target.id == id })?.cmdNumber
    }

    public mutating func setCommandHeld(_ held: Bool) {
        guard commandHeld != held else { return }
        commandHeld = held
        applyCmdNumbers()
    }

    /// Stamp ⌘1–9 / ⌘0 onto the current match list (or clear them).
    public mutating func applyCmdNumbers() {
        for i in matches.indices {
            matches[i].cmdNumber = nil
        }
        guard showsCmdNumbers else { return }
        for i in matches.indices.prefix(9) {
            matches[i].cmdNumber = i + 1
        }
        if matches.count >= 10 {
            matches[9].cmdNumber = 0
        }
    }

    public var selectedTarget: HintTarget? {
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex].target
    }

    public var selectedMatch: HintMatch? {
        guard matches.indices.contains(selectedIndex) else { return nil }
        return matches[selectedIndex]
    }

    /// Bubbles drawn on screen. Empty query = mnemonic controls; typing / ⌘N also
    /// includes framed search hits (Obsidian text, etc.) so palette rows get labels.
    public var visibleTargets: [HintTarget] { bubbleTargets }

    /// Targets to feed `HintLayout` right now.
    public var bubbleTargets: [HintTarget] {
        var byID: [String: HintTarget] = [:]
        for t in targets where t.showsLabel && !t.code.isEmpty {
            byID[t.id] = t
        }
        let includeSearch = !typed.isEmpty || showsCmdNumbers
        guard includeSearch else { return Array(byID.values) }

        for m in matches {
            let t = m.target
            guard Self.hasBubbleGeometry(t.frame) else { continue }
            if t.showsLabel, !t.code.isEmpty { continue }
            // Search-only (no mnemonic): bubble only when stamped ⌘N — never a bare "·".
            guard let n = m.cmdNumber else { continue }
            var copy = t
            if copy.code.isEmpty { copy.code = String(n) }
            copy.showsLabel = true
            byID[t.id] = copy
        }
        return Array(byID.values)
    }

    public static func hasBubbleGeometry(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 4 && frame.height > 4
    }

    public func style(for code: String) -> HintCodeStyle {
        guard !typed.isEmpty, code.hasPrefix(typed.lowercased()) else {
            return HintCodeStyle(highlighted: false, tintedCount: 0)
        }
        if code == typed.lowercased() {
            return HintCodeStyle(highlighted: true, tintedCount: 0)
        }
        return HintCodeStyle(highlighted: false, tintedCount: typed.count)
    }

    public mutating func typeCharacter(_ ch: Character) -> HintTypeResult {
        let next = typed + String(ch).lowercased()
        let ranked = Self.rank(targets: targets, query: next)
        guard !ranked.isEmpty || next.isEmpty else { return .ignored }
        // Always accept the character once something still matches, or when query is building
        // toward a fuzzy hit that needs more letters — drop if nothing matches.
        guard !ranked.isEmpty else { return .ignored }
        typed = next
        matches = ranked
        selectedIndex = 0
        applyCmdNumbers()
        if let first = ranked.first, first.target.code == next {
            return .armed(first.target)
        }
        return .narrowed
    }

    /// Arm the current selection. Empty query only arms after Tab/↑↓ picked a row.
    @discardableResult
    public mutating func armExactMatch() -> Bool {
        if typed.isEmpty {
            return selectedTarget != nil
        }
        if let selected = selectedTarget, selected.code == typed.lowercased() {
            return true
        }
        if let idx = matches.firstIndex(where: { $0.target.code == typed.lowercased() }) {
            selectedIndex = idx
            return true
        }
        return selectedTarget != nil
    }

    public mutating func backspace() {
        if !typed.isEmpty {
            typed.removeLast()
        }
        matches = Self.rank(targets: targets, query: typed)
        if typed.isEmpty {
            selectedIndex = -1
        } else if !matches.isEmpty {
            selectedIndex = min(max(selectedIndex, 0), matches.count - 1)
        } else {
            selectedIndex = -1
        }
        applyCmdNumbers()
    }

    public mutating func moveSelection(_ delta: Int) {
        guard !matches.isEmpty else { return }
        if selectedIndex < 0 {
            selectedIndex = delta >= 0 ? 0 : matches.count - 1
            return
        }
        selectedIndex = (selectedIndex + delta + matches.count) % matches.count
    }

    public mutating func selectCmdNumber(_ n: Int) -> HintTarget? {
        guard showsCmdNumbers else { return nil }
        guard let match = matches.first(where: { $0.cmdNumber == n }) else { return nil }
        if let idx = matches.firstIndex(where: { $0.id == match.id }) {
            selectedIndex = idx
        }
        return match.target
    }

    /// Selected row's green box.
    public var highlightFrame: CGRect? {
        guard let match = selectedMatch else { return nil }
        switch match.target.action {
        case .click:
            return HintFuzzy.highlightFrame(
                label: match.target.title,
                range: match.matchRange,
                frame: match.target.frame
            )
        case .menu, .window, .app:
            return match.target.frame.isEmpty ? nil : match.target.frame
        }
    }

    public var armedTarget: HintTarget? { selectedTarget }

    public static func rank(targets: [HintTarget], query: String) -> [HintMatch] {
        if query.isEmpty {
            // Empty query: focused-window labels + open windows first; menu bar is lower.
            func isPreferred(_ t: HintTarget) -> Bool {
                if t.role == roleMenuBarItem { return false }
                if t.showsLabel { return true }
                if case .window = t.action { return true }
                return false
            }
            let preferred = targets.filter(isPreferred)
            let rest = targets.filter { !isPreferred($0) }
            let ordered = (preferred + rest).prefix(40)
            return ordered.enumerated().map {
                HintMatch(target: $0.element, score: 0, matchRange: nil, cmdNumber: nil)
            }
        }

        var scored: [(match: HintMatch, order: Int)] = []
        let qNorm = HintFuzzy.normalizeQuery(query)
        let qLower = query.lowercased()
        for (order, t) in targets.enumerated() {
            guard let s = HintFuzzy.score(query: query, label: t.title, code: t.code) else { continue }
            // Menu bar titles like "Apple" must not win on a single typed letter when the
            // bubble says `l`/`ap` — only a code prefix counts until the query is longer.
            if t.role == roleMenuBarItem, qNorm.count < HintCoder.cmdNumberMinQuery {
                let codeHit = !t.code.isEmpty
                    && (t.code.hasPrefix(qLower) || t.code.hasPrefix(qNorm))
                if !codeHit { continue }
            }
            scored.append(
                (
                    HintMatch(target: t, score: s.value, matchRange: s.matchRange, cmdNumber: nil),
                    order
                )
            )
        }
        // Equal fuzzy score → earlier target wins (windows/apps are stored MRU-first).
        scored.sort {
            if $0.match.score != $1.match.score { return $0.match.score > $1.match.score }
            if $0.match.target.title.count != $1.match.target.title.count {
                return $0.match.target.title.count < $1.match.target.title.count
            }
            return $0.order < $1.order
        }
        // ⌘N stamps happen in HintState.applyCmdNumbers (query length or ⌘ held).
        return scored.map(\.match)
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

// Role strings without importing ApplicationServices into Core.
private let roleButton = "AXButton"
private let roleMenuBarItem = "AXMenuBarItem"

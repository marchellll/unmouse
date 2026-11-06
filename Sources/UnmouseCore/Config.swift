import Foundation
import TOMLKit

public enum GridBlend: String, Codable, Sendable, CaseIterable {
    case exclusion
    case difference
    case normal
    case colorBurn
    case plusLighter

    /// CALayer `compositingFilter` name. Nil = normal over.
    public var layerFilterName: String? {
        switch self {
        case .exclusion: "exclusionBlendMode"
        case .difference: "differenceBlendMode"
        case .colorBurn: "colorBurnBlendMode"
        case .plusLighter: "plusLighter"
        case .normal: nil
        }
    }
}

public enum HaloAttention: String, Codable, Sendable, CaseIterable {
    case none
    case pulse
    case ping
    case breathe
}

/// Offset in points. Cartesian: +x is right, +y is up.
public struct Cartesian: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try Self.number(from: &c)
        y = try Self.number(from: &c)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }

    private static func number(from c: inout UnkeyedDecodingContainer) throws -> Double {
        if let d = try? c.decode(Double.self) { return d }
        if let i = try? c.decode(Int.self) { return Double(i) }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "expected a number")
    }
}

public struct InputConfig: Codable, Sendable, Equatable {
    public var karabiner: Bool
    /// Max hold for ⌘/⌥ alone-taps. Longer = ignored (so long-press can be used elsewhere).
    public var tapMaxMs: Int
    /// Exit grid / free / hint after this many seconds with no input. `0` disables.
    public var modeTimeoutS: Double

    enum CodingKeys: String, CodingKey {
        case karabiner
        case tapMaxMs = "tap_max_ms"
        case modeTimeoutS = "mode_timeout_s"
    }

    public init(karabiner: Bool = true, tapMaxMs: Int = 200, modeTimeoutS: Double = 10) {
        self.karabiner = karabiner
        self.tapMaxMs = tapMaxMs
        self.modeTimeoutS = modeTimeoutS
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        karabiner = try c.decodeIfPresent(Bool.self, forKey: .karabiner) ?? true
        tapMaxMs = try c.decodeIfPresent(Int.self, forKey: .tapMaxMs) ?? 200
        // TOMLKit stores bare `10` as Int — accept Int or Double.
        if let d = try? c.decode(Double.self, forKey: .modeTimeoutS) {
            modeTimeoutS = d
        } else if let i = try? c.decode(Int.self, forKey: .modeTimeoutS) {
            modeTimeoutS = Double(i)
        } else {
            modeTimeoutS = 10
        }
    }
}

public struct LogConfig: Codable, Sendable, Equatable {
    public var level: LogLevel
    public init(level: LogLevel = .none) { self.level = level }
}

public struct GridConfig: Codable, Sendable, Equatable {
    public var rows: Int
    public var cols: Int
    /// Division of every grid after the first. The same count is used for the second and, when depth is 3, the third.
    public var subRows: Int
    public var subCols: Int
    /// Point size of letters on every grid after the first.
    public var subFontSize: Double
    public var subLabel: String
    /// Soft light behind those letters. A clear color or radius `0` turns it off.
    public var subGlow: String
    public var subGlowRadius: Double
    public var chars: String
    public var depth: Int
    public var selectionDim: String
    public var selectionBlur: Int
    /// PostScript font name. Empty / "system" → system monospaced.
    public var font: String
    /// Stroke around cell letters. A clear color or width `0` turns it off.
    public var labelOutline: String
    /// Stroke thickness in points.
    public var labelOutlineWidth: Double

    enum CodingKeys: String, CodingKey {
        case rows, cols, chars, depth, font
        case subRows = "sub_rows"
        case subCols = "sub_cols"
        case subFontSize = "sub_font_size"
        case subLabel = "sub_label"
        case subGlow = "sub_glow"
        case subGlowRadius = "sub_glow_radius"
        case selectionDim = "selection_dim"
        case selectionBlur = "selection_blur"
        case labelOutline = "label_outline"
        case labelOutlineWidth = "label_outline_width"
    }

    public init(
        rows: Int = 10,
        cols: Int = 10,
        subRows: Int = 7,
        subCols: Int = 7,
        subFontSize: Double = 16,
        subLabel: String = "#FFFFFF",
        subGlow: String = "#FFFFFF",
        subGlowRadius: Double = 8,
        chars: String = "qwertyuiopfghjkl;",
        depth: Int = 2,
        selectionDim: String = "#00000080",
        selectionBlur: Int = 12,
        font: String = "system",
        labelOutline: String = "#000000",
        labelOutlineWidth: Double = 2
    ) {
        self.rows = rows
        self.cols = cols
        self.subRows = max(1, subRows)
        self.subCols = max(1, subCols)
        self.subFontSize = max(1, subFontSize)
        self.subLabel = subLabel
        self.subGlow = subGlow
        self.subGlowRadius = max(0, subGlowRadius)
        self.chars = chars
        self.depth = depth
        self.selectionDim = selectionDim
        self.selectionBlur = selectionBlur
        self.font = font
        self.labelOutline = labelOutline
        self.labelOutlineWidth = labelOutlineWidth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decode(Int.self, forKey: .rows)
        cols = try c.decode(Int.self, forKey: .cols)
        subRows = max(1, try c.decodeIfPresent(Int.self, forKey: .subRows) ?? 7)
        subCols = max(1, try c.decodeIfPresent(Int.self, forKey: .subCols) ?? 7)
        subFontSize = max(1, Self.decodeNumber(c, forKey: .subFontSize) ?? 16)
        subLabel = try c.decodeIfPresent(String.self, forKey: .subLabel) ?? "#FFFFFF"
        subGlow = try c.decodeIfPresent(String.self, forKey: .subGlow) ?? "#FFFFFF"
        subGlowRadius = max(0, Self.decodeNumber(c, forKey: .subGlowRadius) ?? 8)
        chars = try c.decode(String.self, forKey: .chars)
        depth = try c.decode(Int.self, forKey: .depth)
        selectionDim = try c.decodeIfPresent(String.self, forKey: .selectionDim) ?? "#00000080"
        selectionBlur = try c.decodeIfPresent(Int.self, forKey: .selectionBlur) ?? 12
        font = try c.decodeIfPresent(String.self, forKey: .font) ?? "system"
        labelOutline = try c.decodeIfPresent(String.self, forKey: .labelOutline) ?? "#000000"
        labelOutlineWidth = Self.decodeNumber(c, forKey: .labelOutlineWidth) ?? 2
    }

    private static func decodeNumber(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        return nil
    }
}

public struct FreeConfig: Codable, Sendable, Equatable {
    /// Top speed, points per second. The curve scales against this.
    public var speed: Double
    public var accel: AccelPreset
    /// Seconds the speed curve covers. Past this, speed stays at the last knot.
    public var accelSeconds: Double
    public var accelKnots: [SpeedKnot]
    public var fastMultiplier: Double
    public var slowMultiplier: Double
    public var scrollSpeed: Double
    /// When true, scroll left and scroll right trade directions.
    public var scrollReverseX: Bool
    /// When true, scroll up and scroll down trade directions.
    public var scrollReverseY: Bool
    /// When true, a chord, a click, or any other non-hold key leaves free mode.
    public var exitOnAction: Bool
    public var haloAttention: HaloAttention
    /// Seconds for one attention cycle.
    public var haloAttentionPeriod: Double
    /// Peak halo scale relative to the core dot.
    public var haloAttentionScale: Double
    /// Cartesian points from the pointer. +x right, +y up.
    public var haloOffset: Cartesian

    enum CodingKeys: String, CodingKey {
        case speed
        case accel
        case accelSeconds = "accel_seconds"
        case accelKnots = "accel_knots"
        case fastMultiplier = "fast_multiplier"
        case slowMultiplier = "slow_multiplier"
        case scrollSpeed = "scroll_speed"
        case scrollReverseX = "scroll_reverse_x"
        case scrollReverseY = "scroll_reverse_y"
        case exitOnAction = "exit_on_action"
        case haloAttention = "halo_attention"
        case haloAttentionPeriod = "halo_attention_period"
        case haloAttentionScale = "halo_attention_scale"
        case haloOffset = "halo_offset"
    }

    public init(
        speed: Double = 2000,
        accel: AccelPreset = .glide,
        accelSeconds: Double = AccelCurve.defaultDuration,
        accelKnots: [SpeedKnot] = AccelCurve.knots(for: .glide),
        fastMultiplier: Double = 3,
        slowMultiplier: Double = 0.25,
        scrollSpeed: Double = 200,
        scrollReverseX: Bool = false,
        scrollReverseY: Bool = false,
        exitOnAction: Bool = false,
        haloAttention: HaloAttention = .pulse,
        haloAttentionPeriod: Double = 1.4,
        haloAttentionScale: Double = 3.6,
        haloOffset: Cartesian = Cartesian(x: 25, y: -25)
    ) {
        self.speed = speed
        self.accel = accel
        self.accelSeconds = accelSeconds
        self.accelKnots = accelKnots
        self.fastMultiplier = fastMultiplier
        self.slowMultiplier = slowMultiplier
        self.scrollSpeed = scrollSpeed
        self.scrollReverseX = scrollReverseX
        self.scrollReverseY = scrollReverseY
        self.exitOnAction = exitOnAction
        self.haloAttention = haloAttention
        self.haloAttentionPeriod = haloAttentionPeriod
        self.haloAttentionScale = haloAttentionScale
        self.haloOffset = haloOffset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = try Self.decodeNumber(c, forKey: .speed)
        fastMultiplier = try Self.decodeNumber(c, forKey: .fastMultiplier)
        slowMultiplier = try Self.decodeNumber(c, forKey: .slowMultiplier)
        scrollSpeed = try Self.decodeNumber(c, forKey: .scrollSpeed)
        scrollReverseX = try c.decodeIfPresent(Bool.self, forKey: .scrollReverseX) ?? false
        scrollReverseY = try c.decodeIfPresent(Bool.self, forKey: .scrollReverseY) ?? false
        exitOnAction = try c.decodeIfPresent(Bool.self, forKey: .exitOnAction) ?? false
        haloAttention = try c.decodeIfPresent(HaloAttention.self, forKey: .haloAttention) ?? .pulse
        haloAttentionPeriod = (try? Self.decodeNumber(c, forKey: .haloAttentionPeriod)) ?? 1.4
        haloAttentionScale = (try? Self.decodeNumber(c, forKey: .haloAttentionScale)) ?? 3.6
        haloOffset = try c.decodeIfPresent(Cartesian.self, forKey: .haloOffset) ?? Cartesian(x: 25, y: -25)

        let requested = (try? c.decode(AccelPreset.self, forKey: .accel)) ?? .glide
        let secondsPresent = c.contains(.accelSeconds)
        let requestedSeconds = (try? Self.decodeNumber(c, forKey: .accelSeconds)) ?? AccelCurve.defaultDuration
        if let knots = try? c.decode([SpeedKnot].self, forKey: .accelKnots), knots.count >= 2 {
            let window = secondsPresent ? requestedSeconds : (knots.map(\.t).max() ?? requestedSeconds)
            accelSeconds = min(30, max(0.5, window))
            accelKnots = AccelCurve.normalized(knots, duration: accelSeconds)
            accel = requested == .custom ? .custom : AccelCurve.matching(accelKnots, duration: accelSeconds)
        } else {
            accel = requested == .custom ? .glide : requested
            accelSeconds = min(30, max(0.5, requestedSeconds))
            accelKnots = AccelCurve.knots(for: accel, duration: accelSeconds)
        }
    }

    private static func decodeNumber(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Double {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        throw DecodingError.keyNotFound(key, .init(codingPath: c.codingPath, debugDescription: "expected number"))
    }
}

public struct HintConfig: Codable, Sendable, Equatable {
    public var chars: String
    public init(chars: String = "qwesfghjkl") { self.chars = chars }
}

public struct ColorsConfig: Codable, Sendable, Equatable {
    public var background: String
    public var line: String
    public var label: String
    public var highlight: String
    public var gridBlend: GridBlend
    public var freeDot: String
    public var freeDotHalo: String
    /// Blend for free-mode halo against the desktop. Defaults to colorBurn.
    public var freeDotBlend: GridBlend
    public var hintFill: String
    public var hintText: String
    public var hintLine: String

    enum CodingKeys: String, CodingKey {
        case background, line, label, highlight
        case gridBlend = "grid_blend"
        case freeDot = "free_dot"
        case freeDotHalo = "free_dot_halo"
        case freeDotBlend = "free_dot_blend"
        case hintFill = "hint_fill"
        case hintText = "hint_text"
        case hintLine = "hint_line"
    }

    public init(
        background: String = "#00000000",
        line: String = "#FFFFFF",
        label: String = "#FFFFFF",
        highlight: String = "#FFFFFF",
        gridBlend: GridBlend = .exclusion,
        freeDot: String = "#FFFFFF",
        freeDotHalo: String = "#FFFFFF99",
        freeDotBlend: GridBlend = .exclusion,
        hintFill: String = "#111111EE",
        hintText: String = "#FFFFFF",
        hintLine: String = "#FFFFFFCC"
    ) {
        self.background = background
        self.line = line
        self.label = label
        self.highlight = highlight
        self.gridBlend = gridBlend
        self.freeDot = freeDot
        self.freeDotHalo = freeDotHalo
        self.freeDotBlend = freeDotBlend
        self.hintFill = hintFill
        self.hintText = hintText
        self.hintLine = hintLine
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(String.self, forKey: .background) ?? "#00000000"
        line = try c.decodeIfPresent(String.self, forKey: .line) ?? "#FFFFFF"
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "#FFFFFF"
        highlight = try c.decodeIfPresent(String.self, forKey: .highlight) ?? "#FFFFFF"
        gridBlend = try c.decodeIfPresent(GridBlend.self, forKey: .gridBlend) ?? .exclusion
        freeDot = try c.decodeIfPresent(String.self, forKey: .freeDot) ?? "#FFFFFF"
        freeDotHalo = try c.decodeIfPresent(String.self, forKey: .freeDotHalo) ?? "#FFFFFF99"
        freeDotBlend = try c.decodeIfPresent(GridBlend.self, forKey: .freeDotBlend) ?? .exclusion
        hintFill = try c.decodeIfPresent(String.self, forKey: .hintFill) ?? "#111111EE"
        hintText = try c.decodeIfPresent(String.self, forKey: .hintText) ?? "#FFFFFF"
        hintLine = try c.decodeIfPresent(String.self, forKey: .hintLine) ?? "#FFFFFFCC"
    }
}

public struct GlobalBindings: Codable, Sendable, Equatable {
    public var gridMode: [String]
    public var freeMode: [String]
    public var hintMode: [String]

    enum CodingKeys: String, CodingKey {
        case gridMode = "grid_mode"
        case freeMode = "free_mode"
        case hintMode = "hint_mode"
    }

    public init(
        gridMode: [String] = ["command_left"],
        freeMode: [String] = ["option_left"],
        hintMode: [String] = ["command+shift+space"]
    ) {
        self.gridMode = gridMode
        self.freeMode = freeMode
        self.hintMode = hintMode
    }
}

public struct GridBindings: Codable, Sendable, Equatable {
    public var back: [String]
    public var leftClick: [String]
    public var rightClick: [String]
    public var middleClick: [String]
    public var moveOnly: [String]
    public var toFree: [String]
    public var cancel: [String]
    public var nextScreen: [String]

    enum CodingKeys: String, CodingKey {
        case back
        case leftClick = "left_click"
        case rightClick = "right_click"
        case middleClick = "middle_click"
        case moveOnly = "move_only"
        case toFree = "to_free"
        case cancel
        case nextScreen = "next_screen"
    }

    public init(
        back: [String] = ["delete", "backspace"],
        leftClick: [String] = ["space"],
        rightClick: [String] = ["a"],
        middleClick: [String] = ["s"],
        moveOnly: [String] = ["d"],
        toFree: [String] = ["option_left"],
        cancel: [String] = ["escape"],
        nextScreen: [String] = ["tab"]
    ) {
        self.back = back
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.middleClick = middleClick
        self.moveOnly = moveOnly
        self.toFree = toFree
        self.cancel = cancel
        self.nextScreen = nextScreen
    }
}

public struct FreeBindings: Codable, Sendable, Equatable {
    public var moveLeft: [String]
    public var moveDown: [String]
    public var moveUp: [String]
    public var moveRight: [String]
    public var faster: [String]
    public var slower: [String]
    public var scrollUp: [String]
    public var scrollDown: [String]
    public var scrollLeft: [String]
    public var scrollRight: [String]
    public var toggleDrag: [String]
    public var leftClick: [String]
    public var rightClick: [String]
    public var middleClick: [String]
    public var cancel: [String]

    enum CodingKeys: String, CodingKey {
        case moveLeft = "move_left"
        case moveDown = "move_down"
        case moveUp = "move_up"
        case moveRight = "move_right"
        case faster, slower
        case scrollUp = "scroll_up"
        case scrollDown = "scroll_down"
        case scrollLeft = "scroll_left"
        case scrollRight = "scroll_right"
        case toggleDrag = "toggle_drag"
        case leftClick = "left_click"
        case rightClick = "right_click"
        case middleClick = "middle_click"
        case cancel
    }

    public init(
        moveLeft: [String] = ["j", "left"],
        moveDown: [String] = ["k", "down"],
        moveUp: [String] = ["l", "up"],
        moveRight: [String] = [";", "right"],
        faster: [String] = ["z"],
        slower: [String] = ["x"],
        scrollUp: [String] = ["."],
        scrollDown: [String] = [","],
        scrollLeft: [String] = ["m"],
        scrollRight: [String] = ["/"],
        toggleDrag: [String] = ["q"],
        leftClick: [String] = ["space"],
        rightClick: [String] = ["a"],
        middleClick: [String] = ["s"],
        cancel: [String] = ["escape"]
    ) {
        self.moveLeft = moveLeft
        self.moveDown = moveDown
        self.moveUp = moveUp
        self.moveRight = moveRight
        self.faster = faster
        self.slower = slower
        self.scrollUp = scrollUp
        self.scrollDown = scrollDown
        self.scrollLeft = scrollLeft
        self.scrollRight = scrollRight
        self.toggleDrag = toggleDrag
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.middleClick = middleClick
        self.cancel = cancel
    }
}

public struct HintBindings: Codable, Sendable, Equatable {
    public var leftClick: [String]
    public var rightClick: [String]
    public var moveNoAction: [String]
    public var toFree: [String]
    public var cancel: [String]
    public var back: [String]

    enum CodingKeys: String, CodingKey {
        case leftClick = "left_click"
        case rightClick = "right_click"
        case moveNoAction = "move_no_action"
        case toFree = "to_free"
        case cancel, back
    }

    public init(
        leftClick: [String] = ["space"],
        rightClick: [String] = ["a"],
        moveNoAction: [String] = ["d"],
        toFree: [String] = ["option_left"],
        cancel: [String] = ["escape"],
        back: [String] = ["delete", "backspace"]
    ) {
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.moveNoAction = moveNoAction
        self.toFree = toFree
        self.cancel = cancel
        self.back = back
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leftClick = try c.decodeIfPresent([String].self, forKey: .leftClick) ?? ["space"]
        rightClick = try c.decodeIfPresent([String].self, forKey: .rightClick) ?? ["a"]
        moveNoAction = try c.decodeIfPresent([String].self, forKey: .moveNoAction) ?? ["d"]
        toFree = try c.decodeIfPresent([String].self, forKey: .toFree) ?? ["option_left"]
        cancel = try c.decodeIfPresent([String].self, forKey: .cancel) ?? ["escape"]
        back = try c.decodeIfPresent([String].self, forKey: .back) ?? ["delete", "backspace"]
    }
}

public struct BindingsConfig: Codable, Sendable, Equatable {
    public var global: GlobalBindings
    public var grid: GridBindings
    public var free: FreeBindings
    public var hint: HintBindings

    public init(
        global: GlobalBindings = .init(),
        grid: GridBindings = .init(),
        free: FreeBindings = .init(),
        hint: HintBindings = .init()
    ) {
        self.global = global
        self.grid = grid
        self.free = free
        self.hint = hint
    }
}

public struct AppConfig: Codable, Sendable, Equatable {
    public var input: InputConfig
    public var log: LogConfig
    public var grid: GridConfig
    public var free: FreeConfig
    public var hint: HintConfig
    public var colors: ColorsConfig
    public var bindings: BindingsConfig

    public init(
        input: InputConfig = .init(),
        log: LogConfig = .init(),
        grid: GridConfig = .init(),
        free: FreeConfig = .init(),
        hint: HintConfig = .init(),
        colors: ColorsConfig = .init(),
        bindings: BindingsConfig = .init()
    ) {
        self.input = input
        self.log = log
        self.grid = grid
        self.free = free
        self.hint = hint
        self.colors = colors
        self.bindings = bindings
    }

    public static let `default` = AppConfig()

    enum CodingKeys: String, CodingKey {
        case input, log, grid, free, hint, colors, bindings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decodeIfPresent(InputConfig.self, forKey: .input) ?? .init()
        log = try c.decodeIfPresent(LogConfig.self, forKey: .log) ?? .init()
        grid = try c.decode(GridConfig.self, forKey: .grid)
        free = try c.decode(FreeConfig.self, forKey: .free)
        hint = try c.decodeIfPresent(HintConfig.self, forKey: .hint) ?? .init()
        colors = try c.decode(ColorsConfig.self, forKey: .colors)
        bindings = try c.decode(BindingsConfig.self, forKey: .bindings)
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case depthOutOfRange(Int)
    case emptyChars
    case duplicateChars
    case cellsExceedCharset(cells: Int, max: Int)
    case duplicateShortcut(mode: String, shortcut: String)
    case gridShortcutOverlapsChars(String)
    case hintShortcutOverlapsChars(String)
    case parse(String)
    case invalidShortcut(String)

    public var description: String {
        switch self {
        case .depthOutOfRange(let d):
            "depth must be 1...3, got \(d)"
        case .emptyChars:
            "chars must be non-empty"
        case .duplicateChars:
            "chars must be unique"
        case .cellsExceedCharset(let cells, let max):
            "\(cells) cells need at most \(max) labels from chars"
        case .duplicateShortcut(let mode, let shortcut):
            "duplicate shortcut \(shortcut) in \(mode)"
        case .gridShortcutOverlapsChars(let s):
            "grid shortcut \(s) duplicates a grid char"
        case .hintShortcutOverlapsChars(let s):
            "hint shortcut \(s) overlaps hint chars"
        case .parse(let m):
            m
        case .invalidShortcut(let m):
            m
        }
    }

    /// Grid-letter clashes stay visible and still let the rest of the config load.
    public var blocksApply: Bool {
        if case .gridShortcutOverlapsChars = self { return false }
        return true
    }
}

public enum ConfigValidator {
    public static func validate(_ config: AppConfig) -> [ConfigError] {
        var errors: [ConfigError] = []
        let g = config.grid
        if !(1...3).contains(g.depth) {
            errors.append(.depthOutOfRange(g.depth))
        }
        if g.chars.isEmpty {
            errors.append(.emptyChars)
        }
        let chars = Array(g.chars)
        if Set(chars).count != chars.count {
            errors.append(.duplicateChars)
        }
        let cells = g.rows * g.cols
        let n = chars.count
        let maxLabels = n * n
        if cells > maxLabels {
            errors.append(.cellsExceedCharset(cells: cells, max: maxLabels))
        }

        func checkDuplicates(mode: String, groups: [[String]]) {
            var seen: Set<String> = []
            for group in groups {
                for raw in group {
                    let key = raw.lowercased()
                    if seen.contains(key) {
                        errors.append(.duplicateShortcut(mode: mode, shortcut: raw))
                    }
                    seen.insert(key)
                    do {
                        _ = try ShortcutParser.parse(raw)
                    } catch {
                        errors.append(.invalidShortcut("\(mode): \(error)"))
                    }
                }
            }
        }

        let b = config.bindings
        checkDuplicates(mode: "global", groups: [b.global.gridMode, b.global.freeMode, b.global.hintMode])
        let gridBindings = [
            b.grid.back, b.grid.leftClick, b.grid.rightClick, b.grid.middleClick,
            b.grid.moveOnly, b.grid.toFree, b.grid.cancel, b.grid.nextScreen,
        ]
        checkDuplicates(mode: "grid", groups: gridBindings)
        let gridChars = Set(g.chars.lowercased())
        for raw in gridBindings.joined() {
            if let sc = try? ShortcutParser.parse(raw),
               sc.modifiers.isEmpty,
               let c = sc.key.character,
               gridChars.contains(c)
            {
                errors.append(.gridShortcutOverlapsChars(raw))
            }
        }
        checkDuplicates(mode: "free", groups: [
            b.free.moveLeft, b.free.moveDown, b.free.moveUp, b.free.moveRight,
            b.free.faster, b.free.slower, b.free.scrollUp, b.free.scrollDown,
            b.free.scrollLeft, b.free.scrollRight, b.free.toggleDrag,
            b.free.leftClick, b.free.rightClick, b.free.middleClick, b.free.cancel,
        ])
        checkDuplicates(mode: "hint", groups: [
            b.hint.leftClick, b.hint.rightClick, b.hint.moveNoAction, b.hint.toFree,
            b.hint.cancel, b.hint.back,
        ])

        let hintChars = Set(config.hint.chars.lowercased())
        for raw in b.hint.leftClick + b.hint.rightClick + b.hint.moveNoAction + b.hint.toFree {
            if let sc = try? ShortcutParser.parse(raw),
               sc.modifiers.isEmpty,
               let c = sc.key.character,
               hintChars.contains(c)
            {
                errors.append(.hintShortcutOverlapsChars(raw))
            }
        }

        if config.hint.chars.isEmpty {
            errors.append(.emptyChars)
        }
        let hc = Array(config.hint.chars)
        if Set(hc).count != hc.count {
            errors.append(.duplicateChars)
        }

        return errors
    }
}

public enum ConfigIO {
    public static func decode(from toml: String) throws -> AppConfig {
        do {
            return try TOMLDecoder().decode(AppConfig.self, from: toml)
        } catch {
            throw ConfigError.parse(String(describing: error))
        }
    }

    public static func decodeFile(at url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError.parse("not utf8")
        }
        return try decode(from: text)
    }

    public static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("unmouse", isDirectory: true)
    }

    public static func configURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("config.toml")
    }

    public static func ensureConfig(defaultText: String) throws -> URL {
        let dir = applicationSupportDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = configURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try defaultText.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    public static func replaceConfig(with text: String) throws {
        let dir = applicationSupportDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: configURL(), atomically: true, encoding: .utf8)
    }

    public static func encode(_ config: AppConfig) throws -> String {
        do {
            return try TOMLEncoder().encode(config)
        } catch {
            throw ConfigError.parse(String(describing: error))
        }
    }

    public static func save(_ config: AppConfig) throws {
        try replaceConfig(with: try encode(config))
    }
}

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

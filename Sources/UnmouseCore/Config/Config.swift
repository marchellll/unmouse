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
    /// Move the pointer to the center of a newly focused window when it sits outside that window.
    public var centerOnFocus: Bool

    enum CodingKeys: String, CodingKey {
        case karabiner
        case tapMaxMs = "tap_max_ms"
        case modeTimeoutS = "mode_timeout_s"
        case centerOnFocus = "center_on_focus"
    }

    public init(karabiner: Bool = true, tapMaxMs: Int = 200, modeTimeoutS: Double = 10, centerOnFocus: Bool = true) {
        self.karabiner = karabiner
        self.tapMaxMs = tapMaxMs
        self.modeTimeoutS = modeTimeoutS
        self.centerOnFocus = centerOnFocus
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
        centerOnFocus = try c.decodeIfPresent(Bool.self, forKey: .centerOnFocus) ?? true
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
        chars: String = "qtyuiopaghjkl;",
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
        scrollReverseX: Bool = true,
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
        scrollReverseX = try c.decodeIfPresent(Bool.self, forKey: .scrollReverseX) ?? true
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

/// Hint settings. `chars` used to live here; labels now use a fixed a–z alphabet.
public struct HintConfig: Codable, Sendable, Equatable {
    /// Pause after enabling accessibility, before reading the focused window.
    /// Electron builds that tree during the pause. `0` reads immediately.
    public var scanSettleMs: Int

    private enum CodingKeys: String, CodingKey {
        case chars
        case scanSettleMs = "scan_settle_ms"
    }

    public init(scanSettleMs: Int = 200) {
        self.scanSettleMs = Self.clampSettle(scanSettleMs)
    }

    public init(from decoder: Decoder) throws {
        // Legacy configs may still have `chars = "…"` — ignore.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _ = try c.decodeIfPresent(String.self, forKey: .chars)
        scanSettleMs = Self.clampSettle(try c.decodeIfPresent(Int.self, forKey: .scanSettleMs) ?? 200)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scanSettleMs, forKey: .scanSettleMs)
    }

    private static func clampSettle(_ ms: Int) -> Int {
        min(2_000, max(0, ms))
    }
}

public struct ColorsConfig: Codable, Sendable, Equatable {
    public var background: String
    public var line: String
    public var label: String
    public var highlight: String
    public var gridBlend: GridBlend
    public var freeDot: String
    public var freeDotHalo: String
    /// Blend for free-mode halo against the desktop. Defaults to exclusion.
    public var freeDotBlend: GridBlend
    public var hintFill: String
    public var hintText: String
    public var hintLine: String
    /// Box around the selected hint. Fill is drawn lighter than this stroke.
    public var hintHighlight: String

    enum CodingKeys: String, CodingKey {
        case background, line, label, highlight
        case gridBlend = "grid_blend"
        case freeDot = "free_dot"
        case freeDotHalo = "free_dot_halo"
        case freeDotBlend = "free_dot_blend"
        case hintFill = "hint_fill"
        case hintText = "hint_text"
        case hintLine = "hint_line"
        case hintHighlight = "hint_highlight"
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
        hintLine: String = "#FFFFFFCC",
        hintHighlight: String = "#34C759"
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
        self.hintHighlight = hintHighlight
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
        hintHighlight = try c.decodeIfPresent(String.self, forKey: .hintHighlight) ?? "#34C759"
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

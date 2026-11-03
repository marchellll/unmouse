import Foundation
import TOMLKit

public enum GridBlend: String, Codable, Sendable, CaseIterable {
    case exclusion
    case difference
    case normal
    case colorBurn
    case plusLighter
}

public struct InputConfig: Codable, Sendable, Equatable {
    public var karabiner: Bool
    public init(karabiner: Bool = true) { self.karabiner = karabiner }
}

public struct LogConfig: Codable, Sendable, Equatable {
    public var level: LogLevel
    public init(level: LogLevel = .none) { self.level = level }
}

public struct GridConfig: Codable, Sendable, Equatable {
    public var rows: Int
    public var cols: Int
    public var chars: String
    public var depth: Int
    public var selectionDim: String
    public var selectionBlur: Int

    enum CodingKeys: String, CodingKey {
        case rows, cols, chars, depth
        case selectionDim = "selection_dim"
        case selectionBlur = "selection_blur"
    }

    public init(
        rows: Int = 5,
        cols: Int = 4,
        chars: String = "qwertyuiopasdfghjkl;",
        depth: Int = 2,
        selectionDim: String = "#00000080",
        selectionBlur: Int = 12
    ) {
        self.rows = rows
        self.cols = cols
        self.chars = chars
        self.depth = depth
        self.selectionDim = selectionDim
        self.selectionBlur = selectionBlur
    }
}

public struct FreeConfig: Codable, Sendable, Equatable {
    public var speed: Double
    public var fastMultiplier: Double
    public var slowMultiplier: Double
    public var scrollSpeed: Double

    enum CodingKeys: String, CodingKey {
        case speed
        case fastMultiplier = "fast_multiplier"
        case slowMultiplier = "slow_multiplier"
        case scrollSpeed = "scroll_speed"
    }

    public init(
        speed: Double = 480,
        fastMultiplier: Double = 3,
        slowMultiplier: Double = 0.25,
        scrollSpeed: Double = 3
    ) {
        self.speed = speed
        self.fastMultiplier = fastMultiplier
        self.slowMultiplier = slowMultiplier
        self.scrollSpeed = scrollSpeed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = try Self.decodeNumber(c, forKey: .speed)
        fastMultiplier = try Self.decodeNumber(c, forKey: .fastMultiplier)
        slowMultiplier = try Self.decodeNumber(c, forKey: .slowMultiplier)
        scrollSpeed = try Self.decodeNumber(c, forKey: .scrollSpeed)
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
    public var hintFill: String
    public var hintText: String
    public var hintLine: String

    enum CodingKeys: String, CodingKey {
        case background, line, label, highlight
        case gridBlend = "grid_blend"
        case freeDot = "free_dot"
        case freeDotHalo = "free_dot_halo"
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
        freeDotHalo: String = "#000000",
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
        self.hintFill = hintFill
        self.hintText = hintText
        self.hintLine = hintLine
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
        moveLeft: [String] = ["h", "left"],
        moveDown: [String] = ["j", "down"],
        moveUp: [String] = ["k", "up"],
        moveRight: [String] = ["l", "right"],
        faster: [String] = ["z"],
        slower: [String] = ["x"],
        scrollUp: [String] = ["m"],
        scrollDown: [String] = [","],
        scrollLeft: [String] = ["."],
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
    public var cancel: [String]
    public var back: [String]

    enum CodingKeys: String, CodingKey {
        case leftClick = "left_click"
        case rightClick = "right_click"
        case moveNoAction = "move_no_action"
        case cancel, back
    }

    public init(
        leftClick: [String] = ["space"],
        rightClick: [String] = ["a"],
        moveNoAction: [String] = ["d"],
        cancel: [String] = ["escape"],
        back: [String] = ["delete", "backspace"]
    ) {
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.moveNoAction = moveNoAction
        self.cancel = cancel
        self.back = back
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
        case .hintShortcutOverlapsChars(let s):
            "hint shortcut \(s) overlaps hint chars"
        case .parse(let m):
            m
        case .invalidShortcut(let m):
            m
        }
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
        checkDuplicates(mode: "grid", groups: [
            b.grid.back, b.grid.leftClick, b.grid.rightClick, b.grid.middleClick,
            b.grid.moveOnly, b.grid.toFree, b.grid.cancel, b.grid.nextScreen,
        ])
        checkDuplicates(mode: "free", groups: [
            b.free.moveLeft, b.free.moveDown, b.free.moveUp, b.free.moveRight,
            b.free.faster, b.free.slower, b.free.scrollUp, b.free.scrollDown,
            b.free.scrollLeft, b.free.scrollRight, b.free.toggleDrag,
            b.free.leftClick, b.free.rightClick, b.free.middleClick, b.free.cancel,
        ])
        checkDuplicates(mode: "hint", groups: [
            b.hint.leftClick, b.hint.rightClick, b.hint.moveNoAction, b.hint.cancel, b.hint.back,
        ])

        let hintChars = Set(config.hint.chars.lowercased())
        for raw in b.hint.leftClick + b.hint.rightClick + b.hint.moveNoAction {
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
}

public enum GridLabels {
    /// Labels for cells in row-major order from chars. Uses 1 char if enough, else 2.
    public static func labels(chars: String, rows: Int, cols: Int) -> [String] {
        let alphabet = Array(chars)
        let cells = rows * cols
        if alphabet.count >= cells {
            return alphabet.prefix(cells).map(String.init)
        }
        var result: [String] = []
        result.reserveCapacity(cells)
        for i in 0..<cells {
            let a = alphabet[i / alphabet.count]
            let b = alphabet[i % alphabet.count]
            result.append(String([a, b]))
        }
        return result
    }

    public static func labelWidth(chars: String, rows: Int, cols: Int) -> Int {
        chars.count >= rows * cols ? 1 : 2
    }
}

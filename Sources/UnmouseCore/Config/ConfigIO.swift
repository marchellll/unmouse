import Foundation
import TOMLKit

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case depthOutOfRange(Int)
    case emptyChars
    case duplicateChars
    case cellsExceedCharset(cells: Int, max: Int)
    case duplicateShortcut(mode: String, shortcut: String)
    case gridShortcutOverlapsChars(String)
    /// Bare letter as hint left/right click steals that key from typing/search.
    case hintClickStealsTyping(String)
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
        case .hintClickStealsTyping(let s):
            "hint click \(s) is a bare letter — use control+space (or similar) so letters type/search"
        case .parse(let m):
            m
        case .invalidShortcut(let m):
            m
        }
    }

    /// Soft clashes stay visible and still let the rest of the config load.
    public var blocksApply: Bool {
        switch self {
        case .gridShortcutOverlapsChars, .hintClickStealsTyping: return false
        default: return true
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
        let gridBindings = [
            b.grid.back, b.grid.leftClick, b.grid.rightClick, b.grid.middleClick,
            b.grid.moveOnly, b.grid.toggleDrag, b.grid.toggleRightDrag, b.grid.toggleMiddleDrag,
            b.grid.toFree, b.grid.cancel, b.grid.nextScreen,
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
            b.free.toggleRightDrag, b.free.toggleMiddleDrag,
            b.free.leftClick, b.free.rightClick, b.free.middleClick, b.free.cancel,
        ])
        checkDuplicates(mode: "hint", groups: [
            b.hint.leftClick, b.hint.rightClick, b.hint.toFree,
            b.hint.cancel, b.hint.back,
        ])

        // Hint mode types a–z for codes/search. Bare letter clicks steal typing.
        for raw in b.hint.leftClick + b.hint.rightClick + b.hint.toFree {
            if let sc = try? ShortcutParser.parse(raw),
               sc.modifiers.isEmpty,
               case .letter = sc.key
            {
                errors.append(.hintClickStealsTyping(raw))
            }
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

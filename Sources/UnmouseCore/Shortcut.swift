import Foundation

public enum KeyKind: Hashable, Sendable {
    case letter(Character)
    case digit(Character)
    case punctuation(Character)
    case space
    case `return`
    case escape
    case tab
    case delete
    case forwardDelete
    case left
    case right
    case up
    case down
    case home
    case end
    case pageUp
    case pageDown
    case function(Int)
    case command
    case commandLeft
    case commandRight
    case option
    case optionLeft
    case optionRight
    case shift
    case shiftLeft
    case shiftRight
    case control
    case controlLeft
    case controlRight
    case fn
}

public struct Shortcut: Hashable, Sendable {
    public var modifiers: Set<KeyKind>
    public var key: KeyKind

    public init(modifiers: Set<KeyKind> = [], key: KeyKind) {
        self.modifiers = modifiers
        self.key = key
    }

    public var isBareModifier: Bool {
        modifiers.isEmpty && key.isModifier
    }
}

public enum ShortcutParseError: Error, Equatable, CustomStringConvertible {
    case empty
    case unknownToken(String)
    case comboWithoutKey(String)
    case comboWithMultipleKeys(String)

    public var description: String {
        switch self {
        case .empty:
            "empty shortcut"
        case .unknownToken(let t):
            "unknown token: \(t)"
        case .comboWithoutKey(let t):
            "combo needs one key: \(t)"
        case .comboWithMultipleKeys(let t):
            "combo has more than one key: \(t)"
        }
    }
}

extension KeyKind {
    public var isModifier: Bool {
        switch self {
        case .command, .commandLeft, .commandRight,
             .option, .optionLeft, .optionRight,
             .shift, .shiftLeft, .shiftRight,
             .control, .controlLeft, .controlRight,
             .fn:
            true
        default:
            false
        }
    }

    public var character: Character? {
        switch self {
        case .letter(let c), .digit(let c), .punctuation(let c):
            c
        default:
            nil
        }
    }

    static func parseToken(_ raw: String) -> KeyKind? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return nil }
        switch t {
        case "command", "cmd": return .command
        case "command_left", "cmd_left": return .commandLeft
        case "command_right", "cmd_right": return .commandRight
        case "option", "opt", "alt": return .option
        case "option_left", "opt_left", "alt_left": return .optionLeft
        case "option_right", "opt_right", "alt_right": return .optionRight
        case "shift": return .shift
        case "shift_left": return .shiftLeft
        case "shift_right": return .shiftRight
        case "control", "ctrl": return .control
        case "control_left", "ctrl_left": return .controlLeft
        case "control_right", "ctrl_right": return .controlRight
        case "fn": return .fn
        case "space": return .space
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        case "tab": return .tab
        case "delete", "backspace": return .delete
        case "forward_delete": return .forwardDelete
        case "left": return .left
        case "right": return .right
        case "up": return .up
        case "down": return .down
        case "home": return .home
        case "end": return .end
        case "page_up": return .pageUp
        case "page_down": return .pageDown
        default:
            if t.count >= 2, t.first == "f", let n = Int(t.dropFirst()), (1...20).contains(n) {
                return .function(n)
            }
            if t.count == 1, let c = t.first {
                if ("a"..."z").contains(c) { return .letter(c) }
                if ("0"..."9").contains(c) { return .digit(c) }
                return .punctuation(c)
            }
            return nil
        }
    }
}

extension KeyKind {
    /// Config token form (`command_left`, `space`, `a`, `f12`, …).
    public var configToken: String {
        switch self {
        case .letter(let c), .digit(let c), .punctuation(let c):
            String(c)
        case .space: "space"
        case .return: "return"
        case .escape: "escape"
        case .tab: "tab"
        case .delete: "delete"
        case .forwardDelete: "forward_delete"
        case .left: "left"
        case .right: "right"
        case .up: "up"
        case .down: "down"
        case .home: "home"
        case .end: "end"
        case .pageUp: "page_up"
        case .pageDown: "page_down"
        case .function(let n): "f\(n)"
        case .command: "command"
        case .commandLeft: "command_left"
        case .commandRight: "command_right"
        case .option: "option"
        case .optionLeft: "option_left"
        case .optionRight: "option_right"
        case .shift: "shift"
        case .shiftLeft: "shift_left"
        case .shiftRight: "shift_right"
        case .control: "control"
        case .controlLeft: "control_left"
        case .controlRight: "control_right"
        case .fn: "fn"
        }
    }
}

extension Shortcut {
    public var configString: String {
        if modifiers.isEmpty {
            return key.configToken
        }
        let mods = modifiers.map(\.configToken).sorted()
        return (mods + [key.configToken]).joined(separator: "+")
    }
}

public enum ShortcutParser {
    public static func parse(_ raw: String) throws -> Shortcut {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShortcutParseError.empty }

        let parts = trimmed.split(separator: "+", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !parts.contains(where: \.isEmpty) else {
            throw ShortcutParseError.unknownToken(raw)
        }

        if parts.count == 1 {
            guard let kind = KeyKind.parseToken(parts[0]) else {
                throw ShortcutParseError.unknownToken(parts[0])
            }
            return Shortcut(key: kind)
        }

        var modifiers: Set<KeyKind> = []
        var keys: [KeyKind] = []
        for part in parts {
            guard let kind = KeyKind.parseToken(part) else {
                throw ShortcutParseError.unknownToken(part)
            }
            if kind.isModifier {
                modifiers.insert(kind)
            } else {
                keys.append(kind)
            }
        }
        if keys.isEmpty {
            throw ShortcutParseError.comboWithoutKey(raw)
        }
        if keys.count > 1 {
            throw ShortcutParseError.comboWithMultipleKeys(raw)
        }
        return Shortcut(modifiers: modifiers, key: keys[0])
    }

    public static func parseAll(_ raws: [String]) throws -> [Shortcut] {
        try raws.map { try parse($0) }
    }
}

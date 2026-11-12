import Foundation

/// Short glyph for a config shortcut (`option_left` → `⌥`, `control+space` → `⌃Space`).
public enum ShortcutLabel {
    public static func text(_ raw: String) -> String {
        raw.lowercased()
            .split(separator: "+")
            .map { token -> String in
                switch token {
                case "command", "cmd", "command_left", "cmd_left", "command_right", "cmd_right":
                    "⌘"
                case "option", "opt", "alt", "option_left", "opt_left", "alt_left",
                     "option_right", "opt_right", "alt_right":
                    "⌥"
                case "shift", "shift_left", "shift_right":
                    "⇧"
                case "control", "ctrl", "control_left", "ctrl_left", "control_right", "ctrl_right":
                    "⌃"
                case "space":
                    "Space"
                case "return", "enter":
                    "↩"
                case "escape", "esc":
                    "Esc"
                case "delete", "backspace":
                    "⌫"
                case "tab":
                    "Tab"
                case "left":
                    "←"
                case "right":
                    "→"
                case "up":
                    "↑"
                case "down":
                    "↓"
                default:
                    String(token).uppercased()
                }
            }
            .joined()
    }

    /// First shortcut, or "?" when the binding is empty.
    public static func first(_ keys: [String]) -> String {
        guard let raw = keys.first else { return "?" }
        return text(raw)
    }

    /// Every shortcut, joined. Empty bindings become "?".
    public static func list(_ keys: [String], separator: String = "/") -> String {
        let parts = keys.map(text)
        return parts.isEmpty ? "?" : parts.joined(separator: separator)
    }

    /// One shortcut as keycaps: `control+space` → `` `⌃` + `Space` ``.
    public static func marks(_ raw: String) -> String {
        raw.split(separator: "+")
            .map { "`\(text(String($0)))`" }
            .joined(separator: " + ")
    }
}

/// One line under the hint palette. Built from the live bindings.
public enum HintLegend {
    public static func line(_ bindings: BindingsConfig) -> String {
        let b = bindings
        let parts = [
            phrase(b.hint.leftClick, "click"),
            phrase(b.hint.rightClick, "right"),
            phrase(b.hint.toFree, "free"),
            phrase(b.global.gridMode, "grid"),
            phrase(b.hint.cancel, "cancel"),
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private static func phrase(_ keys: [String], _ verb: String) -> String? {
        guard !keys.isEmpty else { return nil }
        return "\(ShortcutLabel.list(keys)) \(verb)"
    }
}

import SwiftUI
import UnmouseCore

struct CoachView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(modeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .allowsHitTesting(false)
    }

    private var modeTitle: String {
        switch model.nav.mode {
        case .idle: "Idle"
        case .grid: "Grid — next"
        case .free: "Free — next"
        case .hint: "Hint — next"
        }
    }

    /// What the user can do right now, given mode progress.
    private var lines: [String] {
        let b = model.config.bindings
        switch model.nav.mode {
        case .idle:
            return []
        case .grid:
            return gridNext(b)
        case .free:
            return freeNext(b)
        case .hint:
            return hintNext(b)
        }
    }

    private func gridNext(_ b: BindingsConfig) -> [String] {
        guard let state = model.nav.gridState else {
            return ["Type a cell label"]
        }
        let space = label(b.grid.leftClick)
        let right = label(b.grid.rightClick)
        let move = label(b.grid.moveOnly)
        let free = label(b.grid.toFree)
        let back = label(b.grid.back)
        let cancel = label(b.grid.cancel)

        if state.isCellSelected {
            return [
                "\(space) click · \(right) right · \(move) move",
                "\(free) free · \(back) back · \(cancel) cancel",
            ]
        }
        if state.hasClickTarget {
            let typed = state.currentLevel.typed
            let need = max(0, state.labelWidth - typed.count)
            let more = need > 0 ? "Type \(need) more · " : ""
            return [
                "\(more)\(space) click this block",
                "\(free) free · \(back) back · \(cancel) cancel",
            ]
        }
        return [
            "Type a cell label",
            "\(back) back · \(cancel) cancel",
        ]
    }

    private func freeNext(_ b: BindingsConfig) -> [String] {
        let move = "\(label(b.free.moveLeft))\(label(b.free.moveDown))\(label(b.free.moveUp))\(label(b.free.moveRight))"
        let fast = label(b.free.faster)
        let slow = label(b.free.slower)
        let scroll = "\(label(b.free.scrollLeft)) \(label(b.free.scrollDown)) \(label(b.free.scrollUp)) \(label(b.free.scrollRight))"
        let click = label(b.free.leftClick)
        let drag = label(b.free.toggleDrag)
        let cancel = label(b.free.cancel)

        if model.nav.dragging {
            return [
                "\(click) or \(drag) drop",
                "\(move) drag · \(cancel) cancel",
            ]
        }
        return [
            "\(move) move · \(fast) fast · \(slow) slow",
            "\(scroll) scroll · \(click) click · \(drag) drag",
        ]
    }

    private func hintNext(_ b: BindingsConfig) -> [String] {
        let space = label(b.hint.leftClick)
        let right = label(b.hint.rightClick)
        let move = label(b.hint.moveNoAction)
        let free = label(b.hint.toFree)
        let back = label(b.hint.back)
        let cancel = label(b.hint.cancel)
        let state = model.nav.hintState

        if state.targets.isEmpty {
            return ["Scanning controls…"]
        }
        if state.armedID != nil {
            return [
                "\(space) click · \(right) right · \(move) move",
                "\(free) free · \(back) back · \(cancel) cancel",
            ]
        }
        if !state.typed.isEmpty {
            let exact = state.targets.contains { $0.code == state.typed }
            if exact {
                return [
                    "\(space) confirm “\(state.typed)” · keep typing for longer",
                    "\(free) free · \(back) back · \(cancel) cancel",
                ]
            }
            return [
                "Keep typing · \(back) back",
                "\(cancel) cancel",
            ]
        }
        return [
            "Type a hint code",
            "\(cancel) cancel",
        ]
    }

    /// First binding, shortened for the strip (`option_left` → `⌥`).
    private func label(_ raw: [String]) -> String {
        guard let first = raw.first else { return "?" }
        return pretty(first)
    }

    private func pretty(_ raw: String) -> String {
        raw.lowercased()
            .split(separator: "+")
            .map { token -> String in
                switch token {
                case "command", "cmd": return "⌘"
                case "command_left", "cmd_left": return "⌘"
                case "command_right", "cmd_right": return "⌘"
                case "option", "opt", "alt": return "⌥"
                case "option_left", "opt_left", "alt_left": return "⌥"
                case "option_right", "opt_right", "alt_right": return "⌥"
                case "shift": return "⇧"
                case "shift_left", "shift_right": return "⇧"
                case "control", "ctrl": return "⌃"
                case "control_left", "control_right": return "⌃"
                case "space": return "Space"
                case "return", "enter": return "↩"
                case "escape", "esc": return "Esc"
                case "delete", "backspace": return "⌫"
                case "tab": return "Tab"
                case "left": return "←"
                case "right": return "→"
                case "up": return "↑"
                case "down": return "↓"
                default: return String(token).uppercased()
                }
            }
            .joined()
    }
}

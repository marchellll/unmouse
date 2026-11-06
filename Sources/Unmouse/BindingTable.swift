import CoreGraphics
import UnmouseCore

/// Parsed once when config applies. Matching a key does not re-run ShortcutParser.
struct BindingTable {
    struct Global {
        var gridMode: BindingMatcher
        var freeMode: BindingMatcher
        var hintMode: BindingMatcher
    }

    struct Grid {
        var cancel: BindingMatcher
        var back: BindingMatcher
        var nextScreen: BindingMatcher
        var leftClick: BindingMatcher
        var rightClick: BindingMatcher
        var middleClick: BindingMatcher
        var moveOnly: BindingMatcher
        var toFree: BindingMatcher
    }

    struct Free {
        var move: [MoveDirection: BindingMatcher]
        var scroll: [MoveDirection: BindingMatcher]
        var faster: BindingMatcher
        var slower: BindingMatcher
        var toggleDrag: BindingMatcher
        var leftClick: BindingMatcher
        var rightClick: BindingMatcher
        var middleClick: BindingMatcher
        var cancel: BindingMatcher
        /// Raw move shortcuts kept for HID / token checks.
        var moveRaw: [MoveDirection: [String]]
        var scrollRaw: [MoveDirection: [String]]
        var fasterRaw: [String]
        var slowerRaw: [String]
    }

    struct Hint {
        var cancel: BindingMatcher
        var back: BindingMatcher
        var leftClick: BindingMatcher
        var rightClick: BindingMatcher
        var moveNoAction: BindingMatcher
        var toFree: BindingMatcher
    }

    var global: Global
    var grid: Grid
    var free: Free
    var hint: Hint

    static let empty = BindingTable(bindings: .init())

    init(bindings: BindingsConfig) {
        let g = bindings.global
        global = Global(
            gridMode: BindingMatcher(g.gridMode),
            freeMode: BindingMatcher(g.freeMode),
            hintMode: BindingMatcher(g.hintMode)
        )
        let gr = bindings.grid
        grid = Grid(
            cancel: BindingMatcher(gr.cancel),
            back: BindingMatcher(gr.back),
            nextScreen: BindingMatcher(gr.nextScreen),
            leftClick: BindingMatcher(gr.leftClick),
            rightClick: BindingMatcher(gr.rightClick),
            middleClick: BindingMatcher(gr.middleClick),
            moveOnly: BindingMatcher(gr.moveOnly),
            toFree: BindingMatcher(gr.toFree)
        )
        let f = bindings.free
        var move: [MoveDirection: BindingMatcher] = [:]
        var scroll: [MoveDirection: BindingMatcher] = [:]
        var moveRaw: [MoveDirection: [String]] = [:]
        var scrollRaw: [MoveDirection: [String]] = [:]
        for direction in MoveDirection.allCases {
            move[direction] = BindingMatcher(f.move(direction))
            scroll[direction] = BindingMatcher(f.scroll(direction))
            moveRaw[direction] = f.move(direction)
            scrollRaw[direction] = f.scroll(direction)
        }
        free = Free(
            move: move,
            scroll: scroll,
            faster: BindingMatcher(f.faster),
            slower: BindingMatcher(f.slower),
            toggleDrag: BindingMatcher(f.toggleDrag),
            leftClick: BindingMatcher(f.leftClick),
            rightClick: BindingMatcher(f.rightClick),
            middleClick: BindingMatcher(f.middleClick),
            cancel: BindingMatcher(f.cancel),
            moveRaw: moveRaw,
            scrollRaw: scrollRaw,
            fasterRaw: f.faster,
            slowerRaw: f.slower
        )
        let h = bindings.hint
        hint = Hint(
            cancel: BindingMatcher(h.cancel),
            back: BindingMatcher(h.back),
            leftClick: BindingMatcher(h.leftClick),
            rightClick: BindingMatcher(h.rightClick),
            moveNoAction: BindingMatcher(h.moveNoAction),
            toFree: BindingMatcher(h.toFree)
        )
    }

    func matchesMove(_ direction: MoveDirection, key: KeyKind, flags: CGEventFlags) -> Bool {
        free.move[direction]?.matches(key: key, flags: flags, alone: false) ?? false
    }

    func matchesScroll(_ direction: MoveDirection, key: KeyKind, flags: CGEventFlags) -> Bool {
        free.scroll[direction]?.matches(key: key, flags: flags, alone: false) ?? false
    }
}

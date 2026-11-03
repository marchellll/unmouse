import Carbon.HIToolbox
import CoreGraphics
import UnmouseCore

enum KeyCodes {
    static func keyCode(for kind: KeyKind) -> CGKeyCode? {
        switch kind {
        case .letter(let c):
            switch c {
            case "a": return CGKeyCode(kVK_ANSI_A)
            case "b": return CGKeyCode(kVK_ANSI_B)
            case "c": return CGKeyCode(kVK_ANSI_C)
            case "d": return CGKeyCode(kVK_ANSI_D)
            case "e": return CGKeyCode(kVK_ANSI_E)
            case "f": return CGKeyCode(kVK_ANSI_F)
            case "g": return CGKeyCode(kVK_ANSI_G)
            case "h": return CGKeyCode(kVK_ANSI_H)
            case "i": return CGKeyCode(kVK_ANSI_I)
            case "j": return CGKeyCode(kVK_ANSI_J)
            case "k": return CGKeyCode(kVK_ANSI_K)
            case "l": return CGKeyCode(kVK_ANSI_L)
            case "m": return CGKeyCode(kVK_ANSI_M)
            case "n": return CGKeyCode(kVK_ANSI_N)
            case "o": return CGKeyCode(kVK_ANSI_O)
            case "p": return CGKeyCode(kVK_ANSI_P)
            case "q": return CGKeyCode(kVK_ANSI_Q)
            case "r": return CGKeyCode(kVK_ANSI_R)
            case "s": return CGKeyCode(kVK_ANSI_S)
            case "t": return CGKeyCode(kVK_ANSI_T)
            case "u": return CGKeyCode(kVK_ANSI_U)
            case "v": return CGKeyCode(kVK_ANSI_V)
            case "w": return CGKeyCode(kVK_ANSI_W)
            case "x": return CGKeyCode(kVK_ANSI_X)
            case "y": return CGKeyCode(kVK_ANSI_Y)
            case "z": return CGKeyCode(kVK_ANSI_Z)
            default: return nil
            }
        case .digit(let c):
            switch c {
            case "0": return CGKeyCode(kVK_ANSI_0)
            case "1": return CGKeyCode(kVK_ANSI_1)
            case "2": return CGKeyCode(kVK_ANSI_2)
            case "3": return CGKeyCode(kVK_ANSI_3)
            case "4": return CGKeyCode(kVK_ANSI_4)
            case "5": return CGKeyCode(kVK_ANSI_5)
            case "6": return CGKeyCode(kVK_ANSI_6)
            case "7": return CGKeyCode(kVK_ANSI_7)
            case "8": return CGKeyCode(kVK_ANSI_8)
            case "9": return CGKeyCode(kVK_ANSI_9)
            default: return nil
            }
        case .punctuation(let c):
            switch c {
            case ",": return CGKeyCode(kVK_ANSI_Comma)
            case ".": return CGKeyCode(kVK_ANSI_Period)
            case "/": return CGKeyCode(kVK_ANSI_Slash)
            case ";": return CGKeyCode(kVK_ANSI_Semicolon)
            case "'": return CGKeyCode(kVK_ANSI_Quote)
            case "[": return CGKeyCode(kVK_ANSI_LeftBracket)
            case "]": return CGKeyCode(kVK_ANSI_RightBracket)
            case "\\": return CGKeyCode(kVK_ANSI_Backslash)
            case "-": return CGKeyCode(kVK_ANSI_Minus)
            case "=": return CGKeyCode(kVK_ANSI_Equal)
            default: return nil
            }
        case .space: return CGKeyCode(kVK_Space)
        case .return: return CGKeyCode(kVK_Return)
        case .escape: return CGKeyCode(kVK_Escape)
        case .tab: return CGKeyCode(kVK_Tab)
        case .delete: return CGKeyCode(kVK_Delete)
        case .forwardDelete: return CGKeyCode(kVK_ForwardDelete)
        case .left: return CGKeyCode(kVK_LeftArrow)
        case .right: return CGKeyCode(kVK_RightArrow)
        case .up: return CGKeyCode(kVK_UpArrow)
        case .down: return CGKeyCode(kVK_DownArrow)
        case .home: return CGKeyCode(kVK_Home)
        case .end: return CGKeyCode(kVK_End)
        case .pageUp: return CGKeyCode(kVK_PageUp)
        case .pageDown: return CGKeyCode(kVK_PageDown)
        case .function(let n):
            let map: [Int: Int] = [
                1: kVK_F1, 2: kVK_F2, 3: kVK_F3, 4: kVK_F4, 5: kVK_F5, 6: kVK_F6,
                7: kVK_F7, 8: kVK_F8, 9: kVK_F9, 10: kVK_F10, 11: kVK_F11, 12: kVK_F12,
                13: kVK_F13, 14: kVK_F14, 15: kVK_F15, 16: kVK_F16, 17: kVK_F17, 18: kVK_F18,
                19: kVK_F19, 20: kVK_F20,
            ]
            return map[n].map { CGKeyCode($0) }
        case .commandLeft: return CGKeyCode(kVK_Command)
        case .commandRight: return CGKeyCode(kVK_RightCommand)
        case .optionLeft: return CGKeyCode(kVK_Option)
        case .optionRight: return CGKeyCode(kVK_RightOption)
        case .shiftLeft: return CGKeyCode(kVK_Shift)
        case .shiftRight: return CGKeyCode(kVK_RightShift)
        case .controlLeft: return CGKeyCode(kVK_Control)
        case .controlRight: return CGKeyCode(kVK_RightControl)
        case .fn: return CGKeyCode(kVK_Function)
        case .command, .option, .shift, .control:
            return nil
        }
    }

    static func kind(from keyCode: CGKeyCode) -> KeyKind? {
        switch Int(keyCode) {
        case kVK_ANSI_A: return .letter("a")
        case kVK_ANSI_B: return .letter("b")
        case kVK_ANSI_C: return .letter("c")
        case kVK_ANSI_D: return .letter("d")
        case kVK_ANSI_E: return .letter("e")
        case kVK_ANSI_F: return .letter("f")
        case kVK_ANSI_G: return .letter("g")
        case kVK_ANSI_H: return .letter("h")
        case kVK_ANSI_I: return .letter("i")
        case kVK_ANSI_J: return .letter("j")
        case kVK_ANSI_K: return .letter("k")
        case kVK_ANSI_L: return .letter("l")
        case kVK_ANSI_M: return .letter("m")
        case kVK_ANSI_N: return .letter("n")
        case kVK_ANSI_O: return .letter("o")
        case kVK_ANSI_P: return .letter("p")
        case kVK_ANSI_Q: return .letter("q")
        case kVK_ANSI_R: return .letter("r")
        case kVK_ANSI_S: return .letter("s")
        case kVK_ANSI_T: return .letter("t")
        case kVK_ANSI_U: return .letter("u")
        case kVK_ANSI_V: return .letter("v")
        case kVK_ANSI_W: return .letter("w")
        case kVK_ANSI_X: return .letter("x")
        case kVK_ANSI_Y: return .letter("y")
        case kVK_ANSI_Z: return .letter("z")
        case kVK_ANSI_0: return .digit("0")
        case kVK_ANSI_1: return .digit("1")
        case kVK_ANSI_2: return .digit("2")
        case kVK_ANSI_3: return .digit("3")
        case kVK_ANSI_4: return .digit("4")
        case kVK_ANSI_5: return .digit("5")
        case kVK_ANSI_6: return .digit("6")
        case kVK_ANSI_7: return .digit("7")
        case kVK_ANSI_8: return .digit("8")
        case kVK_ANSI_9: return .digit("9")
        case kVK_ANSI_Comma: return .punctuation(",")
        case kVK_ANSI_Period: return .punctuation(".")
        case kVK_ANSI_Slash: return .punctuation("/")
        case kVK_ANSI_Semicolon: return .punctuation(";")
        case kVK_ANSI_Quote: return .punctuation("'")
        case kVK_ANSI_LeftBracket: return .punctuation("[")
        case kVK_ANSI_RightBracket: return .punctuation("]")
        case kVK_ANSI_Backslash: return .punctuation("\\")
        case kVK_ANSI_Minus: return .punctuation("-")
        case kVK_ANSI_Equal: return .punctuation("=")
        case kVK_Space: return .space
        case kVK_Return: return .return
        case kVK_Escape: return .escape
        case kVK_Tab: return .tab
        case kVK_Delete: return .delete
        case kVK_ForwardDelete: return .forwardDelete
        case kVK_LeftArrow: return .left
        case kVK_RightArrow: return .right
        case kVK_UpArrow: return .up
        case kVK_DownArrow: return .down
        case kVK_Home: return .home
        case kVK_End: return .end
        case kVK_PageUp: return .pageUp
        case kVK_PageDown: return .pageDown
        case kVK_Command: return .commandLeft
        case kVK_RightCommand: return .commandRight
        case kVK_Option: return .optionLeft
        case kVK_RightOption: return .optionRight
        case kVK_Shift: return .shiftLeft
        case kVK_RightShift: return .shiftRight
        case kVK_Control: return .controlLeft
        case kVK_RightControl: return .controlRight
        case kVK_Function: return .fn
        case kVK_F1: return .function(1)
        case kVK_F2: return .function(2)
        case kVK_F3: return .function(3)
        case kVK_F4: return .function(4)
        case kVK_F5: return .function(5)
        case kVK_F6: return .function(6)
        case kVK_F7: return .function(7)
        case kVK_F8: return .function(8)
        case kVK_F9: return .function(9)
        case kVK_F10: return .function(10)
        case kVK_F11: return .function(11)
        case kVK_F12: return .function(12)
        default: return nil
        }
    }

    static func token(for kind: KeyKind) -> String {
        String(describing: kind)
    }
}

struct BindingMatcher {
    let shortcuts: [Shortcut]

    init(_ raw: [String]) {
        shortcuts = (try? ShortcutParser.parseAll(raw)) ?? []
    }

    func matches(key: KeyKind, flags: CGEventFlags, alone: Bool) -> Bool {
        for sc in shortcuts {
            if match(sc, key: key, flags: flags, alone: alone) {
                return true
            }
        }
        return false
    }

    private func match(_ sc: Shortcut, key: KeyKind, flags: CGEventFlags, alone: Bool) -> Bool {
        if sc.isBareModifier {
            return alone && sameSide(sc.key, key)
        }
        guard keysEqual(sc.key, key) else { return false }
        return modifiersMatch(sc.modifiers, flags: flags)
    }

    private func keysEqual(_ a: KeyKind, _ b: KeyKind) -> Bool {
        if a == b { return true }
        return sameSide(a, b)
    }

    private func sameSide(_ a: KeyKind, _ b: KeyKind) -> Bool {
        switch (a, b) {
        case (.command, .commandLeft), (.command, .commandRight),
             (.commandLeft, .command), (.commandRight, .command),
             (.option, .optionLeft), (.option, .optionRight),
             (.optionLeft, .option), (.optionRight, .option),
             (.shift, .shiftLeft), (.shift, .shiftRight),
             (.shiftLeft, .shift), (.shiftRight, .shift),
             (.control, .controlLeft), (.control, .controlRight),
             (.controlLeft, .control), (.controlRight, .control):
            return true
        default:
            return a == b
        }
    }

    private func modifiersMatch(_ required: Set<KeyKind>, flags: CGEventFlags) -> Bool {
        func has(_ flag: CGEventFlags) -> Bool { flags.contains(flag) }
        var needCommand = false
        var needOption = false
        var needShift = false
        var needControl = false
        for m in required {
            switch m {
            case .command, .commandLeft, .commandRight: needCommand = true
            case .option, .optionLeft, .optionRight: needOption = true
            case .shift, .shiftLeft, .shiftRight: needShift = true
            case .control, .controlLeft, .controlRight: needControl = true
            case .fn: if !has(.maskSecondaryFn) { return false }
            default: break
            }
        }
        if needCommand != has(.maskCommand) { return false }
        if needOption != has(.maskAlternate) { return false }
        if needShift != has(.maskShift) { return false }
        if needControl != has(.maskControl) { return false }
        return true
    }
}

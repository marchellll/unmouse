import AppKit
import Carbon.HIToolbox
import CoreGraphics
import UnmouseCore

final class EventTapController {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// kind, flags, down, alone, eventNanos
    var onKey: ((KeyKind, CGEventFlags, Bool, Bool, UInt64) -> Bool)?
    /// Physical mouse button. Never swallowed.
    var onMouseDown: (() -> Void)?
    /// Tap was disabled (timeout or user input). Held keys may have missed a key-up.
    var onTapReset: (() -> Void)?
    private var alone = AloneTapTracker()
    private var maxTapMs: UInt64 = 200

    func setMaxTapMilliseconds(_ ms: UInt64) {
        maxTapMs = max(1, ms)
        alone.setMaxTapMilliseconds(maxTapMs)
    }

    func start() -> Bool {
        stop()
        alone = AloneTapTracker(maxTapMilliseconds: maxTapMs)
        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        tap = nil
        alone = AloneTapTracker(maxTapMilliseconds: maxTapMs)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            InputTrace.log("tap DISABLED (\(type == .tapDisabledByTimeout ? "timeout" : "userInput")) — re-enable + reset")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onTapReset?()
            return Unmanaged.passUnretained(event)
        }
        if PointerController.isOurs(event) {
            return Unmanaged.passUnretained(event)
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            InputTrace.log("tap was off — re-enable")
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let nanos = Self.eventNanos(event)
        let swallow: Bool

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            InputTrace.log("mouseDown button=\(type.rawValue)")
            onMouseDown?()
            return Unmanaged.passUnretained(event)
        case .keyDown:
            _ = alone.handle(.otherKey)
            guard let kind = KeyCodes.kind(from: keyCode) else {
                InputTrace.log("tap keyDown code=\(keyCode) UNKNOWN — pass")
                return Unmanaged.passUnretained(event)
            }
            swallow = onKey?(kind, flags, true, false, nanos) ?? false
            InputTrace.log(
                "tap keyDown \(KeyCodes.token(for: kind)) flags=\(InputTrace.flags(flags)) → \(swallow ? "SWALLOW" : "pass") t=\(nanos)"
            )
        case .keyUp:
            guard let kind = KeyCodes.kind(from: keyCode) else {
                InputTrace.log("tap keyUp code=\(keyCode) UNKNOWN — pass")
                return Unmanaged.passUnretained(event)
            }
            swallow = onKey?(kind, flags, false, false, nanos) ?? false
            InputTrace.log(
                "tap keyUp \(KeyCodes.token(for: kind)) flags=\(InputTrace.flags(flags)) → \(swallow ? "SWALLOW" : "pass") t=\(nanos)"
            )
        case .flagsChanged:
            swallow = handleFlagsChanged(keyCode: keyCode, flags: flags, nowNanos: nanos)
        default:
            return Unmanaged.passUnretained(event)
        }

        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags, nowNanos: UInt64) -> Bool {
        guard let kind = KeyCodes.kind(from: keyCode), kind.isModifier else {
            InputTrace.log("tap flagsChanged code=\(keyCode) not a tracked modifier — pass")
            return false
        }
        let isDown = Self.modifierPressed(kind, flags: flags)
        let token = kind.configToken
        switch alone.handle(.modifier(token: token, down: isDown, nowNanos: nowNanos)) {
        case .ignored:
            InputTrace.log("tap flags \(token) \(isDown ? "down" : "up") alone=ignored flags=\(InputTrace.flags(flags))")
            return false
        case .down:
            _ = onKey?(kind, flags, true, false, nowNanos)
            InputTrace.log("tap flags \(token) down alone=no flags=\(InputTrace.flags(flags)) → pass (never swallow)")
            return false
        case .up(let wasAlone):
            // Never swallow. A missing key-up leaves Option, Command, Control, or Shift held in every app.
            _ = onKey?(kind, flags, false, wasAlone, nowNanos)
            InputTrace.log(
                "tap flags \(token) up alone=\(wasAlone) flags=\(InputTrace.flags(flags)) → pass (never swallow)"
            )
            return false
        }
    }

    /// Event time in nanoseconds since boot, for ordering against Karabiner HID stamps.
    /// `CGEvent.timestamp` is already CGEventTimestamp (UInt64 nanos). Multiplying by
    /// 1e9 overflows and traps under Swift's checked arithmetic.
    static func eventNanos(_ event: CGEvent) -> UInt64 {
        event.timestamp
    }

    private static func modifierPressed(_ kind: KeyKind, flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        switch kind {
        case .commandLeft:
            if raw & NX_DEVICELCMDKEYMASK != 0 { return true }
            if raw & NX_DEVICERCMDKEYMASK != 0 { return false }
            return flags.contains(.maskCommand)
        case .commandRight:
            if raw & NX_DEVICERCMDKEYMASK != 0 { return true }
            if raw & NX_DEVICELCMDKEYMASK != 0 { return false }
            return flags.contains(.maskCommand)
        case .optionLeft:
            if raw & NX_DEVICELALTKEYMASK != 0 { return true }
            if raw & NX_DEVICERALTKEYMASK != 0 { return false }
            return flags.contains(.maskAlternate)
        case .optionRight:
            if raw & NX_DEVICERALTKEYMASK != 0 { return true }
            if raw & NX_DEVICELALTKEYMASK != 0 { return false }
            return flags.contains(.maskAlternate)
        case .shiftLeft:
            if raw & NX_DEVICELSHIFTKEYMASK != 0 { return true }
            if raw & NX_DEVICERSHIFTKEYMASK != 0 { return false }
            return flags.contains(.maskShift)
        case .shiftRight:
            if raw & NX_DEVICERSHIFTKEYMASK != 0 { return true }
            if raw & NX_DEVICELSHIFTKEYMASK != 0 { return false }
            return flags.contains(.maskShift)
        case .controlLeft:
            if raw & NX_DEVICELCTLKEYMASK != 0 { return true }
            if raw & NX_DEVICERCTLKEYMASK != 0 { return false }
            return flags.contains(.maskControl)
        case .controlRight:
            if raw & NX_DEVICERCTLKEYMASK != 0 { return true }
            if raw & NX_DEVICELCTLKEYMASK != 0 { return false }
            return flags.contains(.maskControl)
        case .command: return flags.contains(.maskCommand)
        case .option: return flags.contains(.maskAlternate)
        case .shift: return flags.contains(.maskShift)
        case .control: return flags.contains(.maskControl)
        case .fn: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }
}

private let NX_DEVICELCTLKEYMASK: UInt64 = 0x00000001
private let NX_DEVICERCTLKEYMASK: UInt64 = 0x00000002
private let NX_DEVICELSHIFTKEYMASK: UInt64 = 0x00000004
private let NX_DEVICERSHIFTKEYMASK: UInt64 = 0x00000008
private let NX_DEVICELCMDKEYMASK: UInt64 = 0x00000010
private let NX_DEVICERCMDKEYMASK: UInt64 = 0x00000020
private let NX_DEVICELALTKEYMASK: UInt64 = 0x00000040
private let NX_DEVICERALTKEYMASK: UInt64 = 0x00000080

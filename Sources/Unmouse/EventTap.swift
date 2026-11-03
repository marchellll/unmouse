import AppKit
import Carbon.HIToolbox
import CoreGraphics
import UnmouseCore

final class EventTapController {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var onKey: ((KeyKind, CGEventFlags, Bool, Bool) -> Bool)?

    /// Tracks modifiers pressed alone for tap detection.
    private var aloneCandidate: KeyKind?
    private var aloneInterrupted = false

    func start() -> Bool {
        stop()
        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

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
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if PointerController.isOurs(event) {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let swallow: Bool

        switch type {
        case .keyDown:
            aloneInterrupted = true
            aloneCandidate = nil
            guard let kind = KeyCodes.kind(from: keyCode) else {
                return Unmanaged.passUnretained(event)
            }
            swallow = onKey?(kind, flags, true, false) ?? false
        case .keyUp:
            guard let kind = KeyCodes.kind(from: keyCode) else {
                return Unmanaged.passUnretained(event)
            }
            swallow = onKey?(kind, flags, false, false) ?? false
        case .flagsChanged:
            swallow = handleFlagsChanged(keyCode: keyCode, flags: flags, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }

        return swallow ? nil : Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags, event: CGEvent) -> Bool {
        guard let kind = KeyCodes.kind(from: keyCode) else { return false }

        let isDown: Bool = {
            switch kind {
            case .commandLeft, .commandRight: return flags.contains(.maskCommand)
            case .optionLeft, .optionRight: return flags.contains(.maskAlternate)
            case .shiftLeft, .shiftRight: return flags.contains(.maskShift)
            case .controlLeft, .controlRight: return flags.contains(.maskControl)
            case .fn: return flags.contains(.maskSecondaryFn)
            default: return false
            }
        }()

        // Track alone taps: press starts candidate, other key clears, release alone fires tap
        if isDown {
            if aloneCandidate == nil {
                aloneCandidate = kind
                aloneInterrupted = false
            }
            _ = onKey?(kind, flags, true, false)
            return false
        } else {
            let wasAlone = aloneCandidate == kind && !aloneInterrupted
            aloneCandidate = nil
            let handled = onKey?(kind, flags, false, wasAlone) ?? false
            return handled
        }
    }
}

// NX device masks for distinguishing left/right command when available
private let NX_DEVICELCMDKEYMASK: UInt32 = 0x00000008
private let NX_DEVICERCMDKEYMASK: UInt32 = 0x00000010

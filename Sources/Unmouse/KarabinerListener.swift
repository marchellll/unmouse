import Foundation
import IOKit.hid
import UnmouseCore

/// Read-only listener for Karabiner's virtual keyboard. Never seizes the device.
final class KarabinerListener {
    private var manager: IOHIDManager?
    var onKey: ((KeyKind, Bool) -> Void)?
    private(set) var isActive = false
    var isRunning: Bool { manager != nil }

    func startIfAvailable() -> Bool {
        if manager != nil { return true }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: 0x05AC, // Apple / pqrs often appear as Apple vendor via DriverKit
            ],
        ]
        // Match by product name containing Karabiner / VirtualHID
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let this = Unmanaged<KarabinerListener>.fromOpaque(context).takeUnretainedValue()
            this.attach(device: device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let this = Unmanaged<KarabinerListener>.fromOpaque(context).takeUnretainedValue()
            this.isActive = false
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let open = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard open == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }
        self.manager = manager

        // Also scan currently attached devices
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices where isKarabinerVirtualKeyboard(device) {
                attach(device: device)
            }
        }
        return true
    }

    func stop() {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        isActive = false
    }

    private func attach(device: IOHIDDevice) {
        guard isKarabinerVirtualKeyboard(device) else { return }
        isActive = true
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, _, value in
            guard let context else { return }
            let this = Unmanaged<KarabinerListener>.fromOpaque(context).takeUnretainedValue()
            this.handle(value: value)
        }, ctx)
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard usagePage == 0x07 else { return } // keyboard/keypad
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        if let kind = KeyKind.fromHIDUsage(usage) {
            // Modifiers are owned by the CGEvent tap (alone-tap detection).
            // Emitting them here races the tap and drops ⌘/⌥ taps intermittently.
            if kind.isModifier { return }
            onKey?(kind, pressed)
        }
    }
}

private func isKarabinerVirtualKeyboard(_ device: IOHIDDevice) -> Bool {
    let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
    let lower = name.lowercased()
    return lower.contains("karabiner") || lower.contains("virtualhid") || lower.contains("virtual keyboard")
}

extension KeyKind {
    static func fromHIDUsage(_ usage: UInt32) -> KeyKind? {
        // HID usage IDs for keyboard
        switch usage {
        case 0x04: return .letter("a")
        case 0x05: return .letter("b")
        case 0x06: return .letter("c")
        case 0x07: return .letter("d")
        case 0x08: return .letter("e")
        case 0x09: return .letter("f")
        case 0x0A: return .letter("g")
        case 0x0B: return .letter("h")
        case 0x0C: return .letter("i")
        case 0x0D: return .letter("j")
        case 0x0E: return .letter("k")
        case 0x0F: return .letter("l")
        case 0x10: return .letter("m")
        case 0x11: return .letter("n")
        case 0x12: return .letter("o")
        case 0x13: return .letter("p")
        case 0x14: return .letter("q")
        case 0x15: return .letter("r")
        case 0x16: return .letter("s")
        case 0x17: return .letter("t")
        case 0x18: return .letter("u")
        case 0x19: return .letter("v")
        case 0x1A: return .letter("w")
        case 0x1B: return .letter("x")
        case 0x1C: return .letter("y")
        case 0x1D: return .letter("z")
        case 0x2C: return .space
        case 0x29: return .escape
        case 0x2A: return .delete
        case 0x2B: return .tab
        case 0x28: return .return
        case 0x50: return .left
        case 0x4F: return .right
        case 0x52: return .up
        case 0x51: return .down
        case 0xE0: return .controlLeft
        case 0xE1: return .shiftLeft
        case 0xE2: return .optionLeft
        case 0xE3: return .commandLeft
        case 0xE4: return .controlRight
        case 0xE5: return .shiftRight
        case 0xE6: return .optionRight
        case 0xE7: return .commandRight
        case 0x36: return .punctuation(",")
        case 0x37: return .punctuation(".")
        case 0x38: return .punctuation("/")
        case 0x33: return .punctuation(";")
        default: return nil
        }
    }
}

enum KarabinerPresence {
    static func cliPresent() -> Bool {
        FileManager.default.isExecutableFile(
            atPath: "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
        )
    }
}

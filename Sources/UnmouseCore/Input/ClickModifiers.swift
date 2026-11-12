import CoreGraphics

/// Command, Option, Control, and Shift ride along on a click. Other flags stay off the event.
public enum ClickModifiers {
    public static let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    public static func carried(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(mask)
    }

    public static func stripped(_ flags: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: flags.rawValue & ~mask.rawValue)
    }
}

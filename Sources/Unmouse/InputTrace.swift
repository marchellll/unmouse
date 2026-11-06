import CoreGraphics
import Foundation
import os
import UnmouseCore

/// Temporary input debugger. Always writes to Console.app (filter subsystem
/// `xyz.marchell.unmouse`, category `input`) and stderr. Turn off with `InputTrace.enabled = false`.
enum InputTrace {
    static var enabled = true

    private static let logger = Logger(subsystem: "xyz.marchell.unmouse", category: "input")

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
        UnmouseLog.debug(text)
        fputs("[input] \(text)\n", stderr)
        fflush(stderr)
    }

    static func flags(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskSecondaryFn) { parts.append("fn") }
        return parts.isEmpty ? "-" : parts.joined()
    }
}

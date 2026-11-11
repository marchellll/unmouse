import CoreGraphics
import Foundation
import os
import UnmouseCore

/// Temporary input debugger. Always writes to Console.app (filter subsystem
/// `xyz.marchell.unmouse`, category `input`) and stderr. Turn off with `InputTrace.enabled = false`.
enum InputTrace {
    /// Readable from the hint AX scan thread — only flipped at startup.
    nonisolated(unsafe) static var enabled = true

    nonisolated private static let logger = Logger(subsystem: "xyz.marchell.unmouse", category: "input")

    /// nonisolated so AccessibilityHintSource phase logs work off the main actor.
    nonisolated static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
        // Always emit on the input category; UnmouseLog may be gated to .none.
        fputs("[input] \(text)\n", stderr)
        fflush(stderr)
    }

    /// CGEvent global, origin at the top-left of the main screen. Same form as click logs.
    static func point(_ p: CGPoint) -> String {
        "\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
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

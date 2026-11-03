import Foundation
import os

public enum LogLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case none
    case error
    case warn
    case info
    case debug

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .none: 0
        case .error: 1
        case .warn: 2
        case .info: 3
        case .debug: 4
        }
    }
}

/// Process-wide log gate. Default is `.none` (silent).
public enum UnmouseLog: Sendable {
    nonisolated(unsafe) private static var level: LogLevel = .none
    private static let logger = Logger(subsystem: "xyz.marchell.unmouse", category: "app")

    public static func setLevel(_ level: LogLevel) {
        self.level = level
    }

    public static func error(_ message: @autoclosure () -> String) {
        guard level >= .error else { return }
        let text = message()
        logger.error("\(text, privacy: .public)")
    }

    public static func warn(_ message: @autoclosure () -> String) {
        guard level >= .warn else { return }
        let text = message()
        logger.warning("\(text, privacy: .public)")
    }

    public static func info(_ message: @autoclosure () -> String) {
        guard level >= .info else { return }
        let text = message()
        logger.info("\(text, privacy: .public)")
    }

    public static func debug(_ message: @autoclosure () -> String) {
        guard level >= .debug else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }
}

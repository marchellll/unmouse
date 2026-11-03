import Foundation

public enum AppMode: String, Sendable, Equatable {
    case idle
    case grid
    case free
    case hint
}

public enum MouseButton: String, Sendable, Equatable {
    case left
    case right
    case middle
}

public enum GridFinalizeAction: Sendable, Equatable {
    case leftClick
    case rightClick
    case middleClick
    case moveOnly
    case toFree
}

import Foundation

public enum TutorialSessionID: String, Sendable, CaseIterable, Codable {
    case aimAndHit = "aim_and_hit"
    case freeOnly = "free_only"
    case aimThenAct = "aim_then_act"
    case hintMode = "hint_mode"

    public var title: String {
        switch self {
        case .aimAndHit: "Aim and hit"
        case .freeOnly: "Free mode"
        case .aimThenAct: "Aim, then act"
        case .hintMode: "Hint mode"
        }
    }

    public var next: TutorialSessionID? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

public enum TutorialEvent: Equatable, Sendable {
    case enteredGrid
    case enteredFree
    case enteredHint
    case typedGridCell
    case leftClick
    case rightClick
    case moved
    case heldFaster
    case heldSlower
    case scrolled
    case dragStarted
    case dragDropped
    case gridToFree
    case hintArmed
    case cancelled
    case skipped
}

public struct TutorialStep: Equatable, Sendable, Identifiable {
    public var id: String
    public var prompt: String
    public var required: TutorialEvent

    public init(id: String, prompt: String, required: TutorialEvent) {
        self.id = id
        self.prompt = prompt
        self.required = required
    }
}

public enum TutorialCatalog {
    public static func steps(for session: TutorialSessionID) -> [TutorialStep] {
        switch session {
        case .aimAndHit:
            [
                .init(id: "a1", prompt: "Tap Left Command to open the grid.", required: .enteredGrid),
                .init(id: "a2", prompt: "Type a cell.", required: .typedGridCell),
                .init(id: "a3", prompt: "Press Space to left-click.", required: .leftClick),
                .init(id: "a4", prompt: "Open the grid again and type a cell.", required: .typedGridCell),
                .init(id: "a5", prompt: "Press A to right-click.", required: .rightClick),
            ]
        case .freeOnly:
            [
                .init(id: "f1", prompt: "Tap Left Option for free mode.", required: .enteredFree),
                .init(id: "f2", prompt: "Move with H J K L or the arrows.", required: .moved),
                .init(id: "f3", prompt: "Hold Z and move (faster).", required: .heldFaster),
                .init(id: "f4", prompt: "Hold X and move (slower).", required: .heldSlower),
                .init(id: "f5", prompt: "Press Space to left-click.", required: .leftClick),
                .init(id: "f6", prompt: "Press A to right-click.", required: .rightClick),
                .init(id: "f7", prompt: "Scroll with M , . /", required: .scrolled),
                .init(id: "f8", prompt: "Press Q to start a drag.", required: .dragStarted),
                .init(id: "f9", prompt: "Move, then Space to drop.", required: .dragDropped),
                .init(id: "f10", prompt: "Press Escape to leave.", required: .cancelled),
            ]
        case .aimThenAct:
            [
                .init(id: "c1", prompt: "Open the grid (Left Command).", required: .enteredGrid),
                .init(id: "c2", prompt: "Type a cell.", required: .typedGridCell),
                .init(id: "c3", prompt: "Tap Left Option to enter free mode on that cell.", required: .gridToFree),
                .init(id: "c4", prompt: "Nudge with H J K L.", required: .moved),
                .init(id: "c5", prompt: "Press Space to click.", required: .leftClick),
            ]
        case .hintMode:
            [
                .init(id: "h1", prompt: "Press Command-Shift-Space for hints.", required: .enteredHint),
                .init(id: "h2", prompt: "Type until one hint is armed.", required: .hintArmed),
                .init(id: "h3", prompt: "Press Space to left-click.", required: .leftClick),
                .init(id: "h4", prompt: "Open hints again and arm one.", required: .hintArmed),
                .init(id: "h5", prompt: "Press A to right-click.", required: .rightClick),
            ]
        }
    }
}

public struct TutorialProgress: Equatable, Sendable {
    public var session: TutorialSessionID
    public var stepIndex: Int
    public var completed: Bool

    public init(session: TutorialSessionID, stepIndex: Int = 0, completed: Bool = false) {
        self.session = session
        self.stepIndex = stepIndex
        self.completed = completed
    }

    public var steps: [TutorialStep] {
        TutorialCatalog.steps(for: session)
    }

    public var current: TutorialStep? {
        guard !completed, stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    public mutating func handle(_ event: TutorialEvent) -> Bool {
        guard !completed, let step = current else { return false }
        if event == .skipped {
            completed = true
            return true
        }
        guard event == step.required else { return false }
        stepIndex += 1
        if stepIndex >= steps.count {
            completed = true
        }
        return true
    }
}

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
    /// Hit the arena's left-click target (real UI under the cursor).
    case hitLeftTarget
    /// Hit the arena's right-click target.
    case hitRightTarget
    /// Dropped the arena drag puck on the drop zone.
    case hitDragDrop
    /// Scrolled the arena scroll strip.
    case hitScroll
}

public enum TutorialArenaFocus: String, Sendable, Equatable {
    case none
    case leftTarget
    case rightTarget
    case drag
    case scroll
    case hintButton
}

public struct TutorialStep: Equatable, Sendable, Identifiable {
    public var id: String
    public var prompt: String
    public var required: TutorialEvent
    public var arenaFocus: TutorialArenaFocus

    public init(
        id: String,
        prompt: String,
        required: TutorialEvent,
        arenaFocus: TutorialArenaFocus = .none
    ) {
        self.id = id
        self.prompt = prompt
        self.required = required
        self.arenaFocus = arenaFocus
    }
}

public enum TutorialCatalog {
    public static func steps(for session: TutorialSessionID) -> [TutorialStep] {
        switch session {
        case .aimAndHit:
            [
                .init(id: "a1", prompt: "Tap Left Command — open the grid.", required: .enteredGrid),
                .init(id: "a2", prompt: "Type the cell over the green target.", required: .typedGridCell, arenaFocus: .leftTarget),
                .init(id: "a3", prompt: "Space — hit the green target.", required: .hitLeftTarget, arenaFocus: .leftTarget),
                .init(id: "a4", prompt: "Grid again. Aim at the orange target.", required: .typedGridCell, arenaFocus: .rightTarget),
                .init(id: "a5", prompt: "A — right-click the orange target.", required: .hitRightTarget, arenaFocus: .rightTarget),
            ]
        case .freeOnly:
            [
                .init(id: "f1", prompt: "Tap Left Option — free mode.", required: .enteredFree),
                .init(id: "f2", prompt: "Steer with H J K L toward the green target.", required: .moved, arenaFocus: .leftTarget),
                .init(id: "f3", prompt: "Hold Z and move — go faster.", required: .heldFaster),
                .init(id: "f4", prompt: "Hold X and move — go slower.", required: .heldSlower),
                .init(id: "f5", prompt: "Space — click the green target.", required: .hitLeftTarget, arenaFocus: .leftTarget),
                .init(id: "f6", prompt: "A — right-click the orange target.", required: .hitRightTarget, arenaFocus: .rightTarget),
                .init(id: "f7", prompt: "Scroll the blue strip — M left, , down, . up, / right.", required: .hitScroll, arenaFocus: .scroll),
                .init(id: "f8", prompt: "Q — grab the puck.", required: .dragStarted, arenaFocus: .drag),
                .init(id: "f9", prompt: "Drag the puck into the ring, then Space to drop.", required: .hitDragDrop, arenaFocus: .drag),
                .init(id: "f10", prompt: "Escape — leave free mode.", required: .cancelled),
            ]
        case .aimThenAct:
            [
                .init(id: "c1", prompt: "Left Command — open the grid.", required: .enteredGrid),
                .init(id: "c2", prompt: "Type a cell near the green target.", required: .typedGridCell, arenaFocus: .leftTarget),
                .init(id: "c3", prompt: "Left Option — drop into free mode.", required: .gridToFree, arenaFocus: .leftTarget),
                .init(id: "c4", prompt: "Nudge onto the target with H J K L.", required: .moved, arenaFocus: .leftTarget),
                .init(id: "c5", prompt: "Space — click it.", required: .hitLeftTarget, arenaFocus: .leftTarget),
            ]
        case .hintMode:
            [
                .init(id: "h1", prompt: "Command-Shift-Space — show hints.", required: .enteredHint, arenaFocus: .hintButton),
                .init(id: "h2", prompt: "Type the code on the labeled button.", required: .hintArmed, arenaFocus: .hintButton),
                .init(id: "h3", prompt: "Space — click via hint.", required: .hitLeftTarget, arenaFocus: .hintButton),
                .init(id: "h4", prompt: "Hints again. Arm the Menu target.", required: .hintArmed, arenaFocus: .rightTarget),
                .init(id: "h5", prompt: "A — right-click Menu.", required: .hitRightTarget, arenaFocus: .rightTarget),
            ]
        }
    }
}

public struct TutorialProgress: Equatable, Sendable {
    public var session: TutorialSessionID
    public var stepIndex: Int
    public var completed: Bool
    public var score: Int

    public init(session: TutorialSessionID, stepIndex: Int = 0, completed: Bool = false, score: Int = 0) {
        self.session = session
        self.stepIndex = stepIndex
        self.completed = completed
        self.score = score
    }

    public var steps: [TutorialStep] {
        TutorialCatalog.steps(for: session)
    }

    public var current: TutorialStep? {
        guard !completed, stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    public var arenaFocus: TutorialArenaFocus {
        current?.arenaFocus ?? .none
    }

    public mutating func handle(_ event: TutorialEvent) -> Bool {
        guard !completed, let step = current else { return false }
        if event == .skipped {
            completed = true
            return true
        }
        guard event == step.required else { return false }
        stepIndex += 1
        score += 1
        if stepIndex >= steps.count {
            completed = true
        }
        return true
    }
}

import Foundation

public enum TutorialSessionID: String, Sendable, CaseIterable, Codable {
    case freeOnly = "free_only"
    case aimAndHit = "aim_and_hit"
    case aimThenAct = "aim_then_act"
    case hintMode = "hint_mode"

    public var title: String {
        switch self {
        case .freeOnly: "Free mode"
        case .aimAndHit: "Aim and hit"
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
    /// One free-mode direction. The steer step waits until every direction has arrived.
    case steered(MoveDirection)
    case steeredAll
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

public enum MoveDirection: String, Sendable, Equatable, CaseIterable {
    case left, down, up, right
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
    /// Shown under the prompt. Use it for anything the grid overlay will hide.
    public var detail: String?
    public var required: TutorialEvent
    public var arenaFocus: TutorialArenaFocus

    public init(
        id: String,
        prompt: String,
        detail: String? = nil,
        required: TutorialEvent,
        arenaFocus: TutorialArenaFocus = .none
    ) {
        self.id = id
        self.prompt = prompt
        self.detail = detail
        self.required = required
        self.arenaFocus = arenaFocus
    }
}

public enum TutorialCatalog {
    public static func steps(for session: TutorialSessionID) -> [TutorialStep] {
        switch session {
        case .freeOnly:
            [
                .init(id: "f1", prompt: "Tap ⌥ — free mode.", required: .enteredFree),
                .init(id: "f2", prompt: "Steer with H J K L toward the green target.", required: .steeredAll, arenaFocus: .leftTarget),
                .init(id: "f3", prompt: "Hold Z and move — go faster.", required: .heldFaster),
                .init(id: "f4", prompt: "Hold X and move — go slower.", required: .heldSlower),
                .init(id: "f5", prompt: "␣ — click the green target.", required: .hitLeftTarget, arenaFocus: .leftTarget),
                .init(id: "f6", prompt: "A — right-click the orange target.", required: .hitRightTarget, arenaFocus: .rightTarget),
                .init(id: "f7", prompt: "Scroll the blue strip — M left, , down, . up, / right.", required: .hitScroll, arenaFocus: .scroll),
                .init(id: "f8", prompt: "Q — grab the puck.", required: .dragStarted, arenaFocus: .drag),
                .init(id: "f9", prompt: "Drag the puck into the ring, then ␣ to drop.", required: .hitDragDrop, arenaFocus: .drag),
                .init(id: "f10", prompt: "⎋ — leave free mode.", required: .cancelled),
            ]
        case .aimAndHit:
            [
                .init(id: "a1", prompt: "Tap ⌘ — open the grid.", required: .enteredGrid),
                .init(
                    id: "a2",
                    prompt: "Type the cell over the green target.",
                    detail: "The last character opens a finer grid on that cell. ␣ clicks the rectangle chosen so far.",
                    required: .typedGridCell,
                    arenaFocus: .leftTarget
                ),
                .init(id: "a3", prompt: "␣ — hit the green target.", required: .hitLeftTarget, arenaFocus: .leftTarget),
                .init(id: "a4", prompt: "Grid again. Aim at the orange target.", required: .typedGridCell, arenaFocus: .rightTarget),
                .init(id: "a5", prompt: "A — right-click the orange target.", required: .hitRightTarget, arenaFocus: .rightTarget),
            ]
        case .aimThenAct:
            [
                .init(id: "c1", prompt: "⌘ — open the grid.", required: .enteredGrid),
                .init(
                    id: "c2",
                    prompt: "Type a cell near the green target.",
                    detail: "Then ⌥ — drop into free mode.",
                    required: .gridToFree,
                    arenaFocus: .leftTarget
                ),
                .init(id: "c3", prompt: "Nudge onto the target with H J K L.", required: .moved, arenaFocus: .leftTarget),
                .init(id: "c4", prompt: "␣ — click it.", required: .hitLeftTarget, arenaFocus: .leftTarget),
            ]
        case .hintMode:
            [
                .init(id: "h1", prompt: "⌘⇧␣ — show hints.", required: .enteredHint, arenaFocus: .hintButton),
                .init(id: "h2", prompt: "Type the code on the labeled button.", required: .hintArmed, arenaFocus: .hintButton),
                .init(id: "h3", prompt: "␣ — click via hint.", required: .hitLeftTarget, arenaFocus: .hintButton),
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
    private var steered: Set<MoveDirection> = []
    /// The aim-then-act cell step shows the Option instruction up front, then waits for both actions.
    private var cellChosen = false

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
        if case .steered(let direction) = event, step.required == .steeredAll {
            steered.insert(direction)
            guard steered.count == MoveDirection.allCases.count else { return false }
        } else if step.required == .gridToFree {
            if event == .typedGridCell {
                cellChosen = true
                return false
            }
            guard event == .gridToFree, cellChosen else { return false }
        } else if event != step.required {
            return false
        }
        steered.removeAll()
        cellChosen = false
        stepIndex += 1
        score += 1
        if stepIndex >= steps.count {
            completed = true
        }
        return true
    }
}

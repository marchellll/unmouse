import CoreGraphics
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
    /// One free-mode scroll direction. The scroll step waits until every direction has arrived.
    case scrolled(MoveDirection)
    case scrolledAll
    /// One zoom on the practice strip. The zoom step waits until both directions have arrived.
    case zoomed(ZoomDirection)
    case zoomedAll
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

    public var logLabel: String {
        switch self {
        case .steered(let direction): "steered.\(direction.rawValue)"
        case .scrolled(let direction): "scrolled.\(direction.rawValue)"
        case .zoomed(let direction): "zoomed.\(direction.rawValue)"
        default: String(describing: self)
        }
    }
}

/// Practice puck. Home is left of center, the ring is right. Q grabs from anywhere;
/// the puck then follows the pointer instead of waiting for a hit on its circle.
public enum PuckDrop {
    public static let homeX: CGFloat = -80
    public static let dropX: CGFloat = 80
    /// Center to center. The ring is 88pt across.
    public static let radius: CGFloat = 50

    public static func contains(offset: CGSize) -> Bool {
        hypot(homeX + offset.width - dropX, offset.height) < radius
    }
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
    /// While the grid is open, this step's words sit on the cell instead of in the practice window.
    public var gridGuide: GridGuideClick?

    public init(
        id: String,
        prompt: String,
        detail: String? = nil,
        required: TutorialEvent,
        arenaFocus: TutorialArenaFocus = .none,
        gridGuide: GridGuideClick? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.detail = detail
        self.required = required
        self.arenaFocus = arenaFocus
        self.gridGuide = gridGuide
    }
}

public enum TutorialCatalog {
    public static func steps(for session: TutorialSessionID) -> [TutorialStep] {
        switch session {
        case .freeOnly:
            [
                .init(id: "f1", prompt: "Tap `⌥` — free mode.", required: .enteredFree),
                .init(id: "f2", prompt: "Steer with `H` `J` `K` `L` toward the green target.", required: .steeredAll, arenaFocus: .leftTarget),
                .init(id: "f3", prompt: "Hold `Z` and move — go faster.", required: .heldFaster),
                .init(id: "f4", prompt: "Hold `X` and move — go slower.", required: .heldSlower),
                .init(id: "f5", prompt: "`␣` — click the green target.", required: .hitLeftTarget, arenaFocus: .leftTarget),
                .init(id: "f6", prompt: "`A` — right-click the orange target.", required: .hitRightTarget, arenaFocus: .rightTarget),
                .init(id: "f7", prompt: "Scroll the blue strip — `M` left, `,` down, `.` up, `/` right.", required: .scrolledAll, arenaFocus: .scroll),
                .init(id: "f8", prompt: "Zoom the blue strip — `⌘` + `.` in, `⌘` + `,` out.", required: .zoomedAll, arenaFocus: .scroll),
                .init(id: "f9", prompt: "`Q` — grab the puck.", required: .dragStarted, arenaFocus: .drag),
                .init(id: "f10", prompt: "Drag the puck into the ring, then `␣` to drop.", required: .hitDragDrop, arenaFocus: .drag),
                .init(id: "f11", prompt: "`⎋` — leave free mode.", required: .cancelled),
            ]
        case .aimAndHit:
            [
                .init(
                    id: "a1",
                    prompt: "Tap `⌘` — open the grid.",
                    required: .hitLeftTarget,
                    arenaFocus: .leftTarget,
                    gridGuide: .left
                ),
                .init(
                    id: "a2",
                    prompt: "Tap `⌘` — open the grid over the orange target.",
                    required: .hitRightTarget,
                    arenaFocus: .rightTarget,
                    gridGuide: .right
                ),
            ]
        case .aimThenAct:
            [
                .init(id: "c1", prompt: "`⌘` — open the grid.", required: .enteredGrid),
                .init(
                    id: "c2",
                    prompt: "Type a cell near the green target.",
                    detail: "Then `⌥` — drop into free mode.",
                    required: .gridToFree,
                    arenaFocus: .leftTarget,
                    gridGuide: .toFree
                ),
                .init(id: "c3", prompt: "Nudge onto the target with `H` `J` `K` `L`.", required: .moved, arenaFocus: .leftTarget),
                .init(id: "c4", prompt: "`␣` — click it.", required: .hitLeftTarget, arenaFocus: .leftTarget),
            ]
        case .hintMode:
            [
                .init(id: "h1", prompt: "`⌘` + `⇧` + `␣` — show hints.", required: .enteredHint, arenaFocus: .hintButton),
                .init(id: "h2", prompt: "Type the code on the labeled button.", required: .hintArmed, arenaFocus: .hintButton),
                .init(id: "h3", prompt: "`␣` — click via hint.", required: .hitLeftTarget, arenaFocus: .hintButton),
                .init(id: "h4", prompt: "`⌘` + `⇧` + `␣` again. Arm the Menu target.", required: .hintArmed, arenaFocus: .rightTarget),
                .init(id: "h5", prompt: "`A` — right-click Menu.", required: .hitRightTarget, arenaFocus: .rightTarget),
            ]
        }
    }
}

public struct TutorialProgress: Equatable, Sendable {
    public var session: TutorialSessionID
    public var stepIndex: Int
    public var completed: Bool
    /// Z/X steps advance only after this much movement with that modifier held.
    public static let speedDemoSeconds: TimeInterval = 1
    /// Directions seen for the current all-of-them step (steer or scroll).
    private var directions: Set<MoveDirection> = []
    /// Zoom directions seen for the zoom step.
    private var zooms: Set<ZoomDirection> = []
    /// Movement time on the current Z or X step.
    private var speedClock = SpeedDemoClock()
    /// The aim-then-act cell step shows the Option instruction up front, then waits for both actions.
    private var cellChosen = false
    /// Tenths of a second still needed on a started Z/X step. Nil before the first movement.
    public private(set) var speedTenthsLeft: Int?

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

    public var arenaFocus: TutorialArenaFocus {
        current?.arenaFocus ?? .none
    }

    /// Step prompt. Once a Z/X hold has started, it also says how much hold time is left.
    /// After one zoom direction, it names the one still needed.
    public var prompt: String? {
        guard let step = current else { return nil }
        if step.required == .zoomedAll, zooms.count == 1 {
            let missing = ZoomDirection.allCases.first { !zooms.contains($0) }
            let chord = missing == .in ? "`⌘` + `.`" : "`⌘` + `,`"
            return "\(step.prompt) Keep zooming \(missing == .in ? "in" : "out") \(chord)."
        }
        guard let tenths = speedTenthsLeft else { return step.prompt }
        let key: String
        switch step.required {
        case .heldFaster: key = "Z"
        case .heldSlower: key = "X"
        default: return step.prompt
        }
        return "\(step.prompt) Keep holding `\(key)` and move for \(tenths / 10).\(tenths % 10) more seconds."
    }

    public mutating func setSpeedTenthsLeft(_ tenths: Int?) {
        speedTenthsLeft = tenths
    }

    public var canMoveBack: Bool { !completed && stepIndex > 0 }
    public var canMoveForward: Bool { !completed && stepIndex + 1 < steps.count }

    /// Partial credit on the current step, for the input log. Empty when nothing is banked.
    public var creditNote: String {
        var parts: [String] = []
        if !directions.isEmpty {
            parts.append("dir=" + directions.map(\.rawValue).sorted().joined(separator: ","))
        }
        if !zooms.isEmpty {
            parts.append("zoom=" + zooms.map(\.rawValue).sorted().joined(separator: ","))
        }
        if cellChosen { parts.append("cell=1") }
        if speedClock.held > 0 {
            parts.append(String(format: "speed=%.1f", speedClock.held))
        }
        return parts.joined(separator: " ")
    }

    /// Jump one step. Drops partial credit so the step you land on starts clean.
    public mutating func move(_ delta: Int) -> Bool {
        guard !completed else { return false }
        let index = stepIndex + delta
        guard steps.indices.contains(index) else { return false }
        stepIndex = index
        clearStepProgress()
        return true
    }

    public mutating func handle(_ event: TutorialEvent) -> Bool {
        guard !completed, let step = current else { return false }
        if event == .skipped {
            completed = true
            return true
        }
        if case .steered(let direction) = event, step.required == .steeredAll {
            directions.insert(direction)
            guard directions.count == MoveDirection.allCases.count else { return false }
        } else if case .scrolled(let direction) = event, step.required == .scrolledAll {
            directions.insert(direction)
            guard directions.count == MoveDirection.allCases.count else { return false }
        } else if case .zoomed(let direction) = event, step.required == .zoomedAll {
            zooms.insert(direction)
            guard zooms.count == ZoomDirection.allCases.count else { return false }
        } else if step.required == .gridToFree {
            if event == .typedGridCell {
                cellChosen = true
                return false
            }
            guard event == .gridToFree, cellChosen else { return false }
        } else if event != step.required {
            return false
        }
        clearStepProgress()
        stepIndex += 1
        if stepIndex >= steps.count {
            completed = true
        }
        return true
    }

    /// Credit a free-mode frame toward the Z or X step.
    /// Bursts add up. Holding the modifier without moving does not count, and a pause does not wipe the total.
    @discardableResult
    public mutating func observeSpeed(faster: Bool, slower: Bool, moved: Bool, dt: TimeInterval) -> Bool {
        guard !completed, let step = current else { return false }
        let active: Bool
        switch step.required {
        case .heldFaster: active = faster && moved
        case .heldSlower: active = slower && moved
        default:
            speedClock = .init()
            return false
        }
        guard speedClock.advance(active: active, dt: dt, goal: Self.speedDemoSeconds) else { return false }
        return handle(step.required)
    }

    private mutating func clearStepProgress() {
        directions.removeAll()
        zooms.removeAll()
        cellChosen = false
        speedClock = .init()
        speedTenthsLeft = nil
    }
}

/// Active time for the Z/X tutorial step. Pauses keep what was already earned.
public struct SpeedDemoClock: Equatable, Sendable {
    public var held: TimeInterval = 0

    public init() {}

    /// True once `goal` of active time has accumulated across separate bursts.
    /// Tenths summed in Double land just under the goal (0.3+0.3+0.3+0.1).
    public mutating func advance(active: Bool, dt: TimeInterval, goal: TimeInterval) -> Bool {
        guard active else { return false }
        let before = held
        held += dt
        guard before < goal, held >= goal - 0.000_001 else { return false }
        held = 0
        return true
    }

    /// Whole tenths still needed, rounded up so an unfinished hold never shows 0.0.
    public func tenthsLeft(goal: TimeInterval) -> Int {
        Int(((goal - held) * 10 - 0.000_001).rounded(.up))
    }
}

/// In or out on the practice strip. Positive scroll zoom is `.in`, matching ⌘-scroll up.
public enum ZoomDirection: String, Sendable, Equatable, CaseIterable {
    case `in`, out
}

/// Counts a real zoom in and out from the scale where the zoom step started.
/// Near a clamp, the start scale moves inward so both directions still fit.
public struct ZoomCredit: Equatable, Sendable {
    public var baseline: Double = 1
    public var sent: Set<ZoomDirection> = []
    public static let ratio = 1.8
    public static let minScale = 0.4
    public static let maxScale = 4.0

    public init() {}

    public static func clamped(_ scale: Double) -> Double {
        min(maxScale, max(minScale, scale))
    }

    /// Returns the scale the strip should show at the start of the zoom step.
    public mutating func arm(scale: Double) -> Double {
        var scale = Self.clamped(scale)
        if scale * Self.ratio > Self.maxScale { scale = Self.maxScale / Self.ratio }
        if scale / Self.ratio < Self.minScale { scale = Self.minScale * Self.ratio }
        baseline = scale
        sent.removeAll()
        return scale
    }

    /// The direction just reached, if this scale newly crosses the bar.
    public mutating func credit(scale: Double) -> ZoomDirection? {
        if !sent.contains(.in), scale >= baseline * Self.ratio {
            sent.insert(.in)
            return .in
        }
        if !sent.contains(.out), scale <= baseline / Self.ratio {
            sent.insert(.out)
            return .out
        }
        return nil
    }
}

/// Tutorial copy marks a pressable key with backticks: `Z`, or a chord as `⌘` + `.`.
public enum KeycapMarkup {
    public struct Run: Equatable, Sendable {
        public var text: String
        public var isKey: Bool
    }

    public static func parse(_ markup: String) -> [Run] {
        var runs: [Run] = []
        var text = ""
        var key = ""
        var inKey = false
        for ch in markup {
            if ch == "`" {
                if inKey {
                    if !key.isEmpty { runs.append(Run(text: key, isKey: true)) }
                    key = ""
                    inKey = false
                } else {
                    if !text.isEmpty {
                        runs.append(Run(text: text, isKey: false))
                        text = ""
                    }
                    inKey = true
                }
            } else if inKey {
                key.append(ch)
            } else {
                text.append(ch)
            }
        }
        if inKey {
            text.append("`")
            text += key
        }
        if !text.isEmpty { runs.append(Run(text: text, isKey: false)) }
        return runs
    }

    /// "qw" → "Type `q` `w`". An empty label is the cell itself.
    public static func typeKeys(_ label: String) -> String {
        let keys = label.map { "`\($0)`" }.joined(separator: " ")
        return keys.isEmpty ? "This cell" : "Type \(keys)"
    }
}

import CoreGraphics
import Foundation

public struct GridLevel: Equatable, Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public var typed: String

    public init(origin: CGPoint, size: CGSize, typed: String = "") {
        self.origin = origin
        self.size = size
        self.typed = typed
    }
}

public struct GridCellIndex: Equatable, Sendable {
    public var row: Int
    public var col: Int
    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

public struct GridState: Equatable, Sendable {
    public var rows: Int
    public var cols: Int
    public var chars: String
    public var depth: Int
    public var screenIndex: Int
    public var levels: [GridLevel]
    public var selectedCell: GridCellIndex?

    public init(
        rows: Int,
        cols: Int,
        chars: String,
        depth: Int,
        screenIndex: Int = 0,
        screenOrigin: CGPoint,
        screenSize: CGSize
    ) {
        self.rows = rows
        self.cols = cols
        self.chars = chars
        self.depth = depth
        self.screenIndex = screenIndex
        self.levels = [GridLevel(origin: screenOrigin, size: screenSize)]
        self.selectedCell = nil
    }

    public var currentLevel: GridLevel {
        levels[levels.count - 1]
    }

    public var labelWidth: Int {
        GridLabels.labelWidth(chars: chars, rows: rows, cols: cols)
    }

    public var labels: [String] {
        GridLabels.labels(chars: chars, rows: rows, cols: cols)
    }

    public var isCellSelected: Bool {
        selectedCell != nil && currentLevel.typed.count >= labelWidth
    }

    public var prospectiveCenter: CGPoint? {
        guard let cell = resolvedCell() else { return nil }
        return CoordinateSpace.cellCenter(
            screenOrigin: currentLevel.origin,
            screenSize: currentLevel.size,
            rows: rows,
            cols: cols,
            row: cell.row,
            col: cell.col
        )
    }

    public var selectedFrame: CGRect? {
        guard let cell = selectedCell else { return nil }
        return CoordinateSpace.cellFrame(
            screenOrigin: currentLevel.origin,
            screenSize: currentLevel.size,
            rows: rows,
            cols: cols,
            row: cell.row,
            col: cell.col
        )
    }

    public func resolvedCell() -> GridCellIndex? {
        if let selectedCell { return selectedCell }
        let typed = currentLevel.typed
        guard typed.count == labelWidth else { return nil }
        guard let idx = labels.firstIndex(of: typed) else { return nil }
        return GridCellIndex(row: idx / cols, col: idx % cols)
    }

    public mutating func typeCharacter(_ ch: Character) -> GridTypeResult {
        let c = Character(ch.lowercased())
        if isCellSelected {
            return .ignored
        }
        var level = levels[levels.count - 1]
        let next = level.typed + String(c)
        let matching = labels.filter { $0.hasPrefix(next) }
        if matching.isEmpty {
            return .ignored
        }
        level.typed = next
        levels[levels.count - 1] = level
        if next.count == labelWidth, let idx = labels.firstIndex(of: next) {
            selectedCell = GridCellIndex(row: idx / cols, col: idx % cols)
            return .selected(row: idx / cols, col: idx % cols)
        }
        return .typing
    }

    public mutating func backspace() -> GridBackResult {
        if selectedCell != nil {
            selectedCell = nil
            var level = levels[levels.count - 1]
            if !level.typed.isEmpty {
                level.typed.removeLast()
                levels[levels.count - 1] = level
            }
            return .clearedSelection
        }
        var level = levels[levels.count - 1]
        if !level.typed.isEmpty {
            level.typed.removeLast()
            levels[levels.count - 1] = level
            return .clearedChar
        }
        if levels.count > 1 {
            levels.removeLast()
            selectedCell = nil
            return .poppedLevel
        }
        return .noop
    }

    /// Descend into selected cell for another grid level.
    public mutating func descend() -> Bool {
        guard let cell = selectedCell, levels.count < depth else { return false }
        let frame = CoordinateSpace.cellFrame(
            screenOrigin: currentLevel.origin,
            screenSize: currentLevel.size,
            rows: rows,
            cols: cols,
            row: cell.row,
            col: cell.col
        )
        levels.append(GridLevel(origin: frame.origin, size: frame.size))
        selectedCell = nil
        return true
    }

    public mutating func resetScreen(origin: CGPoint, size: CGSize, index: Int) {
        screenIndex = index
        levels = [GridLevel(origin: origin, size: size)]
        selectedCell = nil
    }
}

public enum GridTypeResult: Equatable, Sendable {
    case typing
    case selected(row: Int, col: Int)
    case ignored
}

public enum GridBackResult: Equatable, Sendable {
    case clearedChar
    case clearedSelection
    case poppedLevel
    case noop
}

public enum GridInputRouter {
    public enum Decision: Equatable, Sendable {
        case typeCoordinate(Character)
        case finalize(GridFinalizeAction)
        case back
        case cancel
        case nextScreen
        case descend(Character)
        case ignore
    }

    /// Route a character/key after parsing against bindings.
    /// Finalizers only apply when a cell is selected.
    public static func decide(
        character: Character?,
        matchesFinalize: GridFinalizeAction?,
        matchesBack: Bool,
        matchesCancel: Bool,
        matchesNextScreen: Bool,
        state: GridState
    ) -> Decision {
        if matchesCancel { return .cancel }
        if matchesBack { return .back }
        if matchesNextScreen { return .nextScreen }

        if state.isCellSelected {
            if let action = matchesFinalize {
                return .finalize(action)
            }
            if let character,
               state.levels.count < state.depth,
               state.chars.lowercased().contains(character)
            {
                return .descend(character)
            }
            return .ignore
        }

        if let character, state.chars.lowercased().contains(character) {
            return .typeCoordinate(character)
        }
        return .ignore
    }
}

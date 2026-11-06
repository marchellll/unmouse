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
    /// Division used by every grid after the first.
    public var subRows: Int
    public var subCols: Int
    private let rootRows: Int
    private let rootCols: Int
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
        subRows: Int? = nil,
        subCols: Int? = nil,
        screenIndex: Int = 0,
        screenOrigin: CGPoint,
        screenSize: CGSize
    ) {
        self.rows = rows
        self.cols = cols
        self.rootRows = rows
        self.rootCols = cols
        self.subRows = max(1, subRows ?? rows)
        self.subCols = max(1, subCols ?? cols)
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
        if levels.count > 1, GridLabels.singleLabels(chars: chars, rows: rows, cols: cols) != nil { return 1 }
        return GridLabels.labelWidth(chars: chars, rows: rows, cols: cols)
    }

    public var labels: [String] {
        if levels.count > 1, let single = GridLabels.singleLabels(chars: chars, rows: rows, cols: cols) {
            return single
        }
        return GridLabels.labels(chars: chars, rows: rows, cols: cols)
    }

    public var isCellSelected: Bool {
        selectedCell != nil && currentLevel.typed.count >= labelWidth
    }

    /// The rectangle the keys picked so far. The first character is the whole block; the last character is one cell.
    public var targetFrame: CGRect? {
        let indices: [Int]
        let typed = currentLevel.typed
        if let cell = selectedCell, typed.count >= labelWidth {
            indices = [cell.row * cols + cell.col]
        } else if !typed.isEmpty {
            indices = labels.enumerated().compactMap { $0.element.hasPrefix(typed) ? $0.offset : nil }
            guard !indices.isEmpty else { return nil }
        } else if levels.count > 1 {
            return CGRect(origin: currentLevel.origin, size: currentLevel.size)
        } else {
            return nil
        }
        var union: CGRect?
        for index in indices {
            let frame = CoordinateSpace.cellFrame(
                screenOrigin: currentLevel.origin,
                screenSize: currentLevel.size,
                rows: rows,
                cols: cols,
                row: index / cols,
                col: index % cols
            )
            union = union.map { $0.union(frame) } ?? frame
        }
        return union
    }

    public var hasClickTarget: Bool { targetFrame != nil }

    public var prospectiveCenter: CGPoint? {
        guard let frame = targetFrame else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Center of the grid currently on screen. After a subgrid opens, this is the cell that was chosen.
    public var levelCenter: CGPoint {
        CGPoint(
            x: currentLevel.origin.x + currentLevel.size.width / 2,
            y: currentLevel.origin.y + currentLevel.size.height / 2
        )
    }

    public mutating func typeCharacter(_ ch: Character) -> GridTypeResult {
        let c = Character(ch.lowercased())
        if isCellSelected {
            return .ignored
        }
        var level = levels[levels.count - 1]
        let next = level.typed + String(c)
        let hits = labels.enumerated().compactMap { index, label in
            label.hasPrefix(next) ? index : nil
        }
        guard !hits.isEmpty else { return .ignored }
        level.typed = next
        levels[levels.count - 1] = level
        if next.count >= labelWidth, hits.count == 1, let idx = hits.first {
            let row = idx / cols
            let col = idx % cols
            selectedCell = GridCellIndex(row: row, col: col)
            if levels.count < depth, descend() {
                return .openedSubgrid
            }
            return .selected(row: row, col: col)
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
            if levels.count == 1 {
                rows = rootRows
                cols = rootCols
            }
            return .poppedLevel
        }
        return .noop
    }

    /// Descend into selected cell for another grid level.
    public mutating func descend() -> Bool {
        guard let cell = selectedCell, levels.count < depth else { return false }
        let index = cell.row * cols + cell.col
        guard labels.indices.contains(index), !labels[index].isEmpty else { return false }
        let frame = CoordinateSpace.cellFrame(
            screenOrigin: currentLevel.origin,
            screenSize: currentLevel.size,
            rows: rows,
            cols: cols,
            row: cell.row,
            col: cell.col
        )
        var parent = levels[levels.count - 1]
        parent.typed = ""
        levels[levels.count - 1] = parent
        levels.append(GridLevel(origin: frame.origin, size: frame.size))
        selectedCell = nil
        rows = subRows
        cols = subCols
        return true
    }

    public mutating func resetScreen(origin: CGPoint, size: CGSize, index: Int) {
        screenIndex = index
        levels = [GridLevel(origin: origin, size: size)]
        rows = rootRows
        cols = rootCols
        selectedCell = nil
    }
}

public enum GridTypeResult: Equatable, Sendable {
    case typing
    case selected(row: Int, col: Int)
    /// The finished label had a deeper grid, and that grid is now the current level.
    case openedSubgrid
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
    /// A click applies once a rectangle is targeted, including after only the first character.
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

        if let action = matchesFinalize, action == .toFree || state.hasClickTarget {
            return .finalize(action)
        }

        if state.isCellSelected {
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

import Foundation

public struct GlobalBindings: Codable, Sendable, Equatable {
    public var gridMode: [String]
    public var freeMode: [String]
    public var hintMode: [String]

    enum CodingKeys: String, CodingKey {
        case gridMode = "grid_mode"
        case freeMode = "free_mode"
        case hintMode = "hint_mode"
    }

    public init(
        gridMode: [String] = ["command_left"],
        freeMode: [String] = ["option_left"],
        hintMode: [String] = ["command+shift+space"]
    ) {
        self.gridMode = gridMode
        self.freeMode = freeMode
        self.hintMode = hintMode
    }
}

public struct GridBindings: Codable, Sendable, Equatable {
    public var back: [String]
    public var leftClick: [String]
    public var rightClick: [String]
    public var middleClick: [String]
    public var moveOnly: [String]
    public var toggleDrag: [String]
    public var toggleRightDrag: [String]
    public var toggleMiddleDrag: [String]
    public var toFree: [String]
    public var cancel: [String]
    public var nextScreen: [String]

    enum CodingKeys: String, CodingKey {
        case back
        case leftClick = "left_click"
        case rightClick = "right_click"
        case middleClick = "middle_click"
        case moveOnly = "move_only"
        case toggleDrag = "toggle_drag"
        case toggleRightDrag = "toggle_right_drag"
        case toggleMiddleDrag = "toggle_middle_drag"
        case toFree = "to_free"
        case cancel
        case nextScreen = "next_screen"
    }

    public init(
        back: [String] = ["delete", "backspace"],
        leftClick: [String] = ["f", "space", "return"],
        rightClick: [String] = ["d"],
        middleClick: [String] = ["s"],
        moveOnly: [String] = [],
        toggleDrag: [String] = ["r"],
        toggleRightDrag: [String] = ["e"],
        toggleMiddleDrag: [String] = ["w"],
        toFree: [String] = ["option_left"],
        cancel: [String] = ["escape"],
        nextScreen: [String] = ["tab"]
    ) {
        self.back = back
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.middleClick = middleClick
        self.moveOnly = moveOnly
        self.toggleDrag = toggleDrag
        self.toggleRightDrag = toggleRightDrag
        self.toggleMiddleDrag = toggleMiddleDrag
        self.toFree = toFree
        self.cancel = cancel
        self.nextScreen = nextScreen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = GridBindings()
        back = try c.decodeIfPresent([String].self, forKey: .back) ?? fresh.back
        leftClick = try c.decodeIfPresent([String].self, forKey: .leftClick) ?? fresh.leftClick
        rightClick = try c.decodeIfPresent([String].self, forKey: .rightClick) ?? fresh.rightClick
        middleClick = try c.decodeIfPresent([String].self, forKey: .middleClick) ?? fresh.middleClick
        moveOnly = try c.decodeIfPresent([String].self, forKey: .moveOnly) ?? fresh.moveOnly
        toggleDrag = try c.decodeIfPresent([String].self, forKey: .toggleDrag) ?? fresh.toggleDrag
        toggleRightDrag = try c.decodeIfPresent([String].self, forKey: .toggleRightDrag) ?? fresh.toggleRightDrag
        toggleMiddleDrag = try c.decodeIfPresent([String].self, forKey: .toggleMiddleDrag) ?? fresh.toggleMiddleDrag
        toFree = try c.decodeIfPresent([String].self, forKey: .toFree) ?? fresh.toFree
        cancel = try c.decodeIfPresent([String].self, forKey: .cancel) ?? fresh.cancel
        nextScreen = try c.decodeIfPresent([String].self, forKey: .nextScreen) ?? fresh.nextScreen
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(back, forKey: .back)
        try c.encode(leftClick, forKey: .leftClick)
        try c.encode(rightClick, forKey: .rightClick)
        try c.encode(middleClick, forKey: .middleClick)
        try c.encode(moveOnly, forKey: .moveOnly)
        try c.encode(toggleDrag, forKey: .toggleDrag)
        try c.encode(toggleRightDrag, forKey: .toggleRightDrag)
        try c.encode(toggleMiddleDrag, forKey: .toggleMiddleDrag)
        try c.encode(toFree, forKey: .toFree)
        try c.encode(cancel, forKey: .cancel)
        try c.encode(nextScreen, forKey: .nextScreen)
    }
}

public struct FreeBindings: Codable, Sendable, Equatable {
    public var moveLeft: [String]
    public var moveDown: [String]
    public var moveUp: [String]
    public var moveRight: [String]
    public var faster: [String]
    public var slower: [String]
    public var scrollUp: [String]
    public var scrollDown: [String]
    public var scrollLeft: [String]
    public var scrollRight: [String]
    public var toggleDrag: [String]
    public var toggleRightDrag: [String]
    public var toggleMiddleDrag: [String]
    public var leftClick: [String]
    public var rightClick: [String]
    public var middleClick: [String]
    public var cancel: [String]

    enum CodingKeys: String, CodingKey {
        case moveLeft = "move_left"
        case moveDown = "move_down"
        case moveUp = "move_up"
        case moveRight = "move_right"
        case faster, slower
        case scrollUp = "scroll_up"
        case scrollDown = "scroll_down"
        case scrollLeft = "scroll_left"
        case scrollRight = "scroll_right"
        case toggleDrag = "toggle_drag"
        case toggleRightDrag = "toggle_right_drag"
        case toggleMiddleDrag = "toggle_middle_drag"
        case leftClick = "left_click"
        case rightClick = "right_click"
        case middleClick = "middle_click"
        case cancel
    }

    public init(
        moveLeft: [String] = ["j", "left"],
        moveDown: [String] = ["k", "down"],
        moveUp: [String] = ["l", "up"],
        moveRight: [String] = [";", "right"],
        faster: [String] = ["z"],
        slower: [String] = ["x"],
        scrollUp: [String] = ["."],
        scrollDown: [String] = [","],
        scrollLeft: [String] = ["m"],
        scrollRight: [String] = ["/"],
        toggleDrag: [String] = ["r"],
        toggleRightDrag: [String] = ["e"],
        toggleMiddleDrag: [String] = ["w"],
        leftClick: [String] = ["f", "space", "return"],
        rightClick: [String] = ["d"],
        middleClick: [String] = ["s"],
        cancel: [String] = ["escape"]
    ) {
        self.moveLeft = moveLeft
        self.moveDown = moveDown
        self.moveUp = moveUp
        self.moveRight = moveRight
        self.faster = faster
        self.slower = slower
        self.scrollUp = scrollUp
        self.scrollDown = scrollDown
        self.scrollLeft = scrollLeft
        self.scrollRight = scrollRight
        self.toggleDrag = toggleDrag
        self.toggleRightDrag = toggleRightDrag
        self.toggleMiddleDrag = toggleMiddleDrag
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.middleClick = middleClick
        self.cancel = cancel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = FreeBindings()
        moveLeft = try c.decodeIfPresent([String].self, forKey: .moveLeft) ?? fresh.moveLeft
        moveDown = try c.decodeIfPresent([String].self, forKey: .moveDown) ?? fresh.moveDown
        moveUp = try c.decodeIfPresent([String].self, forKey: .moveUp) ?? fresh.moveUp
        moveRight = try c.decodeIfPresent([String].self, forKey: .moveRight) ?? fresh.moveRight
        faster = try c.decodeIfPresent([String].self, forKey: .faster) ?? fresh.faster
        slower = try c.decodeIfPresent([String].self, forKey: .slower) ?? fresh.slower
        scrollUp = try c.decodeIfPresent([String].self, forKey: .scrollUp) ?? fresh.scrollUp
        scrollDown = try c.decodeIfPresent([String].self, forKey: .scrollDown) ?? fresh.scrollDown
        scrollLeft = try c.decodeIfPresent([String].self, forKey: .scrollLeft) ?? fresh.scrollLeft
        scrollRight = try c.decodeIfPresent([String].self, forKey: .scrollRight) ?? fresh.scrollRight
        toggleDrag = try c.decodeIfPresent([String].self, forKey: .toggleDrag) ?? fresh.toggleDrag
        toggleRightDrag = try c.decodeIfPresent([String].self, forKey: .toggleRightDrag) ?? fresh.toggleRightDrag
        toggleMiddleDrag = try c.decodeIfPresent([String].self, forKey: .toggleMiddleDrag) ?? fresh.toggleMiddleDrag
        leftClick = try c.decodeIfPresent([String].self, forKey: .leftClick) ?? fresh.leftClick
        rightClick = try c.decodeIfPresent([String].self, forKey: .rightClick) ?? fresh.rightClick
        middleClick = try c.decodeIfPresent([String].self, forKey: .middleClick) ?? fresh.middleClick
        cancel = try c.decodeIfPresent([String].self, forKey: .cancel) ?? fresh.cancel
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(moveLeft, forKey: .moveLeft)
        try c.encode(moveDown, forKey: .moveDown)
        try c.encode(moveUp, forKey: .moveUp)
        try c.encode(moveRight, forKey: .moveRight)
        try c.encode(faster, forKey: .faster)
        try c.encode(slower, forKey: .slower)
        try c.encode(scrollUp, forKey: .scrollUp)
        try c.encode(scrollDown, forKey: .scrollDown)
        try c.encode(scrollLeft, forKey: .scrollLeft)
        try c.encode(scrollRight, forKey: .scrollRight)
        try c.encode(toggleDrag, forKey: .toggleDrag)
        try c.encode(toggleRightDrag, forKey: .toggleRightDrag)
        try c.encode(toggleMiddleDrag, forKey: .toggleMiddleDrag)
        try c.encode(leftClick, forKey: .leftClick)
        try c.encode(rightClick, forKey: .rightClick)
        try c.encode(middleClick, forKey: .middleClick)
        try c.encode(cancel, forKey: .cancel)
    }

    public func move(_ direction: MoveDirection) -> [String] {
        switch direction {
        case .left: moveLeft
        case .down: moveDown
        case .up: moveUp
        case .right: moveRight
        }
    }

    public func scroll(_ direction: MoveDirection) -> [String] {
        switch direction {
        case .left: scrollLeft
        case .down: scrollDown
        case .up: scrollUp
        case .right: scrollRight
        }
    }
}

public struct HintBindings: Codable, Sendable, Equatable {
    public var leftClick: [String]
    public var rightClick: [String]
    public var toFree: [String]
    public var cancel: [String]
    public var back: [String]

    enum CodingKeys: String, CodingKey {
        case leftClick = "left_click"
        case rightClick = "right_click"
        case toFree = "to_free"
        case cancel, back
        // Old key kept for decode so a stale config.toml still loads.
        case moveNoAction = "move_no_action"
    }

    public init(
        leftClick: [String] = ["space", "return"],
        rightClick: [String] = ["control+space", "control+return"],
        toFree: [String] = ["option_left"],
        cancel: [String] = ["escape"],
        back: [String] = ["delete", "backspace"]
    ) {
        self.leftClick = leftClick
        self.rightClick = rightClick
        self.toFree = toFree
        self.cancel = cancel
        self.back = back
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leftClick = try c.decodeIfPresent([String].self, forKey: .leftClick) ?? ["space", "return"]
        rightClick = try c.decodeIfPresent([String].self, forKey: .rightClick) ?? ["control+space", "control+return"]
        toFree = try c.decodeIfPresent([String].self, forKey: .toFree) ?? ["option_left"]
        cancel = try c.decodeIfPresent([String].self, forKey: .cancel) ?? ["escape"]
        back = try c.decodeIfPresent([String].self, forKey: .back) ?? ["delete", "backspace"]
        // move_no_action intentionally ignored.
        _ = try c.decodeIfPresent([String].self, forKey: .moveNoAction)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(leftClick, forKey: .leftClick)
        try c.encode(rightClick, forKey: .rightClick)
        try c.encode(toFree, forKey: .toFree)
        try c.encode(cancel, forKey: .cancel)
        try c.encode(back, forKey: .back)
    }
}

public struct BindingsConfig: Codable, Sendable, Equatable {
    public var global: GlobalBindings
    public var grid: GridBindings
    public var free: FreeBindings
    public var hint: HintBindings

    public init(
        global: GlobalBindings = .init(),
        grid: GridBindings = .init(),
        free: FreeBindings = .init(),
        hint: HintBindings = .init()
    ) {
        self.global = global
        self.grid = grid
        self.free = free
        self.hint = hint
    }
}

import AppKit
import CoreGraphics
import UnmouseCore

struct MotionResult: Sendable, Equatable {
    var moved = false
    var scrolled = false
    var faster = false
    var slower = false
}

/// Per-frame free-mode engine. Not @Observable — SwiftUI must not see these writes.
@MainActor
final class FreeMotion {
    let heldKeys = HeldKeyStore()
    let deduper = KeyDeduper()
    var speedLatch = SpeedModifierLatch()
    var chordKeys: Set<String> = []
    private var moveHeld: TimeInterval = 0
    private var scrollHeld: TimeInterval = 0
    private var scrollFracX: Double = 0
    private var scrollFracY: Double = 0
    private var speedDemoHeld: TimeInterval = 0

    func resetMotionClocks() {
        moveHeld = 0
        scrollHeld = 0
        scrollFracX = 0
        scrollFracY = 0
        speedDemoHeld = 0
    }

    func resetAll() {
        heldKeys.clearHeld()
        speedLatch.reset()
        chordKeys.removeAll()
        resetMotionClocks()
    }

    /// A move/scroll key that is already up. Held state can survive a swallowed key-up.
    func releaseStaleMoveHolds(bindings: BindingTable.Free) {
        for direction in MoveDirection.allCases {
            for raw in [bindings.moveRaw[direction], bindings.scrollRaw[direction]].compactMap({ $0 }) {
                for shortcut in (try? ShortcutParser.parseAll(raw)) ?? [] {
                    let token = KeyCodes.token(for: shortcut.key)
                    guard heldKeys.isHeld(token), !hidDown(shortcut.key) else { continue }
                    heldKeys.setHeld(token, down: false)
                }
            }
        }
    }

    func arrowMoveHeld(bindings: BindingTable.Free) -> Bool {
        for direction in MoveDirection.allCases {
            for shortcut in (try? ShortcutParser.parseAll(bindings.moveRaw[direction] ?? [])) ?? [] {
                switch shortcut.key {
                case .left, .right, .up, .down:
                    if heldKeys.isHeld(KeyCodes.token(for: shortcut.key)) { return true }
                default:
                    break
                }
            }
        }
        return false
    }

    func bindingHeld(_ raw: [String], chordDown: Bool) -> Bool {
        for shortcut in (try? ShortcutParser.parseAll(raw)) ?? [] {
            if heldKeys.isHeld(KeyCodes.token(for: shortcut.key)) { return true }
            if chordDown { continue }
            if hidDown(shortcut.key) { return true }
        }
        return false
    }

    func bindingHeld(_ matcherRaw: [String], from tableRaw: [String], chordDown: Bool) -> Bool {
        bindingHeld(tableRaw.isEmpty ? matcherRaw : tableRaw, chordDown: chordDown)
    }

    func hidDown(_ kind: KeyKind) -> Bool {
        guard let code = KeyCodes.keyCode(for: kind) else { return false }
        return CGEventSource.keyState(.hidSystemState, key: code)
    }

    func hidDown(_ raw: [String]) -> Bool {
        for shortcut in (try? ShortcutParser.parseAll(raw)) ?? [] {
            if hidDown(shortcut.key) { return true }
        }
        return false
    }

    func liveChordModifierDown() -> Bool {
        chordModifierDown([])
    }

    func chordModifierDown(_ flags: CGEventFlags) -> Bool {
        let live = CGEventSource.flagsState(.hidSystemState)
        let merged = CGEventFlags(rawValue: flags.rawValue | live.rawValue)
        return merged.contains(.maskCommand) || merged.contains(.maskAlternate) || merged.contains(.maskControl)
    }

    /// Tick free-mode motion. Does not touch tutorial or overlays.
    func tick(dt: TimeInterval, free: FreeConfig, bindings: BindingTable.Free, dragging: Bool) -> MotionResult {
        var result = MotionResult()
        if speedLatch.releasePending {
            speedLatch.sync(
                arrowHeld: arrowMoveHeld(bindings: bindings),
                fasterHID: hidDown(bindings.fasterRaw),
                slowerHID: hidDown(bindings.slowerRaw),
                nowNanos: DispatchTime.now().uptimeNanoseconds
            )
        }
        var speedMult = 1.0
        let chordDown = liveChordModifierDown()
        let fasterOn = speedLatch.faster || (!chordDown && hidDown(bindings.fasterRaw))
            || bindingHeld(bindings.fasterRaw, chordDown: chordDown)
        let slowerOn = speedLatch.slower || (!chordDown && hidDown(bindings.slowerRaw))
            || bindingHeld(bindings.slowerRaw, chordDown: chordDown)
        result.faster = fasterOn
        result.slower = slowerOn
        if fasterOn { speedMult *= free.fastMultiplier }
        if slowerOn { speedMult *= free.slowMultiplier }

        let left = bindingHeld(bindings.moveRaw[.left] ?? [], chordDown: chordDown)
        let right = bindingHeld(bindings.moveRaw[.right] ?? [], chordDown: chordDown)
        let up = bindingHeld(bindings.moveRaw[.up] ?? [], chordDown: chordDown)
        let down = bindingHeld(bindings.moveRaw[.down] ?? [], chordDown: chordDown)
        if left || right || up || down {
            moveHeld += min(dt, 0.05)
        } else {
            moveHeld = 0
        }
        let pace = AccelCurve.fraction(knots: free.accelKnots, at: moveHeld)
        let step = CGFloat(free.speed * pace * speedMult * dt)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if left { dx -= step }
        if right { dx += step }
        if up { dy -= step }
        if down { dy += step }
        if dx != 0 || dy != 0 {
            PointerController.moveBy(dx: dx, dy: dy, dragging: dragging)
            result.moved = true
        }

        let scrollUp = bindingHeld(bindings.scrollRaw[.up] ?? [], chordDown: chordDown)
        let scrollDown = bindingHeld(bindings.scrollRaw[.down] ?? [], chordDown: chordDown)
        let scrollLeft = bindingHeld(bindings.scrollRaw[.left] ?? [], chordDown: chordDown)
        let scrollRight = bindingHeld(bindings.scrollRaw[.right] ?? [], chordDown: chordDown)
        if scrollUp || scrollDown || scrollLeft || scrollRight {
            scrollHeld += min(dt, 0.05)
        } else {
            scrollHeld = 0
        }
        let scrollPace = AccelCurve.fraction(knots: free.accelKnots, at: scrollHeld)
        let scrollRate = free.scrollSpeed * scrollPace * speedMult * 16
        if scrollUp { scrollFracY += scrollRate * dt }
        if scrollDown { scrollFracY -= scrollRate * dt }
        if scrollLeft { scrollFracX -= scrollRate * dt }
        if scrollRight { scrollFracX += scrollRate * dt }
        let sdx = scrollFracX.rounded(.towardZero)
        let sdy = scrollFracY.rounded(.towardZero)
        if sdx != 0 || sdy != 0 {
            scrollFracX -= sdx
            scrollFracY -= sdy
            let xSign = free.scrollReverseX ? -1.0 : 1.0
            let ySign = free.scrollReverseY ? -1.0 : 1.0
            PointerController.scroll(dx: sdx * xSign, dy: sdy * ySign)
            result.scrolled = true
        }
        return result
    }

    /// Accumulates Z/X tutorial credit. Returns the event to fire once the second is met.
    func creditSpeedDemo(
        required: TutorialEvent?,
        faster: Bool,
        slower: Bool,
        moved: Bool,
        dt: TimeInterval
    ) -> TutorialEvent? {
        let active: Bool
        switch required {
        case .heldFaster: active = faster && moved
        case .heldSlower: active = slower && moved
        default:
            speedDemoHeld = 0
            return nil
        }
        guard active else {
            speedDemoHeld = 0
            return nil
        }
        let before = speedDemoHeld
        speedDemoHeld += dt
        guard before < TutorialProgress.speedDemoSeconds, speedDemoHeld >= TutorialProgress.speedDemoSeconds else {
            return nil
        }
        speedDemoHeld = 0
        return required
    }
}

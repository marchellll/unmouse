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
    var chordPass = ChordPassthrough()
    private var moveHeld: TimeInterval = 0
    private var scrollHeld: TimeInterval = 0
    private var scrollFracX: Double = 0
    private var scrollFracY: Double = 0
    private var speedClock = SpeedDemoClock()
    private var speedDemoFor: TutorialEvent?

    func resetMotionClocks() {
        moveHeld = 0
        scrollHeld = 0
        scrollFracX = 0
        scrollFracY = 0
        // ponytail: speed clock stays. tap reset calls resetAll often; wiping it
        // there made the Z/X step never reach 1s while HID still moved.
    }

    func resetSpeedDemo() {
        speedClock = .init()
        speedDemoFor = nil
    }

    /// Tenths left on the Z/X hold. Nil until the hold has started.
    var speedTenthsLeft: Int? {
        speedClock.held > 0 ? speedClock.tenthsLeft(goal: TutorialProgress.speedDemoSeconds) : nil
    }

    func resetAll() {
        heldKeys.clearHeld()
        speedLatch.reset()
        chordPass.reset()
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

    /// Move and scroll keys. Arrow and scroll reports drop Z/X; letter moves can too.
    func speedKeyHeld(bindings: BindingTable.Free) -> Bool {
        for direction in MoveDirection.allCases {
            if bindingHeld(bindings.moveRaw[direction] ?? [], chordDown: false) { return true }
            if bindingHeld(bindings.scrollRaw[direction] ?? [], chordDown: false) { return true }
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

    func commandDown() -> Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskCommand)
    }

    func chordModifierDown(_ flags: CGEventFlags) -> Bool {
        let live = CGEventSource.flagsState(.hidSystemState)
        let merged = CGEventFlags(rawValue: flags.rawValue | live.rawValue)
        return merged.contains(.maskCommand) || merged.contains(.maskAlternate) || merged.contains(.maskControl)
    }

    /// Tick free-mode motion. Does not touch tutorial or overlays.
    func tick(
        dt: TimeInterval, free: FreeConfig, bindings: BindingTable.Free,
        drag: MouseButton? = nil, dragFlags: CGEventFlags = []
    ) -> MotionResult {
        var result = MotionResult()
        if speedLatch.releasePending {
            speedLatch.sync(
                arrowHeld: speedKeyHeld(bindings: bindings),
                fasterHID: hidDown(bindings.fasterRaw),
                slowerHID: hidDown(bindings.slowerRaw),
                nowNanos: DispatchTime.now().uptimeNanoseconds
            )
        }
        var speedMult = 1.0
        let chordDown = liveChordModifierDown()
        // Physical Z/X still counts while ⌘ is held.
        let fasterOn = speedLatch.faster || hidDown(bindings.fasterRaw)
            || bindingHeld(bindings.fasterRaw, chordDown: chordDown)
        let slowerOn = speedLatch.slower || hidDown(bindings.slowerRaw)
            || bindingHeld(bindings.slowerRaw, chordDown: chordDown)
        result.faster = fasterOn
        result.slower = slowerOn
        if fasterOn { speedMult *= free.fastMultiplier }
        if slowerOn { speedMult *= free.slowMultiplier }

        let left = bindingHeld(bindings.moveRaw[.left] ?? [], chordDown: chordDown)
        let right = bindingHeld(bindings.moveRaw[.right] ?? [], chordDown: chordDown)
        let up = bindingHeld(bindings.moveRaw[.up] ?? [], chordDown: chordDown)
        let down = bindingHeld(bindings.moveRaw[.down] ?? [], chordDown: chordDown)
        // Direction held counts as moved for the Z/X tutorial clock — pixel step can
        // be 0 for a frame (accel at 0, subpixel) while the user is clearly steering.
        let steering = left || right || up || down
        if steering {
            moveHeld += min(dt, 0.05)
            result.moved = true
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
            PointerController.moveBy(dx: dx, dy: dy, drag: drag, flags: dragFlags)
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
            let x = sdx * xSign
            let y = sdy * ySign
            // Vertical ⌘-scroll is how apps zoom. Horizontal stays plain.
            if y != 0, commandDown() {
                PointerController.scroll(dx: 0, dy: y, command: true)
                if x != 0 { PointerController.scroll(dx: x, dy: 0) }
            } else {
                PointerController.scroll(dx: x, dy: y)
            }
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
        if required != speedDemoFor {
            speedDemoFor = required
            speedClock = .init()
        }
        let active: Bool
        switch required {
        case .heldFaster: active = faster && moved
        case .heldSlower: active = slower && moved
        default:
            speedClock = .init()
            return nil
        }
        guard speedClock.advance(active: active, dt: dt, goal: TutorialProgress.speedDemoSeconds) else {
            return nil
        }
        speedClock = .init()
        return required
    }
}

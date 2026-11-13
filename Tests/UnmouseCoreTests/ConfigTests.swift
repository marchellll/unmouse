import CoreGraphics
import Foundation
import Testing
@testable import UnmouseCore

@Suite("Config")
struct ConfigTests {
    @Test func labelOutlineRoundTrips() throws {
        var config = AppConfig.default
        config.grid.labelOutline = "#112233"
        config.grid.labelOutlineWidth = 3.5
        let decoded = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(decoded.grid.labelOutline == "#112233")
        #expect(decoded.grid.labelOutlineWidth == 3.5)
    }

    @Test func labelOutlineDefaultsWhenMissing() throws {
        let text = try ConfigIO.encode(AppConfig.default)
            .replacingOccurrences(of: "label_outline_width", with: "ignored_outline_width")
            .replacingOccurrences(of: "label_outline", with: "ignored_outline")
        let decoded = try ConfigIO.decode(from: text)
        #expect(decoded.grid.labelOutline == "#000000")
        #expect(decoded.grid.labelOutlineWidth == 2)
    }

    @Test func defaultConfigValidates() throws {
        let url = exampleConfigsDirectory().appending(path: "default.config.toml")
        let text = try String(contentsOf: url, encoding: .utf8)
        let config = try ConfigIO.decode(from: text)
        let errors = ConfigValidator.validate(config)
        #expect(errors.isEmpty)
    }

    @Test func allExampleConfigsValidate() throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: exampleConfigsDirectory(),
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "toml" }
        #expect(!urls.isEmpty)
        for url in urls {
            let text = try String(contentsOf: url, encoding: .utf8)
            let config = try ConfigIO.decode(from: text)
            let errors = ConfigValidator.validate(config)
            let other = errors.filter(\.blocksApply)
            #expect(other.isEmpty, "\(url.lastPathComponent): \(other)")
            let overlaps = errors.filter { if case .gridShortcutOverlapsChars = $0 { true } else { false } }
            #expect(overlaps.isEmpty, "\(url.lastPathComponent): \(overlaps)")
        }
    }

    @Test func depthOutOfRange() {
        var c = AppConfig.default
        c.grid.depth = 4
        #expect(ConfigValidator.validate(c).contains(.depthOutOfRange(4)))
    }

    @Test func duplicateChars() {
        var c = AppConfig.default
        c.grid.chars = "aabb"
        #expect(ConfigValidator.validate(c).contains(.duplicateChars))
    }

    @Test func cellsExceedCharset() {
        var c = AppConfig.default
        c.grid.rows = 10
        c.grid.cols = 10
        c.grid.chars = "ab"
        let errors = ConfigValidator.validate(c)
        #expect(errors.contains { if case .cellsExceedCharset = $0 { true } else { false } })
    }

    @Test func gridShortcutOverlap() {
        var c = AppConfig.default
        c.grid.chars = "qwertyuiopasdfghjkl;"
        let flagged = ConfigValidator.validate(c)
        #expect(flagged.contains(.gridShortcutOverlapsChars("f")))
        #expect(flagged.contains(.gridShortcutOverlapsChars("d")))
        #expect(flagged.contains(.gridShortcutOverlapsChars("s")))
        #expect(flagged.contains(.gridShortcutOverlapsChars("r")))
        #expect(flagged.contains(.gridShortcutOverlapsChars("e")))
        #expect(flagged.contains(.gridShortcutOverlapsChars("w")))
        c.bindings.grid.leftClick = ["1"]
        c.bindings.grid.rightClick = ["2"]
        c.bindings.grid.middleClick = ["3"]
        c.bindings.grid.toggleDrag = ["4"]
        c.bindings.grid.toggleRightDrag = ["5"]
        c.bindings.grid.toggleMiddleDrag = ["6"]
        c.bindings.grid.moveOnly = []
        let clear = ConfigValidator.validate(c)
        #expect(!clear.contains { if case .gridShortcutOverlapsChars = $0 { true } else { false } })
    }

    @Test func hintBareLetterClickWarns() {
        var c = AppConfig.default
        c.bindings.hint.rightClick = ["a"]
        let errors = ConfigValidator.validate(c)
        #expect(errors.contains(.hintClickStealsTyping("a")))
        #expect(errors.contains { !$0.blocksApply && $0 == .hintClickStealsTyping("a") })
    }

    @Test func legacyHintCharsIgnored() throws {
        var base = try ConfigIO.encode(AppConfig.default)
        if let range = base.range(of: "[hint]") {
            base.insert(contentsOf: "\nchars = \"qwfgjluy;r\"", at: range.upperBound)
        } else {
            base += "\n[hint]\nchars = \"qwfgjluy;r\"\n"
        }
        let decoded = try ConfigIO.decode(from: base)
        #expect(decoded.hint.scanSettleMs == 200)
        let roundTrip = try ConfigIO.encode(decoded)
        #expect(!roundTrip.contains("qwfgjluy"))
        #expect(roundTrip.contains("scan_settle_ms"))
    }

    @Test func hintSettleAndHighlightRoundTrip() throws {
        var config = AppConfig.default
        config.hint.scanSettleMs = 400
        config.colors.hintHighlight = "#FF00AA"
        let decoded = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(decoded.hint.scanSettleMs == 400)
        #expect(decoded.colors.hintHighlight == "#FF00AA")
    }

    @Test func hintSettleDefaultsWhenMissing() throws {
        let text = try ConfigIO.encode(AppConfig.default)
            .replacingOccurrences(of: "scan_settle_ms", with: "ignored_settle")
            .replacingOccurrences(of: "hint_highlight", with: "ignored_highlight")
        let decoded = try ConfigIO.decode(from: text)
        #expect(decoded.hint.scanSettleMs == 200)
        #expect(decoded.colors.hintHighlight == "#34C759")
    }

    @Test func hintSettleClamps() throws {
        var config = AppConfig.default
        config.hint.scanSettleMs = 9_000
        let decoded = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(decoded.hint.scanSettleMs == 2_000)
        #expect(HintConfig(scanSettleMs: -5).scanSettleMs == 0)
    }

    @Test func hintRefreshRoundTripAndBudget() throws {
        var config = AppConfig.default
        config.hint.refreshMs = [400, 900, 1_800]
        let text = try ConfigIO.encode(config)
        #expect(text.contains("refresh_ms"))
        let decoded = try ConfigIO.decode(from: text)
        #expect(decoded.hint.refreshMs == [400, 900, 1_800])
        #expect(decoded.hint.scanBudgetMs == 1_800)
    }

    @Test func hintRefreshDefaultsAndOrders() throws {
        var config = AppConfig.default
        config.hint.refreshMs = [15_000, -20, 1_500]
        let decoded = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(decoded.hint.refreshMs == [0, 1_500, 10_000])
        #expect(decoded.hint.scanBudgetMs == 10_000)
        let text = try ConfigIO.encode(AppConfig.default)
            .replacingOccurrences(of: "refresh_ms", with: "ignored_refresh")
        let missing = try ConfigIO.decode(from: text)
        #expect(missing.hint.refreshMs == HintConfig.defaultRefreshMs)
        #expect(missing.hint.scanBudgetMs == 1_500)
        let base = HintConfig()
        #expect(base.settingRefresh(index: 2, to: 800) == [500, 800, 800])
        #expect(base.settingRefresh(index: 0, to: 1_200) == [1_200, 1_200, 1_500])
        #expect(base.settingRefresh(index: 1, to: 700) == [500, 700, 1_500])
    }

    @Test func scrollReverseRoundTrips() throws {
        var config = AppConfig.default
        config.free.scrollReverseX = true
        config.free.scrollReverseY = true
        let decoded = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(decoded.free.scrollReverseX)
        #expect(decoded.free.scrollReverseY)
    }

    @Test func centerOnFocusDefaultsOn() throws {
        let text = try ConfigIO.encode(AppConfig.default)
            .replacingOccurrences(of: "center_on_focus", with: "ignored_center")
        let decoded = try ConfigIO.decode(from: text)
        #expect(decoded.input.centerOnFocus)

        var config = AppConfig.default
        config.input.centerOnFocus = false
        let roundTrip = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(!roundTrip.input.centerOnFocus)
    }

    @Test func exitOnActionDefaultsOff() throws {
        let text = try ConfigIO.encode(AppConfig.default)
            .replacingOccurrences(of: "exit_on_action", with: "ignored_exit")
        let decoded = try ConfigIO.decode(from: text)
        #expect(decoded.free.exitOnAction == false)

        var config = AppConfig.default
        config.free.exitOnAction = true
        let roundTrip = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(roundTrip.free.exitOnAction)
    }

    @Test func scrollReverseDefaults() throws {
        let text = try ConfigIO.encode(AppConfig.default)
            .replacingOccurrences(of: "scroll_reverse_x", with: "ignored_reverse_x")
            .replacingOccurrences(of: "scroll_reverse_y", with: "ignored_reverse_y")
        let decoded = try ConfigIO.decode(from: text)
        #expect(decoded.free.scrollReverseX == true)
        #expect(decoded.free.scrollReverseY == false)
    }

    @Test func shortcutParsing() throws {
        let alone = try ShortcutParser.parse("command_left")
        #expect(alone.isBareModifier)
        let chord = try ShortcutParser.parse("command+shift+space")
        #expect(chord.modifiers.contains(.command))
        #expect(chord.modifiers.contains(.shift))
        #expect(chord.key == .space)

        var noKeyError: ShortcutParseError?
        do { _ = try ShortcutParser.parse("command+shift") } catch let e as ShortcutParseError { noKeyError = e }
        #expect(noKeyError == .comboWithoutKey("command+shift"))

        var multiError: ShortcutParseError?
        do { _ = try ShortcutParser.parse("h+j") } catch let e as ShortcutParseError { multiError = e }
        #expect(multiError == .comboWithMultipleKeys("h+j"))
    }

    @Test func clickModifiersKeepTheFourAndDropTheRest() {
        let flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        #expect(ClickModifiers.carried(flags) == [.maskCommand, .maskAlternate, .maskControl, .maskShift])
        #expect(ClickModifiers.stripped(flags) == .maskSecondaryFn)
    }

    /// Presets live once, at the repo root. This file is Tests/UnmouseCoreTests/ConfigTests.swift.
    private func exampleConfigsDirectory() -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "configs-example")
    }
}

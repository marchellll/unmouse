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
        let url = Bundle.module.url(
            forResource: "default.config",
            withExtension: "toml",
            subdirectory: "configs-example"
        )
        let text = try String(contentsOf: try #require(url), encoding: .utf8)
        let config = try ConfigIO.decode(from: text)
        let errors = ConfigValidator.validate(config)
        #expect(errors == [
            .gridShortcutOverlapsChars("a"),
            .gridShortcutOverlapsChars("s"),
            .gridShortcutOverlapsChars("d"),
        ])
    }

    @Test func allExampleConfigsValidate() throws {
        let urls = try #require(
            Bundle.module.urls(forResourcesWithExtension: "toml", subdirectory: "configs-example")
        )
        #expect(!urls.isEmpty)
        for url in urls {
            let text = try String(contentsOf: url, encoding: .utf8)
            let config = try ConfigIO.decode(from: text)
            let errors = ConfigValidator.validate(config)
            let other = errors.filter(\.blocksApply)
            #expect(other.isEmpty, "\(url.lastPathComponent): \(other)")
            #expect(errors.contains { if case .gridShortcutOverlapsChars = $0 { true } else { false } })
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
        let flagged = ConfigValidator.validate(c)
        #expect(flagged.contains(.gridShortcutOverlapsChars("a")))
        #expect(flagged.contains(.gridShortcutOverlapsChars("s")))
        #expect(flagged.contains(.gridShortcutOverlapsChars("d")))
        c.bindings.grid.rightClick = ["b"]
        c.bindings.grid.middleClick = ["n"]
        c.bindings.grid.moveOnly = ["v"]
        let clear = ConfigValidator.validate(c)
        #expect(!clear.contains { if case .gridShortcutOverlapsChars = $0 { true } else { false } })
    }

    @Test func hintShortcutOverlap() {
        var c = AppConfig.default
        c.hint.chars = "asd"
        c.bindings.hint.moveNoAction = ["a"]
        #expect(ConfigValidator.validate(c).contains(.hintShortcutOverlapsChars("a")))
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
}

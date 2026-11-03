import Foundation
import Testing
@testable import UnmouseCore

@Suite("Config")
struct ConfigTests {
    @Test func defaultConfigValidates() throws {
        let url = Bundle.module.url(
            forResource: "default.config",
            withExtension: "toml",
            subdirectory: "configs-example"
        )
        let text = try String(contentsOf: try #require(url), encoding: .utf8)
        let config = try ConfigIO.decode(from: text)
        let errors = ConfigValidator.validate(config)
        #expect(errors.isEmpty)
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
            #expect(errors.isEmpty, "\(url.lastPathComponent): \(errors)")
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

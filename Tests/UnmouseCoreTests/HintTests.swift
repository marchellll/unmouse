import CoreGraphics
import Testing
@testable import UnmouseCore

@Suite("Hint")
struct HintTests {
    @Test func assignUniqueCodes() {
        let targets = (0..<5).map {
            HintTarget(id: "\($0)", title: "Alpha", frame: CGRect(x: $0 * 10, y: 0, width: 40, height: 20))
        }
        let coded = HintCoder.assignCodes(targets: targets, chars: "asdf", priorityWords: [])
        let codes = coded.map(\.code)
        #expect(Set(codes).count == codes.count)
        #expect(!codes.contains(""))
    }

    @Test func mnemonicOKCancelDNSSearchPull() {
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "ok", title: "OK", frame: .zero, role: "AXButton", isDefault: true),
                HintTarget(id: "cancel", title: "Cancel", frame: .zero, role: "AXButton"),
                HintTarget(id: "dns", title: "DNS", frame: .zero, role: "AXMenuBarItem"),
                HintTarget(id: "sm", title: "search menu", frame: .zero, role: "AXLink"),
                HintTarget(id: "pu", title: "Pull Request", frame: .zero, role: "AXLink"),
                HintTarget(id: "del", title: "Delete", frame: .zero, role: "AXButton"),
            ],
            chars: "abcdefghijklmnopqrstuvwxyz",
            priorityWords: ["ok"]
        )
        let byID = Dictionary(uniqueKeysWithValues: coded.map { ($0.id, $0.code) })
        #expect(byID["ok"] == "o")
        #expect(byID["cancel"] == "ca" || byID["cancel"]?.hasPrefix("c") == true)
        // Window controls claim singles; menu bar DNS takes a longer code.
        #expect(byID["del"] == "d")
        #expect(byID["sm"] == "s")
        #expect(byID["pu"] == "p")
        #expect((byID["dns"]?.count ?? 0) >= 2)
        #expect(byID["dns"] != "d")
    }

    @Test func windowBeatsMenuBarForSingleChar() {
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "file", title: "File", frame: .zero, role: "AXMenuBarItem"),
                HintTarget(id: "find", title: "Find", frame: CGRect(x: 0, y: 100, width: 40, height: 20), role: "AXButton"),
            ],
            chars: "abcdefghijklmnopqrstuvwxyz",
            priorityWords: []
        )
        let byID = Dictionary(uniqueKeysWithValues: coded.map { ($0.id, $0.code) })
        #expect(byID["find"] == "f")
        #expect(byID["file"] != "f")
        #expect((byID["file"]?.count ?? 0) >= 2)
    }

    @Test func appleMenuDoesNotStealLetterA() {
        // No window control starts with `a`, so leftover `a` used to land on Apple.
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "apple", title: "Apple", frame: .zero, role: "AXMenuBarItem"),
                HintTarget(id: "add", title: "Add", frame: CGRect(x: 0, y: 80, width: 40, height: 20), role: "AXButton"),
            ],
            chars: "abcdefghijklmnopqrstuvwxyz",
            priorityWords: []
        )
        let byID = Dictionary(uniqueKeysWithValues: coded.map { ($0.id, $0.code) })
        #expect(byID["add"] == "a")
        #expect(byID["apple"] != "a")
        #expect((byID["apple"]?.count ?? 0) >= 2)
    }

    @Test func prefersTwoCharOverThreeCharMnemonic() {
        // "Settings" used to take "set" when "se" was free — digraphs first.
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "settings", title: "Settings", frame: .zero, role: "AXButton"),
            ],
            chars: "setxyz",
            priorityWords: []
        )
        #expect((coded.first?.code.count ?? 99) <= 2)
    }

    @Test func threeCharOnlyAfterDigraphsExhausted() {
        // 2-letter alphabet → 2 + 4 digraphs = 6 codes before triples.
        let targets = (0..<8).map {
            HintTarget(id: "\($0)", title: "Item\($0)", frame: .zero, role: "AXButton")
        }
        let coded = HintCoder.assignCodes(targets: targets, chars: "ab", priorityWords: [])
        let lengths = coded.map(\.code.count)
        #expect(lengths.filter { $0 <= 2 }.count == 6)
        #expect(lengths.contains(where: { $0 == 3 }))
        #expect(!lengths.contains(where: { $0 > 3 }))
    }

    @Test func trafficLightsAndMenuBarSkipSingles() {
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "close", title: "Close", frame: .zero, role: "AXButton", subrole: "AXCloseButton"),
                HintTarget(id: "min", title: "Minimize", frame: .zero, role: "AXButton"),
                HintTarget(id: "zoom", title: "Zoom", frame: .zero, role: "AXButton", subrole: "AXZoomButton"),
                HintTarget(id: "file", title: "File", frame: .zero, role: "AXMenuBarItem"),
                HintTarget(id: "chev", title: "Show", frame: .zero, role: "AXDisclosureTriangle"),
                HintTarget(id: "copy", title: "Copy", frame: CGRect(x: 0, y: 80, width: 40, height: 20), role: "AXButton"),
            ],
            chars: "abcdefghijklmnopqrstuvwxyz",
            priorityWords: []
        )
        let byID = Dictionary(uniqueKeysWithValues: coded.map { ($0.id, $0.code) })
        #expect(byID["copy"] == "c")
        for id in ["close", "min", "zoom", "file", "chev"] {
            #expect((byID[id]?.count ?? 0) >= 2, "\(id) should not take a single")
            #expect(byID[id] != "c")
        }
    }

    @Test func typingADoesNotSelectAppleWhenCodeIsL() {
        // Real bug: bubble said `l`, but fuzzy title "Apple" still won on `a`.
        var state = HintState(targets: [
            HintTarget(id: "apple", title: "Apple", frame: .zero, code: "l", role: "AXMenuBarItem"),
            HintTarget(id: "add", title: "Add", frame: CGRect(x: 0, y: 80, width: 40, height: 20), code: "a", role: "AXButton"),
        ])
        _ = state.typeCharacter("a")
        #expect(state.selectedTarget?.id == "add")
        #expect(!state.matches.contains(where: { $0.target.id == "apple" }))
    }

    @Test func menuBarStillReachableByItsCode() {
        var state = HintState(targets: [
            HintTarget(id: "apple", title: "Apple", frame: .zero, code: "ap", role: "AXMenuBarItem"),
            HintTarget(id: "add", title: "Add", frame: .zero, code: "a", role: "AXButton"),
        ])
        _ = state.typeCharacter("a")
        _ = state.typeCharacter("p")
        #expect(state.selectedTarget?.id == "apple")
    }

    @Test func priorityWordBeatsPlainButton() {
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "other", title: "Other", frame: CGRect(x: 0, y: 100, width: 40, height: 20), role: "AXButton"),
                HintTarget(id: "save", title: "Save", frame: CGRect(x: 50, y: 100, width: 40, height: 20), role: "AXButton"),
            ],
            chars: "s",
            priorityWords: ["save"]
        )
        let byID = Dictionary(uniqueKeysWithValues: coded.map { ($0.id, $0.code) })
        #expect(byID["save"] == "s")
    }

    @Test func japaneseGetsLeftover() {
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "ja", title: "保存", frame: .zero, role: "AXButton"),
            ],
            chars: "qw",
            priorityWords: []
        )
        #expect(coded.first?.code == "q" || coded.first?.code == "w")
    }

    @Test func searchOnlyTargetsGetNoCode() {
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "t", title: "Hello", frame: .zero, showsLabel: false),
                HintTarget(id: "b", title: "OK", frame: .zero, role: "AXButton", isDefault: true),
            ],
            chars: "ok",
            priorityWords: ["ok"]
        )
        let byID = Dictionary(uniqueKeysWithValues: coded.map { ($0.id, $0.code) })
        #expect(byID["t"] == "")
        #expect(byID["b"] == "o")
    }

    @Test func titlePrefixesShareStemForSpaceConfirm() {
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "1", title: "Save", frame: .zero, role: "AXButton", isDefault: true),
                HintTarget(id: "2", title: "Settings", frame: .zero, role: "AXButton"),
            ],
            chars: "qwesfghjkl",
            priorityWords: ["save"]
        )
        #expect(coded.map(\.code).contains("s"))
        var state = HintState(targets: coded)
        _ = state.typeCharacter("s")
        let armed = state.armExactMatch()
        #expect(armed)
    }

    @Test func emptyQueryDoesNotArmTopRow() {
        var state = HintState(targets: [
            HintTarget(id: "1", title: "Save", frame: .zero, code: "s", role: "AXButton"),
            HintTarget(id: "2", title: "Open", frame: .zero, code: "o", role: "AXButton"),
        ])
        #expect(state.typed.isEmpty)
        #expect(state.selectedTarget == nil)
        #expect(state.armExactMatch() == false)
        state.moveSelection(1)
        #expect(state.selectedTarget?.id == "1")
        let armedEmpty = state.armExactMatch()
        #expect(armedEmpty)
        _ = state.typeCharacter("s")
        #expect(state.selectedTarget?.id == "1")
        let armed = state.armExactMatch()
        #expect(armed)
    }

    @Test func adapterMapsBoundaryLabeling() {
        let isolated = [
            HintTarget(id: "1", title: "A", frame: CGRect(x: 40, y: 100, width: 48, height: 32), code: "a"),
            HintTarget(id: "2", title: "B", frame: CGRect(x: 500, y: 120, width: 48, height: 32), code: "b"),
        ]
        let alone = HintLayout.layout(
            targets: isolated,
            screenBounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        #expect(alone.count == 2)
        #expect(alone.filter { $0.needsLeader }.isEmpty)
    }

    @Test func fuzzyDropsSpacesAndSubsequence() {
        #expect(HintFuzzy.score(query: "pull request", label: "Pull Request") != nil)
        #expect(HintFuzzy.score(query: "pullrequest", label: "Pull Request") != nil)
        #expect(HintFuzzy.score(query: "prst", label: "Pull Request") != nil)
        #expect(HintFuzzy.score(query: "zzzz", label: "Pull Request") == nil)
    }

    @Test func exactCodeOutranksFuzzy() {
        let targets = [
            HintTarget(id: "ok", title: "OK", frame: .zero, code: "o", role: "AXButton"),
            HintTarget(id: "open", title: "Open file", frame: .zero, code: "op", role: "AXButton"),
        ]
        var state = HintState(targets: targets)
        _ = state.typeCharacter("o")
        #expect(state.selectedTarget?.id == "ok")
    }

    @Test func cmdNumbersAfterThreeChars() {
        let targets = (0..<5).map {
            HintTarget(id: "\($0)", title: "Comment item \($0)", frame: .zero, showsLabel: false)
        }
        var state = HintState(targets: targets)
        _ = state.typeCharacter("c")
        _ = state.typeCharacter("o")
        #expect(state.matches.allSatisfy { $0.cmdNumber == nil })
        _ = state.typeCharacter("m")
        #expect(state.matches.first?.cmdNumber == 1)
        #expect(state.selectCmdNumber(1)?.id == state.matches.first?.id)
    }

    @Test func cmdNumbersWhileCommandHeld() {
        let targets = (0..<3).map {
            HintTarget(id: "\($0)", title: "Button \($0)", frame: .zero, code: "b\($0)", role: "AXButton")
        }
        var state = HintState(targets: targets)
        #expect(state.matches.allSatisfy { $0.cmdNumber == nil })
        state.setCommandHeld(true)
        #expect(state.showsCmdNumbers)
        #expect(state.cmdNumber(forTargetID: "0") == 1)
        #expect(state.selectCmdNumber(2)?.id == "1")
        state.setCommandHeld(false)
        #expect(state.cmdNumber(forTargetID: "0") == nil)
    }

    @Test func searchTextGetsBubbleOnlyWithCmdNumber() {
        // Search-only text stays off-screen until ⌘N; no bare "·" placeholders.
        let text = HintTarget(
            id: "kevin",
            title: "kevin notes",
            frame: CGRect(x: 40, y: 80, width: 120, height: 18),
            role: "AXStaticText",
            showsLabel: false
        )
        let button = HintTarget(
            id: "btn",
            title: "Save",
            frame: CGRect(x: 200, y: 80, width: 48, height: 24),
            code: "s",
            role: "AXButton",
            showsLabel: true
        )
        var state = HintState(targets: [text, button])
        #expect(!state.bubbleTargets.contains(where: { $0.id == "kevin" }))
        _ = state.typeCharacter("k")
        #expect(!state.showsCmdNumbers)
        #expect(!state.bubbleTargets.contains(where: { $0.id == "kevin" }))
        _ = state.typeCharacter("e")
        _ = state.typeCharacter("v")
        #expect(state.showsCmdNumbers)
        #expect(state.cmdNumber(forTargetID: "kevin") == 1)
        #expect(state.bubbleTargets.contains(where: { $0.id == "kevin" }))
        #expect(!state.bubbleTargets.contains(where: { $0.code == "·" }))
    }

    @Test func typeToSelectAndBackspace() {
        var state = HintState(targets: [
            HintTarget(id: "1", title: "Ok", frame: .zero, code: "as"),
            HintTarget(id: "2", title: "No", frame: .zero, code: "df"),
        ])
        let first = state.typeCharacter("a")
        #expect(first == .narrowed)
        state.backspace()
        #expect(state.typed.isEmpty)
    }

    @Test func visionStubEmpty() async {
        let source = VisionHintSource()
        let items = await source.collect()
        #expect(items.isEmpty)
    }

    @Test func priorityWordsParse() {
        let words = PriorityWords.parse("""
        # comment
        ok
        Save
        """)
        #expect(words == Set(["ok", "save"]))
    }

    @Test func paletteAnchorCyclesAndDefaultsSemiBottom() {
        var state = HintState()
        #expect(state.paletteAnchor == .semiBottom)
        state.paletteAnchor.toggle()
        #expect(state.paletteAnchor == .center)
        state.paletteAnchor.toggle()
        #expect(state.paletteAnchor == .semiTop)
        state.paletteAnchor.toggle()
        #expect(state.paletteAnchor == .semiBottom)
    }
}

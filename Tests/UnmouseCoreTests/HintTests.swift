import CoreGraphics
import Testing
@testable import UnmouseCore

@Suite("Hint")
struct HintTests {
    @Test func assignUniqueCodes() {
        let targets = (0..<5).map {
            HintTarget(id: "\($0)", title: "Alpha", frame: CGRect(x: $0 * 10, y: 0, width: 40, height: 20))
        }
        let coded = HintCoder.assignCodes(targets: targets, chars: "asdf")
        let codes = coded.map(\.code)
        #expect(Set(codes).count == codes.count)
        #expect(codes[0] == "a")
    }

    @Test func titlePrefixesShareStemForSpaceConfirm() {
        // Full-title coding: first unique stem is 1 char, next keeps going → "s"/"se".
        let coded = HintCoder.assignCodes(
            targets: [
                HintTarget(id: "1", title: "Save", frame: .zero),
                HintTarget(id: "2", title: "Settings", frame: .zero),
            ],
            chars: "qwesfghjkl"
        )
        #expect(coded.map(\.code) == ["s", "se"])
        var state = HintState(targets: coded)
        #expect(state.typeCharacter("s") == .narrowed)
        #expect(state.armedID == nil)
        let armed = state.armExactMatch()
        #expect(armed)
        #expect(state.armedID == "1")
    }

    @Test func adapterMapsBoundaryLabeling() {
        // Far apart → in-situ, no leaders.
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

        // Close neighbors on one row → stay within leash (rail or snap-back).
        let clustered = [
            HintTarget(id: "3", title: "C", frame: CGRect(x: 200, y: 200, width: 10, height: 16), code: "c"),
            HintTarget(id: "4", title: "D", frame: CGRect(x: 214, y: 200, width: 10, height: 16), code: "d"),
            HintTarget(id: "5", title: "E", frame: CGRect(x: 228, y: 200, width: 10, height: 16), code: "e"),
        ]
        let packed = HintLayout.layout(
            targets: clustered,
            screenBounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        for b in packed {
            let d = hypot(b.bubbleFrame.midX - b.targetPoint.x, b.bubbleFrame.midY - b.targetPoint.y)
            #expect(d <= 28.5)
        }
    }

    @Test func typeToArm() {
        var state = HintState(targets: [
            HintTarget(id: "1", title: "Ok", frame: .zero, code: "as"),
            HintTarget(id: "2", title: "No", frame: .zero, code: "df"),
        ])
        let first = state.typeCharacter("a")
        #expect(first == .narrowed)
        #expect(state.style(for: "as") == HintCodeStyle(highlighted: false, tintedCount: 1))
        #expect(state.style(for: "df") == HintCodeStyle(highlighted: false, tintedCount: 0))
        let second = state.typeCharacter("s")
        if case .armed(let t) = second {
            #expect(t.id == "1")
        } else {
            Issue.record("expected armed")
        }
        #expect(state.style(for: "as") == HintCodeStyle(highlighted: true, tintedCount: 0))
    }

    @Test func exactCodeHighlightsBesideLongerPrefix() {
        var state = HintState(targets: [
            HintTarget(id: "r", title: "Run", frame: .zero, code: "r"),
            HintTarget(id: "ru", title: "Rules", frame: .zero, code: "ru"),
        ])
        #expect(state.typeCharacter("r") == .narrowed)
        #expect(state.armedID == nil)
        #expect(state.style(for: "r") == HintCodeStyle(highlighted: true, tintedCount: 0))
        #expect(state.style(for: "ru") == HintCodeStyle(highlighted: false, tintedCount: 1))
        let done = state.typeCharacter("u")
        if case .armed(let t) = done {
            #expect(t.id == "ru")
        } else {
            Issue.record("expected armed")
        }
        #expect(state.style(for: "ru") == HintCodeStyle(highlighted: true, tintedCount: 0))
        #expect(state.style(for: "r") == HintCodeStyle(highlighted: false, tintedCount: 0))
    }

    @Test func spaceArmsExactSingleCharOverLongerPrefix() {
        var state = HintState(targets: [
            HintTarget(id: "short", title: "A", frame: .zero, code: "a"),
            HintTarget(id: "long", title: "Ab", frame: .zero, code: "ab"),
        ])
        let narrowed = state.typeCharacter("a")
        #expect(narrowed == .narrowed)
        #expect(state.armedID == nil)
        let armed = state.armExactMatch()
        #expect(armed)
        #expect(state.armedID == "short")
    }

    @Test func visionStubEmpty() async {
        let source = VisionHintSource()
        let items = await source.collect()
        #expect(items.isEmpty)
    }
}

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

    @Test func leaderWhenCrowded() {
        let targets = [
            HintTarget(id: "1", title: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10), code: "a"),
            HintTarget(id: "2", title: "B", frame: CGRect(x: 2, y: 2, width: 10, height: 10), code: "b"),
        ]
        let bubbles = HintLayout.layout(targets: targets, screenBounds: CGRect(x: 0, y: 0, width: 400, height: 400))
        #expect(bubbles.contains { $0.needsLeader })
    }

    @Test func typeToArm() {
        var state = HintState(targets: [
            HintTarget(id: "1", title: "Ok", frame: .zero, code: "as"),
            HintTarget(id: "2", title: "No", frame: .zero, code: "df"),
        ])
        let first = state.typeCharacter("a")
        #expect(first == .narrowed)
        let second = state.typeCharacter("s")
        if case .armed(let t) = second {
            #expect(t.id == "1")
        } else {
            Issue.record("expected armed")
        }
    }

    @Test func visionStubEmpty() async {
        let source = VisionHintSource()
        let items = await source.collect()
        #expect(items.isEmpty)
    }
}

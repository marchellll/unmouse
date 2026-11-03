import CoreGraphics
import Testing
@testable import BoundaryLabeling

@Suite("BoundaryLabeling")
struct LayoutTests {
    @Test func emptyInput() {
        #expect(BoundaryLabeler.layout(sites: [], bounds: .zero).isEmpty)
    }

    @Test func isolatedStaysInSituNoLeader() {
        let sites = [
            LabelSite(id: "a", point: CGPoint(x: 100, y: 200), tag: "a"),
            LabelSite(id: "b", point: CGPoint(x: 500, y: 200), tag: "b"),
            LabelSite(id: "c", point: CGPoint(x: 300, y: 80), tag: "c"),
        ]
        let placed = BoundaryLabeler.layout(
            sites: sites,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        #expect(placed.count == 3)
        #expect(placed.filter { $0.leader.isEmpty }.count == 3)
        for p in placed {
            #expect(abs(p.frame.midX - p.target.x) < 1)
            #expect(abs(p.frame.midY - p.target.y) < 1)
        }
    }

    @Test func verticalLinesDoNotKatamari() {
        // Editor lines ~20px apart must NOT become one mega-cluster.
        var sites: [LabelSite] = []
        for i in 0..<20 {
            sites.append(LabelSite(
                id: "\(i)",
                point: CGPoint(x: 200, y: 100 + CGFloat(i) * 20),
                tag: "\(i)"
            ))
        }
        let placed = BoundaryLabeler.layout(
            sites: sites,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            config: BoundaryLabelConfig(rowToleranceY: 10, maxLeashDistance: 28)
        )
        #expect(placed.filter { $0.leader.isEmpty }.count == 20)
        for p in placed {
            #expect(hypot(p.frame.midX - p.target.x, p.frame.midY - p.target.y) < 1)
        }
    }

    @Test func adjacentRowNeighborsGetLocalRailWithinLeash() {
        let sites = [
            LabelSite(id: "a", point: CGPoint(x: 200, y: 300), tag: "a"),
            LabelSite(id: "b", point: CGPoint(x: 220, y: 300), tag: "b"),
            LabelSite(id: "c", point: CGPoint(x: 240, y: 300), tag: "c"),
        ]
        let placed = BoundaryLabeler.layout(
            sites: sites,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            config: BoundaryLabelConfig(maxLeashDistance: 28)
        )
        #expect(placed.count == 3)
        for p in placed {
            let d = hypot(p.frame.midX - p.target.x, p.frame.midY - p.target.y)
            #expect(d <= 28.5)
        }
        #expect(BoundaryLabeler.crossingCount(placed) == 0)
    }

    @Test func leashSnapsWhenRowTooDense() {
        // 8 badges into a tiny span → X-relax would drag far; leash snaps back.
        var sites: [LabelSite] = []
        for i in 0..<8 {
            sites.append(LabelSite(
                id: "\(i)",
                point: CGPoint(x: 300 + CGFloat(i) * 4, y: 400),
                tag: "\(i)"
            ))
        }
        let placed = BoundaryLabeler.layout(
            sites: sites,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            config: BoundaryLabelConfig(maxLeashDistance: 28)
        )
        for p in placed {
            let d = hypot(p.frame.midX - p.target.x, p.frame.midY - p.target.y)
            #expect(d <= 28.5)
        }
        // At least some (usually most) abandon the rail.
        #expect(placed.filter { $0.leader.isEmpty }.count >= 1)
    }

    @Test func sameYFarApartStayIsolated() {
        let sites = [
            LabelSite(id: "left", point: CGPoint(x: 60, y: 560), tag: "l"),
            LabelSite(id: "right", point: CGPoint(x: 740, y: 560), tag: "r"),
        ]
        let placed = BoundaryLabeler.layout(
            sites: sites,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        #expect(placed.filter { $0.leader.isEmpty }.count == 2)
    }

    @Test func leadersNeverExceedLeash() {
        var sites: [LabelSite] = []
        for i in 0..<6 {
            sites.append(LabelSite(
                id: "\(i)",
                point: CGPoint(x: 200 + CGFloat(i) * 14, y: 300),
                tag: "\(i)"
            ))
        }
        let placed = BoundaryLabeler.layout(
            sites: sites,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            config: BoundaryLabelConfig(maxLeashDistance: 28)
        )
        for p in placed {
            let d = hypot(p.frame.midX - p.target.x, p.frame.midY - p.target.y)
            #expect(d <= 28.5)
        }
    }
}

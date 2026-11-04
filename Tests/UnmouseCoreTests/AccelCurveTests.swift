import Foundation
import Testing
@testable import UnmouseCore

@Suite("Accel curve")
struct AccelCurveTests {
    @Test func glideStartsLowThenPlateausThenTopsOut() {
        let knots = AccelCurve.knots(for: .glide)
        #expect(abs(AccelCurve.fraction(knots: knots, at: 0) - 0.09) < 0.001)
        #expect(abs(AccelCurve.fraction(knots: knots, at: 0.40) - 0.68) < 0.001)
        #expect(abs(AccelCurve.fraction(knots: knots, at: 2.72) - 0.74) < 0.001)
        #expect(AccelCurve.fraction(knots: knots, at: 3.2) == 1)
        #expect(AccelCurve.fraction(knots: knots, at: 3.5) == 1)
        #expect(AccelCurve.fraction(knots: knots, at: 5) == 1)
        #expect(AccelCurve.matching(knots) == .glide)
        #expect(AccelCurve.defaultDuration == 3.5)
    }

    @Test func linearStaysAtTopSpeed() {
        let knots = AccelCurve.knots(for: .linear)
        #expect(AccelCurve.fraction(knots: knots, at: 0) == 1)
        #expect(AccelCurve.fraction(knots: knots, at: 3) == 1)
        #expect(AccelCurve.matching(knots) == .linear)
    }

    @Test func diagonalClimbsInAStraightLine() {
        let knots = AccelCurve.knots(for: .diagonal)
        #expect(AccelCurve.fraction(knots: knots, at: 0) == 0)
        #expect(abs(AccelCurve.fraction(knots: knots, at: 1.75) - 0.5) < 0.0001)
        #expect(AccelCurve.fraction(knots: knots, at: 3.5) == 1)
        #expect(AccelCurve.matching(knots) == .diagonal)
    }

    @Test func editedKnotsAreCustom() {
        let knots = [SpeedKnot(t: 0, y: 0.5), SpeedKnot(t: 3.5, y: 0.5)]
        #expect(AccelCurve.matching(knots) == .custom)
        #expect(AccelCurve.fraction(knots: knots, at: 1) == 0.5)
    }

    @Test func missingCurveDefaultsToGlide() throws {
        let text = try ConfigIO.encode(AppConfig.default)
            .replacingOccurrences(of: "accel_knots", with: "old_knots")
            .replacingOccurrences(of: "accel", with: "old_accel")
        let decoded = try ConfigIO.decode(from: text)
        #expect(decoded.free.accel == .glide)
        #expect(decoded.free.accelSeconds == 3.5)
        #expect(AccelCurve.matching(decoded.free.accelKnots) == .glide)
    }

    @Test func curveRoundTrips() throws {
        var config = AppConfig.default
        config.free.accel = .custom
        config.free.accelSeconds = 6
        config.free.accelKnots = [
            SpeedKnot(t: 0, y: 0.3),
            SpeedKnot(t: 2, y: 0.5),
            SpeedKnot(t: 6, y: 1),
        ]
        let decoded = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(decoded.free.accel == .custom)
        #expect(decoded.free.accelKnots.count == 3)
        #expect(abs(decoded.free.accelKnots[1].t - 2) < 0.001)
        #expect(abs(decoded.free.accelKnots[1].y - 0.5) < 0.001)

        config.free.accel = .linear
        config.free.accelKnots = []
        let linear = try ConfigIO.decode(from: try ConfigIO.encode(config))
        #expect(linear.free.accel == .linear)
        #expect(AccelCurve.matching(linear.free.accelKnots) == .linear)
    }
}

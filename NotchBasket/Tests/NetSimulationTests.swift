import CoreGraphics
import XCTest
@testable import NotchBasket

final class NetSimulationTests: XCTestCase {
    func testRingStoresRestStateItWasGiven() {
        let ring = NetRing(
            radius: 40,
            centerX: 0,
            centerY: -10,
            restRadius: 40,
            restCenterY: -10,
            isPinned: false
        )

        XCTAssertEqual(ring.restRadius, 40)
        XCTAssertEqual(ring.restCenterY, -10)
        XCTAssertFalse(ring.isPinned)
    }

    func testTopRingIsPinnedToTheRim() {
        let simulation = NetRingSimulation()

        XCTAssertTrue(simulation.rings[0].isPinned)
        XCTAssertEqual(simulation.rings[0].radius, NetRingSimulation.topHalfWidth)
        XCTAssertEqual(simulation.rings[0].centerY, 0)
        XCTAssertFalse(simulation.rings[NetRingSimulation.ringCount - 1].isPinned)
    }

    func testRingsNarrowAndDescendMonotonically() {
        let simulation = NetRingSimulation()

        for index in 1..<NetRingSimulation.ringCount {
            XCTAssertLessThan(
                simulation.rings[index].restRadius,
                simulation.rings[index - 1].restRadius,
                "ring \(index) should be narrower than the one above it"
            )
            XCTAssertLessThan(
                simulation.rings[index].restCenterY,
                simulation.rings[index - 1].restCenterY,
                "ring \(index) should hang below the one above it"
            )
        }

        XCTAssertEqual(
            simulation.rings[NetRingSimulation.ringCount - 1].restRadius,
            NetRingSimulation.bottomHalfWidth,
            accuracy: 0.001
        )
    }

    func testDisturbedNetDampsBackTowardRest() {
        let simulation = NetRingSimulation()
        simulation.disturbForTesting(radiusOffset: 18, sagOffset: -12, swayOffset: 9)
        let disturbed = simulation.displacementFromRest()
        XCTAssertGreaterThan(disturbed, 1)

        for _ in 0..<240 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertLessThan(simulation.displacementFromRest(), disturbed * 0.1)
    }

    func testPinnedTopRingNeverMovesWhileLowerRingsDo() {
        let simulation = NetRingSimulation()
        simulation.disturbForTesting(radiusOffset: 20, sagOffset: -15, swayOffset: 12)

        for _ in 0..<30 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertEqual(simulation.rings[0].radius, NetRingSimulation.topHalfWidth)
        XCTAssertEqual(simulation.rings[0].centerX, 0)
        XCTAssertEqual(simulation.rings[0].centerY, 0)
        XCTAssertNotEqual(simulation.rings[5].centerY, simulation.rings[5].restCenterY)
    }

    func testRingOrderClampHoldsWhenRingsArePushedOutOfOrder() {
        let simulation = NetRingSimulation()

        // Push rings upward (positive sagOffset) to violate ordering constraint,
        // and push radius way above the ceiling to violate radius clamp.
        // bottomHalfWidth = 18, so minimumRadius = 6.3
        // topHalfWidth = 48.5, so maximumRadius = 87.3
        // We use sagOffset = 50 and radiusOffset = 100 to ensure violation.
        simulation.disturbForTesting(radiusOffset: 100, sagOffset: 50, swayOffset: 0)

        // Let the constraint enforcement run
        simulation.step(deltaTime: 1.0 / 60.0)

        // Clamp bounds as defined in enforceRingOrder()
        let minimumRadius = NetRingSimulation.bottomHalfWidth * 0.35
        let maximumRadius = NetRingSimulation.topHalfWidth * 1.8
        let minimumDrop: CGFloat = 1.5

        // Check that all rings obey both clamps
        for index in 1..<NetRingSimulation.ringCount {
            let ceilingY = simulation.rings[index - 1].centerY - minimumDrop
            XCTAssertLessThanOrEqual(
                simulation.rings[index].centerY,
                ceilingY,
                "ring \(index) centerY must not exceed ceiling defined by ring \(index - 1)"
            )
            XCTAssertGreaterThanOrEqual(
                simulation.rings[index].radius,
                minimumRadius,
                "ring \(index) radius must not go below minimum radius"
            )
            XCTAssertLessThanOrEqual(
                simulation.rings[index].radius,
                maximumRadius,
                "ring \(index) radius must not exceed maximum radius"
            )
        }
    }

    func testRadiusFloorClampHoldsWhenRingsAreCrushedInward() {
        let simulation = NetRingSimulation()

        // Push rings inward (negative radiusOffset) to violate radius floor clamp.
        // bottomHalfWidth = 18, so minimumRadius = 6.3
        // Rest radii range from 48.5 (top) down to 18 (bottom).
        // We use radiusOffset = -20 to ensure all rings, especially the bottom one,
        // are pushed well below the minimum clamp.
        simulation.disturbForTesting(radiusOffset: -20, sagOffset: 0, swayOffset: 0)

        // Let the constraint enforcement run
        simulation.step(deltaTime: 1.0 / 60.0)

        // Minimum clamp as defined in enforceRingOrder()
        let minimumRadius = NetRingSimulation.bottomHalfWidth * 0.35

        // Check that all free rings stay at or above the minimum radius floor
        for index in 1..<NetRingSimulation.ringCount {
            XCTAssertGreaterThanOrEqual(
                simulation.rings[index].radius,
                minimumRadius,
                "ring \(index) radius must not go below minimum radius"
            )
        }
    }

    func testWideningOneRingPullsTheRingBelowUpwardAndInward() {
        let simulation = NetRingSimulation()
        let restCenterY = simulation.rings[5].restCenterY
        let restRadius = simulation.rings[5].restRadius
        simulation.widenRingForTesting(at: 4, by: 22)

        for _ in 0..<12 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertGreaterThan(simulation.rings[5].centerY, restCenterY)
        XCTAssertLessThan(simulation.rings[5].radius, restRadius)
    }

    func testDeformationWavePropagatesDownward() {
        let simulation = NetRingSimulation()
        simulation.widenRingForTesting(at: 2, by: 20)

        var ringThreeMovedAtStep: Int?
        var ringSevenMovedAtStep: Int?
        for stepIndex in 0..<90 {
            simulation.step(deltaTime: 1.0 / 240.0)
            let threeMoved = abs(
                simulation.rings[3].centerY - simulation.rings[3].restCenterY
            ) > 0.05
            let sevenMoved = abs(
                simulation.rings[7].centerY - simulation.rings[7].restCenterY
            ) > 0.05
            if threeMoved, ringThreeMovedAtStep == nil {
                ringThreeMovedAtStep = stepIndex
            }
            if sevenMoved, ringSevenMovedAtStep == nil {
                ringSevenMovedAtStep = stepIndex
            }
        }

        guard let three = ringThreeMovedAtStep, let seven = ringSevenMovedAtStep else {
            return XCTFail("the disturbance never reached both rings")
        }
        XCTAssertLessThan(
            three,
            seven,
            "the disturbance must reach ring 3 before ring 7"
        )
    }

    func testSwayPropagatesDownTheSkirt() {
        let simulation = NetRingSimulation()
        XCTAssertEqual(simulation.rings[4].centerX, 0)

        simulation.swayRingForTesting(at: 3, by: 15)

        for _ in 0..<10 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertGreaterThan(
            simulation.rings[4].centerX,
            0,
            "the ring below the swayed ring should be dragged toward the same side"
        )
    }

    func testWideningOneRingPullsBackOnTheRingAbove() {
        // Every free ring drifts slightly away from its rest state purely from
        // gravity settling, even with no coupling at all, so a plain "did it
        // move" check would pass whether or not the reciprocal reaction exists.
        // The reaction's signature is specific: it drags ring 4's radius
        // measurably *below* its rest radius, something gravity alone never
        // does (gravity only acts on sag, not radius).
        let simulation = NetRingSimulation()
        let restRadius = simulation.rings[4].restRadius

        simulation.widenRingForTesting(at: 5, by: 22)

        for _ in 0..<12 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertLessThan(
            simulation.rings[4].radius,
            restRadius,
            "widening the ring below must react back onto the ring above it"
        )
    }

    private func descendingContact(y: CGFloat, x: CGFloat = 0) -> NetRingContact {
        NetRingContact(
            position: CGPoint(x: x, y: y),
            velocity: CGVector(dx: 0, dy: -600),
            radius: GameTuning.ballDiameter / 2
        )
    }

    func testDescendingBallStretchesTheHemOpen() {
        let simulation = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let restRadius = simulation.rings[bottomIndex].restRadius

        for _ in 0..<6 {
            simulation.step(
                deltaTime: 1.0 / 60.0,
                contact: descendingContact(
                    y: simulation.rings[bottomIndex].restCenterY
                ),
                responseScale: 1
            )
        }

        XCTAssertGreaterThan(simulation.rings[bottomIndex].radius, restRadius + 0.5)
    }

    func testBallBelowTheHemPushesTheBottomRingUpward() {
        // Gravity sags every ring slightly below its authored restCenterY
        // regardless of contact, so comparing against restCenterY would be
        // measuring gravity, not the ball. A control simulation stepped the
        // same number of frames with no contact isolates the contact's effect.
        let contacted = NetRingSimulation()
        let control = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let restCenterY = contacted.rings[bottomIndex].restCenterY
        let contact = NetRingContact(
            position: CGPoint(x: 0, y: restCenterY - 8),
            velocity: CGVector(dx: 0, dy: 520),
            radius: GameTuning.ballDiameter / 2
        )

        for _ in 0..<6 {
            contacted.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            control.step(deltaTime: 1.0 / 60.0, contact: nil, responseScale: 1)
        }

        XCTAssertGreaterThan(contacted.rings[bottomIndex].centerY, control.rings[bottomIndex].centerY)
    }

    func testBallBrushingOneSidePushesTheNetTheOtherWay() {
        let simulation = NetRingSimulation()
        let contact = NetRingContact(
            position: CGPoint(x: NetRingSimulation.topHalfWidth, y: -30),
            velocity: CGVector(dx: -240, dy: -120),
            radius: GameTuning.ballDiameter / 2
        )

        for _ in 0..<8 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
        }

        XCTAssertLessThan(
            simulation.rings[4].centerX,
            -0.2,
            "a ball outside the cone must push the cords away from it, not toward it"
        )
    }

    func testFastBallDoesNotTunnelThroughNet() {
        let simulation = NetRingSimulation()
        // One 60 Hz frame carries the ball from the rim plane to below the hem,
        // so only the swept substeps can see the contact at all.
        let contact = NetRingContact(
            position: CGPoint(x: 0, y: -110),
            velocity: CGVector(dx: 0, dy: -6_600),
            radius: GameTuning.ballDiameter / 2
        )

        simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)

        // The ball is already gone. What it left behind is velocity, so the net
        // visibly moves over the frames that follow — measuring position at the
        // instant of crossing would sample before any of it has happened.
        for _ in 0..<6 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: nil, responseScale: 1)
        }

        XCTAssertGreaterThan(
            simulation.displacementFromRest(),
            1,
            "a ball crossing the whole net in one frame must still disturb it"
        )

        let disturbedRings = simulation.rings.filter {
            abs($0.radius - $0.restRadius) > 0.05
        }
        XCTAssertGreaterThanOrEqual(
            disturbedRings.count,
            2,
            "the swept substeps must catch the ball against more than one loop"
        )
    }

    func testContactDampingKeepsTheHemFromOvershooting() {
        let simulation = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let contact = NetRingContact(
            position: CGPoint(x: 0, y: simulation.rings[bottomIndex].restCenterY),
            velocity: CGVector(dx: 0, dy: -600),
            radius: GameTuning.ballDiameter / 2
        )

        // A dwelling contact drives the hem toward its stretched equilibrium.
        // A pure spring would fly past it before dragging back; a spring-damper
        // settles with only a small overshoot. 180 frames (3s) is comfortably
        // past both the peak (reached within the first ~10 frames) and a full
        // settle (steady within the first ~2s), confirmed against a Python
        // reimplementation of this exact model.
        var peakRadius = simulation.rings[bottomIndex].radius
        for _ in 0..<180 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            peakRadius = max(peakRadius, simulation.rings[bottomIndex].radius)
        }
        let settledRadius = simulation.rings[bottomIndex].radius

        XCTAssertLessThan(
            peakRadius - settledRadius,
            1.0,
            "damping should keep the hem's overshoot well short of the ordering clamp"
        )
    }

    func testRingOrderSurvivesSevereContact() {
        let simulation = NetRingSimulation()

        for stepIndex in 0..<120 {
            let sweepY = CGFloat(stepIndex)
                .truncatingRemainder(dividingBy: 20) * -6
            simulation.step(
                deltaTime: 1.0 / 60.0,
                contact: NetRingContact(
                    position: CGPoint(x: sin(CGFloat(stepIndex)) * 40, y: sweepY),
                    velocity: CGVector(dx: 900, dy: -1_400),
                    radius: GameTuning.ballDiameter / 2
                ),
                responseScale: 1
            )

            for index in 1..<NetRingSimulation.ringCount {
                XCTAssertLessThan(
                    simulation.rings[index].centerY,
                    simulation.rings[index - 1].centerY,
                    "ring \(index) rose above ring \(index - 1) at step \(stepIndex)"
                )
                XCTAssertGreaterThan(simulation.rings[index].radius, 0)
            }
        }
    }

    func testReducedMotionScalesNetResponse() {
        let full = NetRingSimulation()
        let reduced = NetRingSimulation()
        let contact = descendingContact(y: -64)

        for _ in 0..<10 {
            full.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            reduced.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 0.38)
        }

        XCTAssertLessThan(reduced.displacementFromRest(), full.displacementFromRest())
    }
}

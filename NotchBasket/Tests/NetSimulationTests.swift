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
        let oneFrame = NetRingSimulation()
        let manyFrames = NetRingSimulation()
        let ballRadius = GameTuning.ballDiameter / 2
        let velocity = CGVector(dx: 0, dy: -6_600)
        let frame: CGFloat = 1.0 / 60.0
        let hem = NetRingSimulation.ringCount - 1

        // One 60 Hz frame carries the ball from the rim plane to below the hem.
        // Resolving that is the sweep's entire job, so the honest test is whether
        // one frame disturbs the net about as much as forty smaller ones do.
        oneFrame.step(
            deltaTime: frame,
            contact: NetRingContact(
                position: CGPoint(x: 0, y: -110),
                velocity: velocity,
                radius: ballRadius
            ),
            responseScale: 1
        )

        let slices = 40
        for index in 1...slices {
            let progress = CGFloat(index) / CGFloat(slices)
            manyFrames.step(
                deltaTime: frame / CGFloat(slices),
                contact: NetRingContact(
                    position: CGPoint(x: 0, y: -110 * progress),
                    velocity: velocity,
                    radius: ballRadius
                ),
                responseScale: 1
            )
        }

        // Measure the hem's stretch, not displacementFromRest: gravity sags every
        // ring whether or not a ball ever arrives, and that baseline is far larger
        // than what a ball moving this fast deposits. Gravity never touches radius.
        var onePeak: CGFloat = 0
        var manyPeak: CGFloat = 0
        for _ in 0..<6 {
            oneFrame.step(deltaTime: frame)
            manyFrames.step(deltaTime: frame)
            onePeak = max(
                onePeak,
                abs(oneFrame.rings[hem].radius - oneFrame.rings[hem].restRadius)
            )
            manyPeak = max(
                manyPeak,
                abs(manyFrames.rings[hem].radius - manyFrames.rings[hem].restRadius)
            )
        }

        // Measured: manyPeak is 0.085 here. A ball this fast barely disturbs the
        // net, which is correct — it is in contact for almost no time.
        XCTAssertGreaterThan(
            manyPeak,
            0.05,
            "a ball crossing the whole net must stretch the hem"
        )
        XCTAssertEqual(
            onePeak,
            manyPeak,
            accuracy: manyPeak * 0.5,
            "one swept frame must resolve the crossing about as well as forty"
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
        let contact = descendingContact(y: -70)

        for _ in 0..<10 {
            full.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            reduced.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 0.38)
        }

        XCTAssertLessThan(reduced.displacementFromRest(), full.displacementFromRest())
    }
    // MARK: - Task 4: net pushes back on the ball

    func testNetDeceleratesDescendingBall() {
        let simulation = NetRingSimulation()
        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: descendingContact(y: -70),
            responseScale: 1
        )

        XCTAssertGreaterThan(
            force.dy,
            0,
            "a ball falling into the cone must be pushed back upward"
        )
    }

    func testCentredBallGetsNoSidewaysKickButOffCentreIsRecentred() {
        let centred = NetRingSimulation()
        let offCentre = NetRingSimulation()

        let centredForce = centred.step(
            deltaTime: 1.0 / 60.0,
            contact: descendingContact(y: -70, x: 0),
            responseScale: 1
        )
        let offCentreForce = offCentre.step(
            deltaTime: 1.0 / 60.0,
            contact: descendingContact(y: -70, x: 12),
            responseScale: 1
        )

        XCTAssertEqual(
            centredForce.dx,
            0,
            accuracy: 0.001,
            "a ball on the axis is squeezed equally from every side"
        )
        XCTAssertLessThan(
            offCentreForce.dx,
            -0.001,
            "a ball off the axis must be pushed back toward it"
        )
    }

    func testContactAppliesRegardlessOfScoring() {
        let fromBelow = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let belowForce = fromBelow.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(
                    x: 0,
                    y: fromBelow.rings[bottomIndex].restCenterY - 8
                ),
                velocity: CGVector(dx: 0, dy: 520),
                radius: GameTuning.ballDiameter / 2
            ),
            responseScale: 1
        )

        let fromSide = NetRingSimulation()
        let sideForce = fromSide.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(x: NetRingSimulation.topHalfWidth, y: -30),
                velocity: CGVector(dx: -300, dy: -60),
                radius: GameTuning.ballDiameter / 2
            ),
            responseScale: 1
        )

        XCTAssertLessThan(belowForce.dy, 0, "the hem must resist a ball rising into it")
        XCTAssertGreaterThan(sideForce.dx, 0, "a side brush must push the ball outward")
    }

    /// The cap being enforced was already covered; that it is a *sane* number was
    /// not, and an absolute force of 90 turned out to be 26 g. Assert the ratio to
    /// the ball's weight, which is scale-free and means something physical.
    func testNetCannotFlingTheBall() {
        let simulation = NetRingSimulation()
        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(x: 8, y: -70),
                velocity: CGVector(dx: 400, dy: -2_800),
                radius: GameTuning.ballDiameter / 2
            ),
            responseScale: 1
        )

        let gravities = hypot(force.dx, force.dy)
            / GameTuning.ballMass
            / abs(GameTuning.gravity)

        XCTAssertGreaterThan(gravities, 0.2, "the net must actually push back")
        XCTAssertLessThan(gravities, 4, "but a net does not fling a basketball")
    }

    func testBallForceIsCapped() {
        let simulation = NetRingSimulation()
        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(x: 0, y: -70),
                velocity: CGVector(dx: 0, dy: -6_000),
                radius: GameTuning.ballDiameter / 2
            ),
            responseScale: 1
        )

        XCTAssertGreaterThan(
            hypot(force.dx, force.dy),
            0,
            "the contact must actually register, or the cap is untested"
        )
        XCTAssertLessThanOrEqual(
            hypot(force.dx, force.dy),
            (3 * GameTuning.ballWeight) + 0.001
        )
    }

    func testGripGrowsWithPenetration() {
        let shallow = NetRingSimulation.grip(penetration: 4, ballRadius: 24)
        let deep = NetRingSimulation.grip(penetration: 20, ballRadius: 24)

        XCTAssertGreaterThan(deep.normal, shallow.normal)
        XCTAssertGreaterThanOrEqual(shallow.normal, 0)
        XCTAssertGreaterThanOrEqual(shallow.drag, 0)
    }

    // MARK: - Task 5: containment backstop

    func testBallInsideTheNetIsNotCorrected() {
        let simulation = NetRingSimulation()

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 0, y: -30),
            ballRadius: GameTuning.ballDiameter / 2
        ))
    }

    func testBallThatSlippedThroughTheSideIsNudgedBack() throws {
        let simulation = NetRingSimulation()
        let escaped = CGPoint(x: NetRingSimulation.topHalfWidth + 30, y: -30)

        let correction = try XCTUnwrap(simulation.containmentCorrection(
            ballPosition: escaped,
            ballRadius: GameTuning.ballDiameter / 2
        ))

        XCTAssertLessThan(correction.x, escaped.x)
        XCTAssertEqual(correction.y, escaped.y, "the backstop is lateral only")
        XCTAssertLessThanOrEqual(
            escaped.x - correction.x,
            NetRingSimulation.maximumCorrectionPerFrame + 0.001
        )
    }

    /// The backstop only exists to recover a ball that slipped through a cord. It
    /// used to test the vertical span alone, so any ball crossing net height
    /// anywhere on screen — a shot thrown straight up from the far side, say — was
    /// treated as an escapee and pulled sideways.
    func testBallFarFromTheNetIsNeverCorrected() {
        let simulation = NetRingSimulation()
        let ballRadius = GameTuning.ballDiameter / 2

        // Sweep the full vertical span of the net at a lateral distance no shot
        // could have reached from inside it.
        for step in 0...20 {
            let y = -NetRingSimulation.depth * CGFloat(step) / 20
            for x in [-500.0, -120.0, 120.0, 500.0] as [CGFloat] {
                XCTAssertNil(
                    simulation.containmentCorrection(
                        ballPosition: CGPoint(x: x, y: y),
                        ballRadius: ballRadius
                    ),
                    "corrected a ball at (\(x), \(y)), which was never in the net"
                )
            }
        }
    }

    func testBallBelowTheNetIsReleased() {
        let simulation = NetRingSimulation()
        let bottom = simulation.rings[NetRingSimulation.ringCount - 1].restCenterY
        let ballRadius = GameTuning.ballDiameter / 2

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 40, y: bottom - ballRadius - 6),
            ballRadius: ballRadius
        ))
    }

    func testBallAboveTheRimIsNotCorrected() {
        let simulation = NetRingSimulation()

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: NetRingSimulation.topHalfWidth + 30, y: 40),
            ballRadius: GameTuning.ballDiameter / 2
        ))
    }

    // MARK: - Task 6: woven mesh derived from the rings

    func testKnotsProjectOntoTheRimEllipse() {
        let simulation = NetRingSimulation()
        let topRing = simulation.rings[0]

        let front = NetMeshPathBuilder.knot(
            ring: topRing,
            cordIndex: 0,
            ringFraction: 0
        )
        let quarter = NetMeshPathBuilder.knot(
            ring: topRing,
            cordIndex: NetMeshPathBuilder.cordCount / 4,
            ringFraction: 0
        )

        XCTAssertEqual(front.point.x, topRing.radius, accuracy: 0.001)
        XCTAssertEqual(
            abs(quarter.point.y - topRing.centerY),
            topRing.radius * NetMeshPathBuilder.projectionRatio,
            accuracy: 0.5,
            "the quarter-turn knot must sit on the shallow rim ellipse"
        )
    }

    func testEveryCordIsAssignedToExactlyOneDepthLayer() {
        let simulation = NetRingSimulation()
        var frontCount = 0
        var rearCount = 0

        for cordIndex in 0..<NetMeshPathBuilder.cordCount {
            let knot = NetMeshPathBuilder.knot(
                ring: simulation.rings[3],
                cordIndex: cordIndex,
                ringFraction: 0.3
            )
            if knot.depth >= 0 {
                rearCount += 1
            } else {
                frontCount += 1
            }
        }

        XCTAssertGreaterThan(frontCount, 0)
        XCTAssertGreaterThan(rearCount, 0)
        XCTAssertEqual(frontCount + rearCount, NetMeshPathBuilder.cordCount)
    }

    func testMeshPathsAreNonEmptyAndTrackRingMotion() {
        let simulation = NetRingSimulation()
        let atRest = NetMeshPathBuilder.paths(for: simulation.rings)
        XCTAssertFalse(atRest.rear.isEmpty)
        XCTAssertFalse(atRest.front.isEmpty)

        simulation.widenRingForTesting(at: 5, by: 24)
        let deformed = NetMeshPathBuilder.paths(for: simulation.rings)

        XCTAssertNotEqual(
            atRest.front.boundingBox.width,
            deformed.front.boundingBox.width,
            accuracy: 0.0001
        )
    }

}

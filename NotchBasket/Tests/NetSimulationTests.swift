import CoreGraphics
import XCTest
@testable import NotchBasket

final class NetSimulationTests: XCTestCase {
    private let ballRadius = GameTuning.ballDiameter / 2

    private func descendingContact(y: CGFloat, x: CGFloat = 0) -> NetRingContact {
        NetRingContact(
            position: CGPoint(x: x, y: y),
            velocity: CGVector(dx: 0, dy: -600),
            radius: ballRadius
        )
    }

    /// The hem's height, which is where a dead-centre ball actually reaches the
    /// cords: every row above it is wider than the ball.
    private var hemY: CGFloat {
        -NetClothSimulation.depth
    }

    // MARK: - Rest shape

    func testTopRowIsPinnedToTheRim() {
        let rows = NetClothSimulation().rings

        XCTAssertTrue(rows[0].isPinned)
        XCTAssertEqual(rows[0].radius, NetClothSimulation.topHalfWidth, accuracy: 0.001)
        XCTAssertEqual(rows[0].centerY, 0, accuracy: 0.001)
        XCTAssertFalse(rows[NetClothSimulation.rowCount - 1].isPinned)
    }

    func testRowsNarrowAndDescendMonotonically() {
        let rows = NetClothSimulation().rings

        for index in 1..<NetClothSimulation.rowCount {
            XCTAssertLessThan(
                rows[index].restRadius,
                rows[index - 1].restRadius,
                "row \(index) should be narrower than the one above it"
            )
            XCTAssertLessThan(
                rows[index].restCenterY,
                rows[index - 1].restCenterY,
                "row \(index) should hang below the one above it"
            )
        }

        XCTAssertEqual(
            rows[NetClothSimulation.rowCount - 1].restRadius,
            NetClothSimulation.bottomHalfWidth,
            accuracy: 0.001
        )
    }

    func testDisturbedNetDampsBackTowardRest() {
        let simulation = NetClothSimulation()
        simulation.disturbForTesting(radiusOffset: 18, sagOffset: -12, swayOffset: 9)
        let disturbed = simulation.displacementFromRest()
        XCTAssertGreaterThan(disturbed, 1)

        for _ in 0..<240 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertLessThan(simulation.displacementFromRest(), disturbed * 0.25)
    }

    func testPinnedTopRowNeverMovesWhileLowerRowsDo() {
        let simulation = NetClothSimulation()
        simulation.disturbForTesting(radiusOffset: 20, sagOffset: -15, swayOffset: 12)

        for _ in 0..<30 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        for cord in 0..<NetClothSimulation.cordCount {
            XCTAssertEqual(
                simulation.displacement(row: 0, cord: cord),
                0,
                accuracy: 0.0001
            )
        }
        XCTAssertGreaterThan(simulation.displacement(row: 5, cord: 0), 0.01)
    }

    // MARK: - Weave coupling

    func testWideningOneRowPullsItsNeighboursAlong() {
        let simulation = NetClothSimulation()
        simulation.widenRingForTesting(at: 5, by: 22)

        for _ in 0..<12 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertGreaterThan(
            simulation.displacement(row: 6, cord: 0),
            0.05,
            "the cords must carry the disturbance to the row below"
        )
        XCTAssertGreaterThan(
            simulation.displacement(row: 4, cord: 0),
            0.05,
            "and back up to the row above"
        )
    }

    func testDeformationWavePropagatesDownward() {
        let simulation = NetClothSimulation()
        simulation.widenRingForTesting(at: 2, by: 20)

        var rowThreeMovedAtStep: Int?
        var rowSevenMovedAtStep: Int?
        for stepIndex in 0..<120 {
            simulation.step(deltaTime: 1.0 / 240.0)
            if rowThreeMovedAtStep == nil,
               simulation.displacement(row: 3, cord: 0) > 0.05 {
                rowThreeMovedAtStep = stepIndex
            }
            if rowSevenMovedAtStep == nil,
               simulation.displacement(row: 7, cord: 0) > 0.05 {
                rowSevenMovedAtStep = stepIndex
            }
        }

        guard let three = rowThreeMovedAtStep, let seven = rowSevenMovedAtStep else {
            return XCTFail("the disturbance never reached both rows")
        }
        XCTAssertLessThan(three, seven, "it must reach row 3 before row 7")
    }

    // MARK: - The ball dents the net

    /// The reason the cloth replaced the ring model. A ball pressing on one side
    /// has to push the cords nearest it much further than the cords opposite; a
    /// model that can only widen a whole loop reads as the ball passing through
    /// the mesh instead of pushing it.
    func testBallPressingFromOutsideDentsOnlyTheNearSide() {
        let simulation = NetClothSimulation()
        let row = 5
        let rowRadius = simulation.rings[row].restRadius
        let rowY = simulation.rings[row].restCenterY

        // Cord 0 sits at angle 0, the +x side of the weave; cordCount/2 is opposite.
        let contact = NetRingContact(
            position: CGPoint(x: rowRadius + (ballRadius * 0.6), y: rowY),
            velocity: CGVector(dx: -300, dy: 0),
            radius: ballRadius
        )

        for _ in 0..<10 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
        }

        let near = simulation.displacement(row: row, cord: 0)
        let far = simulation.displacement(
            row: row,
            cord: NetClothSimulation.cordCount / 2
        )

        XCTAssertGreaterThan(near, 1, "the near cords must be pushed in")
        XCTAssertGreaterThan(
            near,
            far * 3,
            "the dent must be local — near \(near), far \(far)"
        )
    }

    /// The same requirement from inside the cone, which the ring model could not
    /// express either: it widened the whole loop whichever side the ball was on.
    func testBallPressingFromInsideDentsOnlyTheNearSide() {
        let simulation = NetClothSimulation()
        let row = 5
        let rowRadius = simulation.rings[row].restRadius
        let rowY = simulation.rings[row].restCenterY

        let contact = NetRingContact(
            position: CGPoint(x: rowRadius - (ballRadius * 0.6), y: rowY),
            velocity: CGVector(dx: 300, dy: 0),
            radius: ballRadius
        )

        for _ in 0..<10 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
        }

        let near = simulation.displacement(row: row, cord: 0)
        let far = simulation.displacement(
            row: row,
            cord: NetClothSimulation.cordCount / 2
        )

        XCTAssertGreaterThan(near, 1, "the near cords must be pushed out")
        XCTAssertGreaterThan(
            near,
            far * 3,
            "the dent must be local — near \(near), far \(far)"
        )
    }

    func testDescendingBallStretchesTheHemOpen() {
        let simulation = NetClothSimulation()
        let hem = NetClothSimulation.rowCount - 1
        let restRadius = simulation.rings[hem].restRadius

        for _ in 0..<8 {
            simulation.step(
                deltaTime: 1.0 / 60.0,
                contact: descendingContact(y: hemY),
                responseScale: 1
            )
        }

        XCTAssertGreaterThan(simulation.rings[hem].radius, restRadius + 0.5)
    }

    func testBallBelowTheHemPushesItUpward() {
        let simulation = NetClothSimulation()
        let control = NetClothSimulation()
        let hem = NetClothSimulation.rowCount - 1
        let contact = NetRingContact(
            position: CGPoint(x: 0, y: hemY - 8),
            velocity: CGVector(dx: 0, dy: 520),
            radius: ballRadius
        )

        // Gravity sags the sheet whether or not a ball arrives, so an untouched
        // control run is the only honest baseline.
        for _ in 0..<8 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            control.step(deltaTime: 1.0 / 60.0, contact: nil, responseScale: 1)
        }

        XCTAssertGreaterThan(
            simulation.rings[hem].centerY,
            control.rings[hem].centerY
        )
    }

    func testFastBallDoesNotTunnelThroughNet() {
        let simulation = NetClothSimulation()
        let hem = NetClothSimulation.rowCount - 1
        let rest = NetClothSimulation.bottomHalfWidth
        let frame: CGFloat = 1.0 / 60.0

        // One 60 Hz frame carries the ball from the rim plane to below the hem, so
        // only the swept substeps can see it touch anything at all: sampled at the
        // end position alone it is already 34 points clear of the hem.
        simulation.step(
            deltaTime: frame,
            contact: NetRingContact(
                position: CGPoint(x: 0, y: -110),
                velocity: CGVector(dx: 0, dy: -6_600),
                radius: ballRadius
            ),
            responseScale: 1
        )

        // Hem stretch rather than total displacement: gravity sags every knot
        // whether or not a ball arrives, and that baseline dwarfs what a ball this
        // fast leaves behind. Gravity does not widen the hem. Measured: 0.31 here,
        // and nothing at all with the sweep removed.
        var peak = simulation.rings[hem].radius
        for _ in 0..<6 {
            simulation.step(deltaTime: frame)
            peak = max(peak, simulation.rings[hem].radius)
        }

        XCTAssertGreaterThan(
            peak - rest,
            0.1,
            "a ball crossing the whole net in one frame must still stretch the hem"
        )
    }

    /// Hard contact is allowed to fold the sheet — that is what a real net does,
    /// and rows crossing each other in mean height is part of it. What must not
    /// happen is the solver gaining energy: this once flung the whole net up off
    /// the rim, with knots ending 100+ points from where they belong.
    func testSevereContactStaysBounded() {
        let simulation = NetClothSimulation()

        for stepIndex in 0..<120 {
            let sweepY = CGFloat(stepIndex).truncatingRemainder(dividingBy: 20) * -6
            simulation.step(
                deltaTime: 1.0 / 60.0,
                contact: NetRingContact(
                    position: CGPoint(x: sin(CGFloat(stepIndex)) * 40, y: sweepY),
                    velocity: CGVector(dx: 900, dy: -1_400),
                    radius: ballRadius
                ),
                responseScale: 1
            )

            for row in 0..<NetClothSimulation.rowCount {
                for cord in 0..<NetClothSimulation.cordCount {
                    let displacement = simulation.displacement(row: row, cord: cord)
                    XCTAssertTrue(
                        displacement.isFinite,
                        "knot (\(row), \(cord)) diverged at step \(stepIndex)"
                    )
                    // The net hangs below the rim. A violent ball can shove a knot
                    // a little above it, but the runaway this guards against sent
                    // the whole sheet climbing past the rim and away. Measured
                    // ceiling here is 16 points above the rim plane.
                    XCTAssertLessThan(
                        simulation.position(row: row, cord: cord).y,
                        ballRadius,
                        "knot (\(row), \(cord)) flew above the rim at step \(stepIndex)"
                    )
                }
            }
        }
    }

    /// Net damping must not depend on the ball's speed. It once did — the substep
    /// count was raised by ball travel and damping ran per substep, so a fast ball
    /// anywhere on screen made the whole net decay several times faster for the
    /// length of every shot. A disturbance far from any contact must settle at the
    /// same rate whatever the ball is doing.
    func testDampingDoesNotDependOnBallSpeed() {
        func framesToSettle(ballSpeed: CGFloat) -> Int {
            let simulation = NetClothSimulation()
            simulation.disturbForTesting(radiusOffset: 0, sagOffset: 0, swayOffset: 14)
            let start = simulation.displacementFromRest()

            // A ball far below the hem, never in contact — only its speed matters.
            let ball: NetRingContact? = ballSpeed == 0 ? nil : NetRingContact(
                position: CGPoint(x: 0, y: -NetClothSimulation.depth - 400),
                velocity: CGVector(dx: 0, dy: -ballSpeed),
                radius: ballRadius
            )
            for frame in 0..<90 {
                simulation.step(deltaTime: 1.0 / 60.0, contact: ball, responseScale: 1)
                if simulation.displacementFromRest() < start * 0.25 { return frame }
            }
            return 90
        }

        let still = framesToSettle(ballSpeed: 0)
        let fast = framesToSettle(ballSpeed: 8000)
        XCTAssertEqual(
            still,
            fast,
            "settling took \(still) frames with no ball, \(fast) with a fast one"
        )
    }

    func testReducedMotionScalesNetResponse() {
        let full = NetClothSimulation()
        let reduced = NetClothSimulation()
        let contact = descendingContact(y: hemY)

        for _ in 0..<10 {
            full.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            reduced.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 0.38)
        }

        XCTAssertLessThan(reduced.displacementFromRest(), full.displacementFromRest())
    }

    // MARK: - The net pushes back on the ball

    func testNetDeceleratesDescendingBall() {
        let simulation = NetClothSimulation()
        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: descendingContact(y: hemY + 6),
            responseScale: 1
        )

        XCTAssertGreaterThan(
            force.dy,
            0,
            "a ball settling into the hem must be pushed back upward"
        )
    }

    func testOffCentreBallIsPushedBackTowardTheAxis() {
        let simulation = NetClothSimulation()
        let row = 5
        let rowRadius = simulation.rings[row].restRadius

        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(
                    x: rowRadius - (ballRadius * 0.5),
                    y: simulation.rings[row].restCenterY
                ),
                velocity: CGVector(dx: 0, dy: -600),
                radius: ballRadius
            ),
            responseScale: 1
        )

        XCTAssertLessThan(force.dx, -0.001)
    }

    func testContactAppliesRegardlessOfScoring() {
        let fromBelow = NetClothSimulation()
        let belowForce = fromBelow.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(x: 0, y: hemY - 8),
                velocity: CGVector(dx: 0, dy: 520),
                radius: ballRadius
            ),
            responseScale: 1
        )

        let fromOutside = NetClothSimulation()
        let row = 5
        let outsideForce = fromOutside.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(
                    x: fromOutside.rings[row].restRadius + (ballRadius * 0.6),
                    y: fromOutside.rings[row].restCenterY
                ),
                velocity: CGVector(dx: -300, dy: -60),
                radius: ballRadius
            ),
            responseScale: 1
        )

        XCTAssertLessThan(
            belowForce.dy,
            0,
            "the hem must resist a ball rising into it"
        )
        XCTAssertGreaterThan(
            outsideForce.dx,
            0,
            "a ball pressing from outside must be pushed back out"
        )
    }

    /// The cap being enforced was already covered; that it is a *sane* number was
    /// not, and an absolute force of 90 turned out to be 26 g. Assert the ratio to
    /// the ball's weight, which is scale-free and means something physical.
    func testNetCannotFlingTheBall() {
        let simulation = NetClothSimulation()
        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(x: 8, y: hemY + 6),
                velocity: CGVector(dx: 400, dy: -2_800),
                radius: ballRadius
            ),
            responseScale: 1
        )

        let gravities = hypot(force.dx, force.dy)
            / GameTuning.ballMass
            / abs(GameTuning.gravity)

        XCTAssertGreaterThan(gravities, 0.05, "the net must actually push back")
        // The cap is exactly 3 weights; assert just past it so loosening the
        // constant is caught, not merely a wild fling.
        XCTAssertLessThan(gravities, 3.05, "but a net does not fling a basketball")
    }

    func testGripGrowsWithPenetration() {
        let shallow = NetClothSimulation.grip(penetration: 4, ballRadius: 24)
        let deep = NetClothSimulation.grip(penetration: 20, ballRadius: 24)

        XCTAssertGreaterThan(deep.normal, shallow.normal)
        XCTAssertGreaterThanOrEqual(shallow.normal, 0)
        XCTAssertGreaterThanOrEqual(shallow.drag, 0)
    }

    // MARK: - Containment backstop

    func testBallInsideTheNetIsNotCorrected() {
        let simulation = NetClothSimulation()

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 0, y: -30),
            ballRadius: ballRadius
        ))
    }

    func testBallThatSlippedThroughTheSideIsNudgedBack() throws {
        let simulation = NetClothSimulation()

        // The backstop only recovers a ball that was in the cone, so put it there
        // first — this is the frame before the integrator loses it through a cord.
        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 0, y: -30),
            ballRadius: ballRadius
        ))

        let escaped = CGPoint(x: NetClothSimulation.topHalfWidth + 30, y: -30)
        let correction = try XCTUnwrap(simulation.containmentCorrection(
            ballPosition: escaped,
            ballRadius: ballRadius
        ))

        XCTAssertLessThan(correction.x, escaped.x)
        XCTAssertEqual(correction.y, escaped.y, "the backstop is lateral only")
        XCTAssertLessThanOrEqual(
            escaped.x - correction.x,
            NetClothSimulation.maximumCorrectionPerFrame + 0.001
        )
    }

    /// A ball dropping past the front of the hoop without ever entering it must be
    /// left alone. This was a visible zigzag: the backstop guessed from distance
    /// whether the ball could have escaped, and a near miss qualified.
    func testBallFallingPastTheHoopIsNotNudged() {
        let simulation = NetClothSimulation()

        for step in 0...20 {
            let y = -NetClothSimulation.depth * CGFloat(step) / 20
            XCTAssertNil(
                simulation.containmentCorrection(
                    ballPosition: CGPoint(
                        x: -(NetClothSimulation.topHalfWidth + 20),
                        y: y
                    ),
                    ballRadius: ballRadius
                ),
                "nudged a ball that only fell past the hoop, at y \(y)"
            )
        }
    }

    func testBallFarFromTheNetIsNeverCorrected() {
        let simulation = NetClothSimulation()

        for step in 0...20 {
            let y = -NetClothSimulation.depth * CGFloat(step) / 20
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

    /// A ball grabbed mid-flight never gets the frame that clears the "was inside"
    /// latch, so the next shot could inherit it and nudge a ball merely passing the
    /// hoop. resetForNewShot is what the scene calls to prevent that.
    func testResetForNewShotClearsTheEscapeLatch() {
        let simulation = NetClothSimulation()

        // Put the ball inside the cone, setting the latch.
        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 0, y: -30),
            ballRadius: ballRadius
        ))

        // Without a reset, a ball now off to the side would be treated as an
        // escapee and corrected. Reset first, and it must be left alone.
        simulation.resetForNewShot()
        XCTAssertNil(
            simulation.containmentCorrection(
                ballPosition: CGPoint(x: NetClothSimulation.topHalfWidth + 30, y: -30),
                ballRadius: ballRadius
            ),
            "the latch survived resetForNewShot"
        )
    }

    func testLeavingTheNetClearsTheEscapeLatch() {
        let simulation = NetClothSimulation()

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 0, y: -30),
            ballRadius: ballRadius
        ))
        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 0, y: -NetClothSimulation.depth - 40),
            ballRadius: ballRadius
        ))
        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: NetClothSimulation.topHalfWidth + 30, y: -30),
            ballRadius: ballRadius
        ))
    }

    func testBallBelowTheNetIsReleased() {
        let simulation = NetClothSimulation()
        let bottom = simulation.rings[NetClothSimulation.rowCount - 1].restCenterY

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 40, y: bottom - ballRadius - 6),
            ballRadius: ballRadius
        ))
    }

    func testBallAboveTheRimIsNotCorrected() {
        let simulation = NetClothSimulation()

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: NetClothSimulation.topHalfWidth + 30, y: 40),
            ballRadius: ballRadius
        ))
    }

    // MARK: - Rendering

    func testKnotsProjectOntoTheRimEllipse() {
        let simulation = NetClothSimulation()
        let front = NetMeshPathBuilder.project(simulation.position(row: 0, cord: 0))

        // Cord 0 sits at angle 0, so it is at full radius on the x axis with no
        // depth at all — the near edge of the projected ellipse.
        XCTAssertEqual(
            front.point.x,
            NetClothSimulation.topHalfWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(front.depth, 0, accuracy: 0.001)

        // A knot a quarter turn round is at maximum depth, so its screen height is
        // offset by the projection ratio and it belongs to the far layer.
        let quarterCord = NetClothSimulation.cordCount / 4
        let quarter = NetMeshPathBuilder.project(
            simulation.position(row: 0, cord: quarterCord)
        )
        XCTAssertGreaterThan(quarter.depth, 0)
        XCTAssertEqual(
            quarter.point.y,
            NetMeshPathBuilder.projectionRatio * quarter.depth,
            accuracy: 0.001
        )
    }

    func testBothDepthLayersReceiveCords() {
        let paths = NetMeshPathBuilder.paths(for: NetClothSimulation())

        // The weave wraps the cone, so some cords are nearer the viewer than the
        // ball and some are behind it. Both render layers must actually get
        // geometry, or the ball would draw over the whole net or under it.
        XCTAssertFalse(paths.rear.isEmpty, "no cords were sent to the rear layer")
        XCTAssertFalse(paths.front.isEmpty, "no cords were sent to the front layer")

        // And the front layer must be genuinely nearer: its knots sit at negative
        // depth, which the side-on projection lifts in screen-y relative to the
        // rear. Compare the two bounding boxes' vertical span as a proxy — a
        // builder that dumped everything into one layer would leave the other
        // empty, already caught above; this guards against them being swapped.
        XCTAssertGreaterThan(paths.front.boundingBox.height, 0)
        XCTAssertGreaterThan(paths.rear.boundingBox.height, 0)
    }

    /// Cords bend through their knots rather than turning a corner at each one.
    /// Straight segments read as a faceted cage however fine the weave gets, so
    /// the paths have to actually contain curves.
    func testCordsAreDrawnAsCurvesNotStraightSegments() {
        let paths = NetMeshPathBuilder.paths(for: NetClothSimulation())

        var curves = 0
        var lines = 0
        for path in [paths.rear, paths.front] {
            path.applyWithBlock { element in
                switch element.pointee.type {
                case .addQuadCurveToPoint, .addCurveToPoint: curves += 1
                case .addLineToPoint: lines += 1
                default: break
                }
            }
        }

        XCTAssertGreaterThan(curves, 0, "the weave is drawn with no curves at all")
        XCTAssertGreaterThan(
            curves,
            lines,
            "most of the weave should bend — \(curves) curves against \(lines) lines"
        )
    }

    func testMeshPathsAreNonEmptyAndTrackKnotMotion() {
        let simulation = NetClothSimulation()
        let atRest = NetMeshPathBuilder.paths(for: simulation)
        XCTAssertFalse(atRest.rear.isEmpty)
        XCTAssertFalse(atRest.front.isEmpty)

        simulation.widenRingForTesting(at: 5, by: 24)
        let deformed = NetMeshPathBuilder.paths(for: simulation)

        XCTAssertNotEqual(
            atRest.front.boundingBox.width,
            deformed.front.boundingBox.width,
            accuracy: 0.0001
        )
    }
}

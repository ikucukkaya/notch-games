import AppKit
import XCTest
@testable import NotchBasket

final class GeometryTests: XCTestCase {
    func testNotchUsesGapBetweenAuxiliaryAreas() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 956, width: 650, height: 26)
        let right = CGRect(x: 862, y: 956, width: 650, height: 26)

        let notch = NotchGeometryService.estimatedNotchRect(
            screenFrame: screen,
            leftAuxiliaryArea: left,
            rightAuxiliaryArea: right,
            safeAreaTop: 38
        )

        XCTAssertEqual(notch?.minX, 650)
        XCTAssertEqual(notch?.width, 212)
        XCTAssertEqual(notch?.midX, 756)
        XCTAssertEqual(notch?.height, 38)
    }

    func testNotchReturnsNilWithoutAuxiliaryAreas() {
        XCTAssertNil(NotchGeometryService.estimatedNotchRect(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil,
            safeAreaTop: 24
        ))
    }

    func testSideMountedHoopAnchorHonorsRightEdgeAndOffsets() {
        let point = ScreenGeometryService.sideMountedHoopAnchor(
            screenSize: CGSize(width: 1440, height: 900),
            floorY: 80,
            rightBoundaryX: 1432,
            horizontalOffset: 18,
            verticalOffset: -12
        )

        XCTAssertEqual(
            point.x,
            1432 - SideHoopLayout.mountEdgeX + 18
        )
        XCTAssertEqual(point.y, 636)
    }

    func testSideHoopFacesLeftFromRightMount() {
        XCTAssertGreaterThan(SideHoopLayout.mountEdgeX, SideHoopLayout.backboardX)
        XCTAssertGreaterThan(SideHoopLayout.backboardX, SideHoopLayout.attachedRimX)
        XCTAssertLessThan(SideHoopLayout.outerRimX, SideHoopLayout.attachedRimX)
        XCTAssertGreaterThan(SideHoopLayout.supportArmLength, SideHoopLayout.rimDepth)
    }

    func testBallRendersBetweenRearAndFrontRimLayers() throws {
        let hoop = HoopNode()
        let ball = BasketballNode(diameter: GameTuning.ballDiameter)
        let rearRim = try XCTUnwrap(hoop.childNode(withName: "rearRimVisual"))
        let frontRim = try XCTUnwrap(hoop.childNode(withName: "frontRimVisual"))

        XCTAssertLessThan(hoop.zPosition + rearRim.zPosition, ball.zPosition)
        XCTAssertGreaterThan(hoop.zPosition + frontRim.zPosition, ball.zPosition)
    }

    func testRealisticMountingAssemblyIsPresent() {
        let hoop = HoopNode()

        XCTAssertNotNil(hoop.childNode(withName: "backboardVisual"))
        XCTAssertNotNil(hoop.childNode(withName: "supportArmVisual"))
        XCTAssertNotNil(hoop.childNode(withName: "mountBracketVisual"))
        XCTAssertNotNil(hoop.childNode(withName: "wallMountVisual"))
    }

    func testBottomDockInferenceAndFloor() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 806)

        let edge = ScreenGeometryService.inferDockEdge(
            screenFrame: screen,
            visibleFrame: visible
        )
        let floor = ScreenGeometryService.floorY(
            screenFrame: screen,
            visibleFrame: visible,
            dockEdge: edge
        )

        XCTAssertEqual(edge, .bottom)
        XCTAssertEqual(floor, 80)
    }

    func testSideDockInference() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let leftVisible = CGRect(x: 76, y: 0, width: 1364, height: 876)
        let rightVisible = CGRect(x: 0, y: 0, width: 1364, height: 876)

        XCTAssertEqual(
            ScreenGeometryService.inferDockEdge(screenFrame: screen, visibleFrame: leftVisible),
            .left
        )
        XCTAssertEqual(
            ScreenGeometryService.inferDockEdge(screenFrame: screen, visibleFrame: rightVisible),
            .right
        )
    }

    func testBallSpawnStaysInsideBoundaries() {
        let spawn = ScreenGeometryService.ballSpawnPoint(
            screenWidth: 1200,
            floorY: 80,
            leftBoundaryX: 250,
            rightBoundaryX: 1192
        )

        XCTAssertEqual(spawn.x, 600)
        XCTAssertEqual(spawn.y, 109)
    }

    func testOverlayPassesClicksThroughAwayFromBall() {
        XCTAssertFalse(OverlayInteractionPolicy.shouldCaptureMouse(
            isGameActive: true,
            isAiming: false,
            isAdjustingHoopHeight: false,
            isPointerOnGrabbableBall: false,
            isPointerOnHoop: false
        ))
    }

    func testOverlayCapturesReadyBall() {
        XCTAssertTrue(OverlayInteractionPolicy.shouldCaptureMouse(
            isGameActive: true,
            isAiming: false,
            isAdjustingHoopHeight: false,
            isPointerOnGrabbableBall: true,
            isPointerOnHoop: false
        ))
    }

    func testOverlayKeepsCaptureDuringDrag() {
        XCTAssertTrue(OverlayInteractionPolicy.shouldCaptureMouse(
            isGameActive: true,
            isAiming: true,
            isAdjustingHoopHeight: false,
            isPointerOnGrabbableBall: false,
            isPointerOnHoop: false
        ))
    }

    func testOverlayCapturesHoopForHeightAdjustment() {
        XCTAssertTrue(OverlayInteractionPolicy.shouldCaptureMouse(
            isGameActive: true,
            isAiming: false,
            isAdjustingHoopHeight: false,
            isPointerOnGrabbableBall: false,
            isPointerOnHoop: true
        ))
        XCTAssertTrue(OverlayInteractionPolicy.shouldCaptureMouse(
            isGameActive: true,
            isAiming: false,
            isAdjustingHoopHeight: true,
            isPointerOnGrabbableBall: false,
            isPointerOnHoop: false
        ))
    }

    func testHoopHeightIsClampedInsidePlayableScreen() {
        XCTAssertEqual(HoopHeightPolicy.clampedAnchorY(
            20,
            floorY: 80,
            screenHeight: 900
        ), 260)
        XCTAssertEqual(HoopHeightPolicy.clampedAnchorY(
            1_000,
            floorY: 80,
            screenHeight: 900
        ), 872)
        XCTAssertEqual(HoopHeightPolicy.clampedAnchorY(
            600,
            floorY: 80,
            screenHeight: 900
        ), 600)
    }

    func testMovingAndScoredBallsRemainGrabbable() {
        XCTAssertTrue(BallInteractionPolicy.isGrabbable(.ready))
        XCTAssertTrue(BallInteractionPolicy.isGrabbable(.flying))
        XCTAssertTrue(BallInteractionPolicy.isGrabbable(.scored))
    }

    func testTransitionalBallStatesAreNotGrabbable() {
        XCTAssertFalse(BallInteractionPolicy.isGrabbable(.spawning))
        XCTAssertFalse(BallInteractionPolicy.isGrabbable(.aiming))
        XCTAssertFalse(BallInteractionPolicy.isGrabbable(.settling))
        XCTAssertFalse(BallInteractionPolicy.isGrabbable(.resetting))
    }

    func testShotCompletionReportsSettledWithoutRequestingRespawn() {
        var controller = BallResetController()
        controller.beginShot(at: 10)

        XCTAssertNil(controller.completionReason(
            at: 10.2,
            speed: 10,
            isInsidePlayableRegion: true
        ))
        XCTAssertEqual(controller.completionReason(
            at: 11,
            speed: 10,
            isInsidePlayableRegion: true
        ), .settled)
    }

    func testShotCompletionDistinguishesLeavingScreen() {
        var controller = BallResetController()
        controller.beginShot(at: 10)

        XCTAssertEqual(controller.completionReason(
            at: 10.1,
            speed: 200,
            isInsidePlayableRegion: false
        ), .leftPlayableRegion)
    }

    func testQuietFinalFloorBouncesAreSilentEvenWhileBallRolls() {
        XCTAssertFalse(BoundarySoundPolicy.shouldPlay(
            boundaryName: "floor",
            velocity: CGVector(dx: 300, dy: 22),
            collisionImpulse: 2
        ))
    }

    func testStrongFloorImpactStillPlays() {
        XCTAssertTrue(BoundarySoundPolicy.shouldPlay(
            boundaryName: "floor",
            velocity: CGVector(dx: 20, dy: 240),
            collisionImpulse: 2
        ))
    }

    func testNetTopRowStaysPinnedWhileLowerRowsMove() {
        let simulation = NetClothSimulation()
        let topRest = simulation.restPosition(row: 0, column: 5)

        simulation.applySwishImpulse(
            ballVelocity: CGVector(dx: 420, dy: -780)
        )
        for _ in 0..<30 {
            simulation.step(deltaTime: 1.0 / 60.0, ballContact: nil)
        }

        XCTAssertEqual(simulation.position(row: 0, column: 5), topRest)
        XCTAssertGreaterThan(simulation.totalDisplacement(), 0.1)
    }

    func testSideViewNetUsesDenseLongVerletMesh() {
        let simulation = NetClothSimulation()

        XCTAssertEqual(simulation.rowCount, 10)
        XCTAssertEqual(simulation.columnCount, 10)
        XCTAssertEqual(simulation.particleCount, 121)
        XCTAssertLessThan(
            simulation.restPosition(row: 0, column: 5).y,
            simulation.restPosition(row: 0, column: 0).y
        )
        XCTAssertLessThan(
            simulation.restPosition(row: simulation.rowCount, column: 5).y,
            simulation.restPosition(row: 0, column: 5).y - 70
        )
    }

    func testDescendingBallIsCapturedWhenItCrossesNetOpening() {
        let guide = NetFunnelGuide()
        let response = guide.response(
            for: NetBallContact(
                position: CGPoint(x: 8, y: -3),
                velocity: CGVector(dx: 120, dy: -600),
                radius: 24
            ),
            deltaTime: 1.0 / 60.0
        )

        XCTAssertNotNil(response)
        XCTAssertTrue(guide.isCapturingBall)
    }

    func testCapturedBallCannotEscapeThroughNetSide() throws {
        let guide = NetFunnelGuide()
        _ = guide.response(
            for: NetBallContact(
                position: CGPoint(x: 0, y: -3),
                velocity: CGVector(dx: 0, dy: -600),
                radius: 24
            ),
            deltaTime: 1.0 / 60.0
        )

        let response = try XCTUnwrap(guide.response(
            for: NetBallContact(
                position: CGPoint(x: 42, y: -40),
                velocity: CGVector(dx: 1_200, dy: -700),
                radius: 24
            ),
            deltaTime: 1.0 / 60.0
        ))

        XCTAssertLessThan(abs(response.position.x), 16)
        XCTAssertLessThan(response.velocity.dx, 0)
        XCTAssertTrue(guide.isCapturingBall)
    }

    func testCapturedBallReleasesOnlyAfterClearingBottomOpening() throws {
        let guide = NetFunnelGuide()
        _ = guide.response(
            for: NetBallContact(
                position: CGPoint(x: 0, y: -4),
                velocity: CGVector(dx: 0, dy: -600),
                radius: 24
            ),
            deltaTime: 1.0 / 60.0
        )

        let sideResponse = try XCTUnwrap(guide.response(
            for: NetBallContact(
                position: CGPoint(x: 50, y: -62),
                velocity: CGVector(dx: 900, dy: -650),
                radius: 24
            ),
            deltaTime: 1.0 / 60.0
        ))
        XCTAssertLessThan(abs(sideResponse.position.x), 11)
        XCTAssertTrue(guide.isCapturingBall)

        let bottomResponse = try XCTUnwrap(guide.response(
            for: NetBallContact(
                position: CGPoint(x: 30, y: -101),
                velocity: CGVector(dx: 500, dy: -620),
                radius: 24
            ),
            deltaTime: 1.0 / 60.0
        ))
        XCTAssertLessThanOrEqual(abs(bottomResponse.position.x), 7)
        XCTAssertFalse(guide.isCapturingBall)
    }

    func testBallTouchingNetFromBelowIsNotCapturedByFunnel() {
        let guide = NetFunnelGuide()
        let response = guide.response(
            for: NetBallContact(
                position: CGPoint(x: 0, y: -70),
                velocity: CGVector(dx: 0, dy: 500),
                radius: 24
            ),
            deltaTime: 1.0 / 60.0
        )

        XCTAssertNil(response)
        XCTAssertFalse(guide.isCapturingBall)
    }

    func testBallTouchingNetFromBelowPushesItUpwardWithoutScoring() {
        let simulation = NetClothSimulation()
        let rest = simulation.restPosition(row: simulation.rowCount, column: 5)
        let contact = NetBallContact(
            position: CGPoint(x: rest.x, y: rest.y - 18),
            velocity: CGVector(dx: 0, dy: 180),
            radius: 22
        )

        simulation.step(deltaTime: 1.0 / 60.0, ballContact: contact)

        XCTAssertGreaterThan(
            simulation.position(row: simulation.rowCount, column: 5).y,
            rest.y
        )
    }

    func testFastBallUsesSweptContactInsteadOfTunnelingThroughNet() {
        let simulation = NetClothSimulation()
        let rest = simulation.restPosition(row: 4, column: 5)
        let contact = NetBallContact(
            position: CGPoint(x: rest.x, y: rest.y + 30),
            velocity: CGVector(dx: 0, dy: 3_600),
            radius: 8
        )

        simulation.step(deltaTime: 1.0 / 60.0, ballContact: contact)

        XCTAssertGreaterThan(simulation.position(row: 4, column: 5).y, rest.y)
    }

    func testNetMotionDampsBackTowardRest() {
        let simulation = NetClothSimulation()
        simulation.applySwishImpulse(
            ballVelocity: CGVector(dx: 500, dy: -900)
        )
        simulation.step(deltaTime: 1.0 / 60.0, ballContact: nil)
        let initialDisplacement = simulation.totalDisplacement()

        for _ in 0..<300 {
            simulation.step(deltaTime: 1.0 / 60.0, ballContact: nil)
        }

        XCTAssertLessThan(simulation.totalDisplacement(), initialDisplacement)
    }

    func testNetKnotsCannotCrossOrCollapseDuringSevereContact() {
        let simulation = NetClothSimulation()
        let contactCenter = simulation.restPosition(row: 8, column: 5)

        for frame in 0..<24 {
            let direction: CGFloat = frame.isMultiple(of: 2) ? 1 : -1
            let contact = NetBallContact(
                position: CGPoint(
                    x: contactCenter.x + (direction * 7),
                    y: contactCenter.y + CGFloat(frame % 3) - 1
                ),
                velocity: CGVector(dx: direction * 2_400, dy: -1_500),
                radius: 30
            )
            simulation.step(deltaTime: 1.0 / 60.0, ballContact: contact)
        }

        for row in 1...simulation.rowCount {
            for column in 0..<simulation.columnCount {
                let left = simulation.position(row: row, column: column)
                let right = simulation.position(row: row, column: column + 1)
                XCTAssertGreaterThan(right.x - left.x, 1)
            }
        }

        for row in 0..<simulation.rowCount {
            for column in 0...simulation.columnCount {
                let upper = simulation.position(row: row, column: column)
                let lower = simulation.position(row: row + 1, column: column)
                XCTAssertGreaterThan(upper.y - lower.y, 1)
            }
        }
    }

    func testNetUntanglesAndReturnsAfterRepeatedBallContact() {
        let simulation = NetClothSimulation()
        let contactCenter = simulation.restPosition(row: 7, column: 5)

        for _ in 0..<18 {
            simulation.step(
                deltaTime: 1.0 / 60.0,
                ballContact: NetBallContact(
                    position: contactCenter,
                    velocity: CGVector(dx: 1_800, dy: -1_400),
                    radius: 28
                )
            )
        }
        let impactedDisplacement = simulation.totalDisplacement()

        for _ in 0..<480 {
            simulation.step(deltaTime: 1.0 / 60.0, ballContact: nil)
        }

        XCTAssertLessThan(simulation.totalDisplacement(), impactedDisplacement * 0.25)
        let bottomRow = simulation.rowCount
        for column in 0..<simulation.columnCount {
            let left = simulation.position(row: bottomRow, column: column)
            let right = simulation.position(row: bottomRow, column: column + 1)
            XCTAssertGreaterThan(right.x - left.x, 1)
        }
    }

    func testReducedMotionScalesNetResponse() {
        let full = NetClothSimulation()
        let reduced = NetClothSimulation()
        let velocity = CGVector(dx: 520, dy: -880)

        full.applySwishImpulse(ballVelocity: velocity, responseScale: 1)
        reduced.applySwishImpulse(ballVelocity: velocity, responseScale: 0.3)
        full.step(deltaTime: 1.0 / 60.0, ballContact: nil)
        reduced.step(deltaTime: 1.0 / 60.0, ballContact: nil)

        XCTAssertLessThan(reduced.totalDisplacement(), full.totalDisplacement())
    }
}

final class AudioSynthesisTests: XCTestCase {
    func testCourtBounceHasFullBodyAndSilentEndpoints() throws {
        let samples = BasketballCourtBounceSynthesizer.samples(sampleRate: 44_100)

        XCTAssertEqual(
            samples.count,
            Int(BasketballCourtBounceSynthesizer.duration * 44_100)
        )
        XCTAssertEqual(try XCTUnwrap(samples.first), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(samples.last), 0, accuracy: 0.001)
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.65)
    }

    func testCourtBounceAvoidsClickAndBrightGlassLikeOscillation() {
        let samples = BasketballCourtBounceSynthesizer.samples(sampleRate: 44_100)
        var maximumStep: Float = 0
        var zeroCrossingCount = 0

        for index in 1..<samples.count {
            maximumStep = max(
                maximumStep,
                abs(samples[index] - samples[index - 1])
            )
            if (samples[index] >= 0) != (samples[index - 1] >= 0) {
                zeroCrossingCount += 1
            }
        }

        XCTAssertLessThan(maximumStep, 0.025)
        XCTAssertLessThan(zeroCrossingCount, 60)
    }
}

import AppKit
import SpriteKit
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

    /// The net simulation runs in the net's own local space, but the scene hands
    /// it ball positions in scene space and applies the force it returns to the
    /// ball. Every NetSimulationTests case drives the sim directly, so nothing
    /// there would notice if HoopNode mapped the coordinates wrong — dropping the
    /// netNode offset would put every contact ~80 points off with the suite still
    /// green. This exercises the whole scene -> hoop -> net -> force path.
    func testHoopMapsSceneContactIntoNetSpace() {
        let scene = SKScene(size: CGSize(width: 800, height: 600))
        let hoop = HoopNode()
        hoop.position = CGPoint(x: 500, y: 400)
        scene.addChild(hoop)

        // A ball settling into the hem, expressed in SCENE coordinates. The net's
        // hem sits at rimY - depth below the hoop's own origin, plus the net node's
        // own offset of rimY - 2.
        let hemInHoop = CGPoint(x: 0, y: (GameTuning.rimY - 2) + (-NetClothSimulation.depth + 6))
        let hemInScene = CGPoint(
            x: hoop.position.x + hemInHoop.x,
            y: hoop.position.y + hemInHoop.y
        )

        let force = hoop.updateNet(
            deltaTime: 1.0 / 60.0,
            ballScenePosition: hemInScene,
            ballVelocity: CGVector(dx: 0, dy: -600),
            ballRadius: GameTuning.ballDiameter / 2,
            reducedEffects: false
        )

        XCTAssertGreaterThan(
            force.dy,
            0,
            "a ball at the hem, placed in scene space, must be pushed back up"
        )

        // The same ball a full net-width off to the side touches nothing: proof the
        // mapping is not simply returning a force for any input.
        let asideInScene = CGPoint(x: hemInScene.x + 400, y: hemInScene.y)
        let farHoop = HoopNode()
        farHoop.position = hoop.position
        scene.addChild(farHoop)
        let farForce = farHoop.updateNet(
            deltaTime: 1.0 / 60.0,
            ballScenePosition: asideInScene,
            ballVelocity: CGVector(dx: 0, dy: -600),
            ballRadius: GameTuning.ballDiameter / 2,
            reducedEffects: false
        )
        XCTAssertEqual(farForce.dx, 0, accuracy: 0.001)
        XCTAssertEqual(farForce.dy, 0, accuracy: 0.001)
    }

    func testRealisticMountingAssemblyIsPresent() {
        let hoop = HoopNode()

        XCTAssertNotNil(hoop.childNode(withName: "backboardVisual"))
        XCTAssertNotNil(hoop.childNode(withName: "supportArmVisual"))
        XCTAssertNotNil(hoop.childNode(withName: "mountBracketVisual"))
        XCTAssertNotNil(hoop.childNode(withName: "wallMountVisual"))
    }

    /// The guide is drawn over an unknown desktop and the app never samples the
    /// screen, so every bright layer needs a dark one behind it or it disappears
    /// over a white window.
    func testAimGuideCarriesADarkLayerBehindEveryBrightOne() throws {
        let indicator = AimIndicatorNode()
        indicator.update(
            from: CGPoint(x: 100, y: 100),
            velocity: CGVector(dx: 400, dy: 600),
            gravity: GameTuning.gravity,
            powerFraction: 0.5
        )

        let trajectoryOutline = try XCTUnwrap(
            indicator.childNode(withName: "aimTrajectoryOutline") as? SKShapeNode
        )
        let trajectoryFill = try XCTUnwrap(
            indicator.childNode(withName: "aimTrajectoryFill") as? SKShapeNode
        )
        let powerOutline = try XCTUnwrap(
            indicator.childNode(withName: "aimPowerOutline") as? SKShapeNode
        )
        let powerRing = try XCTUnwrap(
            indicator.childNode(withName: "aimPowerRing") as? SKShapeNode
        )

        XCTAssertNotNil(trajectoryOutline.path, "the dark dots must be drawn too")
        XCTAssertNotNil(powerOutline.path, "the dark ring must be drawn too")

        // Each dark layer has to sit behind its bright twin and actually be dark.
        XCTAssertLessThan(trajectoryOutline.zPosition, trajectoryFill.zPosition)
        XCTAssertLessThan(powerOutline.zPosition, powerRing.zPosition)
        XCTAssertLessThan(
            trajectoryOutline.fillColor.brightnessComponentOrOne,
            0.35
        )
        XCTAssertLessThan(
            powerOutline.strokeColor.brightnessComponentOrOne,
            0.35
        )

        // And the dark ring must be wide enough to show around the bright one.
        XCTAssertGreaterThan(powerOutline.lineWidth, powerRing.lineWidth)
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

    /// The net simulation is handed `ball.radius`, while the rim and backboard
    /// collide against the physics body. If those two disagree the ball behaves
    /// as one size and looks another, which is what a 0.94 collision fudge used
    /// to do here.
    func testBallCollidesAtTheSizeItIsDrawn() throws {
        let ball = BasketballNode(diameter: GameTuning.ballDiameter)
        let body = try XCTUnwrap(ball.physicsBody)

        // Compare against a body built at the drawn radius rather than computing
        // an area by hand: SpriteKit reports `area` in its own scaled units, and
        // building the reference the same way makes the scale cancel out.
        let drawnSize = SKPhysicsBody(circleOfRadius: ball.radius)

        XCTAssertEqual(body.area, drawnSize.area, accuracy: drawnSize.area * 0.01)
    }

    func testBallSpawnStaysInsideBoundaries() {
        let floorY: CGFloat = 80
        let spawn = ScreenGeometryService.ballSpawnPoint(
            screenWidth: 1200,
            floorY: floorY,
            leftBoundaryX: 250,
            rightBoundaryX: 1192
        )

        XCTAssertEqual(spawn.x, 600)

        // Assert the clearance, not a coordinate baked from one ball diameter:
        // the ball has to rest just above the floor at whatever size it is.
        let ballRadius = GameTuning.ballDiameter / 2
        XCTAssertGreaterThan(spawn.y - ballRadius, floorY)
        XCTAssertLessThan(spawn.y - ballRadius, floorY + 12)
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
        let screenHeight: CGFloat = 900

        XCTAssertEqual(HoopHeightPolicy.clampedAnchorY(
            20,
            floorY: 80,
            screenHeight: screenHeight
        ), 260)
        XCTAssertEqual(HoopHeightPolicy.clampedAnchorY(
            600,
            floorY: 80,
            screenHeight: screenHeight
        ), 600)

        // Assert the property rather than the number: at the top of its range the
        // backboard's upper edge — the highest part of the assembly — must still
        // be on screen, and not pointlessly far below the edge either. Written
        // this way the test survives the board changing size, and still fails if
        // the ceiling stops accounting for it.
        let highest = HoopHeightPolicy.clampedAnchorY(
            1_000,
            floorY: 80,
            screenHeight: screenHeight
        )
        let boardTop = highest + SideHoopLayout.assemblyTopY
        XCTAssertLessThan(boardTop, screenHeight)
        XCTAssertGreaterThan(boardTop, screenHeight - 40)
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

    func testHoopImpactHasFullBodyAndSilentEndpoints() throws {
        let samples = HoopImpactSynthesizer.samples(sampleRate: 44_100)

        XCTAssertEqual(
            samples.count,
            Int(HoopImpactSynthesizer.duration * 44_100)
        )
        XCTAssertEqual(try XCTUnwrap(samples.first), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(samples.last), 0, accuracy: 0.001)
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.65)
    }

    /// The old rim voice was three bright sines under one shared envelope — a
    /// gated chord, not metal, and the complaint that prompted the redo. The
    /// chosen impact is a low padded thud: measured 89 zero crossings and a
    /// 0.025 peak step, so these bounds hold the character while the old rim's
    /// 760 Hz fundamental alone would cross zero hundreds of times.
    func testHoopImpactStaysPaddedNotGlassy() {
        let samples = HoopImpactSynthesizer.samples(sampleRate: 44_100)
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

        XCTAssertLessThan(maximumStep, 0.05)
        XCTAssertLessThan(zeroCrossingCount, 130)
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

private extension NSColor {
    /// `brightnessComponent` traps on colours outside a compatible space, and the
    /// aim guide builds its colours with `withAlphaComponent`, so convert first.
    var brightnessComponentOrOne: CGFloat {
        (usingColorSpace(.deviceRGB) ?? .white).brightnessComponent
    }
}

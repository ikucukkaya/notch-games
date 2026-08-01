import CoreGraphics
import XCTest
@testable import NotchBasket

final class ShotCalculationTests: XCTestCase {
    private let calculator = ShotController(
        minimumDragDistance: 10,
        maximumDragDistance: 100,
        powerMultiplier: 5,
        maximumLaunchSpeed: 400
    )

    func testLaunchDirectionIsOppositeDrag() {
        let velocity = calculator.launchVelocity(
            ballOrigin: CGPoint(x: 100, y: 100),
            dragPoint: CGPoint(x: 80, y: 60),
            sensitivity: 1
        )

        XCTAssertGreaterThan(velocity.dx, 0)
        XCTAssertGreaterThan(velocity.dy, 0)
    }

    func testMinimumDragReturnsZeroVelocity() {
        let velocity = calculator.launchVelocity(
            ballOrigin: .zero,
            dragPoint: CGPoint(x: 5, y: 2),
            sensitivity: 1
        )

        XCTAssertEqual(velocity, .zero)
    }

    func testDragDistanceIsClamped() {
        let vector = calculator.clampedDragVector(
            ballOrigin: .zero,
            dragPoint: CGPoint(x: 300, y: 400)
        )

        XCTAssertEqual(vector.length, 100, accuracy: 0.001)
    }

    func testMaximumVelocityIsClamped() {
        let velocity = calculator.launchVelocity(
            ballOrigin: .zero,
            dragPoint: CGPoint(x: -100, y: -100),
            sensitivity: 1.5
        )

        XCTAssertEqual(velocity.length, 400, accuracy: 0.001)
    }

    func testSensitivityIsSafelyBounded() {
        let normal = calculator.launchVelocity(
            ballOrigin: .zero,
            dragPoint: CGPoint(x: -20, y: -20),
            sensitivity: 1.5
        )
        let excessive = calculator.launchVelocity(
            ballOrigin: .zero,
            dragPoint: CGPoint(x: -20, y: -20),
            sensitivity: 9
        )

        XCTAssertEqual(normal.length, excessive.length, accuracy: 0.001)
    }

    func testDefaultFullPullComfortablyReachesMacBookHoopHeight() {
        let defaultCalculator = ShotController()
        let velocity = defaultCalculator.launchVelocity(
            ballOrigin: CGPoint(x: 700, y: 270),
            dragPoint: CGPoint(x: 700, y: 115),
            sensitivity: 1
        )

        XCTAssertGreaterThanOrEqual(velocity.dy, 2_300)
        XCTAssertLessThanOrEqual(velocity.length, GameTuning.maximumLaunchSpeed)
    }

    func testLowestSensitivityFullPullStillHasStrongUpwardReach() {
        let velocity = ShotController().launchVelocity(
            ballOrigin: CGPoint(x: 700, y: 270),
            dragPoint: CGPoint(x: 700, y: 115),
            sensitivity: 0.5
        )

        XCTAssertGreaterThanOrEqual(velocity.dy, 1_150)
    }

    func testFullDiagonalPullReachesRightMountedHoop() {
        let origin = CGPoint(x: 756, y: 109)
        let rimCenter = CGPoint(x: 1_414, y: 629)
        let targetVector = CGVector(
            dx: rimCenter.x - origin.x,
            dy: rimCenter.y - origin.y
        )
        let pull = targetVector.scaled(
            by: -GameTuning.maximumDragDistance / targetVector.length
        )
        let velocity = ShotController().launchVelocity(
            ballOrigin: origin,
            dragPoint: CGPoint(x: origin.x + pull.dx, y: origin.y + pull.dy),
            sensitivity: 1
        )
        let flightTime = targetVector.dx / velocity.dx
        let heightAtTarget = origin.y +
            (velocity.dy * flightTime) +
            (0.5 * GameTuning.gravity * pow(flightTime, 2))

        XCTAssertGreaterThan(velocity.dx, 0)
        XCTAssertEqual(heightAtTarget, rimCenter.y, accuracy: 4)
    }

    func testBottomEdgeCompensationAllowsFullPullFromRestingBall() {
        let calculator = ShotController()
        let origin = CGPoint(x: 700, y: 109)
        let compensated = calculator.bottomEdgeCompensatedDragPoint(
            ballOrigin: origin,
            pointerPoint: CGPoint(x: 700, y: 0)
        )
        let drag = calculator.clampedDragVector(
            ballOrigin: origin,
            dragPoint: compensated
        )

        XCTAssertEqual(drag.dy, -GameTuning.maximumDragDistance, accuracy: 0.001)
        XCTAssertEqual(drag.length, GameTuning.maximumDragDistance, accuracy: 0.001)
    }

    func testBottomEdgeCompensationDoesNotChangePullWithEnoughRoom() {
        let calculator = ShotController()
        let pointer = CGPoint(x: 680, y: 115)
        let compensated = calculator.bottomEdgeCompensatedDragPoint(
            ballOrigin: CGPoint(x: 700, y: 270),
            pointerPoint: pointer
        )

        XCTAssertEqual(compensated, pointer)
    }

    func testBottomEdgeCompensationDoesNotAmplifyUpwardDrag() {
        let calculator = ShotController()
        let pointer = CGPoint(x: 700, y: 130)
        let compensated = calculator.bottomEdgeCompensatedDragPoint(
            ballOrigin: CGPoint(x: 700, y: 109),
            pointerPoint: pointer
        )

        XCTAssertEqual(compensated, pointer)
    }
}


extension ShotCalculationTests {
    /// A corner pull used to drag the visual ball off the left edge of the
    /// screen; releasing then stranded it outside the boundary line, where its
    /// only way home was a respawn from the notch.
    func testCornerPullKeepsTheBallOnTheCourt() {
        let controller = ShotController()

        let clamped = controller.courtClampedBallPosition(
            dragPoint: CGPoint(x: -90, y: 12),
            floorY: 80,
            leftBoundaryX: 0,
            rightBoundaryX: 1_710,
            ballRadius: 25.3
        )

        XCTAssertEqual(clamped.x, 27.3, accuracy: 0.001)
        XCTAssertEqual(clamped.y, 110.3, accuracy: 0.001)
    }

    func testInteriorDragPointIsUntouched() {
        let controller = ShotController()

        let clamped = controller.courtClampedBallPosition(
            dragPoint: CGPoint(x: 600, y: 400),
            floorY: 80,
            leftBoundaryX: 0,
            rightBoundaryX: 1_710,
            ballRadius: 25.3
        )

        XCTAssertEqual(clamped.x, 600, accuracy: 0.001)
        XCTAssertEqual(clamped.y, 400, accuracy: 0.001)
    }
}

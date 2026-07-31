import XCTest
@testable import NotchBasket

final class ScoringTests: XCTestCase {
    private var controller: ScoreController!

    override func setUp() {
        super.setUp()
        controller = ScoreController()
    }

    func testDownwardUpperThenLowerCounts() {
        controller.registerUpperSensorEntry()
        XCTAssertTrue(controller.registerLowerSensorEntry(verticalVelocity: -120))
    }

    func testLowerBeforeUpperDoesNotCount() {
        XCTAssertFalse(controller.registerLowerSensorEntry(verticalVelocity: -120))
    }

    func testUpwardLowerContactDoesNotCount() {
        controller.registerUpperSensorEntry()
        XCTAssertFalse(controller.registerLowerSensorEntry(verticalVelocity: 80))
    }

    func testSameShotCannotScoreTwice() {
        controller.registerUpperSensorEntry()
        XCTAssertTrue(controller.registerLowerSensorEntry(verticalVelocity: -100))
        XCTAssertFalse(controller.registerLowerSensorEntry(verticalVelocity: -100))
    }

    func testResetAllowsNextShotToScore() {
        controller.registerUpperSensorEntry()
        XCTAssertTrue(controller.registerLowerSensorEntry(verticalVelocity: -100))
        controller.resetForNewShot()
        controller.registerUpperSensorEntry()
        XCTAssertTrue(controller.registerLowerSensorEntry(verticalVelocity: -100))
    }
}


final class ShotClockTests: XCTestCase {
    func testClockIsArmedButNotRunningUntilTheFirstGrab() {
        let clock = ShotClockController()

        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.remaining(at: 1_000), 24, accuracy: 0.001)
        XCTAssertEqual(clock.checkExpiry(at: 1_000, ballInFlight: false), .none)
    }

    func testFirstGrabStartsTheClockAndLaterGrabsDoNot() {
        let clock = ShotClockController()

        clock.ballGrabbed(at: 100)
        XCTAssertEqual(clock.remaining(at: 110), 14, accuracy: 0.001)

        // Picking the ball up again mid-run must not refresh the deadline.
        clock.ballGrabbed(at: 110)
        XCTAssertEqual(clock.remaining(at: 110), 14, accuracy: 0.001)
    }

    func testScoreBuysAFresh24AndCountsThePoint() {
        let clock = ShotClockController()
        clock.ballGrabbed(at: 100)

        clock.registerScore(at: 110)

        XCTAssertEqual(clock.runScore, 1)
        XCTAssertEqual(clock.remaining(at: 110), 24, accuracy: 0.001)
    }

    func testScoreBeforeTheClockStartsCountsNothing() {
        let clock = ShotClockController()

        clock.registerScore(at: 100)

        XCTAssertEqual(clock.runScore, 0)
        XCTAssertFalse(clock.isRunning)
    }

    func testExpiryWithBallIdleIsAnImmediateViolation() {
        let clock = ShotClockController()
        clock.ballGrabbed(at: 100)

        XCTAssertEqual(clock.checkExpiry(at: 123.9, ballInFlight: false), .none)
        XCTAssertEqual(
            clock.checkExpiry(at: 124, ballInFlight: false),
            .violation
        )
    }

    func testBuzzerBeaterKeepsTheRunAlive() {
        let clock = ShotClockController()
        clock.ballGrabbed(at: 100)

        // The horn sounds while the shot is in the air: no verdict yet.
        XCTAssertEqual(
            clock.checkExpiry(at: 124.5, ballInFlight: true),
            .awaitingShot
        )
        XCTAssertTrue(clock.isAwaitingBuzzerBeater)

        // It drops: the point counts and a fresh 24 starts.
        clock.registerScore(at: 125)
        XCTAssertEqual(clock.runScore, 1)
        XCTAssertFalse(clock.isAwaitingBuzzerBeater)
        XCTAssertEqual(clock.remaining(at: 125), 24, accuracy: 0.001)
    }

    func testEndRunReportsTheScoreAndDisarms() {
        let clock = ShotClockController()
        clock.ballGrabbed(at: 100)
        clock.registerScore(at: 105)
        clock.registerScore(at: 112)

        let finished = clock.endRun(at: 140, ballHeld: false)

        XCTAssertEqual(finished, 2)
        XCTAssertEqual(clock.runScore, 0)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.remaining(at: 140), 24, accuracy: 0.001)
    }

    func testViolationWhileHoldingTheBallStartsTheNextRunImmediately() {
        let clock = ShotClockController()
        clock.ballGrabbed(at: 100)

        // The horn catches the player mid-aim: the ball in hand is already the
        // first grab of the next run.
        _ = clock.endRun(at: 124, ballHeld: true)

        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.remaining(at: 130), 18, accuracy: 0.001)
    }

    func testModeChangeWipesTheRunWithoutRecordingIt() {
        let clock = ShotClockController()
        clock.ballGrabbed(at: 100)
        clock.registerScore(at: 105)

        clock.resetForModeChange()

        XCTAssertEqual(clock.runScore, 0)
        XCTAssertFalse(clock.isRunning)
        XCTAssertFalse(clock.isAwaitingBuzzerBeater)
    }
}

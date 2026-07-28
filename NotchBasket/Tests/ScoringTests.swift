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

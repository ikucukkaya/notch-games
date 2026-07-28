import XCTest
@testable import NotchBasket

final class PersistenceTests: XCTestCase {
    private let suiteName = "NotchBasketTests.Preferences"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsAreUsable() {
        let preferences = PreferencesService(defaults: defaults)

        XCTAssertTrue(preferences.soundEnabled)
        XCTAssertTrue(preferences.showScore)
        XCTAssertEqual(preferences.gravityPreset, .normal)
        XCTAssertEqual(preferences.bestStreak, 0)
    }

    func testBestStreakOnlyMovesUp() {
        let preferences = PreferencesService(defaults: defaults)

        preferences.registerBasket(streak: 4)
        preferences.registerBasket(streak: 2)

        XCTAssertEqual(preferences.bestStreak, 4)
        XCTAssertEqual(preferences.lifetimeBaskets, 2)
    }

    func testHighScoreResetClearsPersistentStatistics() {
        let preferences = PreferencesService(defaults: defaults)
        preferences.registerShot()
        preferences.registerBasket(streak: 3)

        preferences.resetHighScores()

        XCTAssertEqual(preferences.bestStreak, 0)
        XCTAssertEqual(preferences.lifetimeBaskets, 0)
        XCTAssertEqual(preferences.lifetimeShots, 0)
    }

    func testInvalidPersistedValuesAreClampedOrReplaced() {
        defaults.set(9.0, forKey: "masterVolume")
        defaults.set("impossible", forKey: "gravityPreset")

        let preferences = PreferencesService(defaults: defaults)

        XCTAssertEqual(preferences.masterVolume, 1)
        XCTAssertEqual(preferences.gravityPreset, .normal)
    }
}

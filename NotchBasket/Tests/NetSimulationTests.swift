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
}

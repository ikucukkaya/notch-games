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
}

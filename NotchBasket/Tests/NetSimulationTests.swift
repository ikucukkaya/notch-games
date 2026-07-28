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
}

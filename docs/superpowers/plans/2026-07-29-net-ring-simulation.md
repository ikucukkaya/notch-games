# Net Ring Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace NotchBasket's split cloth/funnel/swish net with a single cone-of-revolution ring stack that couples to the ball in both directions.

**Architecture:** The net is modelled as 11 stacked horizontal cord loops (rings). Each ring is a circle in 3D with exactly three degrees of freedom — stretch (`radius`), sag (`centerY`), sway (`centerX`) — so the drawn diamond weave is *derived* from ring state rather than simulated independently. The ball and the rings exchange equal-and-opposite forces through one contact formula, so the same code path handles a swish, a rim-out, a side brush, and a hit from underneath.

**Tech Stack:** Swift 5, SpriteKit, XCTest, hand-authored `.xcodeproj` (macOS app, no SwiftPM, no third-party packages).

**Spec:** `docs/superpowers/specs/2026-07-29-net-ring-simulation-design.md`

## Global Constraints

- Target platform macOS only; build with `-destination 'platform=macOS'`.
- No third-party packages, no private APIs, no network access. Do not add dependencies.
- The repo path contains a space (`~/Documents/notch toys`) — always quote it in shell commands.
- `NotchBasket.xcodeproj` has **zero** `PBXFileSystemSynchronizedRootGroup` entries. Every new Swift file requires four `project.pbxproj` edits: `PBXBuildFile`, `PBXFileReference`, the owning `PBXGroup` children list, and the target's `PBXSourcesBuildPhase` files list. Task 0 does this once for both new files.
- Tests reach app code via `@testable import NotchBasket`.
- Existing geometry constants are authoritative and must not be changed: `GameTuning.rimPostOffset = 54`, `GameTuning.rimPostRadius = 5.5`, `GameTuning.rimY = -78`, `SideHoopLayout.rimDepth = 10`.
- Net z-order must stay exactly as it is (`rearOutline` −1, `rearMesh` 0, `frontOutline` 19, `frontMesh` 20) so the ball at effective z=30 keeps rendering between the rear and front cords.
- Never write to `~/Documents/notch toys copy` — it is a stale duplicate.
- Do not launch the app unattended; it is a screen-covering overlay. All verification in this plan is via `xcodebuild test`, which needs no display interaction.

---

### Task 0: Register new files and confirm the baseline

**Files:**
- Create: `NotchBasket/Nodes/NetRingSimulation.swift`
- Create: `NotchBasket/Tests/NetSimulationTests.swift`
- Modify: `NotchBasket.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces: two compiled-but-empty files that later tasks fill in. Reserved IDs — source file `F00000000000000000000019` / `B00000000000000000000019`, test file `F00000000000000000000105` / `B00000000000000000000105`.

- [ ] **Step 1: Confirm the existing suite is green before touching anything**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`. If this fails, stop and report — do not start the rewrite on a red baseline.

- [ ] **Step 2: Create the source file with a placeholder-free stub**

Create `NotchBasket/Nodes/NetRingSimulation.swift`:

```swift
import CoreGraphics
import Foundation

/// One horizontal cord loop of the net. The net is a cone of revolution seen
/// from the side, so a loop needs only three degrees of freedom: how far it has
/// stretched, how far it has sagged, and how far its centre has swung sideways.
/// Everything the renderer draws is derived from these three numbers, which is
/// why the cords can never tangle.
struct NetRing {
    var radius: CGFloat
    var centerX: CGFloat
    var centerY: CGFloat

    var radiusVelocity: CGFloat = 0
    var centerXVelocity: CGFloat = 0
    var centerYVelocity: CGFloat = 0

    let restRadius: CGFloat
    let restCenterY: CGFloat
    let isPinned: Bool
}
```

- [ ] **Step 3: Create the test file with one trivially passing test**

Create `NotchBasket/Tests/NetSimulationTests.swift`:

```swift
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
```

- [ ] **Step 4: Add the `PBXBuildFile` entries**

In `NotchBasket.xcodeproj/project.pbxproj`, find the line containing `B00000000000000000000018 /* AuxiliaryWindowControllers.swift in Sources */ = {isa = PBXBuildFile;` and add immediately after it:

```
		B00000000000000000000019 /* NetRingSimulation.swift in Sources */ = {isa = PBXBuildFile; fileRef = F00000000000000000000019 /* NetRingSimulation.swift */; };
```

Find the line containing `B00000000000000000000104 /* PersistenceTests.swift in Sources */ = {isa = PBXBuildFile;` and add immediately after it:

```
		B00000000000000000000105 /* NetSimulationTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = F00000000000000000000105 /* NetSimulationTests.swift */; };
```

- [ ] **Step 5: Add the `PBXFileReference` entries**

Find the line containing `F00000000000000000000018 /* AuxiliaryWindowControllers.swift */ = {isa = PBXFileReference;` and add immediately after it:

```
		F00000000000000000000019 /* NetRingSimulation.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NetRingSimulation.swift; sourceTree = "<group>"; };
```

Find the line containing `F00000000000000000000104 /* PersistenceTests.swift */ = {isa = PBXFileReference;` and add immediately after it:

```
		F00000000000000000000105 /* NetSimulationTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NetSimulationTests.swift; sourceTree = "<group>"; };
```

- [ ] **Step 6: Add both files to their groups**

In the `A00000000000000000000014 /* Nodes */` group, change the children list to:

```
			children = (
				F0000000000000000000000F /* BasketballNode.swift */,
				F00000000000000000000010 /* HoopNode.swift */,
				F00000000000000000000011 /* AimIndicatorNode.swift */,
				F00000000000000000000019 /* NetRingSimulation.swift */,
			);
```

In the `A00000000000000000000018 /* Tests */` group, change the children list to:

```
			children = (
				F00000000000000000000101 /* GeometryTests.swift */,
				F00000000000000000000102 /* ShotCalculationTests.swift */,
				F00000000000000000000103 /* ScoringTests.swift */,
				F00000000000000000000104 /* PersistenceTests.swift */,
				F00000000000000000000105 /* NetSimulationTests.swift */,
			);
```

- [ ] **Step 7: Add both files to their build phases**

In the app target's sources phase (`A00000000000000000000211 /* Sources */`), add after the `B00000000000000000000018 /* AuxiliaryWindowControllers.swift in Sources */,` line:

```
				B00000000000000000000019 /* NetRingSimulation.swift in Sources */,
```

In the test target's sources phase (`A00000000000000000000212 /* Sources */`), add after the `B00000000000000000000104 /* PersistenceTests.swift in Sources */,` line:

```
				B00000000000000000000105 /* NetSimulationTests.swift in Sources */,
```

- [ ] **Step 8: Verify both files actually compile into their targets**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **` and `Executed 1 test`. If it reports "no tests were found", the pbxproj wiring is wrong — recheck Steps 4–7 rather than moving on.

- [ ] **Step 9: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/NetRingSimulation.swift NotchBasket/Tests/NetSimulationTests.swift NotchBasket.xcodeproj/project.pbxproj && git commit -m "chore: register NetRingSimulation source and test files"
```

---

### Task 1: Ring rest state, pinning, and restoring springs

**Files:**
- Modify: `NotchBasket/Nodes/NetRingSimulation.swift`
- Test: `NotchBasket/Tests/NetSimulationTests.swift`

**Interfaces:**
- Consumes: `NetRing` from Task 0.
- Produces: `NetRingSimulation` with `static let ringCount = 11`, `static let topHalfWidth: CGFloat`, `static let bottomHalfWidth: CGFloat`, `static let depth: CGFloat`, `private(set) var rings: [NetRing]`, `func step(deltaTime: CGFloat)`, `func displacementFromRest() -> CGFloat`.

- [ ] **Step 1: Write the failing tests**

Add to `NetSimulationTests.swift` inside `final class NetSimulationTests`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -20
```

Expected: compile failure, `cannot find 'NetRingSimulation' in scope`.

- [ ] **Step 3: Implement the simulation core**

Append to `NotchBasket/Nodes/NetRingSimulation.swift`:

```swift
/// The net, modelled as a stack of cord loops. Rendering and ball contact both
/// read this one model, so the net can never look like it is doing something
/// different from what the ball feels.
final class NetRingSimulation {
    static let ringCount = 11
    static let topHalfWidth: CGFloat =
        GameTuning.rimPostOffset - GameTuning.rimPostRadius

    /// Deliberately narrower than the ball's 24-point radius. The old cloth
    /// model used 31, which is wider than the ball — a dead-centre shot could
    /// fall the whole length of the net without touching a single cord, so the
    /// net never billowed on a clean swish. A real net's hem is narrower than
    /// the ball and has to be stretched open by it; that stretch is the swish.
    static let bottomHalfWidth: CGFloat = 18
    static let depth: CGFloat = 76

    private(set) var rings: [NetRing] = []

    // Stretch resists hardest because cords barely lengthen; sway is loosest
    // because the whole skirt can swing without any cord changing length.
    private let radiusStiffness: CGFloat = 260
    private let sagStiffness: CGFloat = 150
    private let swayStiffness: CGFloat = 70
    private let radiusDamping: CGFloat = 9
    private let sagDamping: CGFloat = 7
    private let swayDamping: CGFloat = 6
    private let ringGravity: CGFloat = -30

    private let substepDuration: CGFloat = 1.0 / 240.0

    init() {
        buildRings()
    }

    func displacementFromRest() -> CGFloat {
        rings.reduce(0) { total, ring in
            total
                + abs(ring.radius - ring.restRadius)
                + abs(ring.centerY - ring.restCenterY)
                + abs(ring.centerX)
        }
    }

    /// Test seam: pushes every free ring off its rest state in all three
    /// degrees of freedom so relaxation behaviour can be measured.
    func disturbForTesting(
        radiusOffset: CGFloat,
        sagOffset: CGFloat,
        swayOffset: CGFloat
    ) {
        for index in rings.indices where !rings[index].isPinned {
            rings[index].radius += radiusOffset
            rings[index].centerY += sagOffset
            rings[index].centerX += swayOffset
        }
    }

    func step(deltaTime: CGFloat) {
        let time = min(max(deltaTime, 0), 1.0 / 30.0)
        guard time > 0 else { return }
        let substepCount = max(1, Int(ceil(time / substepDuration)))
        let substep = time / CGFloat(substepCount)
        for _ in 0..<substepCount {
            integrate(deltaTime: substep)
        }
    }

    private func buildRings() {
        rings.removeAll(keepingCapacity: true)
        for index in 0..<Self.ringCount {
            let fraction = CGFloat(index) / CGFloat(Self.ringCount - 1)
            let restRadius = Self.topHalfWidth
                + ((Self.bottomHalfWidth - Self.topHalfWidth) * fraction)
            let restCenterY = -Self.depth * pow(fraction, 1.04)
            rings.append(NetRing(
                radius: restRadius,
                centerX: 0,
                centerY: restCenterY,
                restRadius: restRadius,
                restCenterY: restCenterY,
                isPinned: index == 0
            ))
        }
    }

    private func integrate(deltaTime: CGFloat) {
        for index in rings.indices where !rings[index].isPinned {
            let ring = rings[index]

            let radiusAcceleration =
                (-radiusStiffness * (ring.radius - ring.restRadius))
                - (radiusDamping * ring.radiusVelocity)
            let sagAcceleration =
                (-sagStiffness * (ring.centerY - ring.restCenterY))
                - (sagDamping * ring.centerYVelocity)
                + ringGravity
            let swayAcceleration =
                (-swayStiffness * ring.centerX)
                - (swayDamping * ring.centerXVelocity)

            rings[index].radiusVelocity += radiusAcceleration * deltaTime
            rings[index].centerYVelocity += sagAcceleration * deltaTime
            rings[index].centerXVelocity += swayAcceleration * deltaTime

            rings[index].radius += rings[index].radiusVelocity * deltaTime
            rings[index].centerY += rings[index].centerYVelocity * deltaTime
            rings[index].centerX += rings[index].centerXVelocity * deltaTime
        }
        enforceRingOrder()
    }

    /// The loops are stacked, so loop i can never rise above loop i-1. Enforcing
    /// that ordering is what makes cord tangling structurally impossible rather
    /// than something the solver has to be tuned away from.
    ///
    /// Radius is clamped to absolute bounds only, never against the loop above.
    /// A ball forces the hem wider than the loops above it — that is the whole
    /// point of a net — so a monotonic-radius constraint would fight the ball.
    private func enforceRingOrder() {
        let minimumRadius = Self.bottomHalfWidth * 0.35
        let maximumRadius = Self.topHalfWidth * 1.8
        for index in 1..<rings.count {
            let minimumDrop: CGFloat = 1.5
            let ceilingY = rings[index - 1].centerY - minimumDrop
            if rings[index].centerY > ceilingY {
                rings[index].centerY = ceilingY
                rings[index].centerYVelocity = min(rings[index].centerYVelocity, 0)
            }
            if rings[index].radius > maximumRadius {
                rings[index].radius = maximumRadius
                rings[index].radiusVelocity = min(rings[index].radiusVelocity, 0)
            }
            if rings[index].radius < minimumRadius {
                rings[index].radius = minimumRadius
                rings[index].radiusVelocity = max(rings[index].radiusVelocity, 0)
            }
        }
    }
}
```

Note on `ringGravity`: it biases the rest sag slightly downward, so `testRingsNarrowAndDescendMonotonically` asserts on `restCenterY` (the authored rest state) rather than on live `centerY`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, `Executed 5 tests`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/NetRingSimulation.swift NotchBasket/Tests/NetSimulationTests.swift && git commit -m "feat: add net ring rest state, pinning, and restoring springs"
```

---

### Task 2: Cord coupling so deformation travels down the net

**Files:**
- Modify: `NotchBasket/Nodes/NetRingSimulation.swift`
- Test: `NotchBasket/Tests/NetSimulationTests.swift`

**Interfaces:**
- Consumes: `NetRingSimulation` from Task 1.
- Produces: cord-length and sway coupling inside `integrate(deltaTime:)`. No new public API.

Cords run between neighbouring loops and barely stretch. If one loop is forced wider, the cord length has to come from somewhere, so the loop below is pulled up and inward — this is what makes a real net cinch around the ball and then snap back.

- [ ] **Step 1: Write the failing tests**

Add to `NetSimulationTests.swift`:

```swift
    func testWideningOneRingPullsTheRingBelowUpwardAndInward() {
        let simulation = NetRingSimulation()
        let restCenterY = simulation.rings[5].restCenterY
        let restRadius = simulation.rings[5].restRadius
        simulation.widenRingForTesting(at: 4, by: 22)

        for _ in 0..<12 {
            simulation.step(deltaTime: 1.0 / 60.0)
        }

        XCTAssertGreaterThan(simulation.rings[5].centerY, restCenterY)
        XCTAssertLessThan(simulation.rings[5].radius, restRadius)
    }

    func testDeformationWavePropagatesDownward() {
        let simulation = NetRingSimulation()
        simulation.widenRingForTesting(at: 2, by: 20)

        var ringThreeMovedAtStep: Int?
        var ringSevenMovedAtStep: Int?
        for stepIndex in 0..<90 {
            simulation.step(deltaTime: 1.0 / 240.0)
            let threeMoved = abs(
                simulation.rings[3].centerY - simulation.rings[3].restCenterY
            ) > 0.05
            let sevenMoved = abs(
                simulation.rings[7].centerY - simulation.rings[7].restCenterY
            ) > 0.05
            if threeMoved, ringThreeMovedAtStep == nil {
                ringThreeMovedAtStep = stepIndex
            }
            if sevenMoved, ringSevenMovedAtStep == nil {
                ringSevenMovedAtStep = stepIndex
            }
        }

        guard let three = ringThreeMovedAtStep, let seven = ringSevenMovedAtStep else {
            return XCTFail("the disturbance never reached both rings")
        }
        XCTAssertLessThan(
            three,
            seven,
            "the disturbance must reach ring 3 before ring 7"
        )
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -20
```

Expected: compile failure, `value of type 'NetRingSimulation' has no member 'widenRingForTesting'`.

- [ ] **Step 3: Add the test seam and the coupling forces**

Add to `NetRingSimulation`, next to `disturbForTesting`:

```swift
    /// Test seam: stretches one loop the way a ball passing through would,
    /// without needing a ball.
    func widenRingForTesting(at index: Int, by amount: CGFloat) {
        guard rings.indices.contains(index), !rings[index].isPinned else { return }
        rings[index].radius += amount
    }
```

Add the stored cord rest lengths. Insert this property next to the other constants:

```swift
    private let cordStiffness: CGFloat = 340
    private let swayCoupling: CGFloat = 120
    private var cordRestLengths: [CGFloat] = []
```

At the end of `buildRings()`, append:

```swift
        cordRestLengths = (0..<(rings.count - 1)).map { index in
            let dropDistance = rings[index].restCenterY - rings[index + 1].restCenterY
            let radiusDifference = rings[index].restRadius - rings[index + 1].restRadius
            return hypot(dropDistance, radiusDifference)
        }
```

In `integrate(deltaTime:)`, insert this call immediately before `enforceRingOrder()`:

```swift
        applyCordCoupling(deltaTime: deltaTime)
```

And add the method:

```swift
    /// Cords barely stretch, so the distance between neighbouring loops — a
    /// combination of drop and radius change — is what actually resists. When a
    /// ball forces one loop open, this is the term that hauls the loop below it
    /// up and in, and later throws the net back out.
    private func applyCordCoupling(deltaTime: CGFloat) {
        for index in 0..<(rings.count - 1) {
            let upper = rings[index]
            let lower = rings[index + 1]
            let dropDistance = upper.centerY - lower.centerY
            let radiusDifference = upper.radius - lower.radius
            let length = max(hypot(dropDistance, radiusDifference), 0.001)
            let stretch = length - cordRestLengths[index]
            let force = cordStiffness * stretch
            let dropAxis = dropDistance / length
            let radiusAxis = radiusDifference / length

            if !rings[index].isPinned {
                rings[index].centerYVelocity -= force * dropAxis * deltaTime
                rings[index].radiusVelocity -= force * radiusAxis * deltaTime
            }
            rings[index + 1].centerYVelocity += force * dropAxis * deltaTime
            rings[index + 1].radiusVelocity += force * radiusAxis * deltaTime

            // Sway is carried down the skirt rather than resisted: each loop is
            // dragged toward the lateral position of the one above it.
            let swayDifference = upper.centerX - lower.centerX
            rings[index + 1].centerXVelocity +=
                swayCoupling * swayDifference * deltaTime
            if !rings[index].isPinned {
                rings[index].centerXVelocity -=
                    swayCoupling * swayDifference * deltaTime * 0.35
            }
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, `Executed 7 tests`. If `testDisturbedNetDampsBackTowardRest` now fails, the cord springs added energy faster than damping removes it — raise `radiusDamping` and `sagDamping` together until it settles, rather than weakening `cordStiffness`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/NetRingSimulation.swift NotchBasket/Tests/NetSimulationTests.swift && git commit -m "feat: couple net rings through cord length so deformation propagates"
```

---

### Task 3: Ball deforms the net

**Files:**
- Modify: `NotchBasket/Nodes/NetRingSimulation.swift`
- Test: `NotchBasket/Tests/NetSimulationTests.swift`

**Interfaces:**
- Consumes: `NetRingSimulation` from Task 2.
- Produces: `struct NetRingContact { let position: CGPoint; let velocity: CGVector; let radius: CGFloat }` and `func step(deltaTime: CGFloat, contact: NetRingContact?, responseScale: CGFloat)`. The single-argument `step(deltaTime:)` from Task 1 stays as a convenience that forwards `contact: nil, responseScale: 1`.

Every ring is a circle in 3D. Contact is measured as the distance from the ball's centre to the **nearest point on that circle**, which is why one formula covers the ball being inside, outside, above, or below the net.

- [ ] **Step 1: Write the failing tests**

Add to `NetSimulationTests.swift`:

```swift
    private func descendingContact(y: CGFloat, x: CGFloat = 0) -> NetRingContact {
        NetRingContact(
            position: CGPoint(x: x, y: y),
            velocity: CGVector(dx: 0, dy: -600),
            radius: GameTuning.ballDiameter / 2
        )
    }

    func testDescendingBallStretchesTheHemOpen() {
        let simulation = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let restRadius = simulation.rings[bottomIndex].restRadius

        for _ in 0..<6 {
            simulation.step(
                deltaTime: 1.0 / 60.0,
                contact: descendingContact(
                    y: simulation.rings[bottomIndex].restCenterY
                ),
                responseScale: 1
            )
        }

        XCTAssertGreaterThan(simulation.rings[bottomIndex].radius, restRadius + 0.5)
    }

    func testBallBelowTheHemPushesTheBottomRingUpward() {
        let simulation = NetRingSimulation()
        let control = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let contact = NetRingContact(
            position: CGPoint(
                x: 0,
                y: simulation.rings[bottomIndex].restCenterY - 8
            ),
            velocity: CGVector(dx: 0, dy: 520),
            radius: GameTuning.ballDiameter / 2
        )

        // Gravity sags every ring slightly below its authored rest position, so
        // the control run — identical but untouched — is the only honest
        // baseline for what the contact alone did.
        for _ in 0..<6 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            control.step(deltaTime: 1.0 / 60.0, contact: nil, responseScale: 1)
        }

        XCTAssertGreaterThan(
            simulation.rings[bottomIndex].centerY,
            control.rings[bottomIndex].centerY
        )
    }

    func testBallBrushingOneSidePushesTheNetTheOtherWay() {
        let simulation = NetRingSimulation()
        let contact = NetRingContact(
            position: CGPoint(x: NetRingSimulation.topHalfWidth, y: -30),
            velocity: CGVector(dx: -240, dy: -120),
            radius: GameTuning.ballDiameter / 2
        )

        for _ in 0..<8 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
        }

        XCTAssertLessThan(
            simulation.rings[4].centerX,
            -0.2,
            "a ball outside the cone must push the cords away from it, not toward it"
        )
    }

    func testFastBallDoesNotTunnelThroughNet() {
        let simulation = NetRingSimulation()
        // One 60 Hz frame carries the ball from the rim plane to below the hem,
        // so only the swept substeps can see the contact at all.
        let contact = NetRingContact(
            position: CGPoint(x: 0, y: -110),
            velocity: CGVector(dx: 0, dy: -6_600),
            radius: GameTuning.ballDiameter / 2
        )

        simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)

        // The ball is already gone. What it left behind is velocity, so the net
        // visibly moves over the frames that follow — measuring position at the
        // instant of crossing would sample before any of it has happened.
        for _ in 0..<6 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: nil, responseScale: 1)
        }

        XCTAssertGreaterThan(
            simulation.displacementFromRest(),
            1,
            "a ball crossing the whole net in one frame must still disturb it"
        )

        // The displacement alone does not gate the sweep resolution — with and
        // without refinement it clears the threshold. Whether the ball is caught
        // against more than one loop does: unrefined, only ring 10 registers
        // (ring 9 deviates 0.0411); refined, ring 9 deviates 0.1567.
        let disturbedRings = simulation.rings.filter {
            abs($0.radius - $0.restRadius) > 0.05
        }
        XCTAssertGreaterThanOrEqual(
            disturbedRings.count,
            2,
            "the swept substeps must catch the ball against more than one loop"
        )
    }

    func testRingOrderSurvivesSevereContact() {
        let simulation = NetRingSimulation()

        for stepIndex in 0..<120 {
            let sweepY = CGFloat(stepIndex)
                .truncatingRemainder(dividingBy: 20) * -6
            simulation.step(
                deltaTime: 1.0 / 60.0,
                contact: NetRingContact(
                    position: CGPoint(x: sin(CGFloat(stepIndex)) * 40, y: sweepY),
                    velocity: CGVector(dx: 900, dy: -1_400),
                    radius: GameTuning.ballDiameter / 2
                ),
                responseScale: 1
            )

            for index in 1..<NetRingSimulation.ringCount {
                XCTAssertLessThan(
                    simulation.rings[index].centerY,
                    simulation.rings[index - 1].centerY,
                    "ring \(index) rose above ring \(index - 1) at step \(stepIndex)"
                )
                XCTAssertGreaterThan(simulation.rings[index].radius, 0)
            }
        }
    }

    func testReducedMotionScalesNetResponse() {
        let full = NetRingSimulation()
        let reduced = NetRingSimulation()
        let contact = descendingContact(y: -64)

        for _ in 0..<10 {
            full.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            reduced.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 0.38)
        }

        XCTAssertLessThan(reduced.displacementFromRest(), full.displacementFromRest())
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -20
```

Expected: compile failure, `cannot find type 'NetRingContact' in scope`.

- [ ] **Step 3: Add the contact type and deformation**

Add near the top of `NetRingSimulation.swift`, after `NetRing`:

```swift
/// The ball as the net sees it, expressed in the net's own coordinate space.
struct NetRingContact {
    let position: CGPoint
    let velocity: CGVector
    let radius: CGFloat
}

/// Where a ball touches one cord loop, and how deeply.
struct NetRingTouch {
    let ringIndex: Int
    /// How far the ball's surface has passed the cord.
    let penetration: CGFloat
    /// Unit normal in (radial, vertical) space, pointing from cord to ball.
    let radialNormal: CGFloat
    let verticalNormal: CGFloat
    /// +1 when the ball is on the +x side of the loop's axis, −1 otherwise.
    let lateralSign: CGFloat
    /// How far off the loop's axis the ball is, 0 (dead centre) to 1 (at the
    /// cord). Scales every lateral term: a ball on the axis is pushed by the
    /// whole loop equally from all sides, so its sideways components cancel and
    /// only the vertical one survives. Without this the radial direction is
    /// undefined at the axis and a perfectly centred swish gets kicked sideways.
    let axialFraction: CGFloat
}
```

Add these constants to `NetRingSimulation`:

```swift
    // Sized from the equilibrium a dwelling ball reaches: the contact push
    // balances the ring's restoring spring at
    //   contactStiffness * (ballRadius - r) == radiusStiffness * (r - restRadius)
    // so k = 600 lets the hem settle at r ~= 22.2 against a ball of radius 24 —
    // stretched most of the way open, which is what a real hem does. An order of
    // magnitude lower and the net barely moves with a ball inside it.
    private let contactStiffness: CGFloat = 600
    private let contactSwayShare: CGFloat = 0.45

    /// A stiff contact spring with no dashpot overshoots by construction, and at
    /// this stiffness the overshoot was large enough to invert ring order — the
    /// ordering clamp was catching it in ~8.5% of substeps under hard contact
    /// instead of sitting idle as a backstop. Critical damping for k = 600 on a
    /// unit ring mass is about 49; staying under that keeps the net springy while
    /// removing the overshoot. Damping vanishes at steady state, so the hem still
    /// settles where the equilibrium says it should.
    private let contactDamping: CGFloat = 30

    /// A fast shot crosses the whole net inside one display frame. Sampling by
    /// elapsed time alone would step the ball straight over the cords, so the
    /// sweep is refined until each substep advances it only a few points — well
    /// under a ring's spacing.
    private let maximumBallTravelPerSubstep: CGFloat = 4
    private let maximumSubstepCount = 64
```

Replace `step(deltaTime:)` with:

```swift
    func step(deltaTime: CGFloat) {
        step(deltaTime: deltaTime, contact: nil, responseScale: 1)
    }

    func step(
        deltaTime: CGFloat,
        contact: NetRingContact?,
        responseScale: CGFloat
    ) {
        let time = min(max(deltaTime, 0), 1.0 / 30.0)
        guard time > 0 else { return }
        let scale = min(max(responseScale, 0), 1)
        var substepCount = max(1, Int(ceil(time / substepDuration)))
        if let contact {
            let travel = hypot(contact.velocity.dx, contact.velocity.dy) * time
            substepCount = max(substepCount, Int(ceil(travel / maximumBallTravelPerSubstep)))
        }
        substepCount = min(substepCount, maximumSubstepCount)
        let substep = time / CGFloat(substepCount)

        // Sweep the ball along its path across the substeps so a fast shot
        // cannot skip over the cords between two display frames.
        let startPosition = contact.map {
            CGPoint(
                x: $0.position.x - ($0.velocity.dx * time),
                y: $0.position.y - ($0.velocity.dy * time)
            )
        }

        for substepIndex in 0..<substepCount {
            var swept = contact
            if let contact, let startPosition {
                let progress = CGFloat(substepIndex + 1) / CGFloat(substepCount)
                swept = NetRingContact(
                    position: CGPoint(
                        x: startPosition.x
                            + ((contact.position.x - startPosition.x) * progress),
                        y: startPosition.y
                            + ((contact.position.y - startPosition.y) * progress)
                    ),
                    velocity: contact.velocity,
                    radius: contact.radius
                )
            }
            integrate(deltaTime: substep)
            if let swept, swept.radius > 0, scale > 0 {
                applyContact(swept, deltaTime: substep, responseScale: scale)
            }
        }
    }
```

Add the contact geometry and its effect on the rings:

```swift
    /// Distance from the ball's centre to the nearest point on a cord loop.
    /// One formula, so a ball inside the net, outside it, above it, or below it
    /// all take the same path — scoring is never a condition.
    private func touches(for contact: NetRingContact) -> [NetRingTouch] {
        guard contact.radius > 0 else { return [] }
        var result: [NetRingTouch] = []
        for index in rings.indices where !rings[index].isPinned {
            let ring = rings[index]
            let lateralOffset = contact.position.x - ring.centerX
            let axialDistance = abs(lateralOffset)
            let radial = axialDistance - ring.radius
            let vertical = contact.position.y - ring.centerY
            let distance = hypot(radial, vertical)
            let penetration = contact.radius - distance
            guard penetration > 0 else { continue }

            let safeDistance = max(distance, 0.001)
            result.append(NetRingTouch(
                ringIndex: index,
                penetration: penetration,
                radialNormal: radial / safeDistance,
                verticalNormal: vertical / safeDistance,
                lateralSign: lateralOffset >= 0 ? 1 : -1,
                axialFraction: min(axialDistance / max(ring.radius, 0.001), 1)
            ))
        }
        return result
    }

    private func applyContact(
        _ contact: NetRingContact,
        deltaTime: CGFloat,
        responseScale: CGFloat
    ) {
        for touch in touches(for: contact) {
            let impulse = contactStiffness * touch.penetration
                * responseScale * deltaTime
            // The cord is pushed the opposite way from the ball's normal, so a
            // ball inside the cone opens the loop and a ball outside squeezes it.
            rings[touch.ringIndex].radiusVelocity -= impulse * touch.radialNormal
            rings[touch.ringIndex].centerYVelocity -= impulse * touch.verticalNormal
            rings[touch.ringIndex].centerXVelocity -=
                impulse * contactSwayShare
                * touch.radialNormal * touch.lateralSign * touch.axialFraction

            // Oppose the ring's velocity along the push direction. Without this
            // the ordering clamp becomes the primary stabiliser rather than a
            // backstop.
            let pushRadius = -touch.radialNormal
            let pushVertical = -touch.verticalNormal
            let normalVelocity =
                (rings[touch.ringIndex].radiusVelocity * pushRadius)
                + (rings[touch.ringIndex].centerYVelocity * pushVertical)
            let damping = contactDamping * normalVelocity * responseScale * deltaTime
            rings[touch.ringIndex].radiusVelocity -= damping * pushRadius
            rings[touch.ringIndex].centerYVelocity -= damping * pushVertical
        }
    }
```

Add one more test covering the dashpot. Without it, `contactDamping` could be
set to 0 and every other test would still pass — the ordering clamp would take
over the stabilising silently.

```swift
    func testContactDampingKeepsTheHemFromOvershooting() {
        let simulation = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let contact = descendingContact(
            y: simulation.rings[bottomIndex].restCenterY
        )

        var peak = simulation.rings[bottomIndex].radius
        for _ in 0..<180 {
            simulation.step(deltaTime: 1.0 / 60.0, contact: contact, responseScale: 1)
            peak = max(peak, simulation.rings[bottomIndex].radius)
        }
        let settled = simulation.rings[bottomIndex].radius

        // Damped the hem peaks 0.164 above where it settles; undamped it peaks
        // 2.365 above. The threshold sits between those two measurements.
        XCTAssertLessThan(peak - settled, 1.0)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, `Executed 14 tests`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/NetRingSimulation.swift NotchBasket/Tests/NetSimulationTests.swift && git commit -m "feat: deform net rings from ball contact using nearest-point-on-loop"
```

---

### Task 4: Net pushes back on the ball

**Files:**
- Modify: `NotchBasket/Nodes/NetRingSimulation.swift`
- Test: `NotchBasket/Tests/NetSimulationTests.swift`

**Interfaces:**
- Consumes: `NetRingTouch` and `touches(for:)` from Task 3.
- Produces: `struct NetGrip { let normal: CGFloat; let drag: CGFloat }`, `static func grip(penetration: CGFloat, ballRadius: CGFloat) -> NetGrip`, and `step` returning `CGVector` (the force to hand to the ball's physics body).

This is the half that was missing: the net now returns a force instead of the ball being teleported. The cone narrows downward, so summing the outward normals over a stack of shrinking loops produces an upward resultant on its own — the braking is geometry, not a fudge factor.

- [ ] **Step 1: Write the failing tests**

Add to `NetSimulationTests.swift`:

```swift
    func testNetDeceleratesDescendingBall() {
        let simulation = NetRingSimulation()
        // -64 sits just above the two narrow lower rings, which are the ones a
        // dead-centre ball actually stretches open.
        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: descendingContact(y: -64),
            responseScale: 1
        )

        XCTAssertGreaterThan(
            force.dy,
            0,
            "a ball falling into the cone must be pushed back upward"
        )
    }

    func testCentredBallGetsNoSidewaysKickButOffCentreIsRecentred() {
        let centred = NetRingSimulation()
        let offCentre = NetRingSimulation()

        let centredForce = centred.step(
            deltaTime: 1.0 / 60.0,
            contact: descendingContact(y: -64, x: 0),
            responseScale: 1
        )
        let offCentreForce = offCentre.step(
            deltaTime: 1.0 / 60.0,
            contact: descendingContact(y: -64, x: 12),
            responseScale: 1
        )

        XCTAssertEqual(
            centredForce.dx,
            0,
            accuracy: 0.001,
            "a ball on the axis is squeezed equally from every side"
        )
        XCTAssertLessThan(
            offCentreForce.dx,
            -0.001,
            "a ball off the axis must be pushed back toward it"
        )
    }

    func testContactAppliesRegardlessOfScoring() {
        let fromBelow = NetRingSimulation()
        let bottomIndex = NetRingSimulation.ringCount - 1
        let belowForce = fromBelow.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(
                    x: 0,
                    y: fromBelow.rings[bottomIndex].restCenterY - 8
                ),
                velocity: CGVector(dx: 0, dy: 520),
                radius: GameTuning.ballDiameter / 2
            ),
            responseScale: 1
        )

        let fromSide = NetRingSimulation()
        let sideForce = fromSide.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(x: NetRingSimulation.topHalfWidth, y: -30),
                velocity: CGVector(dx: -300, dy: -60),
                radius: GameTuning.ballDiameter / 2
            ),
            responseScale: 1
        )

        XCTAssertLessThan(belowForce.dy, 0, "the hem must resist a ball rising into it")
        XCTAssertGreaterThan(sideForce.dx, 0, "a side brush must push the ball outward")
    }

    func testBallForceIsCapped() {
        let simulation = NetRingSimulation()
        let force = simulation.step(
            deltaTime: 1.0 / 60.0,
            contact: NetRingContact(
                position: CGPoint(x: 0, y: -64),
                velocity: CGVector(dx: 0, dy: -6_000),
                radius: GameTuning.ballDiameter / 2
            ),
            responseScale: 1
        )

        XCTAssertGreaterThan(
            hypot(force.dx, force.dy),
            0,
            "the contact must actually register, or the cap is untested"
        )
        XCTAssertLessThanOrEqual(hypot(force.dx, force.dy), 90.001)
    }

    func testGripGrowsWithPenetration() {
        let shallow = NetRingSimulation.grip(penetration: 4, ballRadius: 24)
        let deep = NetRingSimulation.grip(penetration: 20, ballRadius: 24)

        XCTAssertGreaterThan(deep.normal, shallow.normal)
        XCTAssertGreaterThanOrEqual(shallow.normal, 0)
        XCTAssertGreaterThanOrEqual(shallow.drag, 0)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -20
```

Expected: compile failure — `step` returns `Void`, and `grip` does not exist.

- [ ] **Step 3: Add the grip law and the ball reaction**

Add after `NetRingTouch` in `NetRingSimulation.swift`:

```swift
/// How firmly the net holds the ball at one contact point.
struct NetGrip {
    /// Scales the outward spring that pushes the ball off the cord.
    let normal: CGFloat
    /// Scales the drag that bleeds off the ball's speed along the cord.
    let drag: CGFloat
}
```

Add to `NetRingSimulation`:

```swift
    // The ring push and the ball reaction are different physical quantities and
    // must not share a constant. `contactStiffness` is an acceleration per unit
    // of penetration applied to a ring; this one is a force in the units
    // SKPhysicsBody.applyForce expects, acting on a 0.34 kg ball whose weight is
    // only about 3.5. At 90 a deep contact brakes the ball hard without hurling
    // it back out, and the cap is reached only at full penetration — so the grip
    // curve below still shapes everything the player feels.
    private let ballContactStiffness: CGFloat = 90
    private let maximumBallForce: CGFloat = 90
    private let contactDrag: CGFloat = 0.6

    // TODO(owner): this is the game-feel dial for the net, deliberately left
    // for the project owner the same way ShotController.powerCurve was.
    //
    // `penetration` is how far the ball's surface has passed a cord, in points,
    // from 0 up to roughly `ballRadius` (24). The return values scale the
    // outward push and the speed-bleeding drag at that contact point.
    //
    // Linear is the honest starting point, but it is probably not the most
    // satisfying one. Things worth trying:
    //   - a progressive curve (pow(t, 1.5)) so light brushes barely register
    //     but a deep entry grabs hard — makes a clean swish feel free and a
    //     rattled shot feel heavy
    //   - more `drag` than `normal` so the net swallows speed instead of
    //     bouncing the ball, which reads as a heavier, older net
    //   - clamping `normal` while letting `drag` keep rising, so the ball is
    //     slowed but never spat back out
    // Too much and the ball hangs in the net; too little and a swish feels
    // weightless. Only playing it will tell you which.
    static func grip(penetration: CGFloat, ballRadius: CGFloat) -> NetGrip {
        guard ballRadius > 0 else { return NetGrip(normal: 0, drag: 0) }
        let depth = min(max(penetration / ballRadius, 0), 1)
        return NetGrip(normal: depth, drag: depth)
    }
```

Change `step(deltaTime:contact:responseScale:)` to accumulate and return the force. Replace its body's loop and add a return:

```swift
    @discardableResult
    func step(
        deltaTime: CGFloat,
        contact: NetRingContact?,
        responseScale: CGFloat
    ) -> CGVector {
        let time = min(max(deltaTime, 0), 1.0 / 30.0)
        guard time > 0 else { return .zero }
        let scale = min(max(responseScale, 0), 1)
        let substepCount = max(1, Int(ceil(time / substepDuration)))
        let substep = time / CGFloat(substepCount)

        let startPosition = contact.map {
            CGPoint(
                x: $0.position.x - ($0.velocity.dx * time),
                y: $0.position.y - ($0.velocity.dy * time)
            )
        }

        var accumulated = CGVector.zero
        for substepIndex in 0..<substepCount {
            var swept = contact
            if let contact, let startPosition {
                let progress = CGFloat(substepIndex + 1) / CGFloat(substepCount)
                swept = NetRingContact(
                    position: CGPoint(
                        x: startPosition.x
                            + ((contact.position.x - startPosition.x) * progress),
                        y: startPosition.y
                            + ((contact.position.y - startPosition.y) * progress)
                    ),
                    velocity: contact.velocity,
                    radius: contact.radius
                )
            }
            integrate(deltaTime: substep)
            if let swept, swept.radius > 0, scale > 0 {
                applyContact(swept, deltaTime: substep, responseScale: scale)
                let force = ballForce(for: swept, responseScale: scale)
                accumulated.dx += force.dx / CGFloat(substepCount)
                accumulated.dy += force.dy / CGFloat(substepCount)
            }
        }

        let magnitude = hypot(accumulated.dx, accumulated.dy)
        guard magnitude > maximumBallForce else { return accumulated }
        let limitScale = maximumBallForce / magnitude
        return CGVector(
            dx: accumulated.dx * limitScale,
            dy: accumulated.dy * limitScale
        )
    }
```

And add the reaction itself:

```swift
    /// Equal and opposite to what `applyContact` does to the cords. Because the
    /// loops narrow with depth, the outward normals of a stack of them add up to
    /// an upward resultant, so the cone brakes a descending ball without any
    /// special-cased damping.
    private func ballForce(
        for contact: NetRingContact,
        responseScale: CGFloat
    ) -> CGVector {
        var force = CGVector.zero
        for touch in touches(for: contact) {
            let grip = Self.grip(
                penetration: touch.penetration,
                ballRadius: contact.radius
            )
            let push = ballContactStiffness * grip.normal * responseScale
            let normalX = touch.radialNormal * touch.lateralSign
                * touch.axialFraction
            force.dx += push * normalX
            force.dy += push * touch.verticalNormal

            let drag = contactDrag * grip.drag * responseScale
            force.dx -= contact.velocity.dx * drag
            force.dy -= contact.velocity.dy * drag
        }
        return force
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, `Executed 18 tests`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/NetRingSimulation.swift NotchBasket/Tests/NetSimulationTests.swift && git commit -m "feat: return net reaction force so the ball feels the cords"
```

---

### Task 5: Containment backstop

**Files:**
- Modify: `NotchBasket/Nodes/NetRingSimulation.swift`
- Test: `NotchBasket/Tests/NetSimulationTests.swift`

**Interfaces:**
- Consumes: `NetRingSimulation` from Task 4.
- Produces: `func containmentCorrection(ballPosition: CGPoint, ballRadius: CGFloat) -> CGPoint?` and `static let maximumCorrectionPerFrame: CGFloat = 2`.

This is a numerical safety valve, not a gameplay rule. It only nudges a ball that the integrator has already let slip through a cord, by at most 2 points per frame, and only while the ball is inside the vertical span of the net.

- [ ] **Step 1: Write the failing tests**

Add to `NetSimulationTests.swift`:

```swift
    func testBallInsideTheNetIsNotCorrected() {
        let simulation = NetRingSimulation()

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 0, y: -30),
            ballRadius: GameTuning.ballDiameter / 2
        ))
    }

    func testBallThatSlippedThroughTheSideIsNudgedBack() throws {
        let simulation = NetRingSimulation()
        let escaped = CGPoint(x: NetRingSimulation.topHalfWidth + 30, y: -30)

        let correction = try XCTUnwrap(simulation.containmentCorrection(
            ballPosition: escaped,
            ballRadius: GameTuning.ballDiameter / 2
        ))

        XCTAssertLessThan(correction.x, escaped.x)
        XCTAssertEqual(correction.y, escaped.y, "the backstop is lateral only")
        XCTAssertLessThanOrEqual(
            escaped.x - correction.x,
            NetRingSimulation.maximumCorrectionPerFrame + 0.001
        )
    }

    func testBallBelowTheNetIsReleased() {
        let simulation = NetRingSimulation()
        let bottom = simulation.rings[NetRingSimulation.ringCount - 1].restCenterY
        let ballRadius = GameTuning.ballDiameter / 2

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: 40, y: bottom - ballRadius - 6),
            ballRadius: ballRadius
        ))
    }

    func testBallAboveTheRimIsNotCorrected() {
        let simulation = NetRingSimulation()

        XCTAssertNil(simulation.containmentCorrection(
            ballPosition: CGPoint(x: NetRingSimulation.topHalfWidth + 30, y: 40),
            ballRadius: GameTuning.ballDiameter / 2
        ))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -20
```

Expected: compile failure, `value of type 'NetRingSimulation' has no member 'containmentCorrection'`.

- [ ] **Step 3: Implement the backstop**

Add to `NetRingSimulation`:

```swift
    /// The most the backstop may move the ball in one frame. Small enough that
    /// a player can never see it, large enough to recover from a tunnelling
    /// event over a few frames.
    static let maximumCorrectionPerFrame: CGFloat = 2

    /// Returns a nudged position only when the ball has ended up outside the
    /// cone while still within its vertical span — that is, when the integrator
    /// let it through a cord. Returns nil in every normal case, including a ball
    /// that has legitimately cleared the hem.
    func containmentCorrection(
        ballPosition: CGPoint,
        ballRadius: CGFloat
    ) -> CGPoint? {
        guard ballRadius > 0 else { return nil }
        guard let top = rings.first, let bottom = rings.last else { return nil }
        guard ballPosition.y <= top.centerY,
              ballPosition.y >= bottom.centerY else { return nil }

        let fraction = (top.centerY - ballPosition.y)
            / max(top.centerY - bottom.centerY, 0.001)
        let index = min(
            max(Int((fraction * CGFloat(rings.count - 1)).rounded()), 0),
            rings.count - 1
        )
        let ring = rings[index]

        let lateralOffset = ballPosition.x - ring.centerX
        let limit = ring.radius - (ballRadius * 0.25)
        guard abs(lateralOffset) > limit else { return nil }

        let target = ring.centerX + (limit * (lateralOffset >= 0 ? 1 : -1))
        let step = min(
            abs(ballPosition.x - target),
            Self.maximumCorrectionPerFrame
        )
        return CGPoint(
            x: ballPosition.x + (step * (target > ballPosition.x ? 1 : -1)),
            y: ballPosition.y
        )
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, `Executed 22 tests`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/NetRingSimulation.swift NotchBasket/Tests/NetSimulationTests.swift && git commit -m "feat: add lateral containment backstop against cord tunnelling"
```

---

### Task 6: Derive the woven mesh from the rings

**Files:**
- Modify: `NotchBasket/Nodes/NetRingSimulation.swift`
- Test: `NotchBasket/Tests/NetSimulationTests.swift`

**Interfaces:**
- Consumes: `NetRing` array from `NetRingSimulation.rings`.
- Produces: `enum NetMeshPathBuilder` with `static let cordCount = 10`, `static let projectionRatio: CGFloat`, `static func knot(ring: NetRing, cordIndex: Int, ringFraction: CGFloat) -> (point: CGPoint, depth: CGFloat)`, and `static func paths(for rings: [NetRing]) -> (rear: CGPath, front: CGPath)`.

The weave is a projection of a real 3D cone, so which cords are in front of the ball falls out of the geometry rather than being assigned by hand.

- [ ] **Step 1: Write the failing tests**

Add to `NetSimulationTests.swift`:

```swift
    func testKnotsProjectOntoTheRimEllipse() {
        let simulation = NetRingSimulation()
        let topRing = simulation.rings[0]

        let front = NetMeshPathBuilder.knot(
            ring: topRing,
            cordIndex: 0,
            ringFraction: 0
        )
        let quarter = NetMeshPathBuilder.knot(
            ring: topRing,
            cordIndex: NetMeshPathBuilder.cordCount / 4,
            ringFraction: 0
        )

        XCTAssertEqual(front.point.x, topRing.radius, accuracy: 0.001)
        XCTAssertEqual(
            abs(quarter.point.y - topRing.centerY),
            topRing.radius * NetMeshPathBuilder.projectionRatio,
            accuracy: 0.5,
            "the quarter-turn knot must sit on the shallow rim ellipse"
        )
    }

    func testEveryCordIsAssignedToExactlyOneDepthLayer() {
        let simulation = NetRingSimulation()
        var frontCount = 0
        var rearCount = 0

        for cordIndex in 0..<NetMeshPathBuilder.cordCount {
            let knot = NetMeshPathBuilder.knot(
                ring: simulation.rings[3],
                cordIndex: cordIndex,
                ringFraction: 0.3
            )
            if knot.depth >= 0 {
                rearCount += 1
            } else {
                frontCount += 1
            }
        }

        XCTAssertGreaterThan(frontCount, 0)
        XCTAssertGreaterThan(rearCount, 0)
        XCTAssertEqual(frontCount + rearCount, NetMeshPathBuilder.cordCount)
    }

    func testMeshPathsAreNonEmptyAndTrackRingMotion() {
        let simulation = NetRingSimulation()
        let atRest = NetMeshPathBuilder.paths(for: simulation.rings)
        XCTAssertFalse(atRest.rear.isEmpty)
        XCTAssertFalse(atRest.front.isEmpty)

        simulation.widenRingForTesting(at: 5, by: 24)
        let deformed = NetMeshPathBuilder.paths(for: simulation.rings)

        XCTAssertNotEqual(
            atRest.front.boundingBox.width,
            deformed.front.boundingBox.width,
            accuracy: 0.0001
        )
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -20
```

Expected: compile failure, `cannot find 'NetMeshPathBuilder' in scope`.

- [ ] **Step 3: Implement the path builder**

Append to `NotchBasket/Nodes/NetRingSimulation.swift`:

```swift
/// Turns ring state into the two stroked paths the net is drawn with. Cords are
/// split by their projected depth, so the ones that end up in front of the ball
/// are the ones genuinely nearer the viewer.
enum NetMeshPathBuilder {
    static let cordCount = 10

    /// How flat the loops look from the side. Derived from the rim so the net
    /// and the rim can never disagree about the viewing angle.
    static let projectionRatio: CGFloat =
        (SideHoopLayout.rimDepth / 2) / NetRingSimulation.topHalfWidth

    /// Real nets are hung with a slight spiral; without it the weave reads as a
    /// flat grid.
    static let twistPerRing: CGFloat = 0.12

    static func knot(
        ring: NetRing,
        cordIndex: Int,
        ringFraction: CGFloat
    ) -> (point: CGPoint, depth: CGFloat) {
        let angle = ((2 * CGFloat.pi) * CGFloat(cordIndex) / CGFloat(cordCount))
            + (ringFraction * twistPerRing)
        let point = CGPoint(
            x: ring.centerX + (ring.radius * cos(angle)),
            y: ring.centerY + (projectionRatio * ring.radius * sin(angle))
        )
        return (point, sin(angle))
    }

    static func paths(for rings: [NetRing]) -> (rear: CGPath, front: CGPath) {
        let rear = CGMutablePath()
        let front = CGMutablePath()
        guard rings.count > 1 else { return (rear, front) }

        let lastIndex = rings.count - 1
        func fraction(_ index: Int) -> CGFloat {
            CGFloat(index) / CGFloat(lastIndex)
        }

        // The attachment cord around the rim.
        for cordIndex in 0...cordCount {
            let knot = knot(
                ring: rings[0],
                cordIndex: cordIndex % cordCount,
                ringFraction: 0
            )
            if cordIndex == 0 {
                rear.move(to: knot.point)
            } else {
                rear.addLine(to: knot.point)
            }
        }

        // The two diagonal cord families that make the diamond weave.
        for index in 0..<lastIndex {
            for cordIndex in 0..<cordCount {
                let upper = knot(
                    ring: rings[index],
                    cordIndex: cordIndex,
                    ringFraction: fraction(index)
                )
                let lowerRight = knot(
                    ring: rings[index + 1],
                    cordIndex: (cordIndex + 1) % cordCount,
                    ringFraction: fraction(index + 1)
                )
                let lowerLeft = knot(
                    ring: rings[index + 1],
                    cordIndex: (cordIndex + cordCount - 1) % cordCount,
                    ringFraction: fraction(index + 1)
                )

                appendCord(from: upper, to: lowerRight, rear: rear, front: front)
                appendCord(from: upper, to: lowerLeft, rear: rear, front: front)
            }
        }

        // A loose scallop along the hem so the bottom does not read as a hoop.
        let hem = rings[lastIndex]
        for cordIndex in 0..<cordCount {
            let left = knot(
                ring: hem,
                cordIndex: cordIndex,
                ringFraction: 1
            )
            let right = knot(
                ring: hem,
                cordIndex: (cordIndex + 1) % cordCount,
                ringFraction: 1
            )
            let target = left.depth + right.depth >= 0 ? rear : front
            target.move(to: left.point)
            target.addQuadCurve(
                to: right.point,
                control: CGPoint(
                    x: (left.point.x + right.point.x) / 2,
                    y: min(left.point.y, right.point.y) - 4
                )
            )
        }

        return (rear, front)
    }

    private static func appendCord(
        from start: (point: CGPoint, depth: CGFloat),
        to end: (point: CGPoint, depth: CGFloat),
        rear: CGMutablePath,
        front: CGMutablePath
    ) {
        let target = start.depth + end.depth >= 0 ? rear : front
        target.move(to: start.point)
        target.addLine(to: end.point)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' -only-testing:NotchBasketTests/NetSimulationTests 2>&1 | tail -8
```

Expected: `** TEST SUCCEEDED **`, `Executed 25 tests`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/NetRingSimulation.swift NotchBasket/Tests/NetSimulationTests.swift && git commit -m "feat: build the woven net paths from projected ring geometry"
```

---

### Task 7: Swap the new net in and delete the old model

**Files:**
- Modify: `NotchBasket/Nodes/HoopNode.swift` (delete lines 454–1256, rewrite `NetMeshNode`, change `HoopNode` net API)
- Modify: `NotchBasket/Game/BasketballScene.swift:246-250`, `:378-410`, `:518-522`
- Modify: `NotchBasket/Tests/GeometryTests.swift` (delete lines 241–481)
- Modify: `README.md:161`

**Interfaces:**
- Consumes: `NetRingSimulation`, `NetRingContact`, `NetMeshPathBuilder` from Tasks 1–6.
- Produces: `HoopNode.updateNet(deltaTime:ballScenePosition:ballVelocity:ballRadius:reducedEffects:) -> CGVector` and `HoopNode.netContainmentCorrection(ballScenePosition:ballRadius:) -> CGPoint?`. `HoopNode.guideBallThroughNet(...)` and `HoopNode.resetNetBallGuide()` are removed.

This task is atomic — the build is broken partway through, so do not commit until Step 6 passes.

- [ ] **Step 1: Delete the old model and its tests**

In `NotchBasket/Nodes/HoopNode.swift`, delete everything from line 454 (`struct NetBallContact {`) to the end of the file. This removes `NetBallContact`, `NetBallGuideResponse`, `NetFunnelGuide`, `NetParticle`, `NetSpring`, `NetClothSimulation`, and the old `NetMeshNode`.

In `NotchBasket/Tests/GeometryTests.swift`, delete lines 241–481 — the eleven net tests from `testNetTopRowStaysPinnedWhileLowerRowsMove()` through the end of `testReducedMotionScalesNetResponse()`. Keep the class's closing brace on what is now the following line.

- [ ] **Step 2: Rewrite `NetMeshNode` against the ring simulation**

Append to `NotchBasket/Nodes/HoopNode.swift`:

```swift
private final class NetMeshNode: SKNode {
    private let rearOutline = SKShapeNode()
    private let rearMesh = SKShapeNode()
    private let frontOutline = SKShapeNode()
    private let frontMesh = SKShapeNode()
    private let simulation = NetRingSimulation()

    override init() {
        super.init()

        rearOutline.strokeColor = NSColor.black.withAlphaComponent(0.34)
        rearOutline.lineWidth = 2.4
        rearOutline.lineCap = .round
        rearOutline.lineJoin = .round
        rearOutline.zPosition = -1
        addChild(rearOutline)

        rearMesh.strokeColor = NSColor.white.withAlphaComponent(0.62)
        rearMesh.lineWidth = 1
        rearMesh.lineCap = .round
        rearMesh.lineJoin = .round
        rearMesh.zPosition = 0
        addChild(rearMesh)

        frontOutline.strokeColor = NSColor.black.withAlphaComponent(0.48)
        frontOutline.lineWidth = 2.6
        frontOutline.lineCap = .round
        frontOutline.lineJoin = .round
        frontOutline.zPosition = 19
        addChild(frontOutline)

        frontMesh.strokeColor = NSColor.white.withAlphaComponent(0.94)
        frontMesh.lineWidth = 1.15
        frontMesh.lineCap = .round
        frontMesh.lineJoin = .round
        frontMesh.glowWidth = 0.2
        frontMesh.zPosition = 20
        addChild(frontMesh)

        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @discardableResult
    func updateSimulation(
        deltaTime: CGFloat,
        ballContact: NetRingContact?,
        reducedEffects: Bool
    ) -> CGVector {
        let force = simulation.step(
            deltaTime: deltaTime,
            contact: ballContact,
            responseScale: reducedEffects ? 0.38 : 1
        )
        render()
        return force
    }

    func containmentCorrection(
        ballPosition: CGPoint,
        ballRadius: CGFloat
    ) -> CGPoint? {
        simulation.containmentCorrection(
            ballPosition: ballPosition,
            ballRadius: ballRadius
        )
    }

    private func render() {
        let paths = NetMeshPathBuilder.paths(for: simulation.rings)
        rearOutline.path = paths.rear
        rearMesh.path = paths.rear
        frontOutline.path = paths.front
        frontMesh.path = paths.front
    }
}
```

- [ ] **Step 3: Change the `HoopNode` net API**

In `NotchBasket/Nodes/HoopNode.swift`, delete the `netBallGuide` property, the `guideBallThroughNet` method, and the `resetNetBallGuide` method. Replace the `updateNet` method with:

```swift
    /// Advances the net and returns the force the cords are exerting on the
    /// ball, in scene coordinates. Contact is purely geometric — a shot that
    /// scores and a ball that clips the net from underneath take the same path.
    @discardableResult
    func updateNet(
        deltaTime: CGFloat,
        ballScenePosition: CGPoint?,
        ballVelocity: CGVector,
        ballRadius: CGFloat,
        reducedEffects: Bool
    ) -> CGVector {
        var contact: NetRingContact?
        if let ballScenePosition, let parent {
            let hoopPoint = convert(ballScenePosition, from: parent)
            contact = NetRingContact(
                position: CGPoint(
                    x: hoopPoint.x - netNode.position.x,
                    y: hoopPoint.y - netNode.position.y
                ),
                velocity: ballVelocity,
                radius: ballRadius
            )
        }

        return netNode.updateSimulation(
            deltaTime: deltaTime,
            ballContact: contact,
            reducedEffects: reducedEffects
        )
    }

    /// Numerical backstop only: recovers a ball that the integrator let slip
    /// through a cord. Returns nil in every normal frame.
    func netContainmentCorrection(
        ballScenePosition: CGPoint,
        ballRadius: CGFloat
    ) -> CGPoint? {
        guard let parent else { return nil }
        let hoopPoint = convert(ballScenePosition, from: parent)
        let localPosition = CGPoint(
            x: hoopPoint.x - netNode.position.x,
            y: hoopPoint.y - netNode.position.y
        )
        guard let corrected = netNode.containmentCorrection(
            ballPosition: localPosition,
            ballRadius: ballRadius
        ) else {
            return nil
        }

        let correctedHoopPoint = CGPoint(
            x: corrected.x + netNode.position.x,
            y: corrected.y + netNode.position.y
        )
        return parent.convert(correctedHoopPoint, from: self)
    }
```

Also stop `playScoreAnimation` from driving the net. Replace its first three lines — the `netNode.playSwish(ballVelocity:reducedEffects:)` call — so the method begins:

```swift
    /// The net is no longer animated on a score: the swish is whatever the ball
    /// actually did to the cords on its way through. Only the rim still flashes.
    func playScoreAnimation(reducedEffects: Bool, ballVelocity: CGVector) {
        _ = ballVelocity
        rearRimVisual.removeAllActions()
        rimVisual.removeAllActions()
```

The rest of the method is unchanged. Keeping the signature means `ScoreController` needs no edit.

- [ ] **Step 4: Wire the scene to forces instead of teleports**

In `NotchBasket/Game/BasketballScene.swift`, replace the block at lines 388–410 with:

```swift
        if isGamePresented, let hoop {
            let ballCanTouchNet = ballState != .spawning && ballState != .resetting
            let interactingBall = ballCanTouchNet ? ball : nil
            let netForce = hoop.updateNet(
                deltaTime: deltaTime,
                ballScenePosition: interactingBall?.position,
                ballVelocity: interactingBall?.physicsBody?.velocity ?? .zero,
                ballRadius: interactingBall?.radius ?? 0,
                reducedEffects: preferences.reducedEffects
            )

            // Only a ball the physics engine owns can be pushed. While aiming,
            // the net still deforms visually but the drag controls the ball.
            if ballState == .flying || ballState == .scored {
                interactingBall?.physicsBody?.applyForce(netForce)
            }
        }
```

Delete the two remaining `hoop?.resetNetBallGuide()` calls (near lines 248 and 520).

Add this override immediately after `update(_:)`:

```swift
    override func didSimulatePhysics() {
        guard isGamePresented,
              ballState == .flying || ballState == .scored,
              let ball,
              let hoop,
              let corrected = hoop.netContainmentCorrection(
                  ballScenePosition: ball.position,
                  ballRadius: ball.radius
              )
        else {
            return
        }
        ball.position = corrected
    }
```

- [ ] **Step 5: Update the README**

In `README.md`, replace the net paragraph on line 161 with:

```markdown
The procedural diamond-weave net is a cone of revolution modelled as eleven stacked cord loops. Each loop carries only three degrees of freedom — stretch, sag, and sway — so the woven cords are derived from ring geometry rather than simulated separately, and can never tangle or cross. Cord-length coupling between neighbouring loops means forcing one loop open hauls the loop below it up and inward, which is what makes the net cinch around the ball and then snap back; a disturbance therefore travels down the skirt instead of the whole net moving at once. Ball contact is measured as the distance to the nearest point on each loop, so a swish, a rim-out, a side brush, and a hit from underneath all take one code path and none of them depend on whether the shot scored. The net returns a force that is applied to the ball's physics body rather than repositioning it, and because the loops narrow with depth their outward normals sum to an upward resultant — the braking a real net gives a falling ball is geometry here, not a damping constant. Cords are split between the rear and front render layers by their projected depth, so the ball passes between them. A lateral backstop of at most two points per frame recovers a ball that the integrator lets slip through a cord.
```

- [ ] **Step 6: Run the full suite**

```bash
cd ~/Documents/"notch toys" && xcodebuild test -project NotchBasket.xcodeproj -scheme NotchBasket -destination 'platform=macOS' 2>&1 | tail -12
```

Expected: `** TEST SUCCEEDED **`. `GeometryTests` should report eleven fewer tests than at Task 0; `NetSimulationTests` should report 25.

If the build fails with `cannot find 'NetBallContact'`, a reference to the deleted model survives — search for it:

```bash
cd ~/Documents/"notch toys" && grep -rn "NetBallContact\|NetFunnelGuide\|NetClothSimulation\|guideBallThroughNet\|resetNetBallGuide\|applySwishImpulse\|playSwish" NotchBasket/
```

Expected after cleanup: no matches.

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/"notch toys" && git add NotchBasket/Nodes/HoopNode.swift NotchBasket/Game/BasketballScene.swift NotchBasket/Tests/GeometryTests.swift README.md && git commit -m "feat: replace cloth/funnel net with two-way coupled ring simulation"
```

---

## Post-implementation: owner tuning pass

The plan ends with a net that is correct but not yet tuned to taste. `NetRingSimulation.grip(penetration:ballRadius:)` is marked `TODO(owner)` and is the intended dial — see the comment there for what to try. The tests deliberately only assert that grip is non-negative and increases with penetration, so any curve the owner prefers keeps the suite green.

Secondary dials, in the order worth touching:

| Constant | Raise it to… | Lower it to… |
|---|---|---|
| `contactStiffness` (600) | open the net wider around the ball | let the net hug the ball tighter |
| `contactDamping` (30) | kill contact overshoot, calmer net | more rebound; past ~49 the ordering clamp starts doing the stabilising |
| `ballContactStiffness` (90) | make the net springier, ball pops out | let the ball sink deeper |
| `contactDrag` (0.6) | swallow more speed, heavier net | keep the ball lively |
| `cordStiffness` (340) | sharper snap-back and faster wave | looser, older-looking net |
| `sagDamping` / `radiusDamping` (7 / 9) | settle sooner | let the net ring longer after a shot |

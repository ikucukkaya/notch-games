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

/// How firmly the net holds the ball at one contact point.
struct NetGrip {
    /// Scales the outward spring that pushes the ball off the cord.
    let normal: CGFloat
    /// Scales the drag that bleeds off the ball's speed along the cord.
    let drag: CGFloat
}

/// The net, modelled as a stack of cord loops. Rendering and ball contact both
/// read this one model, so the net can never look like it is doing something
/// different from what the ball feels.
final class NetRingSimulation {
    static let ringCount = 11
    static let topHalfWidth: CGFloat =
        GameTuning.rimPostOffset - GameTuning.rimPostRadius

    /// Narrower than the ball's 24-point radius, but only just — a regulation
    /// hem is about 0.96 of a ball diameter, so the ball has to stretch it open
    /// without the net strangling it. The old cloth model used 31, wider than the
    /// ball, so a dead-centre shot could fall the whole length of the net without
    /// touching a single cord and the net never billowed on a clean swish. 22
    /// keeps the stretch that makes the swish while holding the real proportion.
    static let bottomHalfWidth: CGFloat = 22
    static let depth: CGFloat = 76

    private(set) var rings: [NetRing] = []

    /// Whether the ball has actually been inside the cone during this pass. The
    /// backstop exists only to recover a ball that slipped out through a cord, so
    /// it has to know the ball was in there. Guessing from distance instead meant
    /// a ball merely falling past the front of the hoop got nudged sideways.
    private var ballWasInsideCone = false

    // Stretch resists hardest because cords barely lengthen; sway is loosest
    // because the whole skirt can swing without any cord changing length.
    private let radiusStiffness: CGFloat = 260
    private let sagStiffness: CGFloat = 150
    private let swayStiffness: CGFloat = 70
    private let radiusDamping: CGFloat = 9
    private let sagDamping: CGFloat = 7
    private let swayDamping: CGFloat = 6
    private let ringGravity: CGFloat = -30

    private let cordStiffness: CGFloat = 340
    private let swayCoupling: CGFloat = 120
    private var cordRestLengths: [CGFloat] = []

    private let substepDuration: CGFloat = 1.0 / 240.0

    private let contactStiffness: CGFloat = 600
    private let contactSwayShare: CGFloat = 0.45

    /// A stiff contact spring with no dashpot overshoots by construction, and at
    /// this stiffness the overshoot was large enough to invert ring order — the
    /// ordering clamp was catching it several times per stress run instead of
    /// sitting idle as a backstop. Critical damping for k = 600 on a unit ring
    /// mass is about 49; staying under that keeps the net springy. At this value
    /// the damping ratio is ~0.61 — still underdamped, so some overshoot remains,
    /// but no longer enough to reach the ordering clamp's threshold. Damping
    /// vanishes at steady state, so the hem still settles where the equilibrium
    /// says it should.
    private let contactDamping: CGFloat = 30

    /// A fast shot crosses the whole net inside one display frame. Sampling by
    /// elapsed time alone would step the ball straight over the cords, so the
    /// sweep is refined until each substep advances it only a few points —
    /// well under a ring's spacing.
    ///
    /// Insurance rather than a hot path: at the game's own launch speeds, and
    /// even at the 6600 pt/s the tunnelling test uses, this changes the result by
    /// under 2%, because the four time-based substeps already land inside the
    /// hem's contact window. It earns its keep only above that, where they would
    /// straddle it. No test gates it for that reason — the swept interpolation
    /// itself is what the tunnelling test protects.
    private let maximumBallTravelPerSubstep: CGFloat = 4
    private let maximumSubstepCount = 64

    // The ring push and the ball reaction are different physical quantities and
    // must not share a constant. `contactStiffness` is an acceleration per unit
    // of penetration applied to a ring; these are forces handed to
    // SKPhysicsBody.applyForce, so they are written as multiples of the ball's
    // own weight. Absolute numbers here are how the net ended up able to
    // accelerate the ball at 26 g, which read on screen as the ball slaloming:
    // a hard centring spring throws it across the axis, then back again.
    private let ballContactStiffness: CGFloat = 2 * GameTuning.ballWeight
    private let maximumBallForce: CGFloat = 3 * GameTuning.ballWeight

    /// Cord friction, expressed as the speed at which it amounts to one ball
    /// weight. It is also the lateral damping that stops the centring push from
    /// oscillating, so it must not be small relative to `ballContactStiffness`.
    private let contactDragReferenceSpeed: CGFloat = 600
    private var contactDrag: CGFloat {
        GameTuning.ballWeight / contactDragReferenceSpeed
    }

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

    /// Test seam: stretches one loop the way a ball passing through would,
    /// without needing a ball.
    func widenRingForTesting(at index: Int, by amount: CGFloat) {
        guard rings.indices.contains(index), !rings[index].isPinned else { return }
        rings[index].radius += amount
    }

    /// Test seam: swings one loop sideways the way a ball entering off-centre
    /// would, without needing a ball.
    func swayRingForTesting(at index: Int, by amount: CGFloat) {
        guard rings.indices.contains(index), !rings[index].isPinned else { return }
        rings[index].centerX += amount
    }

    func step(deltaTime: CGFloat) {
        step(deltaTime: deltaTime, contact: nil, responseScale: 1)
    }

    /// Advances the net and returns the force the cords are exerting on the ball.
    @discardableResult
    func step(
        deltaTime: CGFloat,
        contact: NetRingContact?,
        responseScale: CGFloat
    ) -> CGVector {
        let time = min(max(deltaTime, 0), 1.0 / 30.0)
        guard time > 0 else { return .zero }
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
              ballPosition.y >= bottom.centerY else {
            // Above the rim or below the hem: this pass is over, whatever happened
            // during it. A ball that legitimately dropped out of the bottom and a
            // ball that never arrived both end up here.
            ballWasInsideCone = false
            return nil
        }

        let fraction = (top.centerY - ballPosition.y)
            / max(top.centerY - bottom.centerY, 0.001)
        let index = min(
            max(Int((fraction * CGFloat(rings.count - 1)).rounded()), 0),
            rings.count - 1
        )
        let ring = rings[index]

        let lateralOffset = ballPosition.x - ring.centerX

        // A ball that was never inside the cone cannot have slipped out of it.
        // Without this bound the vertical span alone qualifies, which makes the
        // whole screen-wide strip at net height count as "inside the net": a ball
        // thrown straight up from the far side of the screen got dragged two
        // points sideways every frame it spent in that strip, worst of all near
        // the apex where it lingers longest.
        let limit = ring.radius - (ballRadius * 0.25)
        if abs(lateralOffset) <= limit {
            ballWasInsideCone = true
            return nil
        }

        // Outside the cords but never inside them — a ball falling past the front
        // of the hoop, or crossing net height somewhere else on screen entirely.
        // Nothing to recover.
        guard ballWasInsideCone else { return nil }

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

            // A pure spring overshoots by construction. Oppose the ring's
            // velocity along the push direction so the contact behaves like a
            // spring-damper instead of inverting ring order under a stiff push.
            // This reads radiusVelocity/centerYVelocity after the push above has
            // already landed, so it damps this substep's fresh impulse too, not
            // just velocity carried over from earlier substeps — the ordinary
            // semi-implicit arrangement, and stable at the substep sizes in play.
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
        cordRestLengths = (0..<(rings.count - 1)).map { index in
            let dropDistance = rings[index].restCenterY - rings[index + 1].restCenterY
            let radiusDifference = rings[index].restRadius - rings[index + 1].restRadius
            return hypot(dropDistance, radiusDifference)
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
        applyCordCoupling(deltaTime: deltaTime)
        enforceRingOrder()
    }

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
            let left = knot(ring: hem, cordIndex: cordIndex, ringFraction: 1)
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

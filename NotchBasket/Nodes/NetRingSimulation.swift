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

    private let cordStiffness: CGFloat = 340
    private let swayCoupling: CGFloat = 120
    private var cordRestLengths: [CGFloat] = []

    private let substepDuration: CGFloat = 1.0 / 240.0

    private let contactStiffness: CGFloat = 600
    private let contactSwayShare: CGFloat = 0.45

    /// A fast shot crosses the whole net inside one display frame. Sampling by
    /// elapsed time alone would step the ball straight over the cords, so the
    /// sweep is refined until each substep advances it only a few points —
    /// well under a ring's spacing.
    private let maximumBallTravelPerSubstep: CGFloat = 4
    private let maximumSubstepCount = 64

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

    /// Distance from the ball's centre to the nearest point on a cord loop.
    /// One formula, so a ball inside the net, outside it, above it, or below it
    /// all take the same path — scoring is never a condition.
    func touches(for contact: NetRingContact) -> [NetRingTouch] {
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

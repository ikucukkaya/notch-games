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

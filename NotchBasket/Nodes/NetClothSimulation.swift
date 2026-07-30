import CoreGraphics
import Foundation

/// A point in the net's own space. The net is a cone of revolution and the ball
/// travels in the plane `z = 0`, so the third axis is what lets the near cords
/// and the far cords be pushed apart independently — which is the whole reason
/// the weave can dent locally instead of merely widening.
struct NetPoint3 {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    static let zero = NetPoint3(x: 0, y: 0, z: 0)

    static func + (a: NetPoint3, b: NetPoint3) -> NetPoint3 {
        NetPoint3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }

    static func - (a: NetPoint3, b: NetPoint3) -> NetPoint3 {
        NetPoint3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }

    static func * (a: NetPoint3, s: CGFloat) -> NetPoint3 {
        NetPoint3(x: a.x * s, y: a.y * s, z: a.z * s)
    }

    var length: CGFloat {
        sqrt((x * x) + (y * y) + (z * z))
    }

    /// Distance from the cone's own axis, ignoring height.
    var axialDistance: CGFloat {
        sqrt((x * x) + (z * z))
    }
}

/// One knot of the weave.
struct NetKnot {
    var position: NetPoint3
    var previousPosition: NetPoint3
    let restPosition: NetPoint3
    let isPinned: Bool
}

/// A distance constraint between two knots — a length of cord.
private struct NetCord {
    let first: Int
    let second: Int
    let restLength: CGFloat
    let stiffness: CGFloat
}

/// The ball as the net sees it, expressed in the net's own coordinate space.
struct NetRingContact {
    let position: CGPoint
    let velocity: CGVector
    let radius: CGFloat
}

/// How firmly the net holds the ball at one contact point.
struct NetGrip {
    /// Scales the outward spring that pushes the ball off the cord.
    let normal: CGFloat
    /// Scales the drag that bleeds off the ball's speed along the cord.
    let drag: CGFloat
}

/// A row of the weave, summarised as the loop it approximates. The cloth itself
/// is simulated per knot; this view exists for the code and tests that reason
/// about the net as a stack of loops — chiefly the containment backstop.
struct NetRing {
    let radius: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat
    let restRadius: CGFloat
    let restCenterY: CGFloat
    let isPinned: Bool
}

/// The net, simulated as a woven sheet of knots in three dimensions. Rendering
/// and ball contact both read this one model, so the net cannot look like it is
/// doing something different from what the ball feels.
///
/// This replaced a model that gave each row three degrees of freedom — stretch,
/// sag, sway — and therefore kept every row a perfect circle. A ball pressing
/// from one side could only make the whole loop shrink and slide away, which
/// read on screen as the ball passing through the mesh rather than pushing it.
/// Per-knot positions are what make a local dent possible, and the same sphere
/// contact produces one whether the ball arrives from inside or outside.
final class NetClothSimulation {
    // 11 x 10 originally. The weave was asked to move more softly, and a finer
    // sheet is what delivers it: at the same stiffness, more knots per unit area
    // means each is less constrained by its neighbours, so the cloth flows rather
    // than snapping back. Measured against 11 x 10, the dent stays local more
    // sharply (37.5x the far side, up from 17.6x) and a fast ball stretches the hem
    // more than twice as far, with cord stretch still under 0.1% — the cords are
    // no less inextensible, there are simply more of them. Worst-case cost is
    // ~168k constraint solves per frame at the substep cap; a typical frame is
    // ~21k, which is nothing.
    static let rowCount = 13
    static let cordCount = 18

    static let topHalfWidth: CGFloat =
        GameTuning.rimPostOffset - GameTuning.rimPostRadius

    /// Narrower than the ball's radius, but only just — a regulation hem is about
    /// 0.96 of a ball diameter, so the ball has to stretch it open without the
    /// net strangling it.
    static let bottomHalfWidth: CGFloat = 22
    static let depth: CGFloat = 76

    /// Real nets are hung with a slight spiral; without it the weave reads as a
    /// flat grid.
    static let twistPerRow: CGFloat = 0.12

    private(set) var knots: [NetKnot] = []
    private var cords: [NetCord] = []

    /// Whether the ball has actually been inside the cone during this pass. The
    /// backstop exists only to recover a ball that slipped out through a cord, so
    /// it has to know the ball was in there.
    private var ballWasInsideCone = false

    // Cloth is solved by satisfying cord lengths rather than by integrating stiff
    // springs: at these stiffnesses an explicit spring would need a timestep far
    // below anything a display frame can afford.
    private let structuralStiffness: CGFloat = 0.25
    private let shearStiffness: CGFloat = 0.15
    private let bendStiffness: CGFloat = 0.0375
    private let constraintIterations = 4

    /// How much of a contact displacement becomes knot velocity. Verlet reads a
    /// position change as motion, so projecting a knot onto the ball's surface and
    /// leaving `previousPosition` alone hands the net free energy — with the cords
    /// pulling back in and the ball pushing back out, the sheet gained speed every
    /// solve and flung itself off the rim. Carrying most of the displacement into
    /// `previousPosition` too leaves the dent without the launch.
    private let contactVelocityShare: CGFloat = 0.25

    /// A weak pull back toward the authored silhouette. Without it the sheet is
    /// free to settle anywhere its cord lengths allow, and the net would slowly
    /// drift out of the shape the hoop was drawn around.
    private let restAttraction: CGFloat = 22

    /// How much motion survives each substep. Raised from 0.984 to soften the
    /// net: after a ball brushes past, the weave keeps flowing for 57 frames
    /// rather than 36, which is what reads as soft fabric rather than something
    /// that snaps back to shape. Past about 0.994 it stops buying more flow and
    /// starts letting hard contact throw knots above the rim.
    private let damping: CGFloat = 0.988
    private let knotGravity: CGFloat = -26

    private let substepDuration: CGFloat = 1.0 / 240.0
    private let maximumBallTravelPerSubstep: CGFloat = 4
    private let maximumSubstepCount = 32

    // Forces handed to SKPhysicsBody.applyForce, written as multiples of the
    // ball's own weight. Absolute numbers here once let the net accelerate the
    // ball at 26 g, which read on screen as the ball slaloming.
    private let ballContactStiffness: CGFloat = 2 * GameTuning.ballWeight
    private let maximumBallForce: CGFloat = 3 * GameTuning.ballWeight

    /// Cord friction, as the speed at which it amounts to one ball weight.
    private let contactDragReferenceSpeed: CGFloat = 600
    private var contactDrag: CGFloat {
        GameTuning.ballWeight / contactDragReferenceSpeed
    }

    init() {
        buildKnots()
        buildCords()
    }

    // MARK: - Row summary

    /// The rows as loops: mean radius, mean centre, mean height. Reported rather
    /// than simulated — a dented row has no single radius, and this is the
    /// average that the containment backstop reasons about.
    var rings: [NetRing] {
        (0..<Self.rowCount).map { row in
            var radius: CGFloat = 0
            var centerX: CGFloat = 0
            var centerY: CGFloat = 0
            var restRadius: CGFloat = 0
            var restCenterY: CGFloat = 0
            for cord in 0..<Self.cordCount {
                let knot = knots[index(row: row, cord: cord)]
                radius += knot.position.axialDistance
                centerX += knot.position.x
                centerY += knot.position.y
                restRadius += knot.restPosition.axialDistance
                restCenterY += knot.restPosition.y
            }
            let count = CGFloat(Self.cordCount)
            return NetRing(
                radius: radius / count,
                // The knots ring the axis, so their mean x is the loop's centre
                // only because they are evenly spaced — which the weave keeps.
                centerX: centerX / count,
                centerY: centerY / count,
                restRadius: restRadius / count,
                restCenterY: restCenterY / count,
                isPinned: row == 0
            )
        }
    }

    func displacementFromRest() -> CGFloat {
        knots.reduce(0) { $0 + ($1.position - $1.restPosition).length }
    }

    /// How far one knot has been pushed off its rest position. The measure that
    /// tells a local dent apart from the whole row moving.
    func displacement(row: Int, cord: Int) -> CGFloat {
        let knot = knots[index(row: row, cord: cord)]
        return (knot.position - knot.restPosition).length
    }

    func position(row: Int, cord: Int) -> NetPoint3 {
        knots[index(row: row, cord: cord)].position
    }

    // MARK: - Test seams

    /// Pushes every free knot off its rest position so relaxation can be measured.
    func disturbForTesting(
        radiusOffset: CGFloat,
        sagOffset: CGFloat,
        swayOffset: CGFloat
    ) {
        for i in knots.indices where !knots[i].isPinned {
            let axial = max(knots[i].position.axialDistance, 0.001)
            let scale = (axial + radiusOffset) / axial
            knots[i].position.x = (knots[i].position.x * scale) + swayOffset
            knots[i].position.z *= scale
            knots[i].position.y += sagOffset
            knots[i].previousPosition = knots[i].position
        }
    }

    /// Stretches one row outward the way a ball passing through would.
    func widenRingForTesting(at row: Int, by amount: CGFloat) {
        guard row > 0, row < Self.rowCount else { return }
        for cord in 0..<Self.cordCount {
            let i = index(row: row, cord: cord)
            let axial = max(knots[i].position.axialDistance, 0.001)
            let scale = (axial + amount) / axial
            knots[i].position.x *= scale
            knots[i].position.z *= scale
            knots[i].previousPosition = knots[i].position
        }
    }

    /// Swings one row sideways the way a ball entering off-centre would.
    func swayRingForTesting(at row: Int, by amount: CGFloat) {
        guard row > 0, row < Self.rowCount else { return }
        for cord in 0..<Self.cordCount {
            let i = index(row: row, cord: cord)
            knots[i].position.x += amount
            knots[i].previousPosition = knots[i].position
        }
    }

    // MARK: - Stepping

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
            substepCount = max(
                substepCount,
                Int(ceil(travel / maximumBallTravelPerSubstep))
            )
        }
        substepCount = min(substepCount, maximumSubstepCount)
        let substep = time / CGFloat(substepCount)

        // Sweep the ball along its path so a fast shot cannot step over the cords
        // between two display frames.
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
            for _ in 0..<constraintIterations {
                solveCords()
                pinTopRow()
            }

            // Contact is resolved after the cords, not inside their loop. Solving
            // both together had them fighting several times per substep, and each
            // round of that fight was read as velocity.
            if let swept, swept.radius > 0, scale > 0 {
                let reaction = resolveBall(swept, responseScale: scale)
                accumulated.dx += reaction.dx / CGFloat(substepCount)
                accumulated.dy += reaction.dy / CGFloat(substepCount)
                pinTopRow()
            }
        }

        let magnitude = hypot(accumulated.dx, accumulated.dy)
        guard magnitude > maximumBallForce else { return accumulated }
        let limit = maximumBallForce / magnitude
        return CGVector(dx: accumulated.dx * limit, dy: accumulated.dy * limit)
    }

    // MARK: - Grip

    // TODO(owner): this is the game-feel dial for the net, deliberately left
    // for the project owner the same way ShotController.powerCurve was.
    //
    // `penetration` is how far the ball's surface has passed the deepest cord it
    // is touching, in points, from 0 up to roughly `ballRadius`. The return
    // values scale the outward push and the speed-bleeding drag.
    //
    // Linear is the honest starting point, but probably not the most satisfying.
    // Worth trying:
    //   - a progressive curve (pow(t, 1.5)) so light brushes barely register but
    //     a deep entry grabs hard
    //   - more `drag` than `normal` so the net swallows speed instead of bouncing
    //     the ball, which reads as a heavier, older net
    //   - clamping `normal` while letting `drag` keep rising, so the ball is
    //     slowed but never spat back out
    // Too much and the ball hangs in the net; too little and a swish feels
    // weightless. Only playing it will tell you which.
    static func grip(penetration: CGFloat, ballRadius: CGFloat) -> NetGrip {
        guard ballRadius > 0 else { return NetGrip(normal: 0, drag: 0) }
        let depth = min(max(penetration / ballRadius, 0), 1)
        return NetGrip(normal: depth, drag: depth)
    }

    // MARK: - Containment backstop

    /// The most the backstop may move the ball in one frame.
    static let maximumCorrectionPerFrame: CGFloat = 2

    /// Returns a nudged position only when the ball has ended up outside the cone
    /// after having been inside it — that is, when the integrator let it through
    /// a cord. Returns nil in every normal case.
    func containmentCorrection(
        ballPosition: CGPoint,
        ballRadius: CGFloat
    ) -> CGPoint? {
        guard ballRadius > 0 else { return nil }
        let rows = rings
        guard let top = rows.first, let bottom = rows.last else { return nil }
        guard ballPosition.y <= top.centerY,
              ballPosition.y >= bottom.centerY else {
            // Above the rim or below the hem: this pass is over, whatever happened
            // during it.
            ballWasInsideCone = false
            return nil
        }

        let fraction = (top.centerY - ballPosition.y)
            / max(top.centerY - bottom.centerY, 0.001)
        let index = min(
            max(Int((fraction * CGFloat(rows.count - 1)).rounded()), 0),
            rows.count - 1
        )
        let row = rows[index]

        let lateralOffset = ballPosition.x - row.centerX
        let limit = row.radius - (ballRadius * 0.25)
        if abs(lateralOffset) <= limit {
            ballWasInsideCone = true
            return nil
        }

        // Outside the cords but never inside them — a ball falling past the front
        // of the hoop, or crossing net height elsewhere on screen. Nothing to
        // recover.
        guard ballWasInsideCone else { return nil }

        let target = row.centerX + (limit * (lateralOffset >= 0 ? 1 : -1))
        let step = min(
            abs(ballPosition.x - target),
            Self.maximumCorrectionPerFrame
        )
        return CGPoint(
            x: ballPosition.x + (step * (target > ballPosition.x ? 1 : -1)),
            y: ballPosition.y
        )
    }

    // MARK: - Construction

    private func index(row: Int, cord: Int) -> Int {
        (row * Self.cordCount) + ((cord % Self.cordCount + Self.cordCount) % Self.cordCount)
    }

    private func buildKnots() {
        knots.removeAll(keepingCapacity: true)
        for row in 0..<Self.rowCount {
            let fraction = CGFloat(row) / CGFloat(Self.rowCount - 1)
            let radius = Self.topHalfWidth
                + ((Self.bottomHalfWidth - Self.topHalfWidth) * fraction)
            let height = -Self.depth * pow(fraction, 1.04)
            for cord in 0..<Self.cordCount {
                let angle = ((2 * CGFloat.pi) * CGFloat(cord) / CGFloat(Self.cordCount))
                    + (fraction * Self.twistPerRow)
                let rest = NetPoint3(
                    x: radius * cos(angle),
                    y: height,
                    z: radius * sin(angle)
                )
                knots.append(NetKnot(
                    position: rest,
                    previousPosition: rest,
                    restPosition: rest,
                    isPinned: row == 0
                ))
            }
        }
    }

    private func buildCords() {
        cords.removeAll(keepingCapacity: true)

        // Around each row, and down each cord: the weave's two structural
        // directions, both nearly inextensible.
        for row in 0..<Self.rowCount {
            for cord in 0..<Self.cordCount {
                addCord(
                    index(row: row, cord: cord),
                    index(row: row, cord: cord + 1),
                    structuralStiffness
                )
            }
        }
        for row in 0..<(Self.rowCount - 1) {
            for cord in 0..<Self.cordCount {
                addCord(
                    index(row: row, cord: cord),
                    index(row: row + 1, cord: cord),
                    structuralStiffness
                )
            }
        }

        // The diagonals are what a diamond weave is actually made of, and they
        // are what stops the sheet shearing into a parallelogram under a dent.
        for row in 0..<(Self.rowCount - 1) {
            for cord in 0..<Self.cordCount {
                addCord(
                    index(row: row, cord: cord),
                    index(row: row + 1, cord: cord + 1),
                    shearStiffness
                )
                addCord(
                    index(row: row, cord: cord + 1),
                    index(row: row + 1, cord: cord),
                    shearStiffness
                )
            }
        }

        // Two-knot spans resist creasing, so a dent bends over a few knots
        // instead of folding to a point.
        for row in 0..<(Self.rowCount - 2) {
            for cord in 0..<Self.cordCount {
                addCord(
                    index(row: row, cord: cord),
                    index(row: row + 2, cord: cord),
                    bendStiffness
                )
            }
        }
        for row in 0..<Self.rowCount {
            for cord in 0..<Self.cordCount {
                addCord(
                    index(row: row, cord: cord),
                    index(row: row, cord: cord + 2),
                    bendStiffness
                )
            }
        }
    }

    private func addCord(_ first: Int, _ second: Int, _ stiffness: CGFloat) {
        guard first != second else { return }
        let length = (knots[second].restPosition - knots[first].restPosition).length
        cords.append(NetCord(
            first: first,
            second: second,
            restLength: length,
            stiffness: stiffness
        ))
    }

    // MARK: - Solver

    private func integrate(deltaTime: CGFloat) {
        let timeSquared = deltaTime * deltaTime
        for i in knots.indices where !knots[i].isPinned {
            let knot = knots[i]
            let velocity = (knot.position - knot.previousPosition) * damping
            let toRest = knot.restPosition - knot.position
            let acceleration = NetPoint3(
                x: toRest.x * restAttraction,
                y: (toRest.y * restAttraction) + knotGravity,
                z: toRest.z * restAttraction
            )
            knots[i].previousPosition = knot.position
            knots[i].position = knot.position + velocity + (acceleration * timeSquared)
        }
    }

    private func solveCords() {
        for cord in cords {
            let a = knots[cord.first]
            let b = knots[cord.second]
            let delta = b.position - a.position
            let distance = max(delta.length, 0.0001)
            let difference = (distance - cord.restLength) / distance
            let correction = delta * (difference * cord.stiffness)

            switch (a.isPinned, b.isPinned) {
            case (true, true):
                continue
            case (true, false):
                knots[cord.second].position = b.position - correction
            case (false, true):
                knots[cord.first].position = a.position + correction
            case (false, false):
                knots[cord.first].position = a.position + (correction * 0.5)
                knots[cord.second].position = b.position - (correction * 0.5)
            }
        }
    }

    /// Pushes every knot the ball overlaps out to the ball's surface, and returns
    /// the reaction on the ball. One test, so a ball inside the cone, outside it,
    /// above it or below it all take the same path — the dent simply forms on
    /// whichever side the ball is.
    private func resolveBall(
        _ contact: NetRingContact,
        responseScale: CGFloat
    ) -> CGVector {
        let center = NetPoint3(
            x: contact.position.x,
            y: contact.position.y,
            z: 0
        )
        var pushX: CGFloat = 0
        var pushY: CGFloat = 0
        var deepest: CGFloat = 0

        for i in knots.indices where !knots[i].isPinned {
            let toKnot = knots[i].position - center
            let distance = toKnot.length
            guard distance < contact.radius else { continue }

            let normal: NetPoint3
            if distance > 0.0001 {
                normal = toKnot * (1 / distance)
            } else {
                // Dead centre on a knot: no radial direction exists, so send it
                // the way the ball is going.
                let speed = hypot(contact.velocity.dx, contact.velocity.dy)
                normal = speed > 0.0001
                    ? NetPoint3(
                        x: contact.velocity.dx / speed,
                        y: contact.velocity.dy / speed,
                        z: 0
                    )
                    : NetPoint3(x: 0, y: -1, z: 0)
            }

            let penetration = contact.radius - distance
            let corrected = center + (normal * contact.radius)
            let shift = (corrected - knots[i].position) * responseScale
            knots[i].position = knots[i].position + shift
            knots[i].previousPosition = knots[i].previousPosition
                + (shift * (1 - contactVelocityShare))

            // The reaction is opposite the direction the knot was pushed. Only the
            // game plane can act on the ball, so the out-of-plane component is
            // dropped — for a centred ball it cancels anyway.
            pushX -= normal.x * penetration
            pushY -= normal.y * penetration
            deepest = max(deepest, penetration)
        }

        guard deepest > 0 else { return .zero }

        // Normalised by direction rather than summed per knot, so the force the
        // ball feels does not depend on how many knots the weave happens to have.
        var force = CGVector.zero
        let pushLength = hypot(pushX, pushY)
        if pushLength > 0.0001 {
            let grip = Self.grip(penetration: deepest, ballRadius: contact.radius)
            let magnitude = ballContactStiffness * grip.normal * responseScale
            force.dx = (pushX / pushLength) * magnitude
            force.dy = (pushY / pushLength) * magnitude

            let drag = contactDrag * grip.drag * responseScale
            force.dx -= contact.velocity.dx * drag
            force.dy -= contact.velocity.dy * drag
        }
        return force
    }

    private func pinTopRow() {
        for cord in 0..<Self.cordCount {
            let i = index(row: 0, cord: cord)
            knots[i].position = knots[i].restPosition
            knots[i].previousPosition = knots[i].restPosition
        }
    }
}

/// Turns knot positions into the two stroked paths the net is drawn with. Cords
/// are split by their projected depth, so the ones drawn in front of the ball are
/// the ones genuinely nearer the viewer.
enum NetMeshPathBuilder {
    /// How flat the loops look from the side, derived from the rim so the net and
    /// the rim can never disagree about the viewing angle.
    static let projectionRatio: CGFloat =
        (SideHoopLayout.rimDepth / 2) / NetClothSimulation.topHalfWidth

    /// The side-on projection: height picks up a share of depth, and depth itself
    /// decides which render layer a cord belongs to.
    static func project(_ point: NetPoint3) -> (point: CGPoint, depth: CGFloat) {
        (
            CGPoint(x: point.x, y: point.y + (projectionRatio * point.z)),
            point.z
        )
    }

    static func paths(
        for simulation: NetClothSimulation
    ) -> (rear: CGPath, front: CGPath) {
        let rear = CGMutablePath()
        let front = CGMutablePath()
        let rows = NetClothSimulation.rowCount
        let cordCount = NetClothSimulation.cordCount

        // The attachment cord around the rim, closed.
        let rim = (0...cordCount).map { cord in
            project(simulation.position(row: 0, cord: cord % cordCount))
        }
        appendSmoothRuns(rim, rear: rear, front: front)

        // Each cord of the weave is one continuous helix from the rim to the hem,
        // not a row of separate stitches. Drawing whole chains is what lets them be
        // curved: the same segments as before, but a cord now bends through its
        // knots instead of turning a corner at each one.
        for start in 0..<cordCount {
            for direction in [1, -1] {
                let chain = (0..<rows).map { row -> (point: CGPoint, depth: CGFloat) in
                    let cord = ((start + (direction * row)) % cordCount + cordCount)
                        % cordCount
                    return project(simulation.position(row: row, cord: cord))
                }
                appendSmoothRuns(chain, rear: rear, front: front)
            }
        }

        // A loose scallop along the hem so the bottom does not read as a hoop.
        for cord in 0..<cordCount {
            let left = project(simulation.position(row: rows - 1, cord: cord))
            let right = project(
                simulation.position(row: rows - 1, cord: (cord + 1) % cordCount)
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

    /// Splits a chain of knots wherever it crosses from the far side of the cone
    /// to the near side, and draws each run as a smooth curve. A cord that winds
    /// around the cone has to change render layer partway along, or it would be
    /// drawn in front of the ball for its whole length.
    private static func appendSmoothRuns(
        _ chain: [(point: CGPoint, depth: CGFloat)],
        rear: CGMutablePath,
        front: CGMutablePath
    ) {
        guard chain.count > 1 else { return }

        var runStart = 0
        var runIsRear = chain[0].depth + chain[1].depth >= 0
        for index in 1..<chain.count {
            let segmentIsRear = chain[index - 1].depth + chain[index].depth >= 0
            if segmentIsRear != runIsRear {
                appendSmoothCurve(
                    Array(chain[runStart..<index]).map(\.point),
                    to: runIsRear ? rear : front
                )
                // Overlap by one knot so the two runs meet rather than leaving a
                // gap where the cord passes behind the rim.
                runStart = index - 1
                runIsRear = segmentIsRear
            }
        }
        appendSmoothCurve(
            Array(chain[runStart...]).map(\.point),
            to: runIsRear ? rear : front
        )
    }

    /// Draws a polyline as a curve that bends through its interior points instead
    /// of turning a corner at each one: quadratic spans between the midpoints of
    /// successive segments, with each knot as the control point it bends around.
    private static func appendSmoothCurve(_ points: [CGPoint], to path: CGMutablePath) {
        guard points.count > 1 else { return }
        path.move(to: points[0])
        guard points.count > 2 else {
            path.addLine(to: points[1])
            return
        }

        for index in 1..<points.count {
            let midpoint = CGPoint(
                x: (points[index - 1].x + points[index].x) / 2,
                y: (points[index - 1].y + points[index].y) / 2
            )
            if index == 1 {
                path.addLine(to: midpoint)
            } else {
                path.addQuadCurve(to: midpoint, control: points[index - 1])
            }
        }
        path.addLine(to: points[points.count - 1])
    }
}

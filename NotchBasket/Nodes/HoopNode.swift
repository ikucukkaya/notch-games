import AppKit
import SpriteKit

enum SideHoopLayout {
    static let mountEdgeX: CGFloat = 112
    static let backboardX: CGFloat = 84
    static let backboardWidth: CGFloat = 14
    static let backboardHeight: CGFloat = 138
    static let backboardCenterY: CGFloat = GameTuning.rimY + 25
    static let outerRimX: CGFloat = -GameTuning.rimPostOffset
    static let attachedRimX: CGFloat = GameTuning.rimPostOffset
    static let rimDepth: CGFloat = 10
    static let boardFaceX: CGFloat = backboardX - (backboardWidth / 2)
    static let supportArmLength: CGFloat = boardFaceX - attachedRimX
}

enum HoopHeightPolicy {
    static func clampedAnchorY(
        _ proposedY: CGFloat,
        floorY: CGFloat,
        screenHeight: CGFloat
    ) -> CGFloat {
        let minimumY = floorY + 180
        let maximumY = screenHeight - 28
        return min(max(proposedY, minimumY), maximumY)
    }
}

final class HoopNode: SKNode {
    let upperSensorName = "upperScoreSensor"
    let lowerSensorName = "lowerScoreSensor"

    private let netNode = NetMeshNode()
    private let netBallGuide = NetFunnelGuide()
    private let rearRimVisual = SKShapeNode()
    private let rimVisual = SKShapeNode()

    override init() {
        super.init()
        name = "hoop"
        zPosition = 15
        buildMount()
        buildBackboard()
        buildRim()
        buildNet()
        buildScoringSensors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func playScoreAnimation(reducedEffects: Bool, ballVelocity: CGVector) {
        netNode.playSwish(
            ballVelocity: ballVelocity,
            reducedEffects: reducedEffects
        )
        rearRimVisual.removeAllActions()
        rimVisual.removeAllActions()
        if reducedEffects {
            let flash = SKAction.sequence([
                .colorize(with: .white, colorBlendFactor: 0.25, duration: 0.06),
                .colorize(withColorBlendFactor: 0, duration: 0.14)
            ])
            rearRimVisual.run(flash)
            rimVisual.run(flash)
            return
        }
        let flash = SKAction.sequence([
            .colorize(with: .white, colorBlendFactor: 0.45, duration: 0.07),
            .colorize(withColorBlendFactor: 0, duration: 0.22)
        ])
        rearRimVisual.run(flash)
        rimVisual.run(flash)
    }

    func updateNet(
        deltaTime: CGFloat,
        ballScenePosition: CGPoint?,
        ballVelocity: CGVector,
        ballRadius: CGFloat,
        reducedEffects: Bool
    ) {
        var contact: NetBallContact?
        if let ballScenePosition, let parent {
            let hoopPoint = convert(ballScenePosition, from: parent)
            contact = NetBallContact(
                position: CGPoint(
                    x: hoopPoint.x - netNode.position.x,
                    y: hoopPoint.y - netNode.position.y
                ),
                velocity: ballVelocity,
                radius: ballRadius
            )
        }

        netNode.updateSimulation(
            deltaTime: deltaTime,
            ballContact: contact,
            reducedEffects: reducedEffects
        )
    }

    func guideBallThroughNet(
        ballScenePosition: CGPoint,
        ballVelocity: CGVector,
        ballRadius: CGFloat,
        deltaTime: CGFloat
    ) -> NetBallGuideResponse? {
        guard let parent else { return nil }
        let hoopPoint = convert(ballScenePosition, from: parent)
        let localContact = NetBallContact(
            position: CGPoint(
                x: hoopPoint.x - netNode.position.x,
                y: hoopPoint.y - netNode.position.y
            ),
            velocity: ballVelocity,
            radius: ballRadius
        )
        guard let localResponse = netBallGuide.response(
            for: localContact,
            deltaTime: deltaTime
        ) else {
            return nil
        }

        let correctedHoopPoint = CGPoint(
            x: localResponse.position.x + netNode.position.x,
            y: localResponse.position.y + netNode.position.y
        )
        return NetBallGuideResponse(
            position: parent.convert(correctedHoopPoint, from: self),
            velocity: localResponse.velocity
        )
    }

    func resetNetBallGuide() {
        netBallGuide.reset()
    }

    private func buildMount() {
        let rimY = GameTuning.rimY
        let boardRearX = SideHoopLayout.backboardX +
            (SideHoopLayout.backboardWidth / 2)

        // The wall-side hardware is deliberately darker than the orange rim
        // assembly, matching the steel hinge and brace visible in broadcast
        // side views.
        let supportPath = CGMutablePath()
        supportPath.move(to: CGPoint(x: boardRearX, y: rimY + 72))
        supportPath.addLine(to: CGPoint(x: SideHoopLayout.mountEdgeX - 5, y: rimY + 49))
        supportPath.move(to: CGPoint(x: boardRearX, y: rimY - 31))
        supportPath.addLine(to: CGPoint(x: SideHoopLayout.mountEdgeX - 5, y: rimY + 6))
        supportPath.move(to: CGPoint(x: boardRearX, y: rimY + 8))
        supportPath.addLine(to: CGPoint(x: SideHoopLayout.mountEdgeX - 5, y: rimY + 28))

        let supportHighlight = SKShapeNode(path: supportPath)
        supportHighlight.strokeColor = NSColor.white.withAlphaComponent(0.62)
        supportHighlight.lineWidth = 7
        supportHighlight.lineCap = .round
        supportHighlight.zPosition = -4
        addChild(supportHighlight)

        let support = SKShapeNode(path: supportPath)
        support.strokeColor = NSColor(calibratedWhite: 0.18, alpha: 0.95)
        support.lineWidth = 4
        support.lineCap = .round
        support.zPosition = -3
        addChild(support)

        let cap = SKShapeNode(rectOf: CGSize(width: 15, height: 96), cornerRadius: 4)
        cap.name = "wallMountVisual"
        cap.position = CGPoint(
            x: SideHoopLayout.mountEdgeX - 5,
            y: rimY + 25
        )
        cap.fillColor = NSColor(calibratedWhite: 0.10, alpha: 0.97)
        cap.strokeColor = NSColor.white.withAlphaComponent(0.68)
        cap.lineWidth = 2
        cap.zPosition = -2
        addChild(cap)

        let hinge = SKShapeNode(circleOfRadius: 7)
        hinge.position = CGPoint(x: SideHoopLayout.mountEdgeX - 5, y: rimY + 27)
        hinge.fillColor = NSColor(calibratedWhite: 0.20, alpha: 1)
        hinge.strokeColor = NSColor.white.withAlphaComponent(0.58)
        hinge.lineWidth = 2
        hinge.zPosition = -1
        addChild(hinge)

        let hingePin = SKShapeNode(circleOfRadius: 2.2)
        hingePin.position = hinge.position
        hingePin.fillColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        hingePin.strokeColor = NSColor.black.withAlphaComponent(0.72)
        hingePin.lineWidth = 1
        hingePin.zPosition = 0
        addChild(hingePin)

        buildOrangeSupportArm()
    }

    private func buildOrangeSupportArm() {
        let rimY = GameTuning.rimY
        let boardX = SideHoopLayout.boardFaceX
        let rimX = SideHoopLayout.attachedRimX

        let armPath = CGMutablePath()
        armPath.move(to: CGPoint(x: boardX, y: rimY + 4))
        armPath.addLine(to: CGPoint(x: rimX - 2, y: rimY + 4))
        armPath.addLine(to: CGPoint(x: rimX - 2, y: rimY - 5))
        armPath.addLine(to: CGPoint(x: boardX, y: rimY - 5))
        armPath.closeSubpath()
        addOrangeMetalShape(
            path: armPath,
            name: "supportArmVisual",
            zPosition: 1
        )

        let bracketPath = CGMutablePath()
        bracketPath.move(to: CGPoint(x: boardX, y: rimY - 4))
        bracketPath.addLine(to: CGPoint(x: rimX + 5, y: rimY - 4))
        bracketPath.addLine(to: CGPoint(x: rimX + 13, y: rimY - 36))
        bracketPath.addLine(to: CGPoint(x: boardX, y: rimY - 36))
        bracketPath.closeSubpath()
        addOrangeMetalShape(
            path: bracketPath,
            name: "mountBracketVisual",
            zPosition: 1
        )

        let braceHighlight = CGMutablePath()
        braceHighlight.move(to: CGPoint(x: rimX + 7, y: rimY - 7))
        braceHighlight.addLine(to: CGPoint(x: rimX + 15, y: rimY - 32))
        let highlight = SKShapeNode(path: braceHighlight)
        highlight.strokeColor = NSColor.white.withAlphaComponent(0.28)
        highlight.lineWidth = 1.2
        highlight.zPosition = 3
        addChild(highlight)
    }

    private func addOrangeMetalShape(
        path: CGPath,
        name: String,
        zPosition: CGFloat
    ) {
        let outline = SKShapeNode(path: path)
        outline.fillColor = NSColor.black.withAlphaComponent(0.72)
        outline.strokeColor = NSColor.black.withAlphaComponent(0.78)
        outline.lineWidth = 5
        outline.zPosition = zPosition
        addChild(outline)

        let metal = SKShapeNode(path: path)
        metal.name = name
        metal.fillColor = NSColor(
            calibratedRed: 0.96,
            green: 0.24,
            blue: 0.055,
            alpha: 1
        )
        metal.strokeColor = NSColor(
            calibratedRed: 1,
            green: 0.44,
            blue: 0.16,
            alpha: 1
        )
        metal.lineWidth = 1.4
        metal.zPosition = zPosition + 1
        addChild(metal)
    }

    private func buildBackboard() {
        let boardSize = CGSize(
            width: SideHoopLayout.backboardWidth,
            height: SideHoopLayout.backboardHeight
        )
        let boardPosition = CGPoint(
            x: SideHoopLayout.backboardX,
            y: SideHoopLayout.backboardCenterY
        )

        // A dark translucent silhouette under the glass keeps the board legible
        // over white documents, while the bright inner edge remains visible over
        // dark wallpapers and windows.
        let boardContrast = SKShapeNode(rectOf: boardSize, cornerRadius: 6)
        boardContrast.position = boardPosition
        boardContrast.fillColor = NSColor.black.withAlphaComponent(0.84)
        boardContrast.strokeColor = NSColor.black.withAlphaComponent(0.82)
        boardContrast.lineWidth = 6
        boardContrast.zPosition = 5
        addChild(boardContrast)

        let board = SKShapeNode(
            rectOf: boardSize,
            cornerRadius: 6
        )
        board.position = boardPosition
        board.name = "backboardVisual"
        board.fillColor = NSColor(calibratedWhite: 0.14, alpha: 0.96)
        board.strokeColor = NSColor.white.withAlphaComponent(0.72)
        board.lineWidth = 2.5
        board.zPosition = 6
        addChild(board)

        let boardFace = SKShapeNode(rectOf: CGSize(
            width: 4,
            height: SideHoopLayout.backboardHeight - 8
        ), cornerRadius: 2)
        boardFace.position = CGPoint(
            x: SideHoopLayout.boardFaceX + 1,
            y: SideHoopLayout.backboardCenterY
        )
        boardFace.fillColor = NSColor(calibratedWhite: 0.34, alpha: 0.72)
        boardFace.strokeColor = NSColor.white.withAlphaComponent(0.30)
        boardFace.lineWidth = 1
        boardFace.zPosition = 7
        addChild(boardFace)

        let collider = SKNode()
        collider.name = "backboard"
        let colliderX = SideHoopLayout.boardFaceX
        let halfHeight = SideHoopLayout.backboardHeight / 2
        let body = SKPhysicsBody(edgeFrom:
            CGPoint(x: colliderX, y: SideHoopLayout.backboardCenterY - halfHeight),
            to: CGPoint(x: colliderX, y: SideHoopLayout.backboardCenterY + halfHeight)
        )
        body.isDynamic = false
        body.restitution = GameTuning.backboardRestitution
        body.friction = 0.12
        body.categoryBitMask = PhysicsCategory.backboard
        body.collisionBitMask = PhysicsCategory.ball
        body.contactTestBitMask = PhysicsCategory.ball
        collider.physicsBody = body
        addChild(collider)
    }

    private func buildRim() {
        let rearPath = CGMutablePath()
        rearPath.move(to: CGPoint(x: SideHoopLayout.outerRimX, y: GameTuning.rimY))
        rearPath.addCurve(
            to: CGPoint(x: SideHoopLayout.attachedRimX, y: GameTuning.rimY),
            control1: CGPoint(
                x: SideHoopLayout.outerRimX + 28,
                y: GameTuning.rimY + (SideHoopLayout.rimDepth / 2)
            ),
            control2: CGPoint(
                x: SideHoopLayout.attachedRimX - 28,
                y: GameTuning.rimY + (SideHoopLayout.rimDepth / 2)
            )
        )

        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: SideHoopLayout.attachedRimX, y: GameTuning.rimY))
        frontPath.addCurve(
            to: CGPoint(x: SideHoopLayout.outerRimX, y: GameTuning.rimY),
            control1: CGPoint(
                x: SideHoopLayout.attachedRimX - 28,
                y: GameTuning.rimY - (SideHoopLayout.rimDepth / 2)
            ),
            control2: CGPoint(
                x: SideHoopLayout.outerRimX + 28,
                y: GameTuning.rimY - (SideHoopLayout.rimDepth / 2)
            )
        )

        let rearOutline = SKShapeNode(path: rearPath)
        rearOutline.strokeColor = NSColor.black.withAlphaComponent(0.70)
        rearOutline.lineWidth = 10
        rearOutline.lineCap = .round
        rearOutline.zPosition = 2
        addChild(rearOutline)

        rearRimVisual.name = "rearRimVisual"
        rearRimVisual.path = rearPath
        rearRimVisual.strokeColor = NSColor(
            calibratedRed: 0.92,
            green: 0.18,
            blue: 0.035,
            alpha: 1
        )
        rearRimVisual.lineWidth = 6
        rearRimVisual.lineCap = .round
        rearRimVisual.zPosition = 3
        addChild(rearRimVisual)

        let frontOutline = SKShapeNode(path: frontPath)
        frontOutline.strokeColor = NSColor.black.withAlphaComponent(0.78)
        frontOutline.lineWidth = 11
        frontOutline.lineCap = .round
        frontOutline.zPosition = 20
        addChild(frontOutline)

        rimVisual.name = "frontRimVisual"
        rimVisual.path = frontPath
        rimVisual.strokeColor = NSColor(calibratedRed: 0.98, green: 0.23, blue: 0.05, alpha: 1)
        rimVisual.lineWidth = 7
        rimVisual.lineCap = .round
        rimVisual.zPosition = 21
        addChild(rimVisual)

        addRimCollider(atX: SideHoopLayout.outerRimX)
        addRimCollider(atX: SideHoopLayout.attachedRimX)
    }

    private func addRimCollider(atX x: CGFloat) {
        let node = SKNode()
        node.name = "rim"
        node.position = CGPoint(x: x, y: GameTuning.rimY)
        let body = SKPhysicsBody(circleOfRadius: GameTuning.rimPostRadius)
        body.isDynamic = false
        body.restitution = GameTuning.rimRestitution
        body.friction = 0.60
        body.categoryBitMask = PhysicsCategory.rim
        body.collisionBitMask = PhysicsCategory.ball
        body.contactTestBitMask = PhysicsCategory.ball
        node.physicsBody = body
        addChild(node)
    }

    private func buildNet() {
        netNode.position = CGPoint(x: 0, y: GameTuning.rimY - 2)
        netNode.zPosition = 1
        addChild(netNode)
    }

    private func buildScoringSensors() {
        addSensor(
            name: upperSensorName,
            y: GameTuning.upperSensorY,
            category: PhysicsCategory.upperScoreSensor
        )
        addSensor(
            name: lowerSensorName,
            y: GameTuning.lowerSensorY,
            category: PhysicsCategory.lowerScoreSensor
        )
    }

    private func addSensor(name: String, y: CGFloat, category: UInt32) {
        let sensor = SKNode()
        sensor.name = name
        sensor.position = CGPoint(x: 0, y: y)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: GameTuning.sensorWidth, height: 5))
        body.isDynamic = false
        body.categoryBitMask = category
        body.collisionBitMask = PhysicsCategory.none
        body.contactTestBitMask = PhysicsCategory.ball
        sensor.physicsBody = body
        addChild(sensor)
    }
}

struct NetBallContact {
    let position: CGPoint
    let velocity: CGVector
    let radius: CGFloat
}

struct NetBallGuideResponse {
    let position: CGPoint
    let velocity: CGVector
}

/// Treats the woven net as a continuous, flexible funnel for the basketball.
/// Individual cords still animate as cloth, but the ball cannot unrealistically
/// escape through a visual diamond whose opening is much smaller than the ball.
final class NetFunnelGuide {
    private let topHalfWidth: CGFloat
    private let bottomHalfWidth: CGFloat
    private let depth: CGFloat

    private(set) var isCapturingBall = false

    init(
        topHalfWidth: CGFloat = GameTuning.rimPostOffset - GameTuning.rimPostRadius,
        bottomHalfWidth: CGFloat = 31,
        depth: CGFloat = 76
    ) {
        self.topHalfWidth = topHalfWidth
        self.bottomHalfWidth = bottomHalfWidth
        self.depth = depth
    }

    func reset() {
        isCapturingBall = false
    }

    func response(
        for contact: NetBallContact,
        deltaTime: CGFloat
    ) -> NetBallGuideResponse? {
        let time = min(max(deltaTime, 0), 1.0 / 30.0)
        guard time > 0, contact.radius > 0 else { return nil }

        let previousPosition = CGPoint(
            x: contact.position.x - (contact.velocity.dx * time),
            y: contact.position.y - (contact.velocity.dy * time)
        )
        if !isCapturingBall {
            guard
                contact.velocity.dy < 0,
                previousPosition.y >= 0,
                contact.position.y <= 0
            else {
                return nil
            }

            let verticalTravel = contact.position.y - previousPosition.y
            let topCrossingFraction = abs(verticalTravel) > 0.001
                ? (0 - previousPosition.y) / verticalTravel
                : 1
            let crossingX = previousPosition.x +
                ((contact.position.x - previousPosition.x) * topCrossingFraction)
            let openingHalfWidth = max(topHalfWidth - contact.radius, 0)
            guard abs(crossingX) <= openingHalfWidth else { return nil }
            isCapturingBall = true
        }

        // An upward rebound may still leave through the open rim. Once the ball
        // is inside and descending, however, its only side-free exit is below.
        if contact.position.y > contact.radius * 0.55,
           contact.velocity.dy > 0 {
            isCapturingBall = false
            return nil
        }

        let progress = min(max(-contact.position.y / depth, 0), 1)
        let wallHalfWidth = topHalfWidth +
            ((bottomHalfWidth - topHalfWidth) * progress)
        let centerLimit = max(wallHalfWidth - contact.radius, 2.5)
        var correctedPosition = contact.position
        var correctedVelocity = contact.velocity

        if correctedPosition.x > centerLimit {
            correctedPosition.x = centerLimit
            if correctedVelocity.dx > 0 {
                correctedVelocity.dx = -min(correctedVelocity.dx * 0.10, 90)
            }
        } else if correctedPosition.x < -centerLimit {
            correctedPosition.x = -centerLimit
            if correctedVelocity.dx < 0 {
                correctedVelocity.dx = min(abs(correctedVelocity.dx) * 0.10, 90)
            }
        }

        // Cord friction removes sideways energy and gently recenters the ball,
        // while retaining almost all downward speed so it cannot hang in the net.
        let frameScale = time * 60
        correctedVelocity.dx *= pow(0.91, frameScale)
        correctedVelocity.dx -= correctedPosition.x *
            (2.0 + (2.6 * progress)) * time
        if correctedVelocity.dy < 0 {
            correctedVelocity.dy *= pow(0.993, frameScale)
        }

        let fullyBelowBottom = contact.position.y <= -(depth + contact.radius)
        if fullyBelowBottom {
            isCapturingBall = false
        }

        return NetBallGuideResponse(
            position: correctedPosition,
            velocity: correctedVelocity
        )
    }
}

private struct NetParticle {
    let restPosition: CGPoint
    var position: CGPoint
    var previousPosition: CGPoint
    let isPinned: Bool
}

private struct NetSpring {
    let firstIndex: Int
    let secondIndex: Int
    let restLength: CGFloat
    let stiffness: CGFloat
}

/// A compact Verlet cloth model used by both rendering and ball contact. The
/// pinned top row follows the projected rim ellipse, while iterative distance
/// constraints let an impact travel through the woven cords without turning
/// the net into a rigid physics wall.
final class NetClothSimulation {
    let rowCount: Int
    let columnCount: Int

    private let topHalfWidth: CGFloat
    private let bottomHalfWidth: CGFloat
    private let depth: CGFloat
    private var particles: [NetParticle] = []
    private var springs: [NetSpring] = []

    init(
        rowCount: Int = 10,
        columnCount: Int = 10,
        topHalfWidth: CGFloat = 52,
        bottomHalfWidth: CGFloat = 31,
        depth: CGFloat = 76
    ) {
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.topHalfWidth = topHalfWidth
        self.bottomHalfWidth = bottomHalfWidth
        self.depth = depth
        buildParticles()
        buildSprings()
    }

    func position(row: Int, column: Int) -> CGPoint {
        particles[index(row: row, column: column)].position
    }

    func restPosition(row: Int, column: Int) -> CGPoint {
        particles[index(row: row, column: column)].restPosition
    }

    var particleCount: Int {
        particles.count
    }

    func totalDisplacement() -> CGFloat {
        particles.reduce(0) { result, particle in
            result + hypot(
                particle.position.x - particle.restPosition.x,
                particle.position.y - particle.restPosition.y
            )
        }
    }

    func step(
        deltaTime: CGFloat,
        ballContact: NetBallContact?,
        responseScale: CGFloat = 1
    ) {
        let time = min(max(deltaTime, 0), 1.0 / 30.0)
        guard time > 0 else { return }

        // Short substeps keep the weave stable and make fast ball contacts less
        // likely to tunnel through the narrow cords between display frames.
        let substepCount = max(1, Int(ceil(time / (1.0 / 120.0))))
        let substep = time / CGFloat(substepCount)
        let startPosition = ballContact.map {
            CGPoint(
                x: $0.position.x - ($0.velocity.dx * time),
                y: $0.position.y - ($0.velocity.dy * time)
            )
        }

        for substepIndex in 0..<substepCount {
            var interpolatedContact = ballContact
            if let ballContact, let startPosition {
                let progress = CGFloat(substepIndex + 1) / CGFloat(substepCount)
                interpolatedContact = NetBallContact(
                    position: CGPoint(
                        x: startPosition.x + ((ballContact.position.x - startPosition.x) * progress),
                        y: startPosition.y + ((ballContact.position.y - startPosition.y) * progress)
                    ),
                    velocity: ballContact.velocity,
                    radius: ballContact.radius
                )
            }
            integrate(
                deltaTime: substep,
                ballContact: interpolatedContact,
                responseScale: min(max(responseScale, 0), 1)
            )
        }
    }

    func applySwishImpulse(ballVelocity: CGVector, responseScale: CGFloat = 1) {
        let scale = min(max(responseScale, 0), 1)
        let lateralVelocity = min(max(ballVelocity.dx, -1_000), 1_000)
        let downwardSpeed = min(max(-ballVelocity.dy, 160), 1_100)
        let verletStep: CGFloat = 1.0 / 120.0

        for particleIndex in particles.indices where !particles[particleIndex].isPinned {
            let row = particleIndex / (columnCount + 1)
            let rowWeight = pow(CGFloat(row) / CGFloat(rowCount), 1.25)
            let centerWeight = 1 - min(
                abs(particles[particleIndex].restPosition.x) / topHalfWidth,
                1
            )
            let localWeight = rowWeight * (0.58 + (centerWeight * 0.42))
            let impulse = CGVector(
                dx: lateralVelocity * 0.055 * localWeight * scale,
                dy: -(42 + (downwardSpeed * 0.12)) * localWeight * scale
            )
            particles[particleIndex].previousPosition.x -= impulse.dx * verletStep
            particles[particleIndex].previousPosition.y -= impulse.dy * verletStep
        }
    }

    private func buildParticles() {
        particles.removeAll(keepingCapacity: true)
        for row in 0...rowCount {
            let rowFraction = CGFloat(row) / CGFloat(rowCount)
            let halfWidth = topHalfWidth +
                ((bottomHalfWidth - topHalfWidth) * rowFraction)
            for column in 0...columnCount {
                let columnFraction = CGFloat(column) / CGFloat(columnCount)
                let rimArc = -2.6 * sin(.pi * columnFraction)
                let point = CGPoint(
                    x: (((columnFraction * 2) - 1) * halfWidth) -
                        (2 * rowFraction),
                    y: rimArc - (depth * pow(rowFraction, 1.04))
                )
                particles.append(NetParticle(
                    restPosition: point,
                    position: point,
                    previousPosition: point,
                    isPinned: row == 0
                ))
            }
        }
    }

    private func buildSprings() {
        springs.removeAll(keepingCapacity: true)
        for row in 0...rowCount {
            for column in 0..<columnCount {
                addSpring(
                    rowA: row,
                    columnA: column,
                    rowB: row,
                    columnB: column + 1,
                    stiffness: 0.24
                )
            }
        }

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                addSpring(
                    rowA: row,
                    columnA: column,
                    rowB: row + 1,
                    columnB: column + 1,
                    stiffness: 0.34
                )
                addSpring(
                    rowA: row,
                    columnA: column + 1,
                    rowB: row + 1,
                    columnB: column,
                    stiffness: 0.34
                )
            }
        }

        // Softer vertical links prevent the projected 2D mesh from folding over
        // itself while leaving the diagonal cords as the dominant structure.
        for row in 0..<rowCount {
            for column in 0...columnCount {
                addSpring(
                    rowA: row,
                    columnA: column,
                    rowB: row + 1,
                    columnB: column,
                    stiffness: 0.10
                )
            }
        }

        // Two-knot bending links distribute a local impact along the cord. They
        // do not make the net rigid; their low stiffness only prevents a single
        // high-resolution segment from folding into a sharp, permanent kink.
        for row in 0...rowCount {
            for column in 0..<(columnCount - 1) {
                addSpring(
                    rowA: row,
                    columnA: column,
                    rowB: row,
                    columnB: column + 2,
                    stiffness: 0.075
                )
            }
        }

        for row in 0..<(rowCount - 1) {
            for column in 0...columnCount {
                addSpring(
                    rowA: row,
                    columnA: column,
                    rowB: row + 2,
                    columnB: column,
                    stiffness: 0.055
                )
            }
        }
    }

    private func addSpring(
        rowA: Int,
        columnA: Int,
        rowB: Int,
        columnB: Int,
        stiffness: CGFloat
    ) {
        let first = index(row: rowA, column: columnA)
        let second = index(row: rowB, column: columnB)
        let deltaX = particles[second].position.x - particles[first].position.x
        let deltaY = particles[second].position.y - particles[first].position.y
        springs.append(NetSpring(
            firstIndex: first,
            secondIndex: second,
            restLength: hypot(deltaX, deltaY),
            stiffness: stiffness
        ))
    }

    private func integrate(
        deltaTime: CGFloat,
        ballContact: NetBallContact?,
        responseScale: CGFloat
    ) {
        let damping: CGFloat = 0.986
        let timeSquared = deltaTime * deltaTime
        for particleIndex in particles.indices where !particles[particleIndex].isPinned {
            let particle = particles[particleIndex]
            let displacement = CGVector(
                dx: (particle.position.x - particle.previousPosition.x) * damping,
                dy: (particle.position.y - particle.previousPosition.y) * damping
            )
            let acceleration = CGVector(
                dx: (particle.restPosition.x - particle.position.x) * 16,
                dy: ((particle.restPosition.y - particle.position.y) * 16) - 18
            )
            particles[particleIndex].previousPosition = particle.position
            particles[particleIndex].position.x +=
                displacement.dx + (acceleration.dx * timeSquared)
            particles[particleIndex].position.y +=
                displacement.dy + (acceleration.dy * timeSquared)
        }

        if let ballContact {
            resolveBallContact(
                ballContact,
                deltaTime: deltaTime,
                responseScale: responseScale
            )
        }

        for _ in 0..<8 {
            solveDistanceConstraints()
            solveHorizontalOrdering()
            solveVerticalOrdering()
            pinTopRow()
        }
        constrainParticles()
        solveHorizontalOrdering()
        solveVerticalOrdering()
        pinTopRow()
    }

    private func solveDistanceConstraints() {
        for spring in springs {
            let first = particles[spring.firstIndex].position
            let second = particles[spring.secondIndex].position
            let deltaX = second.x - first.x
            let deltaY = second.y - first.y
            let distance = max(hypot(deltaX, deltaY), 0.001)
            let difference = (distance - spring.restLength) / distance
            let correctionX = deltaX * difference * spring.stiffness
            let correctionY = deltaY * difference * spring.stiffness
            let firstPinned = particles[spring.firstIndex].isPinned
            let secondPinned = particles[spring.secondIndex].isPinned

            if firstPinned, !secondPinned {
                particles[spring.secondIndex].position.x -= correctionX
                particles[spring.secondIndex].position.y -= correctionY
            } else if !firstPinned, secondPinned {
                particles[spring.firstIndex].position.x += correctionX
                particles[spring.firstIndex].position.y += correctionY
            } else if !firstPinned, !secondPinned {
                particles[spring.firstIndex].position.x += correctionX * 0.5
                particles[spring.firstIndex].position.y += correctionY * 0.5
                particles[spring.secondIndex].position.x -= correctionX * 0.5
                particles[spring.secondIndex].position.y -= correctionY * 0.5
            }
        }
    }

    /// A projected side-view net has no real knot-to-knot collision bodies.
    /// Preserve each row's left-to-right ordering explicitly so adjacent knots
    /// cannot pass through one another and remain tangled after an impact.
    private func solveHorizontalOrdering() {
        for row in 1...rowCount {
            for column in 0..<columnCount {
                let leftIndex = index(row: row, column: column)
                let rightIndex = index(row: row, column: column + 1)
                let restGap = particles[rightIndex].restPosition.x -
                    particles[leftIndex].restPosition.x
                let minimumGap = max(restGap * 0.30, 1.25)
                let currentGap = particles[rightIndex].position.x -
                    particles[leftIndex].position.x
                guard currentGap < minimumGap else { continue }

                let correction = minimumGap - currentGap
                translatePreservingVelocity(
                    particleAt: leftIndex,
                    dx: -correction * 0.5,
                    dy: 0
                )
                translatePreservingVelocity(
                    particleAt: rightIndex,
                    dx: correction * 0.5,
                    dy: 0
                )
            }
        }
    }

    /// Keep successive rows in vertical order while still allowing them to
    /// compress around a ball. This prevents the narrow bottom from flipping
    /// upward through itself, which previously left several knots in one spot.
    private func solveVerticalOrdering() {
        for row in 0..<rowCount {
            for column in 0...columnCount {
                let upperIndex = index(row: row, column: column)
                let lowerIndex = index(row: row + 1, column: column)
                let restDrop = particles[upperIndex].restPosition.y -
                    particles[lowerIndex].restPosition.y
                let minimumDrop = max(restDrop * 0.18, 1.15)
                let currentDrop = particles[upperIndex].position.y -
                    particles[lowerIndex].position.y
                guard currentDrop < minimumDrop else { continue }

                let correction = minimumDrop - currentDrop
                if particles[upperIndex].isPinned {
                    translatePreservingVelocity(
                        particleAt: lowerIndex,
                        dx: 0,
                        dy: -correction
                    )
                } else {
                    translatePreservingVelocity(
                        particleAt: upperIndex,
                        dx: 0,
                        dy: correction * 0.30
                    )
                    translatePreservingVelocity(
                        particleAt: lowerIndex,
                        dx: 0,
                        dy: -correction * 0.70
                    )
                }
            }
        }
    }

    private func translatePreservingVelocity(
        particleAt particleIndex: Int,
        dx: CGFloat,
        dy: CGFloat
    ) {
        guard !particles[particleIndex].isPinned else { return }
        particles[particleIndex].position.x += dx
        particles[particleIndex].position.y += dy
        particles[particleIndex].previousPosition.x += dx
        particles[particleIndex].previousPosition.y += dy
    }

    private func pinTopRow() {
        for column in 0...columnCount {
            let particleIndex = index(row: 0, column: column)
            particles[particleIndex].position = particles[particleIndex].restPosition
            particles[particleIndex].previousPosition = particles[particleIndex].restPosition
        }
    }

    private func resolveBallContact(
        _ contact: NetBallContact,
        deltaTime: CGFloat,
        responseScale: CGFloat
    ) {
        guard contact.radius > 0, responseScale > 0 else { return }
        let previousCenter = CGPoint(
            x: contact.position.x - (contact.velocity.dx * deltaTime),
            y: contact.position.y - (contact.velocity.dy * deltaTime)
        )
        let influenceRadius = contact.radius + 4

        for particleIndex in particles.indices where !particles[particleIndex].isPinned {
            let knot = particles[particleIndex].position
            let closest = closestPoint(
                to: knot,
                onSegmentFrom: previousCenter,
                to: contact.position
            )
            let deltaX = knot.x - closest.x
            let deltaY = knot.y - closest.y
            let distance = hypot(deltaX, deltaY)
            guard distance < influenceRadius else { continue }

            let normal: CGVector
            if distance > 0.001 {
                normal = CGVector(dx: deltaX / distance, dy: deltaY / distance)
            } else {
                let speed = hypot(contact.velocity.dx, contact.velocity.dy)
                if speed > 0.001 {
                    normal = CGVector(
                        dx: contact.velocity.dx / speed,
                        dy: contact.velocity.dy / speed
                    )
                } else {
                    normal = CGVector(
                        dx: 0,
                        dy: contact.position.y <=
                            particles[particleIndex].restPosition.y ? 1 : -1
                    )
                }
            }

            let penetration = influenceRadius - distance
            let positionPush = min(penetration * 0.42 * responseScale, 6.5)
            particles[particleIndex].position.x += normal.dx * positionPush
            particles[particleIndex].position.y += normal.dy * positionPush
            particles[particleIndex].previousPosition.x += normal.dx * positionPush
            particles[particleIndex].previousPosition.y += normal.dy * positionPush

            let directionalSpeed = max(
                (contact.velocity.dx * normal.dx) +
                    (contact.velocity.dy * normal.dy),
                0
            )
            // A stationary overlapping ball only holds the cloth aside through
            // position correction; it must not inject fresh energy every frame.
            let normalImpulse = min(directionalSpeed * 0.16, 280) * responseScale
            let transferredVelocity = CGVector(
                dx: (normal.dx * normalImpulse) +
                    (contact.velocity.dx * 0.024 * responseScale),
                dy: (normal.dy * normalImpulse) +
                    (contact.velocity.dy * 0.024 * responseScale)
            )
            particles[particleIndex].previousPosition.x -=
                transferredVelocity.dx * deltaTime
            particles[particleIndex].previousPosition.y -=
                transferredVelocity.dy * deltaTime
        }
    }

    private func constrainParticles() {
        let maximumDisplacement: CGFloat = 54
        for particleIndex in particles.indices {
            if particles[particleIndex].isPinned {
                particles[particleIndex].position = particles[particleIndex].restPosition
                particles[particleIndex].previousPosition = particles[particleIndex].restPosition
                continue
            }

            let rest = particles[particleIndex].restPosition
            let deltaX = particles[particleIndex].position.x - rest.x
            let deltaY = particles[particleIndex].position.y - rest.y
            let distance = hypot(deltaX, deltaY)
            if distance > maximumDisplacement {
                let scale = maximumDisplacement / distance
                particles[particleIndex].position = CGPoint(
                    x: rest.x + (deltaX * scale),
                    y: rest.y + (deltaY * scale)
                )
                particles[particleIndex].previousPosition = CGPoint(
                    x: particles[particleIndex].position.x -
                        ((particles[particleIndex].position.x -
                            particles[particleIndex].previousPosition.x) * 0.45),
                    y: particles[particleIndex].position.y -
                        ((particles[particleIndex].position.y -
                            particles[particleIndex].previousPosition.y) * 0.45)
                )
            }
        }
    }

    private func closestPoint(
        to point: CGPoint,
        onSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGPoint {
        let segmentX = end.x - start.x
        let segmentY = end.y - start.y
        let lengthSquared = (segmentX * segmentX) + (segmentY * segmentY)
        guard lengthSquared > 0.0001 else { return end }
        let projection = min(max(
            (((point.x - start.x) * segmentX) +
                ((point.y - start.y) * segmentY)) / lengthSquared,
            0
        ), 1)
        return CGPoint(
            x: start.x + (segmentX * projection),
            y: start.y + (segmentY * projection)
        )
    }

    private func index(row: Int, column: Int) -> Int {
        (row * (columnCount + 1)) + column
    }
}

private final class NetMeshNode: SKNode {
    private let rearOutline = SKShapeNode()
    private let rearMesh = SKShapeNode()
    private let frontOutline = SKShapeNode()
    private let frontMesh = SKShapeNode()
    private let simulation = NetClothSimulation()

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

    func playSwish(ballVelocity: CGVector, reducedEffects: Bool) {
        simulation.applySwishImpulse(
            ballVelocity: ballVelocity,
            responseScale: reducedEffects ? 0.30 : 1
        )
        render()
    }

    func updateSimulation(
        deltaTime: CGFloat,
        ballContact: NetBallContact?,
        reducedEffects: Bool
    ) {
        simulation.step(
            deltaTime: deltaTime,
            ballContact: ballContact,
            responseScale: reducedEffects ? 0.38 : 1
        )
        render()
    }

    private func render() {
        let rearPath = CGMutablePath()
        let frontPath = CGMutablePath()
        let rowCount = simulation.rowCount
        let columnCount = simulation.columnCount

        // The attachment cord follows the shallow rim ellipse and sits behind
        // the ball. The two alternating diagonal families are split across the
        // rear/front render layers to create a true woven side-view silhouette.
        for column in 0...columnCount {
            let point = simulation.position(row: 0, column: column)
            if column == 0 {
                rearPath.move(to: point)
            } else {
                rearPath.addLine(to: point)
            }
        }

        // Render one woven cell for every two simulation rows. The hidden
        // middle row becomes the curve control point, so all 121 particles
        // still shape the motion without drawing a cage-like number of cords.
        for row in stride(from: 0, to: rowCount, by: 2) {
            let endRow = min(row + 2, rowCount)
            let controlRow = min(row + 1, endRow)
            for column in 0..<columnCount {
                let control = midpoint(
                    simulation.position(row: controlRow, column: column),
                    simulation.position(row: controlRow, column: column + 1)
                )

                addSmoothCord(
                    to: rearPath,
                    from: simulation.position(row: row, column: column),
                    through: control,
                    to: simulation.position(row: endRow, column: column + 1)
                )
                addSmoothCord(
                    to: frontPath,
                    from: simulation.position(row: row, column: column + 1),
                    through: control,
                    to: simulation.position(row: endRow, column: column)
                )
            }
        }

        // Loose scallops at the bottom prevent the constrained grid from reading
        // as a rigid cage when the net is at rest or wrapped around the ball.
        for column in 0..<columnCount {
            let left = simulation.position(row: rowCount, column: column)
            let right = simulation.position(row: rowCount, column: column + 1)
            let midpoint = CGPoint(
                x: (left.x + right.x) / 2,
                y: min(left.y, right.y) - 4
            )
            frontPath.move(to: left)
            frontPath.addQuadCurve(to: right, control: midpoint)
        }

        rearOutline.path = rearPath
        rearMesh.path = rearPath
        frontOutline.path = frontPath
        frontMesh.path = frontPath
    }

    private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(
            x: (first.x + second.x) * 0.5,
            y: (first.y + second.y) * 0.5
        )
    }

    private func addSmoothCord(
        to path: CGMutablePath,
        from start: CGPoint,
        through midpoint: CGPoint,
        to end: CGPoint
    ) {
        // Choose the quadratic control point so the rendered cord passes
        // through the simulated middle vertex at t = 0.5.
        let control = CGPoint(
            x: (2 * midpoint.x) - (0.5 * start.x) - (0.5 * end.x),
            y: (2 * midpoint.y) - (0.5 * start.y) - (0.5 * end.y)
        )
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
    }
}

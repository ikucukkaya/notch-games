import AppKit
import SpriteKit

enum SideHoopLayout {
    static let mountEdgeX: CGFloat = 112
    static let backboardX: CGFloat = 84
    static let backboardWidth: CGFloat = 14
    /// 138 originally, raised twice by 20%. At 2.05 rim diameters the board is now
    /// about 88% of the NBA proportion (2.33); the remaining gap is the price of
    /// hanging the assembly off the notch and keeping it on screen.
    static let backboardHeight: CGFloat = 198.72

    /// The board grows upward only: its lower edge stays fixed relative to the
    /// rim so the mounting hardware, the bracket and the rim keep the alignment
    /// they were drawn with, and only the glass above the rim gets taller.
    static let backboardBottomY: CGFloat = GameTuning.rimY - 44
    static let backboardCenterY: CGFloat =
        backboardBottomY + (backboardHeight / 2)

    /// The highest point of the whole assembly, measured from the hoop's anchor.
    /// `HoopHeightPolicy` needs it to keep the board on screen.
    static let assemblyTopY: CGFloat = backboardCenterY + (backboardHeight / 2)
    static let outerRimX: CGFloat = -GameTuning.rimPostOffset
    static let attachedRimX: CGFloat = GameTuning.rimPostOffset
    static let rimDepth: CGFloat = 10
    static let boardFaceX: CGFloat = backboardX - (backboardWidth / 2)
    static let supportArmLength: CGFloat = boardFaceX - attachedRimX
}

enum HoopHeightPolicy {
    /// How much clear space to leave above the backboard at the top of the range.
    static let topMargin: CGFloat = 12

    static func clampedAnchorY(
        _ proposedY: CGFloat,
        floorY: CGFloat,
        screenHeight: CGFloat
    ) -> CGFloat {
        let minimumY = floorY + 180
        // Derived from the backboard's upper edge rather than a bare constant:
        // the board reaches above the anchor, so making it taller must not
        // silently push it off the top of the display.
        let maximumY = screenHeight - SideHoopLayout.assemblyTopY - topMargin
        return min(max(proposedY, minimumY), maximumY)
    }
}

final class HoopNode: SKNode {
    let upperSensorName = "upperScoreSensor"
    let lowerSensorName = "lowerScoreSensor"

    private let netNode = NetMeshNode()
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

    /// The net is no longer animated on a score: the swish is whatever the ball
    /// actually did to the cords on its way through. Only the rim still flashes.
    func playScoreAnimation(reducedEffects: Bool, ballVelocity: CGVector) {
        _ = ballVelocity
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

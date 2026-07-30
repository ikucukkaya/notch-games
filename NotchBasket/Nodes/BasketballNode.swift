import AppKit
import SpriteKit

final class BasketballNode: SKNode {
    let radius: CGFloat

    init(diameter: CGFloat) {
        radius = diameter / 2
        super.init()
        name = "basketball"
        zPosition = 30
        buildVisuals()
        configurePhysics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildVisuals() {
        let shadow = SKShapeNode(circleOfRadius: radius)
        shadow.fillColor = NSColor.black.withAlphaComponent(0.20)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 1.5, y: -2.5)
        shadow.zPosition = -2
        addChild(shadow)

        let ball = SKShapeNode(circleOfRadius: radius)
        ball.fillColor = NSColor(calibratedRed: 0.95, green: 0.34, blue: 0.08, alpha: 1)
        ball.strokeColor = NSColor(calibratedRed: 0.40, green: 0.12, blue: 0.04, alpha: 1)
        ball.lineWidth = 2
        addChild(ball)

        let highlight = SKShapeNode(ellipseOf: CGSize(width: radius * 0.72, height: radius * 0.40))
        highlight.fillColor = NSColor.white.withAlphaComponent(0.16)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -radius * 0.25, y: radius * 0.32)
        highlight.zRotation = .pi / 5
        highlight.zPosition = 2
        addChild(highlight)

        let seamColor = NSColor(calibratedWhite: 0.12, alpha: 0.78)
        addSeam(path: diameterPath(horizontal: true), color: seamColor)
        addSeam(path: diameterPath(horizontal: false), color: seamColor)
        addSeam(path: curvedSeam(mirrored: false), color: seamColor)
        addSeam(path: curvedSeam(mirrored: true), color: seamColor)
    }

    private func configurePhysics() {
        // The collision radius is the drawn radius. It used to be 0.94 of it —
        // the usual trick of making a hoop quieter about near misses — but that
        // stacked on top of an already-generous rim and left the net simulation
        // (which reads `radius`) disagreeing with what the rim actually collided
        // with. One radius, one ball.
        let body = SKPhysicsBody(circleOfRadius: radius)
        body.mass = 0.34
        body.restitution = GameTuning.ballRestitution
        body.friction = GameTuning.ballFriction
        body.linearDamping = GameTuning.ballLinearDamping
        body.angularDamping = GameTuning.ballAngularDamping
        body.allowsRotation = true
        body.usesPreciseCollisionDetection = true
        body.categoryBitMask = PhysicsCategory.ball
        body.collisionBitMask =
            PhysicsCategory.rim |
            PhysicsCategory.backboard |
            PhysicsCategory.boundary
        body.contactTestBitMask =
            PhysicsCategory.rim |
            PhysicsCategory.backboard |
            PhysicsCategory.boundary |
            PhysicsCategory.upperScoreSensor |
            PhysicsCategory.lowerScoreSensor
        physicsBody = body
    }

    private func diameterPath(horizontal: Bool) -> CGPath {
        let path = CGMutablePath()
        if horizontal {
            path.move(to: CGPoint(x: -radius * 0.92, y: 0))
            path.addLine(to: CGPoint(x: radius * 0.92, y: 0))
        } else {
            path.move(to: CGPoint(x: 0, y: -radius * 0.92))
            path.addLine(to: CGPoint(x: 0, y: radius * 0.92))
        }
        return path
    }

    private func curvedSeam(mirrored: Bool) -> CGPath {
        let direction: CGFloat = mirrored ? -1 : 1
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -radius * 0.66 * direction, y: -radius * 0.66))
        path.addCurve(
            to: CGPoint(x: -radius * 0.66 * direction, y: radius * 0.66),
            control1: CGPoint(x: radius * 0.10 * direction, y: -radius * 0.30),
            control2: CGPoint(x: radius * 0.10 * direction, y: radius * 0.30)
        )
        return path
    }

    private func addSeam(path: CGPath, color: NSColor) {
        let seam = SKShapeNode(path: path)
        seam.strokeColor = color
        seam.lineWidth = max(radius * 0.075, 1.5)
        seam.lineCap = .round
        seam.zPosition = 3
        addChild(seam)
    }
}

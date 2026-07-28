import AppKit
import SpriteKit

final class AimIndicatorNode: SKNode {
    private let trajectoryNode = SKShapeNode()
    private let powerNode = SKShapeNode()

    override init() {
        super.init()
        zPosition = 20
        trajectoryNode.lineCap = .round
        addChild(trajectoryNode)
        addChild(powerNode)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(
        from ballPosition: CGPoint,
        velocity: CGVector,
        gravity: CGFloat,
        powerFraction: CGFloat
    ) {
        guard velocity.length > 0 else {
            hide()
            return
        }

        isHidden = false
        let path = CGMutablePath()
        let timeStep: CGFloat = 0.10
        let displayScale: CGFloat = 0.20

        for index in 1...12 {
            let time = CGFloat(index) * timeStep
            let point = CGPoint(
                x: ballPosition.x + velocity.dx * time * displayScale,
                y: ballPosition.y +
                    velocity.dy * time * displayScale +
                    0.5 * gravity * pow(time * 3.2, 2)
            )
            let dotRadius: CGFloat = index == 1 ? 3.1 : 2.2
            path.addEllipse(in: CGRect(
                x: point.x - dotRadius,
                y: point.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
        }

        trajectoryNode.path = path
        trajectoryNode.fillColor = NSColor.white.withAlphaComponent(0.74)
        trajectoryNode.strokeColor = .clear

        let ringRadius = GameTuning.ballDiameter * 0.63
        let powerPath = CGMutablePath()
        powerPath.addArc(
            center: ballPosition,
            radius: ringRadius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + (2 * .pi * min(max(powerFraction, 0), 1)),
            clockwise: false
        )
        powerNode.path = powerPath
        powerNode.strokeColor = powerFraction >= 0.98
            ? NSColor.systemYellow
            : NSColor.white.withAlphaComponent(0.55)
        powerNode.lineWidth = 3
        powerNode.lineCap = .round
    }

    func hide() {
        isHidden = true
        trajectoryNode.path = nil
        powerNode.path = nil
    }
}

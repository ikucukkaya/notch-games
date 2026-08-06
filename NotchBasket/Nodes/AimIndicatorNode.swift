import AppKit
import SpriteKit

final class AimIndicatorNode: SKNode {
    private let trajectoryOutline = SKShapeNode()
    private let trajectoryNode = SKShapeNode()
    private let powerOutline = SKShapeNode()
    private let powerNode = SKShapeNode()

    override init() {
        super.init()
        zPosition = 20

        // The guide is drawn over whatever the user happens to have on screen and
        // the app never samples the desktop, so a single tone cannot work: plain
        // white vanished over white documents. Same dual-tone treatment the hoop
        // uses — a dark silhouette carries the shape over light backgrounds, the
        // bright fill carries it over dark ones.
        trajectoryOutline.name = "aimTrajectoryOutline"
        trajectoryOutline.lineCap = .round
        trajectoryOutline.fillColor = NSColor.black.withAlphaComponent(0.55)
        trajectoryOutline.strokeColor = NSColor.black.withAlphaComponent(0.62)
        trajectoryOutline.lineWidth = 3.2
        trajectoryOutline.zPosition = 0
        addChild(trajectoryOutline)

        trajectoryNode.name = "aimTrajectoryFill"
        trajectoryNode.lineCap = .round
        trajectoryNode.strokeColor = .clear
        trajectoryNode.zPosition = 1
        addChild(trajectoryNode)

        powerOutline.name = "aimPowerOutline"
        powerOutline.lineCap = .round
        powerOutline.strokeColor = NSColor.black.withAlphaComponent(0.60)
        powerOutline.lineWidth = 6
        powerOutline.zPosition = 0
        addChild(powerOutline)

        powerNode.name = "aimPowerRing"
        powerNode.lineCap = .round
        powerNode.lineWidth = 3
        powerNode.zPosition = 1
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

        trajectoryOutline.path = path
        trajectoryNode.path = path
        trajectoryNode.fillColor = NSColor.white.withAlphaComponent(0.96)

        let ringRadius = GameTuning.ballDiameter * 0.63
        let powerPath = CGMutablePath()
        powerPath.addArc(
            center: ballPosition,
            radius: ringRadius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + (2 * .pi * min(max(powerFraction, 0), 1)),
            clockwise: false
        )
        powerOutline.path = powerPath
        powerNode.path = powerPath
        // Green at rest sweeping through yellow to red at full power. Saturated
        // hues are low-contrast against some windows; the dark outline behind
        // the ring is what keeps it readable, not the hue itself.
        powerNode.strokeColor = Self.powerColor(fraction: powerFraction)
    }

    /// The power ring's hue: green (0.33) at no power, through yellow, to red
    /// (0.0) at full power. Out-of-range fractions clamp rather than wrapping
    /// the hue wheel back toward green.
    static func powerColor(fraction: CGFloat) -> NSColor {
        let clamped = min(max(fraction, 0), 1)
        return NSColor(
            hue: 0.33 * (1 - clamped),
            saturation: 0.85,
            brightness: 0.95,
            alpha: 0.96
        )
    }

    func hide() {
        isHidden = true
        trajectoryOutline.path = nil
        trajectoryNode.path = nil
        powerOutline.path = nil
        powerNode.path = nil
    }
}

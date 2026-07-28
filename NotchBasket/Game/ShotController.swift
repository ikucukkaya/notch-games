import CoreGraphics

protocol ShotCalculating {
    func launchVelocity(
        ballOrigin: CGPoint,
        dragPoint: CGPoint,
        sensitivity: CGFloat
    ) -> CGVector
}

struct ShotController: ShotCalculating {
    let minimumDragDistance: CGFloat
    let maximumDragDistance: CGFloat
    let powerMultiplier: CGFloat
    let maximumLaunchSpeed: CGFloat

    init(
        minimumDragDistance: CGFloat = GameTuning.minimumDragDistance,
        maximumDragDistance: CGFloat = GameTuning.maximumDragDistance,
        powerMultiplier: CGFloat = GameTuning.defaultPowerMultiplier,
        maximumLaunchSpeed: CGFloat = GameTuning.maximumLaunchSpeed
    ) {
        self.minimumDragDistance = minimumDragDistance
        self.maximumDragDistance = maximumDragDistance
        self.powerMultiplier = powerMultiplier
        self.maximumLaunchSpeed = maximumLaunchSpeed
    }

    func clampedDragVector(ballOrigin: CGPoint, dragPoint: CGPoint) -> CGVector {
        let raw = CGVector(dx: dragPoint.x - ballOrigin.x, dy: dragPoint.y - ballOrigin.y)
        let length = raw.length
        guard length > maximumDragDistance, length > 0 else { return raw }
        return raw.scaled(by: maximumDragDistance / length)
    }

    func clampedDragPoint(ballOrigin: CGPoint, dragPoint: CGPoint) -> CGPoint {
        let vector = clampedDragVector(ballOrigin: ballOrigin, dragPoint: dragPoint)
        return CGPoint(x: ballOrigin.x + vector.dx, y: ballOrigin.y + vector.dy)
    }

    /// Preserves the full slingshot range when a settled ball is too close to the
    /// bottom of the display for the pointer to travel `maximumDragDistance`.
    func bottomEdgeCompensatedDragPoint(
        ballOrigin: CGPoint,
        pointerPoint: CGPoint,
        sceneBottomY: CGFloat = 0
    ) -> CGPoint {
        let rawVerticalPull = pointerPoint.y - ballOrigin.y
        guard rawVerticalPull < 0 else { return pointerPoint }

        let availableDownwardTravel = max(ballOrigin.y - sceneBottomY, 1)
        guard availableDownwardTravel < maximumDragDistance else { return pointerPoint }

        let verticalGain = maximumDragDistance / availableDownwardTravel
        return CGPoint(
            x: pointerPoint.x,
            y: ballOrigin.y + rawVerticalPull * verticalGain
        )
    }

    func launchVelocity(
        ballOrigin: CGPoint,
        dragPoint: CGPoint,
        sensitivity: CGFloat
    ) -> CGVector {
        let drag = clampedDragVector(ballOrigin: ballOrigin, dragPoint: dragPoint)
        guard drag.length >= minimumDragDistance else { return .zero }

        let safeSensitivity = min(max(sensitivity, 0.5), 1.5)
        let launch = CGVector(
            dx: -drag.dx * powerMultiplier * safeSensitivity,
            dy: -drag.dy * powerMultiplier * safeSensitivity
        )
        guard launch.length > maximumLaunchSpeed else { return launch }
        return launch.scaled(by: maximumLaunchSpeed / launch.length)
    }
}

extension CGVector {
    var length: CGFloat {
        sqrt((dx * dx) + (dy * dy))
    }

    func scaled(by scale: CGFloat) -> CGVector {
        CGVector(dx: dx * scale, dy: dy * scale)
    }
}

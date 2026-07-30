import CoreGraphics
import Foundation

enum GameTuning {
    static let gravity: CGFloat = -10.2
    static let lowGravity: CGFloat = -7.8
    static let highGravity: CGFloat = -12.4

    /// Regulation proportion against the rim. An NBA ball is 29.5" around, so
    /// 9.39" across, against an 18" rim — a ratio of 0.522. The rim's clear
    /// opening here is `2 * (rimPostOffset - rimPostRadius)` = 97, so 50.6
    /// reproduces that exactly. It was 48 (0.495), which read a touch small.
    static let ballDiameter: CGFloat = 50.6
    static let minimumBallDiameter: CGFloat = 40
    static let maximumBallDiameter: CGFloat = 60
    static let ballMass: CGFloat = 0.34

    /// The force the ball's own weight represents. Net reaction forces are sized
    /// in multiples of this rather than in absolute numbers: a ratio to weight is
    /// a real, scale-free quantity, whereas a bare force is only meaningful once
    /// you also know the mass and SpriteKit's internal force scale — and getting
    /// that wrong once already had the net shoving the ball around at 26 g.
    static let ballWeight: CGFloat = ballMass * abs(gravity)

    static let ballRestitution: CGFloat = 0.74
    static let ballFriction: CGFloat = 0.58
    static let ballLinearDamping: CGFloat = 0.22
    static let ballAngularDamping: CGFloat = 0.10

    static let rimRestitution: CGFloat = 0.68
    static let backboardRestitution: CGFloat = 0.62
    static let boundaryRestitution: CGFloat = 0.72

    static let minimumDragDistance: CGFloat = 12
    static let maximumDragDistance: CGFloat = 155
    // Tuned so a firm pull comfortably reaches the rim on a 16-inch MacBook panel.
    static let defaultPowerMultiplier: CGFloat = 15
    static let maximumLaunchSpeed: CGFloat = 2_800

    static let shotTimeout: TimeInterval = 8
    static let stillSpeedThreshold: CGFloat = 24
    static let stillDurationBeforeReset: TimeInterval = 0.65
    static let minimumAudibleFloorImpactSpeed: CGFloat = 125
    static let defaultResetDelay: TimeInterval = 0.55

    static let hoopScale: CGFloat = 1
    static let rimPostRadius: CGFloat = 5.5
    static let rimPostOffset: CGFloat = 54
    static let rimY: CGFloat = -78
    static let upperSensorY: CGFloat = -66
    static let lowerSensorY: CGFloat = -105
    static let sensorWidth: CGFloat = 82
}

import CoreGraphics
import Foundation

enum GameTuning {
    static let gravity: CGFloat = -10.2
    static let lowGravity: CGFloat = -7.8
    static let highGravity: CGFloat = -12.4

    static let ballDiameter: CGFloat = 48
    static let minimumBallDiameter: CGFloat = 40
    static let maximumBallDiameter: CGFloat = 60
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

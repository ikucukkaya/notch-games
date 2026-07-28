import CoreGraphics
import Foundation

protocol ScoreTracking: AnyObject {
    func registerUpperSensorEntry()
    func registerLowerSensorEntry(verticalVelocity: CGFloat) -> Bool
    func resetForNewShot()
}

final class ScoreController: ScoreTracking {
    private enum PassageState {
        case waitingForUpper
        case crossedUpper
        case completed
    }

    private var passageState: PassageState = .waitingForUpper

    func registerUpperSensorEntry() {
        guard passageState == .waitingForUpper else { return }
        passageState = .crossedUpper
    }

    func registerLowerSensorEntry(verticalVelocity: CGFloat) -> Bool {
        guard passageState == .crossedUpper, verticalVelocity < 0 else { return false }
        passageState = .completed
        return true
    }

    func resetForNewShot() {
        passageState = .waitingForUpper
    }
}

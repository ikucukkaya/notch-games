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

    // NBA and FIBA both rule that a ball entering the basket from below can
    // never score. An upward pass through the lower sensor latches this; the
    // latch clears when the ball drops back out of the bottom of the cylinder,
    // so a later genuine descent may score again.
    private var enteredFromBelow = false

    func registerUpperSensorEntry() {
        guard !enteredFromBelow, passageState == .waitingForUpper else { return }
        passageState = .crossedUpper
    }

    func registerLowerSensorEntry(verticalVelocity: CGFloat) -> Bool {
        if verticalVelocity > 0 {
            enteredFromBelow = true
            passageState = .waitingForUpper
            return false
        }
        guard verticalVelocity < 0 else { return false }
        if enteredFromBelow {
            enteredFromBelow = false
            passageState = .waitingForUpper
            return false
        }
        guard passageState == .crossedUpper else { return false }
        passageState = .completed
        return true
    }

    func resetForNewShot() {
        passageState = .waitingForUpper
        enteredFromBelow = false
    }
}

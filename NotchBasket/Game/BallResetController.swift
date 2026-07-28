import CoreGraphics
import Foundation

enum ShotCompletionReason: Equatable {
    case settled
    case timedOut
    case leftPlayableRegion
}

struct BallResetController {
    private(set) var shotStartedAt: TimeInterval?
    private(set) var becameStillAt: TimeInterval?

    mutating func beginShot(at time: TimeInterval) {
        shotStartedAt = time
        becameStillAt = nil
    }

    mutating func reset() {
        shotStartedAt = nil
        becameStillAt = nil
    }

    mutating func completionReason(
        at time: TimeInterval,
        speed: CGFloat,
        isInsidePlayableRegion: Bool
    ) -> ShotCompletionReason? {
        guard let shotStartedAt else { return nil }
        if !isInsidePlayableRegion {
            return .leftPlayableRegion
        }
        if time - shotStartedAt >= GameTuning.shotTimeout {
            return .timedOut
        }

        if speed <= GameTuning.stillSpeedThreshold {
            if let becameStillAt {
                return time - becameStillAt >= GameTuning.stillDurationBeforeReset
                    ? .settled
                    : nil
            }
            becameStillAt = time
        } else {
            becameStillAt = nil
        }
        return nil
    }
}

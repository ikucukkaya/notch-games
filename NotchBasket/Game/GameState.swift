import Foundation

enum GameMode: Equatable {
    case hidden
    case presenting
    case active
    case dismissing
}

enum BallState: String, Equatable {
    case spawning
    case ready
    case aiming
    case flying
    case scored
    case settling
    case resetting
}

enum BallInteractionPolicy {
    static func isGrabbable(_ state: BallState) -> Bool {
        switch state {
        case .ready, .flying, .scored:
            true
        case .spawning, .aiming, .settling, .resetting:
            false
        }
    }
}

struct SessionStatistics: Equatable {
    var score = 0
    var streak = 0
    var bestStreak = 0
    var shotsAttempted = 0
    var successfulShots = 0

    var accuracy: Double {
        guard shotsAttempted > 0 else { return 0 }
        return Double(successfulShots) / Double(shotsAttempted)
    }
}

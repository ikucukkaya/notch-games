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


/// Which game is being played. `free` is the original toy; `shotClock24` is the
/// NBA-style possession game: 24 seconds to score, a basket buys a fresh 24,
/// and an expired clock ends the run.
enum PlayMode: String, CaseIterable, Identifiable {
    case free
    case shotClock24

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free play"
        case .shotClock24: "24 Seconds"
        }
    }
}

/// The 24-second clock's rules, kept pure and time-injected so every rule is
/// testable without a scene. The scene owns *when* things happen (grabs, scores,
/// shot resolutions) and asks this controller what they mean.
final class ShotClockController {
    static let duration: TimeInterval = 24

    private(set) var deadline: TimeInterval?
    private(set) var runScore = 0

    /// The clock expired while a shot was in the air. NBA rule: a ball released
    /// before the buzzer still counts if it goes in — so the run's fate rides on
    /// that shot instead of ending at the horn.
    private(set) var isAwaitingBuzzerBeater = false

    var isRunning: Bool { deadline != nil }

    /// Full 24 while armed; the live remainder once running; never negative.
    func remaining(at now: TimeInterval) -> TimeInterval {
        guard let deadline else { return Self.duration }
        return max(deadline - now, 0)
    }

    /// The clock does not start with the game — it starts the first time the
    /// player takes the ball. Later grabs in the same run change nothing.
    func ballGrabbed(at now: TimeInterval) {
        guard deadline == nil else { return }
        deadline = now + Self.duration
    }

    /// A basket: its point value and a fresh 24 — including a buzzer-beater,
    /// which is precisely a basket scored after the deadline passed.
    func registerScore(points: Int, at now: TimeInterval) {
        guard isRunning else { return }
        runScore += points
        isAwaitingBuzzerBeater = false
        deadline = now + Self.duration
    }

    enum Expiry: Equatable {
        case none
        case awaitingShot
        case violation
    }

    /// Poll once per frame. A ball in flight defers the verdict to that shot;
    /// a held or resting ball at zero is a violation on the spot.
    func checkExpiry(at now: TimeInterval, ballInFlight: Bool) -> Expiry {
        guard let deadline, now >= deadline else { return .none }
        if ballInFlight {
            isAwaitingBuzzerBeater = true
            return .awaitingShot
        }
        return .violation
    }

    /// Ends the run and returns its score. `ballHeld` means the horn caught the
    /// player mid-aim: the ball in their hand is already the first grab of the
    /// next run, so the fresh clock starts immediately.
    func endRun(at now: TimeInterval, ballHeld: Bool) -> Int {
        let finished = runScore
        runScore = 0
        isAwaitingBuzzerBeater = false
        deadline = ballHeld ? now + Self.duration : nil
        return finished
    }

    /// Wipes the run without recording it: mode changes and session restarts
    /// both abandon the possession rather than scoring it.
    func resetAbandoningRun() {
        runScore = 0
        isAwaitingBuzzerBeater = false
        deadline = nil
    }
}


/// Two- and three-point scoring. What counts is where the shot was *released* —
/// the shooter's feet, not where the ball lands — and the hoop hangs on the
/// right, so smaller x means farther out. On the line is two, as in the NBA.
enum ScoringPolicy {
    /// The three-point line's distance from the rim, as a fraction of the
    /// playable depth between the left boundary and the rim: the NBA arc sits
    /// 23.75 ft from the basket on a 47 ft half court.
    static let threePointDepthFraction: CGFloat = 23.75 / 47

    static func threePointLineX(
        leftBoundaryX: CGFloat,
        rimCenterX: CGFloat
    ) -> CGFloat {
        rimCenterX - ((rimCenterX - leftBoundaryX) * threePointDepthFraction)
    }

    static func points(releaseX: CGFloat, threePointLineX: CGFloat) -> Int {
        releaseX < threePointLineX ? 3 : 2
    }
}

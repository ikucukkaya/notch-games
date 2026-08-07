import Combine
import Foundation

enum GravityPreset: String, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var gravity: CGFloat {
        switch self {
        case .low: GameTuning.lowGravity
        case .normal: GameTuning.gravity
        case .high: GameTuning.highGravity
        }
    }
}

final class PreferencesService: ObservableObject {
    static let hoopVerticalOffsetRange: ClosedRange<Double> = -500...250

    private enum Key {
        static let soundEnabled = "soundEnabled"
        static let masterVolume = "masterVolume"
        static let showScore = "showScore"
        static let aimGuideEnabled = "aimGuideEnabled"
        static let hapticsEnabled = "hapticsEnabled"
        static let hoopHorizontalOffset = "hoopHorizontalOffset"
        static let hoopVerticalOffset = "hoopVerticalOffset"
        static let launchSensitivity = "launchSensitivity"
        static let gravityPreset = "gravityPreset"
        static let debugGeometry = "debugGeometry"
        static let reducedEffects = "reducedEffects"
        static let showDockIcon = "showDockIcon"
        static let bestStreak = "bestStreak"
        static let playMode = "playMode"
        static let hideFromScreenCapture = "hideFromScreenCapture"
        static let bestShotClockRun = "bestShotClockRun"
        static let bestFreePlayScore = "bestFreePlayScore"
        static let lifetimeBaskets = "lifetimeBaskets"
        static let lifetimeShots = "lifetimeShots"
        static let hasShownOnboarding = "hasShownOnboarding"
    }

    private let defaults: UserDefaults

    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }
    @Published var masterVolume: Double { didSet { defaults.set(masterVolume, forKey: Key.masterVolume) } }
    @Published var showScore: Bool { didSet { defaults.set(showScore, forKey: Key.showScore) } }
    @Published var aimGuideEnabled: Bool { didSet { defaults.set(aimGuideEnabled, forKey: Key.aimGuideEnabled) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }
    @Published var hoopHorizontalOffset: Double { didSet { defaults.set(hoopHorizontalOffset, forKey: Key.hoopHorizontalOffset) } }
    @Published var hoopVerticalOffset: Double { didSet { defaults.set(hoopVerticalOffset, forKey: Key.hoopVerticalOffset) } }
    @Published var launchSensitivity: Double { didSet { defaults.set(launchSensitivity, forKey: Key.launchSensitivity) } }
    @Published var gravityPreset: GravityPreset { didSet { defaults.set(gravityPreset.rawValue, forKey: Key.gravityPreset) } }
    @Published var debugGeometry: Bool { didSet { defaults.set(debugGeometry, forKey: Key.debugGeometry) } }
    @Published var reducedEffects: Bool { didSet { defaults.set(reducedEffects, forKey: Key.reducedEffects) } }
    @Published var showDockIcon: Bool { didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) } }
    @Published var playMode: PlayMode { didSet { defaults.set(playMode.rawValue, forKey: Key.playMode) } }
    @Published var hideFromScreenCapture: Bool { didSet { defaults.set(hideFromScreenCapture, forKey: Key.hideFromScreenCapture) } }

    private(set) var bestShotClockRun: Int {
        didSet { defaults.set(bestShotClockRun, forKey: Key.bestShotClockRun) }
    }

    /// Free play's headline record: the highest the score ever climbed in a
    /// session. `bestStreak` still tracks the longest run of makes — it earns
    /// the celebratory haptic — but it is not what the scoreboard chases.
    private(set) var bestFreePlayScore: Int {
        didSet { defaults.set(bestFreePlayScore, forKey: Key.bestFreePlayScore) }
    }

    private(set) var bestStreak: Int {
        didSet { defaults.set(bestStreak, forKey: Key.bestStreak) }
    }
    private(set) var lifetimeBaskets: Int {
        didSet { defaults.set(lifetimeBaskets, forKey: Key.lifetimeBaskets) }
    }
    private(set) var lifetimeShots: Int {
        didSet { defaults.set(lifetimeShots, forKey: Key.lifetimeShots) }
    }

    var hasShownOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasShownOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasShownOnboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.soundEnabled: true,
            Key.masterVolume: 0.7,
            Key.showScore: true,
            Key.aimGuideEnabled: true,
            Key.hapticsEnabled: true,
            Key.hoopHorizontalOffset: 0.0,
            Key.hoopVerticalOffset: 0.0,
            Key.launchSensitivity: 1.0,
            Key.gravityPreset: GravityPreset.normal.rawValue,
            Key.debugGeometry: false,
            Key.reducedEffects: false,
            Key.showDockIcon: false,
            Key.bestStreak: 0,
            Key.playMode: PlayMode.shotClock24.rawValue,
            Key.hideFromScreenCapture: false,
            Key.bestShotClockRun: 0,
            Key.bestFreePlayScore: 0,
            Key.lifetimeBaskets: 0,
            Key.lifetimeShots: 0,
            Key.hasShownOnboarding: false
        ])

        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        masterVolume = Self.clamp(defaults.double(forKey: Key.masterVolume), range: 0...1)
        showScore = defaults.bool(forKey: Key.showScore)
        aimGuideEnabled = defaults.bool(forKey: Key.aimGuideEnabled)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        hoopHorizontalOffset = Self.clamp(defaults.double(forKey: Key.hoopHorizontalOffset), range: -180...180)
        hoopVerticalOffset = Self.clamp(
            defaults.double(forKey: Key.hoopVerticalOffset),
            range: Self.hoopVerticalOffsetRange
        )
        launchSensitivity = Self.clamp(defaults.double(forKey: Key.launchSensitivity), range: 0.5...1.5)
        gravityPreset = GravityPreset(rawValue: defaults.string(forKey: Key.gravityPreset) ?? "") ?? .normal
        debugGeometry = defaults.bool(forKey: Key.debugGeometry)
        reducedEffects = defaults.bool(forKey: Key.reducedEffects)
        showDockIcon = defaults.bool(forKey: Key.showDockIcon)
        playMode = PlayMode(rawValue: defaults.string(forKey: Key.playMode) ?? "") ?? .free
        hideFromScreenCapture = defaults.bool(forKey: Key.hideFromScreenCapture)
        bestShotClockRun = max(defaults.integer(forKey: Key.bestShotClockRun), 0)
        bestFreePlayScore = max(defaults.integer(forKey: Key.bestFreePlayScore), 0)
        bestStreak = max(defaults.integer(forKey: Key.bestStreak), 0)
        lifetimeBaskets = max(defaults.integer(forKey: Key.lifetimeBaskets), 0)
        lifetimeShots = max(defaults.integer(forKey: Key.lifetimeShots), 0)
    }

    func registerShot() {
        lifetimeShots += 1
    }

    func registerBasket(streak: Int) {
        lifetimeBaskets += 1
        if streak > bestStreak {
            bestStreak = streak
        }
    }

    func registerShotClockRun(_ score: Int) {
        if score > bestShotClockRun {
            bestShotClockRun = score
        }
    }

    func registerFreePlayScore(_ score: Int) {
        if score > bestFreePlayScore {
            bestFreePlayScore = score
        }
    }

    func resetHighScores() {
        bestStreak = 0
        bestFreePlayScore = 0
        bestShotClockRun = 0
        lifetimeBaskets = 0
        lifetimeShots = 0
    }

    private static func clamp(_ value: Double, range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

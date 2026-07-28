import AppKit

enum HapticEvent {
    case dragBegan
    case maximumPower
    case basket
    case bestStreak
}

final class HapticService {
    func perform(_ event: HapticEvent, preferences: PreferencesService) {
        guard preferences.hapticsEnabled else { return }

        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch event {
        case .dragBegan:
            pattern = .alignment
        case .maximumPower, .basket, .bestStreak:
            pattern = .levelChange
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

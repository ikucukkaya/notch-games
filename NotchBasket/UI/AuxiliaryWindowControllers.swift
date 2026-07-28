import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        preferences: PreferencesService,
        onGameplayPreferenceChanged: @escaping () -> Void,
        onGeometryChanged: @escaping () -> Void,
        onResetScores: @escaping () -> Void
    ) {
        let view = SettingsView(
            preferences: preferences,
            onGameplayPreferenceChanged: onGameplayPreferenceChanged,
            onGeometryChanged: onGeometryChanged,
            onResetScores: onResetScores
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "NotchBasket Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 570))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(
        onPlay: @escaping (Bool) -> Void,
        onDismiss: @escaping (Bool) -> Void
    ) {
        let view = OnboardingView(onPlay: onPlay, onDismiss: onDismiss)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to NotchBasket"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

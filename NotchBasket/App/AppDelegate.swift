import AppKit
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = Logger(subsystem: "com.notchbasket.app", category: "AppDelegate")
    private let preferences = PreferencesService()
    private lazy var appState = AppState(preferences: preferences)
    private let globalShortcut = GlobalShortcutService()
    private var statusItem: NSStatusItem?
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var cancellables = Set<AnyCancellable>()

    private var playItem: NSMenuItem?
    private var hideItem: NSMenuItem?
    private var soundItem: NSMenuItem?
    private var scoreItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DemoRecorder.recordIfRequested() {
            // Recording drives the run loop and exits the process itself.
            return
        }

        NSApp.applicationIconImage = makeApplicationIcon()
        applyActivationPolicy(showDockIcon: preferences.showDockIcon)
        configureMenuBar()
        observePreferences()

        if !globalShortcut.register(handler: { [weak self] in self?.appState.toggle() }) {
            logger.warning("Control-Option-B could not be registered; menu controls remain available.")
        }

        if !preferences.hasShownOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcut.unregister()
        appState.hide(immediately: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        playItem?.isEnabled = appState.mode == .hidden
        hideItem?.isEnabled = appState.mode == .active || appState.mode == .presenting
        soundItem?.state = preferences.soundEnabled ? .on : .off
        scoreItem?.state = preferences.showScore ? .on : .off
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "basketball.fill",
                accessibilityDescription: "NotchBasket"
            )
            button.toolTip = "NotchBasket"
        }

        let menu = NSMenu(title: "NotchBasket")
        menu.delegate = self

        let play = NSMenuItem(title: "Play", action: #selector(play), keyEquivalent: "")
        play.target = self
        menu.addItem(play)
        playItem = play

        let hide = NSMenuItem(title: "Hide Game", action: #selector(hideGame), keyEquivalent: "\u{1b}")
        hide.target = self
        menu.addItem(hide)
        hideItem = hide

        let restart = NSMenuItem(title: "Restart", action: #selector(restart), keyEquivalent: "r")
        restart.target = self
        menu.addItem(restart)
        menu.addItem(.separator())

        let sound = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        sound.target = self
        menu.addItem(sound)
        soundItem = sound

        let score = NSMenuItem(title: "Show Score", action: #selector(toggleScore), keyEquivalent: "")
        score.target = self
        menu.addItem(score)
        scoreItem = score
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        // The app itself never touches the network — a point the README makes
        // loudly — so updates are the browser's job, and only when asked.
        let updates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        let shortcut = NSMenuItem(title: "Toggle Shortcut: ⌃⌥B", action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit NotchBasket", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func observePreferences() {
        preferences.$showDockIcon
            .removeDuplicates()
            .sink { [weak self] showDockIcon in
                self?.applyActivationPolicy(showDockIcon: showDockIcon)
            }
            .store(in: &cancellables)
    }

    private func applyActivationPolicy(showDockIcon: Bool) {
        // An agent app promoted to .regular at runtime gets its Dock tile
        // without the bundle icon — the tile comes up generic even though
        // Finder shows the icon perfectly. Setting the runtime icon explicitly
        // is the documented cure, and it is harmless while in accessory mode.
        NSApp.applicationIconImage = NSImage(named: "AppIcon")
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    private func makeApplicationIcon() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            let background = NSBezierPath(
                roundedRect: rect.insetBy(dx: 10, dy: 10),
                xRadius: 54,
                yRadius: 54
            )
            NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
            background.fill()

            let ballRect = rect.insetBy(dx: 48, dy: 48)
            let ball = NSBezierPath(ovalIn: ballRect)
            NSColor(calibratedRed: 0.96, green: 0.34, blue: 0.07, alpha: 1).setFill()
            ball.fill()
            NSColor(calibratedWhite: 0.08, alpha: 0.78).setStroke()
            ball.lineWidth = 7
            ball.stroke()

            let seams = NSBezierPath()
            seams.move(to: NSPoint(x: ballRect.minX + 5, y: ballRect.midY))
            seams.line(to: NSPoint(x: ballRect.maxX - 5, y: ballRect.midY))
            seams.move(to: NSPoint(x: ballRect.midX, y: ballRect.minY + 5))
            seams.line(to: NSPoint(x: ballRect.midX, y: ballRect.maxY - 5))
            seams.lineWidth = 7
            seams.lineCapStyle = .round
            seams.stroke()
            return true
        }
    }

    @objc private func play() {
        appState.play()
    }

    @objc private func hideGame() {
        appState.hide()
    }

    @objc private func restart() {
        appState.restart()
    }

    @objc private func toggleSound() {
        preferences.soundEnabled.toggle()
        appState.applyPreferences()
    }

    @objc private func toggleScore() {
        preferences.showScore.toggle()
        appState.applyPreferences()
    }

    @objc private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                preferences: preferences,
                onGameplayPreferenceChanged: { [weak self] in self?.appState.applyPreferences() },
                onGeometryChanged: { [weak self] in self?.appState.refreshGeometry() },
                onResetScores: { [weak self] in self?.appState.restart() }
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        let close: (Bool) -> Void = { [weak self] doNotShowAgain in
            guard let self else { return }
            self.preferences.hasShownOnboarding = doNotShowAgain
            self.onboardingController?.close()
        }
        onboardingController = OnboardingWindowController(
            onPlay: { [weak self] doNotShowAgain in
                close(doNotShowAgain)
                self?.appState.play()
            },
            onDismiss: close
        )
        NSApp.activate(ignoringOtherApps: true)
        onboardingController?.showWindow(nil)
        onboardingController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        guard let url = URL(
            string: "https://github.com/ikucukkaya/notch-games/releases"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

import AppKit
import Combine
import OSLog

@MainActor
final class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.notchbasket.app", category: "AppState")
    private let geometryService: ScreenGeometryProviding
    private let audioService = AudioService()
    private let hapticService = HapticService()
    private let escapeShortcut = GlobalShortcutService(shortcut: .escapeGame)
    private var overlayController: OverlayWindowController?
    private var activeGeometry: ScreenGeometry?
    private var displayObserver: NSObjectProtocol?

    let preferences: PreferencesService

    @Published private(set) var mode: GameMode = .hidden

    init(
        preferences: PreferencesService,
        geometryService: ScreenGeometryProviding = ScreenGeometryService()
    ) {
        self.preferences = preferences
        self.geometryService = geometryService
        observeDisplayChanges()
    }

    func play() {
        guard mode == .hidden else { return }
        guard let screen = geometryService.activeScreen() else {
            logger.error("No active display is available; gameplay overlay was not created.")
            return
        }

        ensureOverlay(for: screen)
        mode = .presenting
        overlayController?.show()
        if !escapeShortcut.register(handler: { [weak self] in self?.hide() }) {
            logger.warning("Global Escape could not be registered; menu and toggle shortcut remain available.")
        }
        mode = .active
    }

    func hide(immediately: Bool = false) {
        guard mode == .active || mode == .presenting else { return }
        escapeShortcut.unregister()
        mode = .dismissing
        overlayController?.hide(immediately: immediately) { [weak self] in
            self?.mode = .hidden
        }
    }

    func toggle() {
        switch mode {
        case .hidden:
            play()
        case .presenting, .active:
            hide()
        case .dismissing:
            break
        }
    }

    func restart() {
        if mode == .hidden {
            play()
        }
        overlayController?.restart()
    }

    func applyPreferences() {
        overlayController?.applyPreferences()
    }

    func refreshGeometry() {
        guard mode == .active, let screen = geometryService.activeScreen() else { return }
        overlayController?.hide(immediately: true)
        overlayController = nil
        ensureOverlay(for: screen)
        overlayController?.show()
    }

    private func ensureOverlay(for screen: NSScreen) {
        if let overlayController, overlayController.screen === screen {
            return
        }

        overlayController?.hide(immediately: true)
        let geometry = currentGeometry(for: screen)
        activeGeometry = geometry
        let controller = OverlayWindowController(
            screen: screen,
            geometry: geometry,
            preferences: preferences,
            audioService: audioService,
            hapticService: hapticService
        )
        controller.onHideRequested = { [weak self] in
            self?.hide()
        }
        overlayController = controller
    }

    private func observeDisplayChanges() {
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleDisplayChange()
            }
        }
    }

    private func handleDisplayChange() {
        guard mode == .active else {
            overlayController = nil
            activeGeometry = nil
            return
        }

        // Minimizing any window changes the Dock's contents, and macOS reports
        // that with the same notification as a real display change — handing
        // back a brand-new NSScreen instance for the same display, so identity
        // must be compared by display ID, never by object. Tearing the overlay
        // down restarts the run, so only rebuild when the geometry the game
        // was built from meaningfully changed.
        let screen = geometryService.activeScreen()
        let refreshed = screen.map { currentGeometry(for: $0) }
        let sameScreen = screen.flatMap(Self.displayID(of:)) != nil &&
            screen.flatMap(Self.displayID(of:)) ==
            overlayController.flatMap { Self.displayID(of: $0.screen) }
        if Self.shouldKeepRunningOverlay(
            current: activeGeometry,
            refreshed: refreshed,
            sameScreen: sameScreen
        ) {
            logger.notice("Screen notification was Dock wobble; keeping the run.")
            return
        }

        logger.notice("Display configuration changed; rebuilding the overlay.")
        refreshGeometry()
    }

    nonisolated static func shouldKeepRunningOverlay(
        current: ScreenGeometry?,
        refreshed: ScreenGeometry?,
        sameScreen: Bool
    ) -> Bool {
        guard sameScreen, let current, let refreshed else { return false }
        return current.isEquivalent(to: refreshed)
    }

    private nonisolated static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private func currentGeometry(for screen: NSScreen) -> ScreenGeometry {
        geometryService.geometry(
            for: screen,
            hoopHorizontalOffset: CGFloat(preferences.hoopHorizontalOffset),
            hoopVerticalOffset: CGFloat(preferences.hoopVerticalOffset)
        )
    }

    deinit {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
    }
}

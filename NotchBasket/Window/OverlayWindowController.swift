import AppKit
import SpriteKit

enum OverlayInteractionPolicy {
    static func shouldCaptureMouse(
        isGameActive: Bool,
        isAiming: Bool,
        isAdjustingHoopHeight: Bool,
        isPointerOnGrabbableBall: Bool,
        isPointerOnHoop: Bool
    ) -> Bool {
        isGameActive && (
            isAiming ||
            isAdjustingHoopHeight ||
            isPointerOnGrabbableBall ||
            isPointerOnHoop
        )
    }
}

@MainActor
final class OverlayWindowController {
    private(set) var screen: NSScreen
    private let panel: OverlayPanel
    private let skView: SKView
    private let scene: BasketballScene
    private let audioService: AudioService
    private var keyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var isGameActive = false

    var onHideRequested: (() -> Void)? {
        didSet {
            panel.onEscape = onHideRequested
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    init(
        screen: NSScreen,
        geometry: ScreenGeometry,
        preferences: PreferencesService,
        audioService: AudioService,
        hapticService: HapticService
    ) {
        self.screen = screen
        self.audioService = audioService
        panel = OverlayPanel(screen: screen)
        skView = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        scene = BasketballScene(
            size: screen.frame.size,
            geometry: geometry,
            preferences: preferences,
            audioService: audioService,
            hapticService: hapticService
        )

        skView.wantsLayer = true
        skView.layer?.backgroundColor = NSColor.clear.cgColor
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60
        skView.presentScene(scene)
        panel.contentView = skView
        panel.onEscape = { [weak self] in
            self?.onHideRequested?()
        }
        scene.onInteractionStateChanged = { [weak self] in
            self?.updateMouseCapture()
        }
    }

    func show() {
        installKeyMonitor()
        installMouseMonitors()
        isGameActive = true
        panel.ignoresMouseEvents = true
        scene.isPaused = false
        panel.orderFrontRegardless()
        scene.presentGame()
        updateMouseCapture()
    }

    func hide(immediately: Bool = false, completion: (() -> Void)? = nil) {
        guard panel.isVisible else {
            panel.ignoresMouseEvents = true
            completion?()
            return
        }

        if immediately {
            removeKeyMonitor()
            removeMouseMonitors()
            isGameActive = false
            scene.isPaused = true
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
            audioService.stopAll()
            completion?()
            return
        }

        scene.dismissGame { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.removeKeyMonitor()
            self.removeMouseMonitors()
            self.isGameActive = false
            self.panel.ignoresMouseEvents = true
            self.panel.orderOut(nil)
            self.audioService.stopAll()
            completion?()
        }
    }

    func restart() {
        scene.restartSession()
    }

    func applyPreferences() {
        scene.applyPreferences()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.onHideRequested?()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func installMouseMonitors() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseUp]
        ) { [weak self] event in
            self?.updateMouseCapture()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMouseCapture()
            }
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func updateMouseCapture() {
        let mouse = NSEvent.mouseLocation
        let scenePoint = CGPoint(
            x: mouse.x - screen.frame.minX,
            y: mouse.y - screen.frame.minY
        )
        let shouldCapture = OverlayInteractionPolicy.shouldCaptureMouse(
            isGameActive: isGameActive,
            isAiming: scene.isAiming,
            isAdjustingHoopHeight: scene.isAdjustingHoopHeight,
            isPointerOnGrabbableBall: scene.canBeginAim(at: scenePoint),
            isPointerOnHoop: scene.canBeginHoopHeightAdjustment(at: scenePoint)
        )
        panel.ignoresMouseEvents = !shouldCapture
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }
}

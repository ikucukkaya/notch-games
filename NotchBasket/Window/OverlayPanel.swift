import AppKit
import SpriteKit

/// The overlay is a nonactivating panel, so it is almost never the key window.
/// A plain view swallows the first click as window activation (macOS
/// click-through protection); the ball must be grabbable on the click that
/// arrives, focus or no focus.
final class GameOverlayView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class OverlayPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        animationBehavior = .none
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        // Visible to screen recordings by default: the owner could not record
        // a promo and users could not share clips while this was .none. The
        // stealth behaviour survives as a Settings toggle for people who play
        // during screen shares.
        sharingType = .readOnly
        title = "NotchBasket Gameplay"
        setAccessibilityLabel("NotchBasket gameplay overlay")
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

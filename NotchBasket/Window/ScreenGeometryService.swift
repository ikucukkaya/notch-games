import AppKit
import CoreGraphics

enum DockEdge: String, Equatable {
    case bottom
    case left
    case right
    case hiddenOrUnknown
}

struct ScreenGeometry {
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let notchRect: CGRect?
    let hoopAnchor: CGPoint
    let ballSpawnPoint: CGPoint
    let floorY: CGFloat
    let leftBoundaryX: CGFloat
    let rightBoundaryX: CGFloat
    let dockEdge: DockEdge
    let screenName: String
}

extension ScreenGeometry {
    /// Whether a freshly measured geometry is close enough to the one the game
    /// was built from to keep the running overlay. Minimizing any window adds
    /// an icon to the Dock and macOS shrinks the Dock to make room, wobbling
    /// the visible frame (and everything derived from it) by a few points —
    /// measured at ~6 pt on a MacBook Air. Hardware-derived fields must still
    /// match exactly; only the Dock-derived continuous ones get tolerance.
    /// The display name is deliberately ignored: display identity is decided
    /// by CGDirectDisplayID, not by this comparison.
    func isEquivalent(to other: ScreenGeometry, tolerance: CGFloat = 24) -> Bool {
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
        func close(_ a: CGPoint, _ b: CGPoint) -> Bool { close(a.x, b.x) && close(a.y, b.y) }
        func close(_ a: CGRect, _ b: CGRect) -> Bool {
            close(a.origin, b.origin) && close(a.width, b.width) && close(a.height, b.height)
        }

        guard screenFrame == other.screenFrame,
              safeAreaInsets.top == other.safeAreaInsets.top,
              safeAreaInsets.left == other.safeAreaInsets.left,
              safeAreaInsets.bottom == other.safeAreaInsets.bottom,
              safeAreaInsets.right == other.safeAreaInsets.right,
              notchRect == other.notchRect,
              dockEdge == other.dockEdge
        else { return false }

        return close(visibleFrame, other.visibleFrame) &&
            close(hoopAnchor, other.hoopAnchor) &&
            close(ballSpawnPoint, other.ballSpawnPoint) &&
            close(floorY, other.floorY) &&
            close(leftBoundaryX, other.leftBoundaryX) &&
            close(rightBoundaryX, other.rightBoundaryX)
    }
}

protocol ScreenGeometryProviding {
    func activeScreen() -> NSScreen?
    func geometry(
        for screen: NSScreen,
        hoopHorizontalOffset: CGFloat,
        hoopVerticalOffset: CGFloat
    ) -> ScreenGeometry
}

struct ScreenGeometryService: ScreenGeometryProviding {
    private let notchService = NotchGeometryService()

    func activeScreen() -> NSScreen? {
        if let notchedScreen = NSScreen.screens.first(where: { notchService.notchRect(for: $0) != nil }) {
            return notchedScreen
        }

        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    func geometry(
        for screen: NSScreen,
        hoopHorizontalOffset: CGFloat = 0,
        hoopVerticalOffset: CGFloat = 0
    ) -> ScreenGeometry {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let localVisible = visible.offsetBy(dx: -frame.minX, dy: -frame.minY)
        let globalNotch = notchService.notchRect(for: screen)
        let localNotch = globalNotch?.offsetBy(dx: -frame.minX, dy: -frame.minY)
        let dock = Self.inferDockEdge(screenFrame: frame, visibleFrame: visible)

        let floor = Self.floorY(
            screenFrame: frame,
            visibleFrame: visible,
            dockEdge: dock
        )
        let left = dock == .left ? localVisible.minX + 8 : 8
        let right = dock == .right ? localVisible.maxX - 8 : frame.width - 8

        return ScreenGeometry(
            screenFrame: frame,
            visibleFrame: localVisible,
            safeAreaInsets: screen.safeAreaInsets,
            notchRect: localNotch,
            hoopAnchor: Self.sideMountedHoopAnchor(
                screenSize: frame.size,
                floorY: floor,
                rightBoundaryX: right,
                horizontalOffset: hoopHorizontalOffset,
                verticalOffset: hoopVerticalOffset
            ),
            ballSpawnPoint: Self.ballSpawnPoint(
                screenWidth: frame.width,
                floorY: floor,
                leftBoundaryX: left,
                rightBoundaryX: right
            ),
            floorY: floor,
            leftBoundaryX: left,
            rightBoundaryX: right,
            dockEdge: dock,
            screenName: screen.localizedName
        )
    }

    static func inferDockEdge(screenFrame: CGRect, visibleFrame: CGRect) -> DockEdge {
        let bottomInset = visibleFrame.minY - screenFrame.minY
        let leftInset = visibleFrame.minX - screenFrame.minX
        let rightInset = screenFrame.maxX - visibleFrame.maxX
        let threshold: CGFloat = 30

        if bottomInset > threshold, bottomInset >= leftInset, bottomInset >= rightInset {
            return .bottom
        }
        if leftInset > threshold, leftInset >= rightInset {
            return .left
        }
        if rightInset > threshold {
            return .right
        }
        return .hiddenOrUnknown
    }

    static func floorY(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        dockEdge: DockEdge
    ) -> CGFloat {
        let localVisibleMinY = visibleFrame.minY - screenFrame.minY
        if dockEdge == .bottom {
            return max(localVisibleMinY + 10, 22)
        }
        return 22
    }

    static func sideMountedHoopAnchor(
        screenSize: CGSize,
        floorY: CGFloat,
        rightBoundaryX: CGFloat,
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat
    ) -> CGPoint {
        let preferredY = screenSize.height * 0.72
        let minimumY = floorY + 260
        let maximumY = screenSize.height - 110
        return CGPoint(
            // SideHoopLayout.mountEdgeX lands exactly on the usable right edge.
            x: rightBoundaryX - SideHoopLayout.mountEdgeX + horizontalOffset,
            y: min(max(preferredY, minimumY), maximumY) + verticalOffset
        )
    }

    /// Where a ball must sit to be fully hidden before its drop: centred on the
    /// notch, with its bottom edge just above the notch's lower boundary. The
    /// notch is dead pixels and everything above the screen top is off-panel, so
    /// a ball parked here is invisible however much taller it is than the notch —
    /// the hardware does the occlusion.
    static func notchDropPoint(
        notchRect: CGRect,
        ballRadius: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: notchRect.midX,
            y: notchRect.minY + ballRadius + 2
        )
    }

    static func ballSpawnPoint(
        screenWidth: CGFloat,
        floorY: CGFloat,
        leftBoundaryX: CGFloat,
        rightBoundaryX: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: min(max(screenWidth * 0.5, leftBoundaryX + 50), rightBoundaryX - 50),
            // Start directly above the inferred Dock/floor. Bottom-edge pull
            // compensation supplies the full slingshot range from here.
            y: floorY + (GameTuning.ballDiameter / 2) + 5
        )
    }
}

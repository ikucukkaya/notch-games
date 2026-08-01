import AppKit
import OSLog
import SpriteKit

/// Where the arena scoreboard hangs when the screen has a notch: centred under
/// it, slightly narrower, suspended just below its lower edge — the notch reads
/// as the jumbotron housing.
enum ScoreboardLayout {
    static let height: CGFloat = 40

    static func panelFrame(notchRect: CGRect) -> CGRect {
        // Full notch width: the panel and the housing above it read as one unit.
        let width = max(notchRect.width, 120)
        return CGRect(
            x: notchRect.midX - (width / 2),
            y: notchRect.minY - height,
            width: width,
            height: height
        )
    }
}

enum BoundarySoundPolicy {
    static func impactSpeed(boundaryName: String?, velocity: CGVector) -> CGFloat {
        switch boundaryName {
        case "floor", "topBoundary": abs(velocity.dy)
        default: abs(velocity.dx)
        }
    }

    static func shouldPlay(
        boundaryName: String?,
        velocity: CGVector,
        collisionImpulse: CGFloat
    ) -> Bool {
        let minimumSpeed = boundaryName == "floor"
            ? GameTuning.minimumAudibleFloorImpactSpeed
            : 85
        return impactSpeed(boundaryName: boundaryName, velocity: velocity) >= minimumSpeed &&
            collisionImpulse >= 0.45
    }
}

final class BasketballScene: SKScene, SKPhysicsContactDelegate {
    private let logger = Logger(subsystem: "com.notchbasket.app", category: "BasketballScene")
    private let geometry: ScreenGeometry
    private var currentHoopAnchor: CGPoint
    private let preferences: PreferencesService
    private let audioService: AudioService
    private let hapticService: HapticService
    private let shotController = ShotController()
    private let scoreController = ScoreController()

    private var resetController = BallResetController()
    /// Consecutive update frames in which nothing on screen was moving. Once the
    /// toy has been genuinely still for half a second, the view drops to a slow
    /// render pace: SpriteKit otherwise composites the full-screen transparent
    /// overlay 60 times a second forever, which alone held the idle app near half
    /// a core. Any interaction or state change restores full pace immediately.
    private var quiescentFrames = 0

    /// True while a fresh ball is falling out of the notch. The top boundary
    /// spans the notch's x-range, so the ball's boundary collision and contact
    /// masks are stripped for the drop and restored once it is clear below —
    /// otherwise it would land on the ceiling from outside, or fire a phantom
    /// boundary thud crossing the line.
    private var isNotchDropInProgress = false

    private let shotClock = ShotClockController()
    private var pendingShotPoints = 2
    private let threePointMarking = SKNode()
    private var lastThreePointLineX: CGFloat = .nan
    private var activePlayMode: PlayMode = .free
    private var lastClockText = ""
    // 2, not 10: while quiescent the frame never changes, and grab response is
    // unaffected — mouseDown restores 60 before the event is handled. The only
    // thing this slows is a Settings change reaching the screen, by up to half a
    // second, which is invisible next to the battery cost of redrawing a static
    // full-screen layer ten times a second.
    private let idleFramesPerSecond = 2
    private let quiescentFramesBeforeIdle = 30

    private var ballState: BallState = .spawning {
        didSet {
            updateDebugLabel()
            onInteractionStateChanged?()
        }
    }
    private var statistics = SessionStatistics()
    private var ball: BasketballNode?
    private var hoop: HoopNode?
    private let aimIndicator = AimIndicatorNode()
    private let scoreOverlay = SKNode()
    private let scoreLabel = SKLabelNode(
        fontNamed: NSFont.systemFont(ofSize: 28, weight: .semibold).fontName
    )
    private let streakLabel = SKLabelNode(
        fontNamed: NSFont.systemFont(ofSize: 13, weight: .medium).fontName
    )
    private let bestLabel = SKLabelNode(
        fontNamed: NSFont.systemFont(ofSize: 13, weight: .medium).fontName
    )
    private let debugLayer = SKNode()
    private let debugLabel = SKLabelNode(
        fontNamed: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular).fontName
    )
    private let velocityNode = SKShapeNode()

    private var ballOrigin = CGPoint.zero
    private var currentDragPoint = CGPoint.zero
    private var currentTime: TimeInterval = 0
    private var previousUpdateTime: TimeInterval?
    private var didScoreCurrentShot = false
    private var maximumPowerHapticPlayed = false
    private var isGamePresented = false
    private var hoopDragPointerStartY: CGFloat = 0
    private var hoopDragAnchorStartY: CGFloat = 0
    private var hoopDragOffsetStart: Double = 0
    private var pendingHoopVerticalOffset: Double = 0

    private(set) var isAdjustingHoopHeight = false {
        didSet {
            guard oldValue != isAdjustingHoopHeight else { return }
            onInteractionStateChanged?()
        }
    }

    var onStatisticsChanged: ((SessionStatistics) -> Void)?
    var onInteractionStateChanged: (() -> Void)?

    var isAiming: Bool {
        ballState == .aiming
    }

    func canBeginAim(at scenePoint: CGPoint) -> Bool {
        guard isBallGrabbable, let ball else { return false }
        return ball.calculateAccumulatedFrame()
            .insetBy(dx: -16, dy: -16)
            .contains(scenePoint)
    }

    func canBeginHoopHeightAdjustment(at scenePoint: CGPoint) -> Bool {
        guard
            isGamePresented,
            !isAiming,
            let hoop,
            abs(hoop.position.x - currentHoopAnchor.x) < 4
        else { return false }
        return hoop.calculateAccumulatedFrame()
            .insetBy(dx: -12, dy: -12)
            .contains(scenePoint)
    }

    private var isBallGrabbable: Bool {
        BallInteractionPolicy.isGrabbable(ballState)
    }

    init(
        size: CGSize,
        geometry: ScreenGeometry,
        preferences: PreferencesService,
        audioService: AudioService,
        hapticService: HapticService
    ) {
        self.geometry = geometry
        currentHoopAnchor = geometry.hoopAnchor
        self.preferences = preferences
        self.audioService = audioService
        self.hapticService = hapticService
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: preferences.gravityPreset.gravity)
        physicsWorld.contactDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        buildScene()
        applyPreferences()
    }

    func presentGame() {
        guard !isGamePresented else {
            if ballState != .ready && ballState != .aiming {
                resetBall(immediately: true)
            }
            return
        }
        isPaused = false
        isGamePresented = true
        previousUpdateTime = nil

        let reduceMotion = preferences.reducedEffects || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let hoop else {
            spawnBall()
            return
        }

        hoop.removeAllActions()
        hoop.position = CGPoint(x: size.width + 120, y: currentHoopAnchor.y)
        hoop.alpha = 1
        let duration = reduceMotion ? 0.12 : 0.58
        let deploy = SKAction.move(to: currentHoopAnchor, duration: duration)
        deploy.timingMode = reduceMotion ? .easeOut : .easeInEaseOut
        hoop.run(deploy) { [weak hoop] in
            guard let hoop else { return }
            if !reduceMotion {
                let settle = SKAction.sequence([
                    .moveBy(x: -5, y: 0, duration: 0.08),
                    .moveBy(x: 5, y: 0, duration: 0.14)
                ])
                settle.timingMode = .easeInEaseOut
                hoop.run(settle)
            }
        }
        audioService.play(.deploy, intensity: 0.55, preferences: preferences)
        run(.sequence([
            .wait(forDuration: reduceMotion ? 0.04 : 0.24),
            .run { [weak self] in self?.spawnBall() }
        ]))
    }

    func dismissGame(completion: @escaping () -> Void) {
        guard isGamePresented else {
            completion()
            return
        }
        finishHoopHeightAdjustment()
        isGamePresented = false
        ballState = .resetting
        aimIndicator.hide()
        audioService.play(.retract, intensity: 0.42, preferences: preferences)

        let reduceMotion = preferences.reducedEffects || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduceMotion ? 0.04 : 0.20
        ball?.run(.fadeOut(withDuration: duration * 0.75))
        hoop?.run(.moveTo(x: size.width + 120, duration: duration))
        run(.sequence([
            .wait(forDuration: duration),
            .run { [weak self] in
                self?.isPaused = true
                completion()
            }
        ]))
    }

    func restartSession() {
        statistics = SessionStatistics(bestStreak: preferences.bestStreak)
        shotClock.resetAbandoningRun()
        lastClockText = ""
        onStatisticsChanged?(statistics)
        updateScoreOverlay()
        resetBall(immediately: true)
    }

    func applyPreferences() {
        physicsWorld.gravity = CGVector(dx: 0, dy: preferences.gravityPreset.gravity)
        scoreOverlay.isHidden = !preferences.showScore
        aimIndicator.isHidden = !preferences.aimGuideEnabled || ballState != .aiming
        view?.showsPhysics = preferences.debugGeometry
        view?.showsFPS = preferences.debugGeometry
        view?.showsNodeCount = false
        debugLayer.isHidden = !preferences.debugGeometry
        updateDebugLabel()
    }

    private func updateNotchDrop() {
        guard isNotchDropInProgress, ballState == .spawning, let ball else { return }

        // Clear of the ceiling line: give the ball its boundaries back — and give
        // the ball to the player in the same moment. A falling ball is already
        // obeying the same physics a thrown one does, so there is no reason to
        // make the player wait for it to land; catching it out of the air and
        // firing is part of the toy.
        if let notchRect = geometry.notchRect,
           ball.position.y < notchRect.minY - ball.radius,
           let body = ball.physicsBody,
           body.collisionBitMask & PhysicsCategory.boundary == 0 {
            body.collisionBitMask |= PhysicsCategory.boundary
            body.contactTestBitMask |= PhysicsCategory.boundary
            isNotchDropInProgress = false
            ballState = .ready
        }
    }

    /// The little court marking on the floor where the three-point zone begins.
    /// Everything left of it is a three; the marking itself stands on the two side.
    private func buildThreePointMarking() {
        threePointMarking.removeFromParent()
        threePointMarking.removeAllChildren()
        threePointMarking.zPosition = 6
        addChild(threePointMarking)

        let contrast = SKShapeNode(rectOf: CGSize(width: 6, height: 16), cornerRadius: 2)
        contrast.fillColor = NSColor.black.withAlphaComponent(0.72)
        contrast.strokeColor = NSColor.black.withAlphaComponent(0.66)
        contrast.lineWidth = 2
        contrast.position = CGPoint(x: 0, y: 8)
        threePointMarking.addChild(contrast)

        let line = SKShapeNode(rectOf: CGSize(width: 2.6, height: 13), cornerRadius: 1.3)
        line.fillColor = NSColor.white.withAlphaComponent(0.85)
        line.strokeColor = .clear
        line.position = CGPoint(x: 0, y: 8)
        threePointMarking.addChild(line)

        updateThreePointMarking()
    }

    private func updateThreePointMarking() {
        let lineX = ScoringPolicy.threePointLineX(
            leftBoundaryX: geometry.leftBoundaryX,
            rimCenterX: currentHoopAnchor.x
        )
        guard lineX != lastThreePointLineX else { return }
        lastThreePointLineX = lineX
        threePointMarking.position = CGPoint(x: lineX, y: geometry.floorY)
    }

    private func updateShotClock() {
        guard isGamePresented else { return }

        // Switching modes wipes the run without recording it and redraws the
        // board for the new mode's layout.
        if activePlayMode != preferences.playMode {
            activePlayMode = preferences.playMode
            shotClock.resetAbandoningRun()
            buildScoreOverlay()
            updateScoreOverlay()
        }
        guard activePlayMode == .shotClock24 else { return }

        let ballInFlight = ballState == .flying || ballState == .scored
        if shotClock.checkExpiry(at: currentTime, ballInFlight: ballInFlight)
            == .violation {
            performShotClockViolation(ballHeld: ballState == .aiming)
        }

        // NBA-style readout: whole seconds until the last five, then tenths.
        let remaining = shotClock.remaining(at: currentTime)
        let text = remaining < 5
            ? String(format: "%.1f", remaining)
            : "\(Int(remaining.rounded(.up)))"
        if text != lastClockText {
            lastClockText = text
            updateScoreOverlay()
        }
    }

    private func performShotClockViolation(ballHeld: Bool) {
        let run = shotClock.endRun(at: currentTime, ballHeld: ballHeld)
        preferences.registerShotClockRun(run)
        audioService.play(.buzzer, intensity: 0.9, preferences: preferences)
        hapticService.perform(.basket, preferences: preferences)

        // The horn also ends the streak story: a violation is a turnover.
        statistics.streak = 0
        updateScoreOverlay()
        onStatisticsChanged?(statistics)

        scoreOverlay.removeAction(forKey: "violationFlash")
        let flash = SKAction.sequence([
            .run { [weak self] in
                self?.scoreOverlay.childNode(withName: "notchScoreboardVisual")?
                    .run(.sequence([
                        .colorize(with: .systemRed, colorBlendFactor: 0.55, duration: 0.08),
                        .colorize(withColorBlendFactor: 0, duration: 0.5)
                    ]))
            },
            .wait(forDuration: 0.6)
        ])
        scoreOverlay.run(flash, withKey: "violationFlash")
    }

    private func updateRenderPace() {
        guard !isRenderPacingDisabled else {
            setPreferredFramesPerSecond(60)
            return
        }
        // Quiescent means the shot cycle is at rest AND the net has fallen
        // asleep AND the ball itself is still. The last condition is not implied
        // by .ready any more: a ball dropping out of the notch becomes the
        // player's the moment it clears the notch, mid-fall.
        let ballIsStill = (ball?.physicsBody?.velocity ?? .zero).length
            < GameTuning.stillSpeedThreshold
        let quiescent = isGamePresented
            && ballState == .ready
            && ballIsStill
            && (hoop?.isNetResting ?? false)
            && !shotClock.isRunning
        guard quiescent else {
            quiescentFrames = 0
            setPreferredFramesPerSecond(60)
            return
        }
        quiescentFrames += 1
        if quiescentFrames >= quiescentFramesBeforeIdle {
            setPreferredFramesPerSecond(idleFramesPerSecond)
        }
    }

    private func setPreferredFramesPerSecond(_ fps: Int) {
        guard let view, view.preferredFramesPerSecond != fps else { return }
        view.preferredFramesPerSecond = fps
    }

    override func mouseDown(with event: NSEvent) {
        // Restore full pace before handling the event, so a grab that starts an
        // aim is fluid from its first frame rather than after the next slow tick.
        setPreferredFramesPerSecond(60)

        guard isGamePresented, let point = scenePoint(for: event) else { return }

        if canBeginAim(at: point), let ball {
            beginBallAim(ball)
            return
        }

        guard canBeginHoopHeightAdjustment(at: point), let hoop else { return }
        hoop.removeAllActions()
        hoopDragPointerStartY = point.y
        hoopDragAnchorStartY = hoop.position.y
        hoopDragOffsetStart = preferences.hoopVerticalOffset
        pendingHoopVerticalOffset = hoopDragOffsetStart
        isAdjustingHoopHeight = true
    }

    private func beginBallAim(_ ball: BasketballNode) {
        let interruptedUnscoredShot = ballState == .flying && !didScoreCurrentShot
        removeAction(forKey: "scheduledReset")
        resetController.reset()
        scoreController.resetForNewShot()
        hoop?.resetNetForNewShot()
        if interruptedUnscoredShot, statistics.streak != 0 {
            statistics.streak = 0
            updateScoreOverlay()
            onStatisticsChanged?(statistics)
        }

        if preferences.playMode == .shotClock24 {
            shotClock.ballGrabbed(at: currentTime)
        }

        ballState = .aiming
        ballOrigin = ball.position
        currentDragPoint = ball.position
        maximumPowerHapticPlayed = false
        ball.physicsBody?.velocity = .zero
        ball.physicsBody?.angularVelocity = 0
        ball.physicsBody?.isDynamic = false
        ball.physicsBody?.affectedByGravity = false
        hapticService.perform(.dragBegan, preferences: preferences)
    }

    private func updateHoopHeight(using pointer: CGPoint) {
        guard let hoop else { return }
        let proposedY = hoopDragAnchorStartY + (pointer.y - hoopDragPointerStartY)
        let screenClampedY = HoopHeightPolicy.clampedAnchorY(
            proposedY,
            floorY: geometry.floorY,
            screenHeight: size.height
        )
        let rawOffset = hoopDragOffsetStart +
            Double(screenClampedY - hoopDragAnchorStartY)
        let range = PreferencesService.hoopVerticalOffsetRange
        let boundedOffset = min(max(rawOffset, range.lowerBound), range.upperBound)
        let finalY = hoopDragAnchorStartY +
            CGFloat(boundedOffset - hoopDragOffsetStart)

        hoop.position.y = finalY
        currentHoopAnchor.y = finalY
        pendingHoopVerticalOffset = boundedOffset
    }

    private func finishHoopHeightAdjustment() {
        guard isAdjustingHoopHeight else { return }
        preferences.hoopVerticalOffset = pendingHoopVerticalOffset
        isAdjustingHoopHeight = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = scenePoint(for: event) else { return }
        if isAdjustingHoopHeight {
            updateHoopHeight(using: point)
            return
        }

        guard ballState == .aiming, let ball else { return }
        let effectivePoint = shotController.bottomEdgeCompensatedDragPoint(
            ballOrigin: ballOrigin,
            pointerPoint: point
        )
        let clampedPoint = shotController.clampedDragPoint(
            ballOrigin: ballOrigin,
            dragPoint: effectivePoint
        )
        currentDragPoint = clampedPoint
        // Preserve the full pull vector while keeping the visual ball on the
        // court — a corner pull used to drag it off the left edge, and the
        // release then stranded it outside the boundary line.
        ball.position = shotController.courtClampedBallPosition(
            dragPoint: clampedPoint,
            floorY: geometry.floorY,
            leftBoundaryX: geometry.leftBoundaryX,
            rightBoundaryX: geometry.rightBoundaryX,
            ballRadius: ball.radius
        )

        let dragDistance = hypot(clampedPoint.x - ballOrigin.x, clampedPoint.y - ballOrigin.y)
        let powerFraction = min(dragDistance / GameTuning.maximumDragDistance, 1)
        let velocity = shotController.launchVelocity(
            ballOrigin: ballOrigin,
            dragPoint: currentDragPoint,
            sensitivity: CGFloat(preferences.launchSensitivity)
        )
        if preferences.aimGuideEnabled {
            aimIndicator.update(
                // Keep the power ring visible around the on-screen ball even when
                // the virtual pull point extends below the floor collider.
                from: ball.position,
                velocity: velocity,
                gravity: preferences.gravityPreset.gravity,
                powerFraction: powerFraction
            )
        }
        if powerFraction >= 0.98 && !maximumPowerHapticPlayed {
            maximumPowerHapticPlayed = true
            hapticService.perform(.maximumPower, preferences: preferences)
        }
    }

    // MARK: - Scripting seams

    /// Read-only state for the demo recorder and future scene-level tests.
    var scriptedBallState: BallState { ballState }

    /// The demo recorder samples the view on its own clock, so the idle
    /// render-pace drop must never fire: there is no mouseDown to restore 60,
    /// and at 2 fps the clamped delta runs the whole simulation at ~1/15th
    /// speed — which is exactly what the first three takes recorded.
    var isRenderPacingDisabled = false
    var scriptedBallPosition: CGPoint? { ball?.position }

    /// Launches the ball exactly as a player's release does — including starting
    /// the shot clock, since a scripted shot implies the grab that precedes it.
    func scriptedShot(velocity: CGVector) {
        guard ballState == .ready, let ball else { return }
        if preferences.playMode == .shotClock24 {
            shotClock.ballGrabbed(at: currentTime)
        }
        didScoreCurrentShot = false
        scoreController.resetForNewShot()
        hoop?.resetNetForNewShot()
        ball.physicsBody?.isDynamic = true
        ball.physicsBody?.affectedByGravity = true
        ball.physicsBody?.velocity = velocity
        ball.physicsBody?.angularVelocity = -velocity.dx / max(ball.radius, 1) * 0.035
        pendingShotPoints = ScoringPolicy.points(
            releaseX: ball.position.x,
            threePointLineX: ScoringPolicy.threePointLineX(
                leftBoundaryX: geometry.leftBoundaryX,
                rimCenterX: currentHoopAnchor.x
            )
        )
        ballState = .flying
        resetController.beginShot(at: currentTime)
        statistics.shotsAttempted += 1
    }

    override func mouseUp(with event: NSEvent) {
        if isAdjustingHoopHeight {
            finishHoopHeightAdjustment()
            return
        }

        guard ballState == .aiming, let ball else { return }
        aimIndicator.hide()

        let velocity = shotController.launchVelocity(
            ballOrigin: ballOrigin,
            dragPoint: currentDragPoint,
            sensitivity: CGFloat(preferences.launchSensitivity)
        )
        guard velocity.length > 0 else {
            let returnAction = SKAction.move(to: ballOrigin, duration: 0.14)
            returnAction.timingMode = .easeOut
            ball.run(returnAction) { [weak self, weak ball] in
                ball?.physicsBody?.isDynamic = false
                self?.ballState = .ready
            }
            return
        }

        didScoreCurrentShot = false
        scoreController.resetForNewShot()
        ball.position = shotController.courtClampedBallPosition(
            dragPoint: ball.position,
            floorY: geometry.floorY,
            leftBoundaryX: geometry.leftBoundaryX,
            rightBoundaryX: geometry.rightBoundaryX,
            ballRadius: ball.radius
        )
        ball.physicsBody?.isDynamic = true
        ball.physicsBody?.affectedByGravity = true
        ball.physicsBody?.velocity = velocity
        ball.physicsBody?.angularVelocity = -velocity.dx / max(ball.radius, 1) * 0.035
        pendingShotPoints = ScoringPolicy.points(
            releaseX: ball.position.x,
            threePointLineX: ScoringPolicy.threePointLineX(
                leftBoundaryX: geometry.leftBoundaryX,
                rimCenterX: currentHoopAnchor.x
            )
        )
        ballState = .flying
        resetController.beginShot(at: currentTime)

        statistics.shotsAttempted += 1
        preferences.registerShot()
        onStatisticsChanged?(statistics)
        updateScoreOverlay()
    }

    override func update(_ currentTime: TimeInterval) {
        self.currentTime = currentTime
        let deltaTime: CGFloat
        if let previousUpdateTime {
            deltaTime = CGFloat(min(max(currentTime - previousUpdateTime, 0), 1.0 / 30.0))
        } else {
            deltaTime = 1.0 / 60.0
        }
        previousUpdateTime = currentTime

        if isGamePresented, let hoop {
            let ballCanTouchNet = ballState != .spawning && ballState != .resetting
            let interactingBall = ballCanTouchNet ? ball : nil
            let netForce = hoop.updateNet(
                deltaTime: deltaTime,
                ballScenePosition: interactingBall?.position,
                ballVelocity: interactingBall?.physicsBody?.velocity ?? .zero,
                ballRadius: interactingBall?.radius ?? 0,
                reducedEffects: preferences.reducedEffects
            )

            // Only a ball the physics engine owns can be pushed. While aiming,
            // the net still deforms visually but the drag controls the ball.
            if ballState == .flying || ballState == .scored {
                interactingBall?.physicsBody?.applyForce(netForce)
            }
        }

        updateNotchDrop()
        updateThreePointMarking()
        updateShotClock()
        updateRenderPace()

        guard isGamePresented, ballState == .flying || ballState == .scored, let ball else {
            velocityNode.path = nil
            return
        }

        let velocity = ball.physicsBody?.velocity ?? .zero
        let playableRegion = CGRect(
            x: -120,
            y: geometry.floorY - 160,
            width: size.width + 240,
            height: size.height + 320
        )
        if let completionReason = resetController.completionReason(
            at: currentTime,
            speed: velocity.length,
            isInsidePlayableRegion: playableRegion.contains(ball.position)
        ) {
            finishShot(reason: completionReason)
        }
        updateVelocityDebug(ball: ball, velocity: velocity)
    }

    /// Numerical backstop only: recovers a ball the integrator let slip through
    /// a cord. Runs after physics so it never fights the integrator.
    override func didSimulatePhysics() {
        guard isGamePresented,
              ballState == .flying || ballState == .scored,
              let ball,
              let hoop,
              let corrected = hoop.netContainmentCorrection(
                  ballScenePosition: ball.position,
                  ballRadius: ball.radius
              )
        else {
            return
        }
        ball.position = corrected
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let categories = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard let ballBody = [contact.bodyA, contact.bodyB].first(where: {
            $0.categoryBitMask == PhysicsCategory.ball
        }) else {
            return
        }

        if categories & PhysicsCategory.upperScoreSensor != 0 {
            if ballBody.velocity.dy < 40 {
                scoreController.registerUpperSensorEntry()
            }
        }
        if categories & PhysicsCategory.lowerScoreSensor != 0 {
            let isCentered = isBallCenteredInRim()
            if isCentered,
               scoreController.registerLowerSensorEntry(verticalVelocity: ballBody.velocity.dy) {
                registerBasket()
            }
        }
        if categories & PhysicsCategory.rim != 0 {
            playCollision(.rim, impulse: contact.collisionImpulse)
        } else if categories & PhysicsCategory.backboard != 0 {
            playCollision(.backboard, impulse: contact.collisionImpulse)
        } else if categories & PhysicsCategory.boundary != 0 {
            playBoundaryCollision(contact: contact, ballBody: ballBody)
        }
    }

    private func buildScene() {
        removeAllChildren()
        buildBoundaries()

        let hoop = HoopNode()
        hoop.position = CGPoint(x: size.width + 120, y: currentHoopAnchor.y)
        self.hoop = hoop
        addChild(hoop)

        addChild(aimIndicator)
        buildThreePointMarking()
        buildScoreOverlay()
        buildDebugLayer()
        statistics.bestStreak = preferences.bestStreak
        updateScoreOverlay()
    }

    private func buildBoundaries() {
        addBoundary(
            from: CGPoint(x: geometry.leftBoundaryX, y: geometry.floorY),
            to: CGPoint(x: geometry.rightBoundaryX, y: geometry.floorY),
            name: "floor"
        )
        addBoundary(
            from: CGPoint(x: geometry.leftBoundaryX, y: geometry.floorY),
            to: CGPoint(x: geometry.leftBoundaryX, y: size.height),
            name: "leftBoundary"
        )
        addBoundary(
            from: CGPoint(x: geometry.rightBoundaryX, y: geometry.floorY),
            to: CGPoint(x: geometry.rightBoundaryX, y: size.height),
            name: "rightBoundary"
        )
        addBoundary(
            from: CGPoint(x: geometry.leftBoundaryX, y: size.height - 1),
            to: CGPoint(x: geometry.rightBoundaryX, y: size.height - 1),
            name: "topBoundary"
        )
    }

    private func addBoundary(from start: CGPoint, to end: CGPoint, name: String) {
        let node = SKNode()
        node.name = name
        let body = SKPhysicsBody(edgeFrom: start, to: end)
        body.isDynamic = false
        body.restitution = GameTuning.boundaryRestitution
        body.friction = 0.66
        body.categoryBitMask = PhysicsCategory.boundary
        body.collisionBitMask = PhysicsCategory.ball
        body.contactTestBitMask = PhysicsCategory.ball
        node.physicsBody = body
        addChild(node)
    }

    private func spawnBall() {
        ball?.removeFromParent()
        resetController.reset()
        scoreController.resetForNewShot()
        hoop?.resetNetForNewShot()
        didScoreCurrentShot = false

        let diameter = min(
            max(GameTuning.ballDiameter, GameTuning.minimumBallDiameter),
            GameTuning.maximumBallDiameter
        )
        let ball = BasketballNode(diameter: diameter)
        self.ball = ball
        isNotchDropInProgress = false

        if let notchRect = geometry.notchRect {
            // The ball is born behind the notch — invisible, because the notch is
            // dead pixels and the rest of it pokes above the panel — and simply
            // falls into view. The hardware supplies the reveal.
            ball.position = ScreenGeometryService.notchDropPoint(
                notchRect: notchRect,
                ballRadius: ball.radius
            )
            ball.physicsBody?.collisionBitMask &= ~PhysicsCategory.boundary
            ball.physicsBody?.contactTestBitMask &= ~PhysicsCategory.boundary
            isNotchDropInProgress = true
            addChild(ball)
            ballState = .spawning
            // No spawn jingle: the drop announces itself with its own landing
            // bounce, and the hoop's deploy whoosh already covers presentation.
            return
        }

        ball.position = geometry.ballSpawnPoint
        ball.alpha = 0
        ball.setScale(0.72)
        ball.physicsBody?.isDynamic = false
        ball.physicsBody?.affectedByGravity = false
        addChild(ball)

        ballState = .spawning
        let appear = SKAction.group([
            .fadeIn(withDuration: preferences.reducedEffects ? 0.06 : 0.18),
            .scale(to: 1, duration: preferences.reducedEffects ? 0.06 : 0.24)
        ])
        appear.timingMode = .easeOut
        ball.run(appear) { [weak self] in
            self?.ballState = .ready
        }
    }

    private func scheduleReset() {
        guard ballState != .resetting else { return }
        ballState = .settling
        let delay = preferences.reducedEffects ? 0.12 : GameTuning.defaultResetDelay
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self] in self?.resetBall(immediately: false) }
        ]), withKey: "scheduledReset")
    }

    private func finishShot(reason: ShotCompletionReason) {
        guard ballState == .flying || ballState == .scored else { return }
        if !didScoreCurrentShot, shotClock.isAwaitingBuzzerBeater {
            performShotClockViolation(ballHeld: false)
        }
        switch reason {
        case .leftPlayableRegion:
            scheduleReset()
        case .settled, .timedOut:
            settleBallInPlace()
        }
    }

    private func settleBallInPlace() {
        guard let ball else { return }
        removeAction(forKey: "scheduledReset")
        ballState = .settling
        ball.physicsBody?.velocity = .zero
        ball.physicsBody?.angularVelocity = 0
        ball.physicsBody?.affectedByGravity = false
        ball.physicsBody?.isDynamic = false
        resetController.reset()

        if !didScoreCurrentShot {
            statistics.streak = 0
            updateScoreOverlay()
            onStatisticsChanged?(statistics)
        }
        ballState = .ready
    }

    private func resetBall(immediately: Bool) {
        removeAction(forKey: "scheduledReset")
        guard isGamePresented else { return }
        ballState = .resetting
        if !didScoreCurrentShot {
            statistics.streak = 0
            updateScoreOverlay()
            onStatisticsChanged?(statistics)
        }

        guard let ball, !immediately else {
            spawnBall()
            return
        }
        ball.physicsBody?.isDynamic = false
        ball.run(.group([
            .fadeOut(withDuration: 0.16),
            .scale(to: 0.78, duration: 0.16)
        ])) { [weak self] in
            self?.spawnBall()
        }
    }

    private func registerBasket() {
        guard !didScoreCurrentShot else { return }
        didScoreCurrentShot = true
        ballState = .scored
        statistics.score += pendingShotPoints
        statistics.streak += 1
        statistics.successfulShots += 1
        statistics.bestStreak = max(statistics.bestStreak, statistics.streak)
        preferences.registerBasket(streak: statistics.streak)
        if preferences.playMode == .shotClock24 {
            shotClock.registerScore(points: pendingShotPoints, at: currentTime)
        }
        updateScoreOverlay()
        onStatisticsChanged?(statistics)

        hoop?.playScoreAnimation(reducedEffects: preferences.reducedEffects)
        showScorePop()
        emitScoreParticles()
        hapticService.perform(.basket, preferences: preferences)
        if statistics.streak == statistics.bestStreak && statistics.streak > 1 {
            hapticService.perform(.bestStreak, preferences: preferences)
        }
    }

    private func isBallCenteredInRim() -> Bool {
        guard let ball, let hoop else { return false }
        let maximumCenterOffset =
            GameTuning.rimPostOffset -
            GameTuning.rimPostRadius -
            ball.radius
        return abs(ball.position.x - hoop.position.x) <= maximumCenterOffset
    }

    private func playCollision(_ effect: SoundEffect, impulse: CGFloat) {
        let intensity = min(max(impulse / 5, 0.2), 1)
        audioService.play(effect, intensity: intensity, preferences: preferences)
    }

    private func playBoundaryCollision(
        contact: SKPhysicsContact,
        ballBody: SKPhysicsBody
    ) {
        let boundaryBody = [contact.bodyA, contact.bodyB].first(where: {
            $0.categoryBitMask == PhysicsCategory.boundary
        })
        let boundaryName = boundaryBody?.node?.name
        guard BoundarySoundPolicy.shouldPlay(
            boundaryName: boundaryName,
            velocity: ballBody.velocity,
            collisionImpulse: contact.collisionImpulse
        ) else { return }

        let speed = BoundarySoundPolicy.impactSpeed(
            boundaryName: boundaryName,
            velocity: ballBody.velocity
        )
        let minimumSpeed = boundaryName == "floor"
            ? GameTuning.minimumAudibleFloorImpactSpeed
            : 85
        let intensity = min(max((speed - minimumSpeed) / 620, 0.08), 1)
        audioService.play(.bounce, intensity: intensity, preferences: preferences)
    }

    private func buildScoreOverlay() {
        scoreOverlay.removeFromParent()
        scoreOverlay.removeAllChildren()

        if let notchRect = geometry.notchRect {
            buildNotchScoreboard(under: notchRect)
            return
        }

        scoreOverlay.position = CGPoint(x: min(size.width - 112, geometry.rightBoundaryX - 104), y: size.height - 86)
        scoreOverlay.zPosition = 100
        addChild(scoreOverlay)

        let background = SKShapeNode(rectOf: CGSize(width: 188, height: 72), cornerRadius: 18)
        background.fillColor = NSColor(calibratedWhite: 0.08, alpha: 0.58)
        background.strokeColor = NSColor.white.withAlphaComponent(0.16)
        background.lineWidth = 1
        scoreOverlay.addChild(background)

        scoreLabel.fontSize = 28
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: -76, y: 11)
        scoreOverlay.addChild(scoreLabel)

        streakLabel.fontSize = 13
        streakLabel.fontColor = NSColor.white.withAlphaComponent(0.82)
        streakLabel.horizontalAlignmentMode = .left
        streakLabel.position = CGPoint(x: -76, y: -21)
        scoreOverlay.addChild(streakLabel)

        bestLabel.fontSize = 13
        bestLabel.fontColor = NSColor.white.withAlphaComponent(0.62)
        bestLabel.horizontalAlignmentMode = .right
        bestLabel.position = CGPoint(x: 78, y: -21)
        scoreOverlay.addChild(bestLabel)
    }

    /// The arena scoreboard: a panel hanging beneath the notch on two straps, so
    /// the notch itself reads as the jumbotron housing. Part of the scenery — it
    /// sits behind the ball, not on top of everything like the fallback overlay.
    private func buildNotchScoreboard(under notchRect: CGRect) {
        let panel = ScoreboardLayout.panelFrame(notchRect: notchRect)
        scoreOverlay.position = CGPoint(x: panel.midX, y: panel.midY)
        scoreOverlay.zPosition = 12
        addChild(scoreOverlay)

        // Dual-tone like the rest of the court furniture: a dark silhouette so it
        // reads over light desktops, a bright inner edge for dark ones.
        let contrast = SKShapeNode(
            rectOf: CGSize(width: panel.width + 6, height: panel.height + 6),
            cornerRadius: 11
        )
        contrast.fillColor = NSColor.black.withAlphaComponent(0.78)
        contrast.strokeColor = NSColor.black.withAlphaComponent(0.72)
        contrast.lineWidth = 4
        contrast.zPosition = -1
        scoreOverlay.addChild(contrast)

        let background = SKShapeNode(
            rectOf: CGSize(width: panel.width, height: panel.height),
            cornerRadius: 9
        )
        background.name = "notchScoreboardVisual"
        background.fillColor = NSColor(calibratedWhite: 0.10, alpha: 0.94)
        background.strokeColor = NSColor.white.withAlphaComponent(0.60)
        background.lineWidth = 1.6
        scoreOverlay.addChild(background)

        // Two straps up to the notch's lower edge.
        for direction in [-1.0, 1.0] {
            let strapX = direction * (panel.width / 2 - 14)
            let strap = SKShapeNode(rectOf: CGSize(width: 3, height: 8))
            strap.position = CGPoint(x: strapX, y: (panel.height / 2) + 4)
            strap.fillColor = NSColor(calibratedWhite: 0.22, alpha: 0.95)
            strap.strokeColor = NSColor.white.withAlphaComponent(0.35)
            strap.lineWidth = 1
            scoreOverlay.addChild(strap)
        }

        scoreLabel.fontSize = 19
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: -(panel.width / 2) + 12, y: 1)
        scoreOverlay.addChild(scoreLabel)

        streakLabel.fontSize = 11
        streakLabel.fontColor = NSColor.white.withAlphaComponent(0.82)
        streakLabel.horizontalAlignmentMode = .right
        streakLabel.verticalAlignmentMode = .center
        streakLabel.position = CGPoint(x: (panel.width / 2) - 12, y: 8)
        scoreOverlay.addChild(streakLabel)

        bestLabel.fontSize = 11
        bestLabel.fontColor = NSColor.white.withAlphaComponent(0.62)
        bestLabel.horizontalAlignmentMode = .right
        bestLabel.verticalAlignmentMode = .center
        bestLabel.position = CGPoint(x: (panel.width / 2) - 12, y: -8)
        scoreOverlay.addChild(bestLabel)
    }

    private func updateScoreOverlay() {
        if preferences.playMode == .shotClock24 {
            let remaining = shotClock.remaining(at: currentTime)
            scoreLabel.text = remaining < 5
                ? String(format: "%.1f", remaining)
                : "\(Int(remaining.rounded(.up)))"
            // Urgency reads at a glance: the readout turns red from 10 down.
            // Derived every update rather than painted on an event, so a fresh
            // 24 — basket, restart, mode change — goes back to white by itself.
            scoreLabel.fontColor = remaining <= 10 ? .systemRed : .white
            streakLabel.text = "Point \(shotClock.runScore)"
            bestLabel.text = "Best \(preferences.bestShotClockRun)"
        } else {
            scoreLabel.fontColor = .white
            scoreLabel.text = "Score  \(statistics.score)"
            streakLabel.text = "Streak \(statistics.streak)"
            bestLabel.text = "Best \(max(statistics.bestStreak, preferences.bestStreak))"
        }
        scoreOverlay.isHidden = !preferences.showScore
    }

    private func showScorePop() {
        guard let hoop else { return }
        let label = SKLabelNode(
            fontNamed: NSFont.systemFont(ofSize: 28, weight: .bold).fontName
        )
        label.text = statistics.streak >= 3
            ? "+\(pendingShotPoints)  \(statistics.streak)x"
            : "+\(pendingShotPoints)"
        label.fontSize = statistics.streak >= 3 ? 24 : 28
        label.fontColor = .white
        label.position = CGPoint(x: hoop.position.x, y: hoop.position.y + GameTuning.rimY + 34)
        label.zPosition = 120
        addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 30, duration: 0.42),
                .sequence([.wait(forDuration: 0.18), .fadeOut(withDuration: 0.24)])
            ]),
            .removeFromParent()
        ]))
    }

    private func emitScoreParticles() {
        guard !preferences.reducedEffects, let hoop else { return }
        let emitter = SKEmitterNode()
        emitter.position = CGPoint(x: hoop.position.x, y: hoop.position.y + GameTuning.rimY - 8)
        emitter.zPosition = 80
        emitter.particleTexture = Self.particleTexture()
        emitter.particleBirthRate = 85
        emitter.numParticlesToEmit = 22
        emitter.particleLifetime = 0.55
        emitter.particleLifetimeRange = 0.18
        emitter.emissionAngleRange = .pi
        emitter.particleSpeed = 80
        emitter.particleSpeedRange = 38
        emitter.yAcceleration = -90
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -1.4
        emitter.particleScale = 0.16
        emitter.particleScaleRange = 0.08
        emitter.particleColor = .systemOrange
        emitter.particleColorBlendFactor = 1
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
    }

    private static func particleTexture() -> SKTexture {
        let image = NSImage(size: CGSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 10, height: 10)).fill()
        image.unlockFocus()
        return SKTexture(image: image)
    }

    private func buildDebugLayer() {
        debugLayer.removeFromParent()
        debugLayer.removeAllChildren()
        debugLayer.zPosition = 200
        addChild(debugLayer)

        addDebugRect(geometry.visibleFrame, color: .systemGreen)
        if let notchRect = geometry.notchRect {
            addDebugRect(notchRect, color: .systemPink)
        }

        let anchor = SKShapeNode(circleOfRadius: 5)
        anchor.position = currentHoopAnchor
        anchor.fillColor = .systemYellow
        anchor.strokeColor = .black
        debugLayer.addChild(anchor)

        debugLabel.fontSize = 11
        debugLabel.fontColor = .white
        debugLabel.horizontalAlignmentMode = .left
        debugLabel.verticalAlignmentMode = .top
        debugLabel.position = CGPoint(x: 14, y: size.height - 38)
        debugLayer.addChild(debugLabel)

        velocityNode.strokeColor = .systemCyan
        velocityNode.lineWidth = 2
        debugLayer.addChild(velocityNode)
        debugLayer.isHidden = !preferences.debugGeometry
    }

    private func addDebugRect(_ rect: CGRect, color: NSColor) {
        let shape = SKShapeNode(rect: rect)
        shape.fillColor = .clear
        shape.strokeColor = color.withAlphaComponent(0.72)
        shape.lineWidth = 2
        debugLayer.addChild(shape)
    }

    private func updateDebugLabel() {
        debugLabel.text = "\(geometry.screenName) • \(geometry.dockEdge.rawValue) • \(ballState.rawValue)"
    }

    private func updateVelocityDebug(ball: BasketballNode, velocity: CGVector) {
        guard preferences.debugGeometry else { return }
        let path = CGMutablePath()
        path.move(to: ball.position)
        path.addLine(to: CGPoint(
            x: ball.position.x + velocity.dx * 0.08,
            y: ball.position.y + velocity.dy * 0.08
        ))
        velocityNode.path = path
    }

    private func scenePoint(for event: NSEvent) -> CGPoint? {
        guard let view else { return nil }
        let pointInView = view.convert(event.locationInWindow, from: nil)
        return convertPoint(fromView: pointInView)
    }
}

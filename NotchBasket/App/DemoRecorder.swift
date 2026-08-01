import AVFoundation
import Metal
import SpriteKit

/// Renders a scripted gameplay demo straight to a video file — no visible
/// window, no permissions, no screen capture. The footage is the real game:
/// the same scene, physics, net and shot clock the player gets, driven by
/// scripted shots and sampled frame by frame from a live SKView.
///
/// The view is real because it has to be: SKRenderer rasterizes a scene but
/// does not step its physics — only SKView's own loop does. The window hosting
/// it is fully transparent, ignores the mouse, and none of the game's overlay
/// machinery (panel, hotkey, status item) is ever created in record mode.
///
/// Run: NotchBasket --record-demo /path/to/out.mov
enum DemoRecorder {
    private static let stage = CGSize(width: 1280, height: 800)
    private static let frameRate = 30
    private static let duration: TimeInterval = 32

    static func recordIfRequested() -> Bool {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--record-demo"),
              CommandLine.arguments.count > flagIndex + 1 else { return false }
        let path = CommandLine.arguments[flagIndex + 1]
        do {
            try start(writingTo: URL(fileURLWithPath: path))
        } catch {
            print("demo failed: \(error)")
            exit(1)
        }
        return true
    }

    private static func makeGeometry() -> ScreenGeometry {
        let floorY: CGFloat = 64
        let notch = CGRect(x: (stage.width - 200) / 2, y: stage.height - 32,
                           width: 200, height: 32)
        let hoopAnchor = ScreenGeometryService.sideMountedHoopAnchor(
            screenSize: stage,
            floorY: floorY,
            rightBoundaryX: stage.width,
            horizontalOffset: 0,
            verticalOffset: 0
        )
        return ScreenGeometry(
            screenFrame: CGRect(origin: .zero, size: stage),
            visibleFrame: CGRect(x: 0, y: floorY, width: stage.width,
                                 height: stage.height - floorY - 32),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            notchRect: notch,
            hoopAnchor: hoopAnchor,
            ballSpawnPoint: ScreenGeometryService.ballSpawnPoint(
                screenWidth: stage.width,
                floorY: floorY,
                leftBoundaryX: 0,
                rightBoundaryX: stage.width
            ),
            floorY: floorY,
            leftBoundaryX: 0,
            rightBoundaryX: stage.width,
            dockEdge: .bottom,
            screenName: "Demo"
        )
    }

    /// The stage dressing a real screen provides for free: the dark desktop
    /// behind the overlay, the hardware notch that occludes the ball, and a
    /// floor line where the Dock would sit.
    private static func dress(_ scene: BasketballScene, geometry: ScreenGeometry) {
        scene.backgroundColor = NSColor(
            calibratedRed: 0.055, green: 0.082, blue: 0.133, alpha: 1
        )

        // A menu-bar band along the top: without it the black notch silhouette
        // vanishes into the dark backdrop, and the whole ball-from-the-notch
        // story is invisible.
        let menuBar = SKShapeNode(
            rect: CGRect(x: 0, y: stage.height - 32, width: stage.width, height: 32)
        )
        menuBar.fillColor = NSColor(calibratedWhite: 1, alpha: 0.10)
        menuBar.strokeColor = .clear
        menuBar.zPosition = 490
        scene.addChild(menuBar)

        if let notch = geometry.notchRect {
            let pill = SKShapeNode(
                rect: CGRect(x: notch.minX, y: notch.minY,
                             width: notch.width, height: notch.height + 40),
                cornerRadius: 18
            )
            pill.fillColor = NSColor(calibratedRed: 0.02, green: 0.027, blue: 0.043, alpha: 1)
            pill.strokeColor = NSColor.white.withAlphaComponent(0.30)
            pill.lineWidth = 1.5
            // Above everything, exactly as the hardware notch occludes the ball.
            pill.zPosition = 500
            scene.addChild(pill)
        }

        let floor = SKShapeNode(
            rect: CGRect(x: 0, y: geometry.floorY - 3, width: stage.width, height: 3)
        )
        floor.fillColor = NSColor.white.withAlphaComponent(0.22)
        floor.strokeColor = .clear
        floor.zPosition = 2
        scene.addChild(floor)
    }

    private static var session: RecordingSession?

    private static func start(writingTo url: URL) throws {
        let defaults = UserDefaults(suiteName: "demo-recorder")!
        defaults.removePersistentDomain(forName: "demo-recorder")
        let preferences = PreferencesService(defaults: defaults)
        preferences.soundEnabled = false
        preferences.playMode = .shotClock24
        preferences.aimGuideEnabled = false

        let geometry = makeGeometry()
        let scene = BasketballScene(
            size: stage,
            geometry: geometry,
            preferences: preferences,
            audioService: AudioService(),
            hapticService: HapticService()
        )
        // App Nap throttles a UI-less agent process to a crawl — both failed
        // takes ran the simulation at roughly 1/14th speed with identical
        // frames. Recording is user-initiated latency-critical work; say so.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled],
            reason: "recording gameplay demo"
        )
        _ = activity

        // The host window must count as visible, or the window server throttles
        // its display link and the simulation crawls — an alpha-zero window ran
        // at roughly 1/14th speed. So it is opaque but parked almost entirely
        // off the right edge of the screen: an 8-point sliver stays on screen,
        // which is enough to keep the view un-occluded and the physics at full
        // rate, while texture(from:) renders the whole scene regardless.
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: stage),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(
                x: screen.frame.maxX - 8,
                y: screen.frame.midY - (stage.height / 2)
            ))
        }
        window.ignoresMouseEvents = true
        window.level = .normal
        let view = SKView(frame: CGRect(origin: .zero, size: stage))
        view.preferredFramesPerSecond = frameRate
        window.contentView = view
        window.orderFrontRegardless()
        view.presentScene(scene)
        scene.presentGame()
        // Dressing must come after presentation: the scene's own buildScene()
        // begins with removeAllChildren(), which silently deleted the backdrop,
        // the notch silhouette and the floor line on the first two takes.
        dress(scene, geometry: geometry)
        scene.isRenderPacingDisabled = true

        session = try RecordingSession(
            url: url,
            view: view,
            scene: scene,
            script: DemoScript(scene: scene, geometry: geometry),
            frameRate: frameRate,
            frameCount: Int(duration * Double(frameRate)),
            stage: stage
        )
        session?.begin()
    }

    /// Samples the live view at the frame rate and writes each sample straight
    /// to the movie, then exits the process with a verdict.
    private final class RecordingSession {
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let view: SKView
        private let scene: BasketballScene
        private let script: DemoScript
        private let frameRate: Int
        private let frameCount: Int
        private let stage: CGSize
        private let url: URL
        private var frame = 0
        private var startedAt: CFTimeInterval = 0
        private var firstBallY: CGFloat?
        private var ballEverMoved = false
        private var timer: Timer?

        init(
            url: URL,
            view: SKView,
            scene: BasketballScene,
            script: DemoScript,
            frameRate: Int,
            frameCount: Int,
            stage: CGSize
        ) throws {
            self.url = url
            self.view = view
            self.scene = scene
            self.script = script
            self.frameRate = frameRate
            self.frameCount = frameCount
            self.stage = stage

            try? FileManager.default.removeItem(at: url)
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(stage.width),
                AVVideoHeightKey: Int(stage.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000
                ]
            ])
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: Int(stage.width),
                    kCVPixelBufferHeightKey as String: Int(stage.height)
                ]
            )
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
        }

        func begin() {
            startedAt = CACurrentMediaTime()
            let interval = 1.0 / Double(frameRate)
            let timer = Timer(timeInterval: interval, repeats: true) { [self] _ in
                captureFrame()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        private func captureFrame() {
            // Wall-clock everywhere: the capture loop cannot keep a perfect
            // cadence, and stamping frames by index compressed the first take's
            // timeline ~5x wherever the loop fell behind. Elapsed real time
            // drives both the script and the presentation stamps, so the video
            // plays at true speed however unevenly the frames arrive.
            let elapsed = CACurrentMediaTime() - startedAt
            script.tick(at: elapsed)

            if let y = scene.scriptedBallPosition?.y {
                if firstBallY == nil { firstBallY = y }
                if let first = firstBallY, abs(y - first) > 5 { ballEverMoved = true }
            }

            if let texture = view.texture(from: scene),
               let image = texture.cgImage() as CGImage?,
               input.isReadyForMoreMediaData,
               let pool = adaptor.pixelBufferPool {
                var maybeBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
                if let buffer = maybeBuffer {
                    CVPixelBufferLockBaseAddress(buffer, [])
                    if let context = CGContext(
                        data: CVPixelBufferGetBaseAddress(buffer),
                        width: Int(stage.width),
                        height: Int(stage.height),
                        bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue
                    ) {
                        context.draw(
                            image,
                            in: CGRect(origin: .zero, size: stage)
                        )
                    }
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    adaptor.append(buffer, withPresentationTime: CMTime(
                        seconds: elapsed,
                        preferredTimescale: 600
                    ))
                }
            }

            frame += 1
            if elapsed >= Double(frameCount) / Double(frameRate) {
                finish()
            }
        }

        private func finish() {
            timer?.invalidate()
            input.markAsFinished()
            let moved = ballEverMoved
            let path = url.path
            writer.finishWriting {
                if moved {
                    print("demo written: \(path)")
                    exit(0)
                } else {
                    print("demo failed: physics never advanced")
                    exit(2)
                }
            }
        }
    }
}

/// The choreography: which shot to take once the ball is ready, aimed by solving
/// the projectile for a chosen flight time rather than by hand-tuned numbers.
private final class DemoScript {
    private let scene: BasketballScene
    private let geometry: ScreenGeometry
    private var shotIndex = 0

    /// (earliest time, flight seconds, aim offset from rim centre)
    ///
    /// Flight times are long on purpose: they set the arc's steepness, and the
    /// first take proved a ~1 s flight arrives nearly horizontal and smashes
    /// the front rim — every shot missed. ~1.35 s peaks well above the rim and
    /// drops in steeply.
    ///
    /// The story the clock tells: a three at 3 s resets it to 24 as the swish
    /// drops (~4.4 s); the deliberate front-rim miss at 8.5 s does not reset
    /// anything, so the clock runs red from ~18.4 s and reaches zero at
    /// ~28.4 s — and the last shot leaves the hand at 27.2 with about a second
    /// left. The horn catches it mid-air: a buzzer-beater, the rule this mode
    /// was built around.
    private let shots: [(after: TimeInterval, flight: Double, aim: CGPoint)] = [
        (3.0, 1.35, CGPoint(x: 0, y: 10)),
        (8.5, 1.20, CGPoint(x: -40, y: -20)),
        (27.2, 1.40, CGPoint(x: 0, y: 10))
    ]

    init(scene: BasketballScene, geometry: ScreenGeometry) {
        self.scene = scene
        self.geometry = geometry
    }

    func tick(at time: TimeInterval) {
        guard shotIndex < shots.count else { return }
        let shot = shots[shotIndex]
        guard time >= shot.after,
              scene.scriptedBallState == .ready,
              let ballPosition = scene.scriptedBallPosition else { return }

        let rim = CGPoint(
            x: geometry.hoopAnchor.x,
            y: geometry.hoopAnchor.y + GameTuning.rimY
        )
        let target = CGPoint(x: rim.x + shot.aim.x, y: rim.y + shot.aim.y)
        // SpriteKit gravity is metres/s²; the default scale is 150 points/metre.
        let gravity = abs(scene.physicsWorld.gravity.dy) * 150
        let flight = CGFloat(shot.flight)

        // The ball carries linear damping — air drag — and a vacuum solution
        // undershoots by the ~25% of velocity the drag bleeds over a lob:
        // frame-by-frame review showed every "swish" arriving at rim height
        // while still left of the hoop. With drag k the trajectory has the
        // closed form x(t) = x0 + vx(1-e^(-kt))/k, and its inversion aims true.
        let k = max(GameTuning.ballLinearDamping, 0.0001)
        let decay = 1 - exp(-k * flight)
        let velocity = CGVector(
            dx: (target.x - ballPosition.x) * k / decay,
            dy: (((target.y - ballPosition.y) + (gravity * flight / k))
                * k / decay) - (gravity / k)
        )
        scene.scriptedShot(velocity: velocity)
        shotIndex += 1
    }
}

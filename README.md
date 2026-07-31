# NotchBasket

NotchBasket is a lightweight native macOS desktop toy with a basketball hoop mounted to the right edge of the display. It lives in the menu bar, presents a transparent SpriteKit overlay for a quick shot or two, and gets out of the way immediately when hidden.

The MVP is built entirely with public Apple frameworks:

- Swift and AppKit for the application and transparent overlay
- SwiftUI for onboarding and settings
- SpriteKit for rendering, input, contacts, and 2D physics
- AVFoundation procedural audio and `NSHapticFeedbackManager` for feedback
- Carbon hot-key registration for Control–Option–B without Accessibility permission
- `UserDefaults` for preferences and lifetime statistics
- `OSLog.Logger` for useful runtime diagnostics

## Screenshots

Screenshots are intentionally left as placeholders until the app is captured on representative notched and non-notched hardware.

- Gameplay overlay on a notched MacBook: _coming soon_
- Right-side mounted layout: _coming soon_
- Settings: _coming soon_

## Requirements

- macOS 14 Sonoma or newer
- Xcode 26.6 or another Xcode version with a current macOS SDK
- Apple Silicon is the primary target
- A notched MacBook display is preferred, but non-notched Macs and external displays use a centered fallback

No third-party packages, private APIs, screen-recording permission, input-monitoring permission, network access, or analytics SDK are used.

## Build and run

1. Open `NotchBasket.xcodeproj` in Xcode.
2. Select the **NotchBasket** scheme and the **My Mac** run destination.
3. Open the NotchBasket target’s **Signing & Capabilities** pane.
4. Select your development team if Xcode asks for signing. A local command-line build can also use ad-hoc/no signing.
5. Press Command–R to build and run.
6. On first launch, read the compact onboarding panel.
7. Click the basketball icon in the menu bar and select **Play**.
8. Pull the ball backward and release it to shoot. Press Escape to hide the game.

Command-line build:

```sh
xcodebuild \
  -project NotchBasket.xcodeproj \
  -scheme NotchBasket \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Command-line tests:

```sh
xcodebuild \
  -project NotchBasket.xcodeproj \
  -scheme NotchBasket \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## How to play

- Choose **Play** from the menu bar or press Control–Option–B.
- Click and hold the ball.
- Pull opposite the intended shot direction. Pull farther for more power.
- Release to shoot.
- A score counts only when the ball passes through the rim from top to bottom.
- Choose **Restart** to clear the current session.
- Press Escape, choose **Hide Game**, or press Control–Option–B again to leave play mode.

When hidden, the panel is ordered out, SpriteKit is paused, the local Escape monitor is removed, audio is stopped, and no invisible surface can intercept desktop clicks.

## Architecture

```text
NotchBasket/
├── App/         app lifecycle, menu commands, and game-mode coordination
├── Window/      transparent panel plus screen/notch/Dock geometry
├── Game/        SpriteKit scene, states, physics categories, shot/score/reset logic
├── Nodes/       procedural ball, hoop, rim, net, and aim visuals
├── Services/    preferences, sound, haptics, and no-permission global shortcut
├── UI/          SwiftUI onboarding and settings
├── Config/      application property list
└── Tests/       deterministic geometry, shooting, scoring, and persistence tests
```

`AppState` owns the game mode and exactly one `OverlayWindowController`. The window controller owns one transparent `NSPanel`, one `SKView`, and one `BasketballScene`. Display changes discard and safely recreate this graph, avoiding duplicate overlay windows and stale physics geometry.

The scene uses explicit `BallState` values instead of loosely related flags. Pure logic is kept outside SpriteKit where practical so it can be tested without a live renderer.

## Overlay behavior and window level

The overlay is a borderless, transparent, non-activating `NSPanel`. It uses the `.floating` window level, which is sufficient to appear over ordinary desktop applications without using the higher status-bar, pop-up, screen-saver, or private system levels that could interfere with alerts and protected UI.

The panel joins all Spaces and opts into full-screen auxiliary behavior using public collection behaviors. Mission Control, authentication panels, protected system surfaces, and some application-managed full-screen arrangements remain under macOS control.

The overlay uses hover-based selective mouse capture. It ignores mouse events across the display until the pointer enters the compact hit region of a ready or moving ball, or the hoop body. It keeps capture for the full drag after a gesture begins. A flying ball can be grabbed and thrown again immediately; dragging the hoop vertically adjusts and persists its height. Everywhere else, the desktop remains interactive. When play mode ends, the panel is fully removed rather than left transparent.

## Notch and screen geometry

`NotchGeometryService` first asks `NSScreen` for:

- `auxiliaryTopLeftArea`
- `auxiliaryTopRightArea`
- `safeAreaInsets`

When both auxiliary rectangles exist, their horizontal gap estimates the physical notch:

```text
left edge  = auxiliary left area maxX
right edge = auxiliary right area minX
center     = midpoint of the gap
```

The global screen rectangle is translated to overlay-local SpriteKit coordinates. The hoop anchor is placed against the usable right boundary at 72% of screen height, then adjusted by the user’s horizontal and vertical offsets. Notch geometry remains useful for selecting the built-in display and debugging, but no longer controls hoop placement.

The active display policy prefers the first display with detected notch geometry. If none is notched, it uses the display under the pointer, then `NSScreen.main`, then the first connected display.

The app listens for `NSApplication.didChangeScreenParametersNotification`. During play, it hides the old overlay, recalculates all geometry, recreates the scene, and resets safely.

## Dock inference

Public AppKit does not expose an exact Dock rectangle. `ScreenGeometryService` compares `NSScreen.frame` and `visibleFrame`:

- a large bottom inset means a bottom Dock
- a large left inset means a left Dock
- a large right inset means a right Dock
- small insets are treated as an auto-hidden or unknown Dock

For a bottom Dock, the physics floor is placed ten points above `visibleFrame.minY`. For side or auto-hidden Docks, the floor uses a small bottom safety margin. Side-Dock visible bounds also constrain the left or right wall.

The ball spawns directly above the inferred floor/Dock. Bottom-edge pull compensation preserves the full downward pull range from this low starting position.

## Physics and shot tuning

All gameplay constants live in `GameTuning.swift`. The current baseline uses:

- gravity presets around `-7.8`, `-10.2`, and `-12.4`
- 48-point ball diameter
- 0.74 ball restitution
- 0.58 ball friction
- 155-point maximum drag
- bottom-edge pull compensation, so a ball resting above the Dock can still reach full power
- 15.0 launch-power multiplier and 2,800 maximum launch speed
- settled and timed-out balls freeze where they finish and become draggable again; only out-of-region shots respawn
- precise collision detection on the ball
- an 8-second maximum shot lifetime

`ShotController` clamps drag distance, validates a minimum pull, applies sensitivity, reverses the vector for slingshot behavior, and clamps final speed. Its output is covered by unit tests.

Two play modes share the court. Free play is the original toy. 24 Seconds is an NBA-style possession game: the clock arms at 24 and starts only when the player first takes the ball; every basket buys a fresh 24 and one point; an expired clock is a violation — arena horn, red flash, run recorded — with one exception ported from the real rule: a shot already in the air when the horn sounds still counts if it drops, and a buzzer-beater keeps the run alive. The clock lives on the scoreboard, switching to tenths under five seconds, and the best run persists. On notched screens the notch itself is part of the court: every fresh ball is born behind it and drops into view — the notch is dead pixels, so the hardware performs the reveal — and the scoreboard hangs beneath it on straps, making the notch read as the jumbotron housing. The top boundary stays solid; the ball's boundary masks are stripped only for the drop. Both features vanish gracefully on screens without a notch. The right-mounted hoop uses a broadcast-style side profile. A padded vertical backboard sits near the screen edge with a steel wall plate, hinge, and diagonal braces behind it; a boxed orange support arm and lower mounting bracket extend leftward from the board before meeting the rim. The projected rim is a shallow ellipse split into rear and front render layers, so the basketball appears in front of the far edge and behind the near edge while passing through. Dual-tone contrast edges pair dark silhouettes with bright inner strokes so the complete assembly remains readable over both white documents and dark desktops without sampling the screen. Two small circular rim colliders leave the opening physically clear, and the thin vertical board collider supports bank shots without creating a horizontal shelf.

The procedural diamond-weave net is a woven sheet of 234 knots simulated in three dimensions on a cone of revolution. Cord lengths are solved as constraints rather than integrated as springs, with shear cords holding the diamonds square and two-knot spans resisting creases, so a ball pressing on the weave leaves a local dent instead of widening the whole loop — from inside or outside, through one sphere contact that never asks which side the ball is on or whether the shot scored. The hem is deliberately narrower than the ball, so a clean shot has to stretch it open; that stretch is the swish. The net returns a force applied to the ball's physics body rather than repositioning it, sized in multiples of the ball's own weight and capped at three, so the cords can brake a shot without flinging it. Contact is resolved after the cord constraints rather than inside their solve, and most of a contact displacement is carried into the knot's previous position as well: Verlet reads a bare position change as velocity, and letting the cords and the ball fight over one repeatedly used to hand the sheet enough free energy to throw itself off the rim. The contact sweep subdivides by ball travel, so a shot crossing the whole net inside one display frame still touches it. Knots are projected side-on — height picks up a share of depth — and each cord is drawn as one continuous helix from the rim to the hem, bending through its knots rather than turning a corner at each one. A cord is split between the rear and front render layers wherever it winds past the side of the cone, so the ball passes between them. A lateral backstop of at most two points per frame recovers a ball that slipped through a cord, and only ever a ball that was genuinely inside the cone.

To tune the feel:

1. Change only values in `GameTuning.swift`.
2. Turn on **Debug geometry and physics** in Settings.
3. Watch the velocity vector, bodies, sensors, screen bounds, state, and FPS.
4. Test low, normal, and high power shots.
5. Re-run `ShotCalculationTests` and `ScoringTests` after changing thresholds.

## Scoring

The hoop contains an upper and lower non-colliding sensor. `ScoreController` accepts a score only when:

1. the current shot crosses the upper sensor,
2. then crosses the lower sensor,
3. the lower crossing velocity is downward,
4. the ball center is inside the rim’s physically clear width, and
5. the current shot has not already completed its scoring sequence.

The controller resets for each new shot. The scene records total session score, current streak, best streak, attempts, successes, and accuracy-ready counts. Lifetime baskets, shots, and best streak are persisted.

## Settings

The MVP settings window includes:

- aim guide
- gravity preset
- launch sensitivity
- hoop horizontal offset and persisted height control
- sound and master volume
- haptic feedback
- score visibility
- reduced visual effects
- debug geometry/physics
- Dock icon visibility
- lifetime-score reset

The app also respects the macOS Reduce Motion accessibility preference for hoop deployment.

## Debug mode

Enable **Debug geometry and physics** in Settings. It shows:

- SpriteKit physics bodies, including rim, board, sensors, and boundaries
- FPS
- visible-frame outline
- estimated notch rectangle
- hoop anchor
- ball velocity vector
- active display name
- inferred Dock edge
- current ball state

Debug visuals are disabled by default and are never persisted as production overlays unless the user explicitly enables them.

## Privacy

NotchBasket:

- does not capture or inspect the screen
- does not enumerate window contents
- does not record input outside active gameplay
- does not require Accessibility, Screen Recording, or Input Monitoring permission
- does not use private APIs
- does not contain analytics or networking code
- does not upload desktop, gameplay, or preference data

The overlay is transparent because its own background has no pixels; it does not read the desktop underneath it. The overlay window also opts out of window sharing.

## Known limitations

- Physical feel and exact hoop alignment still require manual validation across real MacBook panel sizes and display scaling modes.
- The built-in display is preferred when notch geometry is available, but there is not yet a menu for choosing a specific display.
- The hoop visually models broadcast-style side depth, while collision depth remains a deliberate 2D approximation using two small circular rim colliders.
- Audio is procedurally generated at launch. The rim and backboard deliberately share one impact voice — a modally synthesized padded thud chosen by ear from auditioned candidates; future passes can still replace the bank with recorded assets.
- Full-screen auxiliary windows are supported through public AppKit behaviors, but individual full-screen apps, Stage Manager layouts, or future macOS policies may place content differently.
- Mission Control and protected system surfaces intentionally remain outside the app’s control.
- Because click-through switches at the window level, a very fast move-and-click over the ball can occasionally require a second click on heavily loaded systems.
- Launch at login and shortcut customization are not included in this MVP.

## Manual testing

Use [Docs/ManualTestChecklist.md](Docs/ManualTestChecklist.md) for device and interaction testing. The most important acceptance pass is a real notched MacBook with its Dock both visible and auto-hidden.

## Roadmap

The separated geometry, state, node, and service layers leave room for:

- moving hoops and timed challenges
- trick-shot and bank-shot recognition
- skins, themes, and richer original audio
- daily challenges and local statistics
- multiple game modes and low-gravity variants
- a broader “Notch Toys” collection

These features are intentionally excluded until the core physical feel has been validated on representative hardware.

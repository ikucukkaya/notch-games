# NotchBasket manual test checklist

Record the Mac model, macOS version, display scaling, Dock position, and connected displays for every pass.

## Core launch and lifecycle

- [ ] First launch shows one compact onboarding window.
- [ ] “Do not show again” is persisted.
- [ ] The app has no Dock icon by default.
- [ ] The basketball menu-bar icon remains visible.
- [ ] Play creates one transparent overlay.
- [ ] Repeated Play commands never create duplicate overlays.
- [ ] Hide Game retracts and removes the overlay.
- [ ] Escape hides the game.
- [ ] Control–Option–B toggles play without an Accessibility prompt.
- [ ] Hidden mode never blocks clicks in another app.
- [ ] During play, clicks away from the ball and hoop operate the app underneath the overlay.
- [ ] Hovering a ready or moving ball captures it without blocking nearby desktop controls.
- [ ] Hovering the hoop body captures it for vertical adjustment.
- [ ] Dragging remains captured after the pointer leaves the selected hit region.
- [ ] CPU usage falls to an idle level while hidden.
- [ ] Ten rapid show/hide cycles do not leak windows or crash.
- [ ] Quit removes the menu item and overlay immediately.

## Notched MacBook

- [ ] Hoop stays clear of the physical notch and menu bar.
- [ ] Backboard mounts against the usable right screen edge.
- [ ] Rim and net extend left from the right-side backboard.
- [ ] Wall plate, hinge, diagonal braces, padded backboard edge, orange support arm, and lower bracket read as one plausible mounting assembly.
- [ ] Backboard, split rim, mount, support arm, bracket, and net remain distinct over a white document and a dark desktop.
- [ ] Deployment slides in horizontally from the right edge.
- [ ] Score overlay does not overlap the side-mounted hoop.
- [ ] Hoop offsets can correct alignment without restarting the app.
- [ ] Dragging the hoop moves it vertically only, clamps it on-screen, and persists the height after reopening.
- [ ] Default spawn point sits directly above a visible bottom Dock.

## Non-notched built-in display

- [ ] Hoop uses the same stable right-side mount.
- [ ] Safe-area/menu-bar spacing remains sensible.
- [ ] Gameplay works at every supported scaling option.

## External and multiple displays

- [ ] With no notched display, the pointer’s display is selected.
- [ ] With a notched built-in display connected, it is preferred.
- [ ] Connecting a display during a shot resets safely.
- [ ] Disconnecting the active display recreates the overlay on a valid display.
- [ ] Changing resolution or scaling rebuilds boundaries and spawn geometry.
- [ ] Sleeping and waking leaves the app responsive.

## Dock geometry

- [ ] Visible bottom Dock places the floor just above it.
- [ ] Auto-hidden Dock uses the bottom safety margin.
- [ ] Left Dock constrains the left wall without shifting the spawn off-center.
- [ ] Right Dock constrains the right wall without shifting the spawn off-center.
- [ ] Resizing the Dock does not crash the app after display parameters update.

## Shooting and physics

- [ ] Clicking outside the ball does not begin aiming.
- [ ] The ball follows the pointer only after a ready, flying, or scored ball is grabbed.
- [ ] A flying or scored ball can be grabbed immediately and thrown again without waiting for it to settle.
- [ ] Pulling down launches upward.
- [ ] Pulling left launches right, and vice versa.
- [ ] Very short drags return the ball to its origin.
- [ ] Maximum pull shows a distinct power state and one haptic.
- [ ] A ball resting above the bottom Dock can still reach full power by dragging to the screen edge.
- [ ] The power ring remains visible around the ball during an edge-compensated pull.
- [ ] Aim guide updates smoothly and disappears on release.
- [ ] Launch speed is capped.
- [ ] Ball rotation is visible in flight.
- [ ] Floor and side-wall bounces lose energy naturally.
- [ ] Ball does not tunnel through rim posts at maximum power.
- [ ] Ball can bounce and roll off either rim side without becoming trapped.
- [ ] The vertical right-side backboard produces bank-shot deflections without a top shelf.
- [ ] A still or timed-out shot freezes at its resting position and becomes draggable again.
- [ ] A shot that leaves the playable region resets safely.
- [ ] Small final floor bounces are silent while the first meaningful impact remains audible.
- [ ] A meaningful floor bounce sounds like a hollow rubber basketball on a wooden court, without a glassy or metallic click.

## Scoring

- [ ] Clean downward pass scores exactly once.
- [ ] During a pass, the ball renders in front of the rear rim and rear cords, then behind the front rim and front cords.
- [ ] A made basket stretches the net downward, follows the ball's lateral motion, and settles without snapping.
- [ ] After entering downward through the rim, the ball cannot leave through the net's sides or diamond gaps and clears the net only through its bottom opening.
- [ ] A missed shot brushing the lower net from underneath pushes the touched area upward without awarding a score.
- [ ] Side and glancing contacts move the closest cords first, then spread a smaller ripple through neighboring cords.
- [ ] Very fast shots still move the net instead of tunneling through it between rendered frames.
- [ ] The net's top loops remain attached to the rim while lower rows swing and return smoothly to rest.
- [ ] Repeated hard contacts do not make the narrow bottom knots cross, stack, or remain tangled.
- [ ] Reduce Motion produces a shorter, subtler net response.
- [ ] Ball moving upward through the opening does not score.
- [ ] Lower-sensor-first contact does not score.
- [ ] Rim contact alone does not score.
- [ ] A ball outside the clear inner-rim width does not score.
- [ ] One shot cannot add multiple baskets.
- [ ] Score, streak, best streak, attempts, and successes update correctly.
- [ ] A miss clears the current streak.
- [ ] Lifetime best streak survives relaunch.
- [ ] Reset lifetime scores clears persisted totals.

## Feedback and accessibility

- [ ] Rim, backboard, boundary, score, deploy, and retract feedback are distinct.
- [ ] Collision sound cooldown prevents machine-gun audio.
- [ ] Sound toggle silences effects immediately.
- [ ] Master volume changes effect volume.
- [ ] Haptics toggle disables haptic feedback.
- [ ] Score produces net movement, a `+1`, and subtle particles.
- [ ] Show Score toggle updates during play.
- [ ] Aim Guide toggle updates during play.
- [ ] macOS Reduce Motion shortens and simplifies deployment.
- [ ] Reduced visual effects removes particles and large secondary motion.
- [ ] Settings controls have useful VoiceOver labels and values.

## Spaces and system UI

- [ ] Ordinary Safari, Xcode, Terminal, and Finder windows remain visible behind play.
- [ ] Full-screen Safari can show the auxiliary overlay.
- [ ] Full-screen Xcode can show the auxiliary overlay.
- [ ] Switching Spaces does not strand an invisible input-capturing panel.
- [ ] Stage Manager activation/deactivation leaves geometry valid.
- [ ] Mission Control remains usable after hiding the game.
- [ ] Authentication prompts and protected system UI are not covered permanently.

## Debug pass

- [ ] Debug mode shows FPS and physics bodies.
- [ ] Visible-frame outline matches AppKit geometry.
- [ ] Notch rectangle matches the auxiliary-area gap.
- [ ] Hoop anchor marker matches the deployed mount.
- [ ] Sensors and rim posts have no invisible body across the opening.
- [ ] Velocity vector follows the active ball.
- [ ] Display name, Dock edge, and ball state update correctly.

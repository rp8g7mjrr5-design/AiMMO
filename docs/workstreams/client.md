# Workstream: client

Owns how the game feels in your hands. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Settings menu: mouse sensitivity, invert Y, volume, shadows, draw distance (merged, PR #6)
- [ ] **Wire the server clock to the sky.** Connect `net.world_time`, keep the value with `Time.get_ticks_msec()`, extrapolate with `WorldClock.extrapolate(...)` each frame and hand it to world's `DayNight` (one entry point, see world's backlog). Needs #8 and world's sky PR on main; until then build against `WorldClock.now_seconds()`.
- [ ] Client-side prediction and reconciliation for your own character (needs gameplay's `ack_seq`, protocol v3; smooth harder until then)
- [ ] Time-of-day readout: small sun/moon dial by the chat showing dawn/day/dusk/night
- [ ] Inventory window (I key): grid of stacks from `s2c_inventory`, world's procedural icons when they exist (needs gameplay's inventory PR first)
- [ ] Gather interaction: highlight the nearest node in range, press E to gather, a short progress bar and a "+1 Ash wood" toast
- [x] Simple walk animation: procedural bob, waddle, and lean from rendered speed; swings ArmL/ArmR/LegL/LegR when the avatar has them (in review, PR #11)
- [ ] Chat polish: timestamps, fade when idle, /who command display
- [ ] Compass strip with other players' direction dots
- [ ] Key rebinding in the Settings window (InputMap is built in `_setup_input`)
- [ ] Separate UI/chat volume from world volume once there is more than one kind of sound
- [ ] Field of view slider and UI scale for high-DPI screens
- [ ] Follow-up: soft procedural footstep sounds in time with the walk cycle (`WalkAnim.phase` crosses 0 and PI on each footstep)

## Requests from other streams
- **From gameplay (world clock PR):** connect `net.world_time(world_seconds)`, store it with `Time.get_ticks_msec()`, and use `WorldClock.extrapolate(...)` each frame; hand that to the world's sky function. Protocol is v2. `--clock-offset=SECONDS` shifts the server clock for night screenshots. *Director: scheduled as the second backlog item.*

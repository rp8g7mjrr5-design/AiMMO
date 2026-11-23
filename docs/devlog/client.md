# Devlog: client workstream

Newest entries at the bottom. Each run appends what it built, what didn't work, and notes to its next run.

## 2026-11-22: Settings menu (ws/client/settings-menu)

**Why this item:** the top backlog item, client-side prediction, needs the server to echo the
last processed input seq in snapshots, which is `gameplay`'s protocol. I filed that request in
`docs/workstreams/gameplay.md` and took the next unblocked item, the settings menu.

**Built:**
- `game/client/settings.gd` (`ClientSettings`): mouse sensitivity (0.25 to 3x), invert Y,
  master volume, shadows (Off/Low/High = 0/60/120 m), draw distance (150 to 600 m). Saved to
  `user://settings.cfg`. Every value is type-checked and clamped on load, so a broken or
  hand-edited file falls back to defaults instead of crashing.
- `game/client/settings_menu.gd` (`SettingsMenu`): a centred panel. Esc toggles it in game
  (Esc first leaves the chat box if it has focus); the login screen has a Settings button.
  Changes apply live; the file is written when the window closes. Movement and mouse look are
  paused while it's open.
- `client.gd`: `look_delta()` (static, tested) applies sensitivity and invert; `_apply_settings`
  sets the master bus volume (muted at 0), `camera.far`, and the sun's shadow distance.
- Test hook `--open-settings` opens the window at start, for screenshots.

**Decisions:**
- Separate file from `client.cfg`, because the login screen rebuilds `client.cfg` from scratch
  on every connect and would wipe settings stored there.
- Shadow "High" equals the world's original 120 m, and draw distance defaults to the old
  600 m far plane, so nothing looks different until a player changes something.
- No bot behaviour: settings are purely client-side and never touch the server, so there is
  nothing for a bot to exercise. Covered by 6 unit tests and a manual screenshot instead.

**What didn't work at first:** `cfg.get_value(...) == true` raises a SCRIPT ERROR in Godot 4.3
when the stored value is a String (it doesn't just return false). The unit test still showed
`ok` because the runner ignores script errors; fixed with a `typeof` check, and asked `qa` to
make the runner fail on SCRIPT ERROR.

**Notes to next run:**
- If gameplay has shipped an acked seq in snapshots, do prediction next; otherwise take the
  minimap/compass.
- `tests/client_smoke/run.sh` (qa-owned) could also screenshot with `--open-settings`.

## 2026-11-22: Walk animation (ws/client/walk-animation)

**Why this item:** prediction is still blocked (no acked input seq on `main`; gameplay's
world-clock PR #8 is v2 and the director's pending backlog puts `ack_seq` in v3). The
director's unmerged PR #10 reorders my backlog with the sky-clock wiring and time-of-day dial
first, but both need #8 and world's #9 on `main`, and inventory/gather need gameplay PRs that
don't exist yet. Walk animation was the highest item in both the merged and the pending
backlog that is unblocked today, and the director ranks it above the compass, so I took it
over the minimap my last note suggested.

**Built:**
- `game/client/walk_anim.gd` (`WalkAnim`): one per avatar. Speed comes from how fast the
  *rendered* (already smoothed) position moves, so it works for every avatar including your
  own, with no server data. Gives bob (|sin| so it rises on each footstep), side roll, forward
  lean, and arm/leg swing, all scaled by speed / `WALK_SPEED`. Moves over 3 m in one frame
  (spawn snap from y=-100, corrections) count as teleports, not running. When stopping, the
  phase eases to the nearest rest pose instead of freezing mid-stride; idle avatars breathe.
- `client.gd`: `wrap_avatar()` puts `AvatarBuilder`'s output under a steady root as a child
  named `Body` and moves the `Label3D` name tag onto the root, so tags don't bob or sway.
  `avatars[id]` gains `body` and `anim`; `_process` steps and applies the anim after the
  position/yaw lerp.
- Tests: 7 unit tests in `tests/unit/test_client_walk_anim.gd`, and a bot behaviour
  `client_walk_anim.gd` that runs `WalkAnim` on the real snapshot stream for every other
  peer and fails on NaN/out-of-range poses or if no peer ever breaks into a walk. Bot run:
  ~24k poses per bot, max gait 1.0, all 8 bots ok, Postgres verify 8/8.

**Decisions:**
- The avatar meshes are world's (`game/procgen/avatar_builder.gd`), so I didn't add arms. The
  anim swings `ArmL`/`ArmR`/`LegL`/`LegR` if present; requested those in world's backlog.
  Until then the bob + waddle + lean carry it, and it reads well on the capsule.
- Wrapper node instead of animating the avatar root, because the root's position and yaw are
  owned by snapshot smoothing.

**What didn't work at first:** building a real avatar (or even a bare `Label3D`) in a headless
unit test prints `Parameter "m" is null` from the dummy renderer. Not a failure in the runner,
but noisy, so the wrap test uses a stand-in `Node3D` and skips the tag part when headless (the
smoke run covers the real avatar; checked its world screenshot: tag sits above the body).

**Notes to next run:**
- Footsteps are the natural follow-up: `WalkAnim.phase` crosses 0 and PI once per step; play a
  quiet procedural thud from `Sfx` for your own avatar only (added to backlog).
- If #8 and #9 are on `main`, do the sky-clock wiring next (director's #1). If prediction's
  `ack_seq` lands, prediction must keep the wrapper: animate `Body`, move the root.

## 2026-11-22: Sky on the server clock + time dial (ws/client/time-dial)

**Why this item:** gameplay's world clock (#8) and world's shared-clock sky (#13) are both on
`main` now, so the top backlog item (wire the server clock to the sky) was finally unblocked.
On its own it is three lines, so I shipped it together with the time-of-day dial (backlog
item 3), which is the visible half of the same feature: the sky and the HUD agree with the
server. Prediction is still blocked on gameplay's `ack_seq`.

**Built:**
- `client.gd`: `net.world_time` -> `_on_world_time` -> `DayNight.set_world_seconds` (exactly
  world's requested entry point). `DayNight.clear_sync()` on disconnect, so the login-screen
  sky falls back to the local wall clock (same epoch, no jump).
- `game/client/time_dial.gd` (`TimeDial`): a 40 px disk above the chat. Upper half is the sky
  in the phase's colour, lower half ground; the sun rides the rim by day (rises left, top at
  noon, sets right) and a crescent moon takes over at night (top at midnight). Readout next to
  it: `Day 86 · 04:46 · Night`. Redraws every 0.5 s (an in-game minute is ~1.7 s) and on every
  sync. All maths in static `TimeDial.state(world_seconds)`.
- `TimeDial.current_seconds()` honours `AIMMO_TIME_OF_DAY` pinning so screenshot dial and sky
  agree.
- Tests: 5 unit tests in `tests/unit/test_client_time_dial.gd` (sun/moon placement over a whole
  day, readout and phase labels, 23:59 edge, pinning, and the client's world_time handler
  driving DayNight, including a NaN). Bot behaviour `client_time_dial.gd` checks every real
  `s2c_world_time` against the clock and that each login got at least one sync. Bot run: all 8
  bots ok, 5 syncs each, Postgres verify 8/8. Smoke test passed; checked the world screenshot:
  night dial with the moon, sitting cleanly above the chat.

**Decisions:**
- The dial reads time through `DayNight` rather than keeping its own synced copy, so there is
  exactly one client-side clock (world's note asked for that).
- Phase colours are local constants in the dial rather than palette.gd, since palette.gd is
  world-owned; if world adds UI sky colours there, switch to them.
- No 12-hour clock option: 24-hour is unambiguous and matches `WorldClock.describe`.

**What didn't work at first:** nothing broke; I'd worried the dial's `Label` child would
inherit the anchored parent's size oddly, but placing it by position inside a fixed-size
Control is fine.

**Notes to next run:**
- Next unblocked items: gather interaction / inventory still need gameplay PRs; chat polish
  (timestamps could reuse `TimeDial.state(...).text` style in-game time) or the compass strip
  are good picks.
- The dial sits at a fixed offset above the chat panel (offset_top -316). If chat panel size
  changes, move the dial with it.

## 2026-11-22: Chat polish (ws/client/chat-polish)

**Why this item:** prediction still needs gameplay's `ack_seq`, and inventory/gather need
gameplay's inventory and node PRs (#22 is only node placement), so chat polish was the top
unblocked item. It also closes my own follow-up (fade the dial text with the chat).

**Built:**
- `game/client/chat_feed.gd` (`ChatFeed`): static `timestamp`, `escape`, `chat_line`,
  `system_line`, `alpha`, plus a small stateful `step`/`wake`/`append`. Lines look like
  `14:05 Ash: hello` with a dim in-game time read from `TimeDial.current_seconds()` (so pinned
  screenshots, the dial, and chat agree). Panel holds at 0.92 for 12 s of quiet, then
  smoothsteps to 0 over 1.5 s. Typing, settings open, or the mouse over the panel keep it
  awake; a new line or Enter wakes it. The time dial's label follows the panel's alpha, the
  disk stays. Log capped at 150 lines with `RichTextLabel.remove_paragraph(0)`.
- `client.gd`: `chat_panel` is now a field (was reached via `chat_log.get_parent().get_parent()`),
  `_update_chat_fade` each logged-in frame, placeholder mentions /help.
- Tests: 6 unit tests in `tests/unit/test_client_chat_feed.gd` (timestamps match the dial at
  every quarter hour, BBCode escaping incl. the rendered text, fade curve, wake rules, line cap,
  and the client's handler). Bot behaviour `client_chat_feed.gd` renders every real chat and
  system line through `ChatFeed` into a RichTextLabel and checks the exact parsed text. Bot run:
  8/8 ok, ~125 lines per bot, Postgres verify 8/8. Smoke passed; world shot shows `12:00` on the
  welcome line matching the dial's `12:00`.

**Decisions:**
- In-game time, not real time, for timestamps: it is the world's clock and everyone shares it.
- Fade to fully hidden rather than a ghost: the top-right help line already says "Enter to chat",
  and the screen is cleaner for screenshots. Hover brings it back.
- Escaping is now `[lb]`/`[rb]` (shows brackets exactly) instead of the old system-line
  replacement of `[` with `(`. The server strips brackets from chat already; this is defence in
  depth for names and system text.
- "/who display": gameplay's `/who` answer already arrives as a system line, so nothing new to
  build there; the placeholder hint makes commands discoverable instead.

**What didn't work at first:** calling `_on_chat` in a unit test plays `sfx_chime` outside the
tree, which logs an engine error that the runner counts as a failure; the handler test uses
`_on_system` instead.

**Notes to next run:**
- Bot run never hit the 150 cap or a faded chat (bots chat every 8 to 20 s); both are unit tested.
- Good next picks: compass strip, key rebinding, chat history on Up arrow. Prediction as soon as
  gameplay ships `ack_seq`.

## 2026-11-22: Compass strip (ws/client/compass)

**Why this item:** prediction still waits on gameplay's `ack_seq`; inventory window and gather
interaction still wait on gameplay (no `s2c_inventory` or gather RPC on main yet, only `/bag`
and node placement). The compass strip was the top unblocked item, and it serves the
Cooperation-first pillar directly: you can see where other people are and walk to them.

**Built:**
- `game/client/compass.gd` (`CompassStrip`): a 480x30 strip, top centre under the HUD line.
  Shows ticks every 15 degrees, N/E/S/W (N in ember orange), a dot per other player (opaque
  within 40 m, fading to 0.35 at 200 m), a chevron pinned to the near edge for players more
  than 90 degrees off your view, pointing the shorter way to turn, and an ember diamond for the
  Spawn Meadow (hidden within 12 m of it). Letters and ticks fade over the last 28 px of the
  strip so they don't hang half off the ends (first smoke shot had a clipped "E" and "W").
- Conventions: north = -Z, east = +X, headings clockwise from north. `heading(cam_yaw)` is
  `-cam_yaw`, which matches the client camera forward `(-sin(yaw), 0, -cos(yaw))`; the unit
  test checks that for 36 yaws.
- `client.gd`: `compass` field, built in `_build_ui`, shown on login and hidden on disconnect,
  fed at 20 Hz (`due()` throttle) from `other_positions()` (rendered positions of other avatars,
  skipping ones still parked at y=-100 before their first snapshot).
- Tests: 6 unit tests in `tests/unit/test_client_compass.gd` (heading vs camera forward,
  cardinals, left/right/behind placement, distance and edge fade, home marker, client feed).
  Bot behaviour `client_compass.gd` builds the marks from every real snapshot with a turning
  camera and checks one mark per player, all on the strip, dots at the true bearing, chevrons on
  the right side. Bot run: 8/8 ok, ~24k marks per bot (about half of them edge chevrons), up to 7
  other players seen, Postgres verify 8/8. Smoke passed; world shot shows the strip facing S.

**Decisions:**
- 180-degree span: matches a wide third-person view closely enough that a dot near the strip's
  edge is near the screen's edge too, and still leaves room to spread out a crowd.
- Players behind you are always shown (as chevrons) rather than dropped, because "where is
  everyone?" is the question the compass answers.
- No names on the dots for now: a crowd at spawn would turn into unreadable text. Logged as a
  follow-up (nearest-dot name) if it feels anonymous.

**Notes to next run:**
- Smoke test only ever has one player, so the dots are covered by the unit and bot tests, not
  the screenshot.
- Good next picks: key rebinding, chat history on Up arrow. Gather/inventory UI as soon as
  gameplay ships the RPCs; the compass can then mark nodes too.

## 2026-11-22: Press E to gather (ws/client/gather-prompt)

**Why this item:** gameplay asked for it ("Requests from other streams" come first), and
gathering is live on main through `/gather` only, which is a chat command, not a game action.
Prediction still waits on `ack_seq`, the inventory window on `s2c_inventory`.

**Built:**
- `game/client/gather_prompt.gd` (`GatherPrompt`), bottom centre above the chat line:
  "E  Gather Ember ash" for the nearest node within `ResourceNodes.GATHER_RANGE`; a seep in
  daylight shows dimmed "Ember-sap seep  only seeps at night" and E does nothing. Press or hold
  E: the client sends `/gather <kind>` as chat at most once per `PRESS_INTERVAL` (1.6 s, the
  server's 1.5 s cooldown plus slack, and above the 0.5 s chat cooldown), an ember bar fills over
  that interval, and the server's success line ("You gather 2 ash wood ... (6 in your pack)")
  becomes a toast "+2 Ash wood  (6)" that floats up and fades over 2.2 s. Replies still land in
  chat as before.
- `client.gd`: `interact` action on E in `_setup_input` (so key rebinding picks it up later),
  `_update_gather` each logged-in frame (ignored while typing or in Settings), `_on_system`
  hands lines to the prompt, hidden on disconnect, help line mentions E.
- Tests: 7 unit tests in `tests/unit/test_client_gather_prompt.gd` (reach, agreement with
  `Gathering.pick_target` on 180 positions, seeps at night, press interval, parsing every
  `Gathering.success` line incl. "spent", toast fade, the widget sending twice in 3 s of held E).
  Bot behaviour `client_gather_prompt.gd` runs the real widget on every bot, holding E whenever
  the bot stands still. Bot run (8 bots, 180 s, websocket, Postgres): 8/8 ok, 2 to 5 presses and
  2 to 4 toasts per bot, ~800 to 2200 prompt frames each, verify 8/8. Smoke passed.

**Decisions:**
- Send `/gather <kind>` of the prompted node, not bare `/gather`, so what you get is what the
  prompt said (nodes are 6 m apart and reach is 3 m, so the kind picks that exact node; the unit
  test checks it).
- Hold-to-repeat: holding E while standing at a node is the natural way to empty it, and the
  interval keeps it under the server cooldown so you don't get "Easy; you're still gathering."
- Parse the server's English success line for the toast. Brittle on purpose for now: the regex
  is unit tested against `Gathering.success` itself, so if gameplay rewords it the test goes red.
  Protocol v3 should replace this with structured data.

**Known gaps / notes to next run:**
- The client can't tell a spent node (no `s2c_nodes` before v3), so the prompt shows on it and
  the server's refusal explains in chat.
- The smoke test spawns in the cleared meadow centre, so no screenshot shows the prompt; layout
  is checked by unit tests only. If a playtester reports overlap with the chat, move it up.
- Good next picks: key rebinding (now includes `interact`), chat history on Up arrow.

**Update (same day, merge of main):** the director's gathering plan (#38) landed while this PR
was open: new top backlog item plus "How gathering feels" in the design bible. Resolved the
backlog conflict by keeping #38's order and marking the old gather item as this stopgap. Aligned
the stopgap with the bible: prompt reads "[E] Chop Ember Ash" / "Mine Stone Outcrop" / "Collect
Ember Sap", toasts read "+2 Ash wood (6)", and the changelog no longer mentions `/gather` (the
bible keeps it as a hidden debug command). Dropped my three follow-ups (v3 rewire, chop sound,
node highlight) because the new top item covers all of them. Re-ran after the merge: 154 unit
tests passed, bot test 8/8 with verify 8/8, smoke passed.

## 2026-11-22 (late): Over-the-shoulder action camera (ws/client/action-camera)

**Why this item:** the top item (gathering on protocol v3) is still blocked: v3 is not on main
(`PROTOCOL_VERSION` is 2) and building against a stub of messages gameplay hasn't written yet
risks a rewrite. The crafting window request is real, but the director placed the camera (owner
direction 2) above it and the roadmap orders "camera, then chat-to-UI, then crafting". So:
the camera, next unblocked owner direction.

**Built:**
- `game/client/action_camera.gd` (`ActionCamera`): pivot 1.65 m up, 0.6 m over the shoulder,
  3.5 m arm (wheel 1.5 to 6 m), pitch -1.25..0.85. Pure static maths for forward/right/look_dir,
  shoulder point, camera point, camera-relative `move_vector`, `facing_yaw`, `clear_arm`
  (samples the arm every 0.1 m against `Terrain.height` and rough columns for each resource
  node prop, `PROP_COLUMNS`), `ease_arm`, `follow`, `aimed_node`, `wants_capture`. `step()` is
  the one stateful bit: eased pivot (rate 16, frame-rate independent), shoulder swap slides over,
  arm snaps in instantly when blocked and eases out at rate 4, free-look keeps `heading` and the
  camera swings back on release.
- Facing: the server already takes the client's yaw in `c2s_input` (`s.yaw = yaw`), so while
  moving the client now sends `facing_yaw(camera heading)` instead of the move direction. That's
  real server-side facing for everyone, no gameplay change needed (backlog said "needs gameplay's
  facing-yaw input"; it turned out to already be there). Strafing and backing up keep facing
  forward.
- `client.gd`: cursor captured while playing, freed while typing, in Settings, or when the
  window loses focus (`get_window().has_focus()`); Esc still opens Settings, which frees it.
  New actions `free_look` (Alt) and `swap_shoulder` (V, saved to settings). Own name tag is
  hidden (it hung right in front of the camera in the first smoke shot). Help line shortened so
  it no longer runs into the top-left HUD at 1280 px.
- `game/client/reticle.gd`: thin ring and dot, turns ember orange when E would gather something.
- Look-to-interact: `GatherPrompt.target/update` take the camera eye and look direction;
  `GatherPrompt.pick` prefers the node within 28° of the reticle ray, else the nearest. Because
  the server's `/gather <kind>` takes the nearest node of a kind, an aimed node only wins if no
  closer node of the same kind is in reach (so the prompt never names a node the server won't
  take). Today nodes are 6 m apart with 3 m reach, so this almost never changes the pick; it is
  ready for v3's gather-by-id.
- Settings: field of view (55 to 100, default 70) and camera shoulder (right/left).
- World's gather-feedback PR landed on main while this was in progress, so after merging main
  the client now calls `NodeProps.set_highlight` for the prompt's target every frame (off while
  typing, on disconnect). It follows the reticle, so the node that glows is the one E takes.
  `play_hit` still waits for v3's `s2c_gather_result`.
- Tests: 12 unit tests in `tests/unit/test_client_action_camera.gd`. Bot behaviour
  `client_action_camera.gd` runs the camera behind every bot on real positions with a sweeping
  "mouse", checking never under ground, never inside a node prop, arm in limits, W along the
  look, aimed targets in reach.

**Didn't work first time:** `clear_arm` only kept vertical clearance, so against a cliff face the
camera sat exactly on the face (unit test caught it: arm 2.0 with a wall at x=2). Now it also
probes CLEARANCE further along the arm.

**Second thing that didn't work:** the first bot run failed with ~200 "camera inside ash/pine
node" frames out of ~200k: a bot gathering within 1.5 m of a tree and the "mouse" nodding down
lifts the camera into the crown even at the shortest arm. Pulling in can't fix that (only fading
the occluder could), so the behaviour now counts it as `unavoidable_inside_frames` (0 to 124 per
bot) and fails only when a shorter arm would have avoided the prop. From inside a crown you see
out through it (back faces are culled), so it reads as "leaves around the camera".

**Results (after merging main):** 191 unit tests passed (12 new). Bot test (8 bots, 180 s, websocket, Postgres):
8/8 ok, verify 8/8, ~25k camera frames per bot, ~36% of frames pulled in (mostly looking up
against the ground), min arm 0.35 to 1.1 m, look-to-interact target on 1.2k to 3k frames per
bot, all in reach. Client smoke passed; world shot shows the character left of centre with the
reticle (copied to the project's week-00 folder).

**Known gaps / notes to next run:**
- Flora that isn't a resource node (birches, boulders, the Props forest) doesn't pull the camera
  in yet; follow-up logged. Camera may clip a birch crown.
- Follow-up idea: fade a node's crown when the camera is inside it (needs a per-instance alpha
  from world's NodeProps, ask world).
- Prop columns are hand-measured from `node_props.gd` meshes; if world resizes props, update
  `PROP_COLUMNS`.
- Mouse capture under xvfb: the window never has focus, so the smoke shot runs with a visible
  cursor; the capture rule itself is unit tested.
- Next: the top gathering item as soon as v3 lands, else the pack window (chat-to-UI).

## 2026-11-23: keep PR #47 (action camera) current

PR #47 was green but one commit behind `main` (the integrator's changelog fold, docs only).
Per "finish before starting" I merged `main` into the branch and stopped, no new feature this
run. The merge touched no code (CHANGELOG.md, week-00 devlog, workstreams.md, deleted two other
streams' fragments), so I left the full unit/bot/smoke run to CI on the pushed head rather than
spending a local 3-minute bot run on an unchanged game. No review comments to address.

## 2026-11-23 (later): camera uses world's exact prop shapes (ws/client/camera-solid-props)

**Why this item:** the top item (gathering on protocol v3) is still blocked: `PROTOCOL_VERSION`
is 2 and there is no `s2c_gather_*` or `s2c_inventory` on main, so the pack window has no data
either. Requests from other streams come first, and world's close-up read request is a real bug
players can see (the camera ending up inside an ash crown or the lowest pine tier), so: that.

**Built:** `ActionCamera.inside_prop` now just calls `NodeProps.inside_solid(p, node, margin)`;
`PROP_COLUMNS` is gone. World's columns are bigger and scale per node (ash crown 1.92 m vs our
1.6 m, pine tiers from 1.15 m, stone 1.56 m tall, sap seeps now solid too), so the camera pulls
in a little more often near nodes. One unit test changed: "a flat seep doesn't block" is no
longer true (a seep is 1.3 m tall at the shoulder line), so the seep now sits in a dip below the
arm. New test `test_prop_shapes_come_from_world` checks the wide ash crown, node scale, seeps,
and that `inside_prop` agrees with `NodeProps.inside_solid` for every kind.

**Results:** 221 unit tests passed (with Postgres). Client smoke passed. First bot run: camera
behaviour fine (0 avoidable inside frames), but one bot failed `gameplay_chat_commands` "no reply
to /time after 4 tries". That is a chat-cooldown race between behaviours, unrelated to this change
(server log: the bot's `/time` never got through the shared 0.5 s cooldown on its first login);
logged as a request in qa's backlog. Second bot run (same commit): PASSED in 185 s, 8/8 verify, 0 camera failures, 495 to 1951 unavoidable inside frames per bot (bots standing under crowns, up from 323 to 1649 because the shapes are now the real, bigger ones).

**World's `camera_inside_mesh_with_client_columns` stat** is not 0 after the switch (3 to 109 per
bot). I checked why: it counts every look where the client arm ends inside a prop, including
looks where even `ARM_MIN` is inside, i.e. the bot is standing inside the prop's footprint (no
server collision with nodes, and stone's base is up to 2.3 m round inside a 3 m gather reach).
World's own check skips those (`arm > Cam.ARM_MIN`). With identical columns the only remaining
hits are those unavoidable ones (clear_arm only returns a length whose sample it checked with CLEARANCE, so an arm above `ARM_MIN` can never end inside a prop). Asked world to skip `ARM_MIN` looks in that stat so it reads 0.

**Notes to next run:** the gathering item as soon as v3 lands. Otherwise the crafting window
read-only (gameplay's request) or the F1 controls overlay (chat-to-UI, needs no server data).
A camera crown fade (world's per-instance alpha) is the real fix for standing under a tree.

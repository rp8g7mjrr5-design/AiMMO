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

## 2026-11-23 (night): the workbench window (ws/client/workbench-window)

**Why this item:** the top item (gathering on protocol v3) is still blocked: main is on
protocol v2, with no `s2c_gather_*`, `s2c_inventory` or `c2s_craft` RPC on `Net`. Requests from
other streams come first, and gameplay's crafting-window request is the only one left open.
It also does owner direction 1 (chat is for talking) for crafting.

**Fun, in one sentence:** you walk up to the bench, press E, and see at a glance how close you
are to your first axe ("Ash wood 2/3"), then craft it with a click, a knock-knock-chime and a
"Crafted: Stone axe!" pop-up, instead of knowing that a hidden `/craft axe` command exists.

**Built:** `game/client/craft_window.gd` (`CraftWindow`): "[E] Use Workbench" in the gather
prompt line when you are within `Crafting.BENCH_RANGE` and no node is in reach (the node prompt
wins). E opens a centred window: every recipe in `Crafting.RECIPE_ORDER`, each part as
have/need in green or red, a hint line (Ready / Need 1 ash wood / In your pack / craft
anywhere), and a Craft button enabled only when `Crafting.check` on the client's view is "".
E, Esc or Close shuts it; walking a metre past the range closes it too. Movement and the
camera are frozen while it is open and the cursor is freed (`window_open()` in client.gd).
New procedural `Sfx.craft()` (two wooden knocks and a rising pair), toast via
`GatherPrompt.show_toast`.

**Decision: make it work now, not read-only.** Gameplay asked for a read-only window until
`c2s_craft` exists, but the server already runs the real craft code for the hidden `/craft`
command, and the gather prompt set the precedent of sending a hidden chat command until v3.
So Craft sends `/craft <recipe_id>` and opening sends `/bag`; the replies are shown in the
window and kept out of the chat box (the window "consumes" only lines it was waiting for).
The window queues its lines and never sends faster than `CHAT_COOLDOWN` + 0.1 s; a line the
cooldown drops silently times out after 1.5 s (bag: asked again; craft: "The bench didn't
answer").

**The pack mirror:** with no `s2c_inventory` in v2, the client keeps a mirror only to light
the buttons: seeded from the login character's `inventory`, then updated from "Your pack: ..."
lines, gather successes ("(6 in your pack)") and our own craft successes. The server still
decides; a "You need ..." reply means the mirror was stale and triggers a fresh `/bag`.

**Tests:** 6 unit tests in `tests/unit/test_client_craft_window.gd` (pack text round trip for
every item, mirror equals the server after gather and craft lines, every row's reason equals
`Crafting.check` across packs and positions, refusals vs successes, one line per cooldown with
timeout retry, walk-away close). Bot behaviour `client_craft_window.gd` is passive (sends no
chat, since chat cooldown races already hurt the gameplay behaviours): it seeds the window from
login, feeds it every system line, and fails if the mirror ever disagrees with a real
"Your pack" answer (from gameplay_inventory's /bag) or if the axe row disagrees with the
server's "You need ..." refusal (from gameplay_crafting).

**Didn't work first time:** the Craft buttons stayed enabled for a moment after a press,
because the craft line sits in the send queue before it becomes the awaited line; `refresh`
now checks the queue too (`_crafting()`). The first screenshot showed the panel spilling off
the bottom (it grows down from a centre anchor), so it now grows both ways with a solid dark
panel.

**Notes to next run:** when gameplay's v3/v4 lands, replace the `/bag` and `/craft` lines with
`c2s_craft` and feed `s2c_inventory` to `seed_pack` (follow-up in the backlog). Then the top
gathering item. The F1 controls overlay is still the best no-dependency item after that.

## 2026-11-23 (early morning): item icons on toasts and the workbench (ws/client/item-icons)

**Why this item:** the top item (gathering on protocol v3) is still blocked: main is still on
protocol v2 (`GameConfig.PROTOCOL_VERSION := 2`, no `s2c_gather_*` RPCs). Requests from other
streams come first, and world's item-icons request was the only one still open.

**Fun, in one sentence:** every gather now pops a little picture of the log, stone or glowing
sap drop you just got next to "+2 Ash wood (6)", and every craft pops the tool you made, so the
reward reads at a glance instead of as a line of text; the workbench shows each recipe's
picture and an icon by every part.

**Built:** `game/client/icon_shelf.gd` (`IconShelf`). World's `ItemIcons.image` is slow (I
measured 12 ms at 24 px, 20 ms at 32 px, 74 ms at 64 px per icon here), so the client draws
every item at the two sizes it uses (32 px for toasts and recipe rows, 18 px for parts) on a
low-priority `Thread` that starts in `client.start()`, i.e. while you're on the login screen.
Drawing an `Image` touches no shared state; only `ImageTexture.create_from_image` runs on the
main thread, lazily, in `texture()`. If an icon isn't drawn yet `texture()` falls back to
`ItemIcons.texture` (draws it now), so it never returns null and the worst case is the old cost.
`client._exit_tree` joins the thread. I used my own cache rather than writing into world's
`ItemIcons._cache`, which is world's file and not thread-safe.
`GatherPrompt.show_toast(text, item)` puts a 32 px icon left of the text and centres the pair
(`icon_x`); gather toasts take the item from `parse_gain`, craft toasts from the recipe id.
`CraftWindow` rows get a product icon, and the parts line is built with `RichTextLabel.add_image`
instead of bbcode (`parts_bbcode` stays for tests and the bot); parts now carry `item`.
New test hook `--show-toast=<item>` shows a gather toast just before `--screenshot`.

**Didn't work first time:** the campfire's three parts wrapped onto a second line once each
had an icon; the window is 600 px wide now (was 520).

**Tests:** 7 unit tests in `tests/unit/test_client_item_icons.gd` (every item at every size,
same pixels as world's `ItemIcons.image`, threaded draw completes and joins, never null incl.
unknown items and an early stop, every resource kind's real gather line gets its item's icon,
icon/text centring, workbench rows). Bot behaviour `client_item_icons.gd` is passive: it starts
the shelf like the client and checks every real gather success gets its own icon (not the
bundle). Bot run: 4 to 9 iconed toasts per bot, shelf ready in 0.6 to 1.1 s with 8 bots and a
server sharing the CPU. Smoke passed.

**Notes to next run:** still the v3 gathering item first. When the inventory window is built,
use `IconShelf` and add its slot size to `SIZES`. The F1 controls overlay remains the best
no-dependency item.

## 2026-11-23: self-updating client (owner request)

**Why:** the owner had to download a new zip from the Releases page every time the client
changed. Now they install once and every launch plays the newest build.

**How:** the exported binary stays fixed; only the game pack changes. CI now also exports
`AiMMO-<os>.pck` per platform (about 260 KB, since all art is procedural) and `update.json`
(`build` = the CI run number, `engine` = `GODOT_VERSION`, per-file size and SHA-256), uploaded
last so a half-uploaded release is never offered. It bakes `client/build_id.txt` and
`client/update_url.txt` (`https://github.com/<repo>/releases/latest/download`) into the client.
At startup `main.gd` shows `Updater` (only in exported builds with a build number, never in
tests, bots, the editor or the server). It fetches `update.json` (6 s timeout), and if the build is
newer it downloads the pack to `user://updates/`, checks the SHA-256 and restarts the same
executable with `--main-pack <pack> -- --updated`. Godot then boots that pack as the whole game,
including the global class cache and autoloads.

**Tried first and dropped:** loading the new pack in-process with `ProjectSettings.load_resource_pack`.
New `class_name` scripts are not registered after startup in Godot 4, and we add classes almost
every PR, so the in-process route would break on the first new class. Replacing the exe itself
was also out (Windows locks a running exe; macOS app bundles need permission bits).

**Safety:** never downgrades (build numbers only go up). A pack that fails to reach the game
8 s after launch three times is skipped and not downloaded again until a newer build exists.
Offline, it boots the newest pack already downloaded. If `update.json` names a different engine
version, the player gets a "new installer, just this once" screen with a button to the
download page and can keep playing what they have. When the server refuses a login as "out of
date", an installed client restarts itself to update.

**Tested:** 10 unit tests in `tests/unit/test_client_updater.gd` (manifest parsing incl. path
tricks, every decide() branch, relaunch args). End to end by hand with a real Linux export:
build 1 binary + a local server offering build 2: it downloaded, restarted into build 2 (login
screen rendered), marked it good; second launch relaunched without downloading; offline launch
still booted build 2; a 30 MB slow download showed the progress screen. Packs export for all
three platforms with no errors. Windows and macOS were not run (no machines here); they use
the same `--main-pack` engine flag.

**Notes:** `OS.get_cmdline_args()` is empty in exported builds, so engine flags (like
`--rendering-driver`) are not carried over on the restart; players don't pass any. Bumping
`GODOT_VERSION` means everyone needs one new download (the engine is in the exe), so do it rarely.

## 2026-11-23 (morning): camera keeps out of decoration, bench glows, craft-window flake (ws/client/camera-clears-decoration)

**Why this item:** the top item (gathering on protocol v3) is still blocked: main is on
protocol v2. Three requests from other streams were open, all small and all from world (plus
one flake), so they come first. I shipped them as one PR: one feature (camera clearance for
decoration) plus the bench highlight wiring (one line) and a bug fix (the flake).

**Fun, in one sentence:** walking through the forest or past the lanterns and workbench, the
camera now slides in front of trunks and boulders instead of putting you inside a wall of bark,
and the bench lights up warm the moment you can use it, the same "this is ready" cue as a node
in reach.

**Built:**
- `ActionCamera.camera_solids(pos, radius = DIST_MAX + 3)`: `ResourceNodes.near + WorldSolids.near`,
  exactly as world asked. `client.gd` passes it to `cam.step`. Gathering and look-to-interact
  still use `ResourceNodes.near` only. `clear_arm` needed no change: `NodeProps.inside_solid`
  already dispatches on `columns`.
- `_update_bench` calls `Workbench.set_highlight(world.get_node_or_null("Workbench"), at_bench and free)`
  every frame, so it is lit exactly while the prompt shows (hidden while typing or a window is open).
- **Flake root cause:** not a race. The bot's window mirror never sends "/craft" itself (it
  only listens), while `gameplay_crafting` sends "/craft axe" on the same bot. `apply_line`
  only applied a "You craft ..." line when `crafted` named the recipe the window had sent, so
  another sender's successful craft was ignored and the next "Your pack" line disagreed. A
  unit test even asserted "a craft we didn't ask for changes nothing", which was the wrong
  call: "You craft" lines are only ever about your own pack. New `CraftWindow.crafted_in(text)`
  reads the recipe from the server's own success wording (`Crafting.success`), and
  `apply_line` uses it when nothing was sent. In the real client this also fixes a dev-command
  `/craft` leaving the window stale.

**Tests:** `test_client_action_camera::test_camera_solids_include_decoration` (workbench and
nodes are in the set, an arm backing straight into the widest decorative column pulls in before
it, both via `clear_arm` and a settled `step`), `test_client_craft_window::test_mirror_follows_crafts_it_did_not_send`
(every recipe, the exact flake numbers, axe vs pickaxe). New bot behaviour
`client_camera_solids.gd`: 8 looks a second through the client's own `camera_solids`, fails if
the camera ends inside anything.

**Not tested directly:** the bench highlight call has no unit test of its own (it is one line in
`client.gd` calling world's tested `Workbench.set_highlight`); the smoke run still loads the
client with it and fails on any script error.

**Notes to next run:** still the v3 gathering item first. If v3 is not on main, the F1 controls
overlay (third item, replaces `/help`) is the best no-dependency item.

## 2026-11-23 (evening): F1 controls overlay (ws/client/controls-overlay)

**Why this item:** the top item (gathering on protocol v3) is still blocked: `main` is on
protocol v2 (`GameConfig.PROTOCOL_VERSION == 2`). No open requests from other streams. The
last run's note said the F1 overlay is the best no-dependency item, and it is part of owner
direction 1 (chat is for talking), which is in Milestone 0's "done when".

**Fun, in one sentence:** a new player who wonders "how do I gather?" presses F1 (or clicks
"?") and sees every key as a keycap on one card, instead of typing a slash command into chat
or reading a 120-character line in the corner.

**Built:**
- `ControlsOverlay` (`game/client/controls_overlay.gd`): a centre window in the workbench's
  style. Sections Moving / Doing / Talking and menus; each row reads its key from the InputMap on
  every open (`key_text`), so the future rebinding window needs no change here.
- The default keys moved from `client._setup_input` into `ControlsOverlay.DEFAULT_BINDS` (one
  table; `install_input()` adds them). New action `toggle_controls` (F1).
- F1 toggles it (not while the workbench or Settings is open); Esc closes it first; it counts
  as a window, so the cursor is freed and movement stops while it is open. A "?" button sits
  top right beside the corner hint, which is now just "F1 controls · Esc settings". The chat
  placeholder says "F1 for controls" instead of "/help for commands".
- Test hook `--open-controls` opens it after login (for a future smoke shot).

**Tests:** 6 unit tests in `tests/unit/test_client_controls_overlay.gd` (every listed action
bound, key names, rows cover every key, a rebind shows the new key, hint has no /help, window
toggles). Bot behaviour `client_controls_overlay.gd`: each bot builds the real window, checks
every row has a key, and opens/closes it every 7 s while playing.

**Not done:** no smoke screenshot of the overlay (the smoke script is qa's; follow-up in the
backlog). The server's `/help` command still works for anyone who types it; that is gameplay's
to retire when every command has UI. `CHANGELOG.md` still mentions /help in old entries
(integrator only).

**Notes to next run:** still v3 gathering first. If v3 is still not on main, the time dial
hover tooltip (replaces `/time`) or the centre-screen system messages are the next
no-dependency slices of the third item.

## 2026-11-23 (night): timed gathering on protocol v3 (ws/client/timed-gathering)

**Why this item:** protocol v3 is on `main` now (`GameConfig.PROTOCOL_VERSION == 3`), so the
top item, blocked for three runs, is unblocked. It is the owner's top request.

**Fun, in one sentence:** pressing E at a tree now feels like chopping it: a bar fills over
exactly the server's time with "Chopping Ember Ash", the haul lands with a chop/clink/slosh
and a chime, holding E keeps you swinging with no dead time, and a spent tree visibly empties
after its last shake instead of a refusal in chat.

**Built:**
- `GatherPrompt` rewritten around the v3 channel: `decide()` (pure) turns E held/pressed,
  moving, the target and the channel state into start/cancel. Holding E chains gathers;
  pressing E again or moving cancels (locally at once, then `c2s_gather_cancel`); after a
  refusal or cancel, holding does nothing until E is let go (no hammering the server). An
  unanswered start is re-asked after `ASK_TIMEOUT` (1.5 s). The bar fills from
  `s2c_gather_begin`'s `seconds`. Toast from `s2c_gather_result` with the count from
  `s2c_inventory` (which the server sends first). `notice_text(reason)` gives short centre
  words for "full", "depleted", "day", "far", "unknown"; the server's longer line stays in chat.
- `target()` takes the set of spent nodes and skips them, so the prompt moves on to the next
  live node in reach; with only spent nodes in reach it shows "Pine is spent for now", greyed.
  `pick()` no longer avoids an aimed node whose kind has a nearer twin: v3 gathers by id.
- `GatherWatch` (`game/client/gather_watch.gd`): tracks everyone's running gathers and turns
  events into `play_hit` / `set_depleted` ops. The server sends `s2c_node_state` *before* the
  "done" end that emptied the node, so a depletion on a node someone is gathering waits for
  that end (max 0.6 s), giving world's "hit first, then depleted" order.
- `Sfx.haul(kind)`: wood thunk + bite, stone clink, sap slosh, each followed by a two-note
  pickup chime, ~0.46 s. One player per kind in the client.
- Chat: the server's echo lines for your own gather ("You start gathering", "You gather",
  "You stop gathering") are kept out of chat (`GatherPrompt.is_echo`). Gameplay can keep
  sending them; nothing else reads them except the workbench mirror, which still sees them.
- The workbench window now seeds from every `s2c_inventory` too.

**Tests:** unit: `test_decide`, `test_widget_runs_a_timed_gather` (start, no double start,
bar at half time, toast, chained next gather, cancel, no restart while held, refusal notice),
`test_unanswered_start_is_asked_again`, `test_spent_nodes_are_skipped`,
`test_watch_hits_before_depletion`, `test_haul_sounds`, plus the old target tests. Bot:
`client_gather_prompt.gd` rewritten to be passive: it feeds the real widget and watch every v3
event of the gathers `gameplay_gather_v3` makes on the same bot, applies ops to a real
NodeProps world, and checks bar, toasts, notices, spent nodes. It can't press E itself:
`gameplay_gather_v3` fails on any begin it didn't ask for. `client_item_icons.gd` now toasts
from `s2c_gather_result`.

**Not done / known:** no avatar gather swing yet (follow-up). The one `rpc_id` line that sends
the start in `client.gd` is covered only by the smoke run loading the client; the bot's
gathers prove the server side of the same calls. Other players' "done" ends shake the node
but make no sound.

**Notes to next run:** the avatar swing is the natural next slice (it finishes the top item).
Then XP (`s2c_xp`) once gameplay's v4 lands.

## 2026-11-23 (morning): the gather swing (ws/client/gather-swing)

**Why this item:** the top backlog items are done or in review except the XP items, which
need gameplay's protocol v4 (PR #89, still open; the procedure says never build on an
unmerged PR). The avatar gather swing is the last missing piece of the owner's top request
("gathering that feels like an MMO") and needs nobody else. qa's request (Medium shadows by
default) is a one-line fix, so it rides along as a bug fix.

**Fun, in one sentence:** when you press E at a tree your wanderer now turns to it and chops,
blow after blow, instead of standing still beside a filling bar; and you can see across the
meadow who is mining, chopping or collecting sap.

**Built:**
- `GatherSwing` (`game/client/gather_swing.gd`): per avatar, driven from
  `GatherWatch.running` (so it covers you and every other player in view). Three stroke
  styles: chop (ash, pine; 0.8 s, slow wind-up over the head, accelerating bite down), mine
  (stone; 1.0 s, higher and heavier, deeper lean into the blow), collect (sap; 1.4 s, hands
  low and forward, dipping). Blends in at 10/s and out at 7/s over the walk pose, both arms
  together. Only the rendered `Body` turns to face the node (root yaw stays the server's).
- `client.gd`: one block in the avatar loop after `WalkAnim.apply`.
- Settings: `shadow_quality` defaults to 1 (60 m) for new installs, per qa's request and the
  art bible's Medium default. Saved values are kept (`from_config` reads the saved key first;
  unit test `test_saved_high_shadows_are_kept`).

**Tests:** unit `tests/unit/test_client_gather_swing.gd` (facing maths, styles for every node
kind, stroke shape, blend in/out with no snap, turn relative to root yaw, no spin on top of
the node, the real rig's arms and body). Bot `client_gather_swing.gd`: every bot poses a real
rig for every avatar it sees from snapshots and v3 gather events, checks facing during
settled gathers, arm range per gather, blend-out within 1.5 s, and no NaN poses.

**What didn't work:** qa expected the 60 m default to cut the spawn frame's primitives. It
didn't: the smoke run (fresh settings, so 60 m) measured 1,998,157 noon / 1,999,513 night,
the same as the 120 m baseline plus world's ember veins. The forest is a handful of
world-spanning MultiMeshes, so the shadow pass can't cull them by distance and draws every
instance either way. The fix is world chunking its MultiMeshes (or casting no shadow from
flora), not a client setting. Told qa in its backlog. The default stays at 60 m anyway: it is
the art bible's Medium and gives sharper shadows near you.

**Not done:** no tool in the hands; no sound on other players' blows; your own last blow
isn't timed to the bar's end (follow-ups). The render ceiling in qa's `render_baseline.json`
is qa's file and needs no change (nothing dropped).

**Notes to next run:** XP floaters (`s2c_xp`) as soon as protocol v4 (PR #89) is on main.
If it isn't, the Graphics quality setting (Low/Medium/High plus F3 overlay) is the next
no-dependency item; it can reuse the shadow default changed here.

## 2026-11-23 (afternoon): Graphics quality and the F3 overlay (ws/client/graphics-quality)

**Why this item:** the XP items still need gameplay's protocol v4 (PR #89, open), and the
procedure says never build on an unmerged PR. My last note said the Graphics quality setting
was the next no-dependency item, and it is a director item for owner direction 7.

**Fun, in one sentence:** a player on an older laptop picks Low and gets smooth movement
instead of a stuttering camera, and the owner can press F3 to see exactly what a scene costs.

**Built:**
- `Quality` (`game/client/quality.gd`): one static `level` (Low, Medium default, High) and a
  preset table: shadow distance (60/60/120 m via the existing `shadow_quality` index), view
  distance (400/600/600 m; 600 m is where the 0.006 haze is about 97% solid, so it is "the end
  of the haze"), sun shadow map (2048 on Low), soft-shadow filter (hard/low/medium), and
  `flora_density()` / `motes_scale()` for world to read.
- Settings: a Graphics row; picking a level writes its shadows and distance into the two rows
  below, which still fine-tune. Saved as `graphics_quality`; files without it read as Medium
  and keep their own values (loading never re-applies a preset). Shadow labels renamed from
  Off/Low/High to Off/60 m/120 m, because "Graphics: Medium, Shadows: Low" read as a contradiction
  (indices unchanged, so saved files are fine).
- `PerfOverlay` (`game/client/perf_overlay.gd`) on F3, bottom-right (the only free corner, also
  on the login screen): fps and average frame ms over each quarter second, draw calls,
  triangles, and the level. Works anywhere, never takes the cursor. In the F1 list. Test hook
  `--show-perf`.

**Render defaults:** checked the art bible's list. Nothing in the project enables SDFGI,
VoxelGI, SSR, SSIL or SSAO, there is one sun, and the far plane already ends at the haze, so
`project.godot` needed no change. I found no `glow_enabled` anywhere; the "one glow pass" may
not be on at all. That's world's environment; noted here, not touched.

**Tests:** unit `tests/unit/test_client_quality.gd` (presets, apply, saved and old files,
garbage, overlay text and refresh, F3 listed). Bot `client_graphics_quality.gd`: every bot
cycles levels with save/reload to its own file and runs the real overlay on its frames
(about 19 picks and 690 redraws per bot). Unit 365 passed, bot test passed (8 bots, 180 s),
client smoke passed (render numbers unchanged: Medium is today's defaults).

**Not done:** flora density and motes don't change yet (world's code; requested in its
backlog). A level change mid-game moves shadows and distance at once, flora only after world
wires it. No Low smoke screenshot yet (follow-up).

**Notes to next run:** XP floaters (`s2c_xp`) the moment PR #89 is on main. If not, the
time-dial tooltip (replaces `/time`) or the Players panel are small no-dependency items.

## 2026-11-23: XP you can see (ws/client/xp-floaters)

**Why this item:** protocol v4 (PR #89) is on `main`, so Milestone 1 part 1 is unblocked and
is the top open item that isn't waiting on another window. The slash-command item ahead of it
needs the pack window, which is bigger than a run.

**Fun, in one sentence:** every chop now pays twice in the same instant, the wood and a gold
"+10 Felling" with a bar that visibly moves, so a player always sees how close the next level is.

**Built:** `XpMeter` (`game/client/xp_meter.gd`), centred just under the gather prompt.
`skills_changed` seeds a running total per skill; each `xp_gained` pops "+N Skill" (rises 22 px,
fades over 1.6 s) and shows "Felling 2 · 215 XP to 3" with a thin gold bar that slides from the
old progress to the new over 0.55 s (ease out), holds 3 s and fades over 0.8 s. A gain that
crosses a level runs the bar to full and wraps into the new level. Hidden and cleared on
disconnect. Test hook `--show-xp` (with `--show-toast`) for screenshots.

**What didn't work:** the first bot run failed every check that the bar landed on the server's
progress (0.350 vs 0.347): Godot's ProgressBar defaults to `step = 0.01` and snaps the value.
`bar.step = 0.0` fixed it, and it also makes the slide smooth instead of stepped.

**Tests:** unit `tests/unit/test_client_xp_meter.gd` (texts, motion within and across a level,
slide easing and landing, fades, node lifecycle). Bot `client_xp_meter.gd` runs the real meter on
the server's messages: label texts, running total equals the server's, bar lands on
`Skills.progress(total)`, then fades (7 to 12 gains per bot). Unit 382 passed, bot test passed
(8 bots, 180 s), client smoke passed (render numbers unchanged).

**Not done:** no XP sound of its own (the haul sound carries the moment); the level-up chat
line still goes out (part 2's banner replaces it). Mid-slide second gains restart from the
remembered progress, not the bar's current position; at ~1 gain per 1.6 s that never shows.

**Notes to next run:** part 2, the level-up moment: `level_up` -> rising chord in `sfx.gd`,
banner with the unlock, `LevelUpFx.play(avatar)`; `level_up_seen` -> the burst on that avatar.
Then tell gameplay (its backlog) the banner shows so it can drop the chat line for v4 clients.

## 2026-11-23: the workbench on c2s_craft (ws/client/workbench-c2s-craft)

**Why this item:** top of the backlog, and the last thing holding gameplay's chat gate
(owner direction 1, Milestone 0 "no chat command anywhere"). No dependency: `c2s_craft`,
`craft_result` and `s2c_inventory` have been on `main` since protocol v3.

**Fun, in one sentence:** the window opens already knowing your pack and answers a Craft
press in one round trip (toast with the icon, craft sound, "+N Toolcraft"), instead of
waiting out the 0.5 s chat cooldown for "/bag" and then "/craft", so crafting feels like a
button, not a command.

**Built:** `CraftWindow` lost every chat path: `parse_pack`, `apply_line`, `crafted_in`,
`item_for_label`, `craft_reply`, the send queue and `on_system` are gone (about 150 lines).
`craft(id)` now emits `craft_requested(id)` (one request in flight; refuses with the pack
unknown or an unknown id) and `client.gd` sends it as `net.play.c2s_craft`. `on_craft_result`
shows the server's text (accent on success, red on a refusal) and returns the recipe for the
toast. The pack comes from `seed_pack` on login and every `inventory_changed` (already wired).
`tick()` no longer returns a line; it closes on walking away and gives up on an answer after
`REPLY_TIMEOUT` (3 s) with "The bench didn't answer. Try again." `client._on_system` no longer
routes lines through the window. Also fixed gameplay's request: the `client_xp_meter` bot
resets `_pending`/`_age` on login.

**Tests:** unit `test_client_craft_window.gd` rewritten (one request per press, answer
handling, refusals in the window, timeout, late answers for another recipe, walk-away, and a
check that the script contains no "/bag", "/craft", c2s_chat or on_system). Bot
`client_craft_window.gd` now presses Craft through the real window up to 4 times per login at
quiet moments (no gather running or just ended, 6 s clear of a disconnect, torches or a
campfire only so gameplay_crafting's "/craft axe" answers stay as it expects), and checks each
answer: right recipe, the row predicted it, a "missing" refusal in the server's exact words,
the window shows the text, and Toolcraft XP for every success. Unit 396 passed (with
Postgres), bot test passed (8 bots, 180 s; 8 presses and 8 answers per bot), client smoke
passed. Screenshot by hand with `--open-workbench`: rows counted at once, nothing in chat.

**What didn't work / not done:** every bot press was a refusal (bots don't hold pine wood
and ember sap together), so the success path is proven by unit tests only; follow-up added.
`gather_prompt.on_system` still parses gather echo lines from the `/gather` dev path; that is
for bots and goes away with gameplay's gate.

**Notes to next run:** part 2, the level-up moment (`level_up` -> chord, banner,
`LevelUpFx.play`; `level_up_seen` -> burst on that avatar). Then the skills window (K).

## 2026-11-23: the skills window and the next goal (ws/client/skills-window)

**Why this item:** Milestone 1 part 3 is the top backlog item not already in a PR (part 2,
the level-up moment, is #102). It needs nothing from #102: it reads `Skills` and world's
`SkillIcons`, both on `main`.

**Fun, in one sentence:** you can always see where your next payoff is and how close it is
("Next: Felling 5 unlocks Old ember ash (1,680 XP)"), so every gather is a step toward
something you can name, and K shows the whole road at a glance.

**Built:** `SkillsWindow` (`game/client/skills_window.gd`): Ember-bordered window like the F1
list; title, gold "Total level N · X XP", then one row per skill: world's badge (40 px),
"Felling 3", "1,240 XP to level 4", a gold bar, and the next named unlock ("Level 5: Old ember
ash, ...", "(coming soon)" for unlocks not built yet). K (new `toggle_skills` in
`ControlsOverlay.DEFAULT_BINDS`, listed in F1) or the "Skills" button opens it; K, Esc or Close
shut it; it frees the cursor via `window_open()`. It doesn't open over the workbench, F1 or
Settings. Goal line: a 14 px label under the compass (y 76 to 96, clear of #102's banner at
96) with `SkillsWindow.goal_text`, the named unlock with the least XP left across all skills.
**Decision:** `soon` unlocks are skipped as goals (Toolcraft 3 would be the cheapest goal for
many players, but sending them toward something that isn't in the game is a broken promise);
ties go to the skill listed first. When a gain moves the goal on, the line flashes gold for
1.2 s (`goal_colour`). Test hook `--open-skills`.

**Tests:** unit `test_client_skills_window.gd` (totals, grouping, row texts, closest goal,
soon skipped, goal moves on and runs out at the cap, flash colour, K bound and listed, the
window's rows follow on_skills/on_gain, reset). Bot `client_skills_window.gd`, network-only:
on every s2c_xp the texts match the shared rules for the server's total, total level is the
sum, and the goal is a built unlock still ahead whose XP left equals the threshold minus the
server total and never rises for the same goal. 8-bot runs saw 12 to 23 gains and goal changes
per bot.

**What went wrong:** the first local bot run failed in qa's pair check (both pair bots
picked tier-2 node 403, which needs level 5, since #104). Not my code; the rerun passed. I
wrote it up in qa's backlog with the one-line fix (skip tier 2 in `GatherLedger.pair_node`).
A first screenshot attempt failed on Vulkan; use `--rendering-driver opengl3` like run.sh.

**Notes to next run:** when #102 lands, hide the goal line while the banner shows (follow-up
added). Then part 4 (level requirements in prompts) can reuse `SkillsWindow.next_goal`'s need.

## 2026-11-23: the level-up moment (ws/client/level-up-moment)

**First, PR #101 (workbench on `c2s_craft`):** it had a merge conflict in the client and
gameplay backlogs (both sides added a request line). Merged `main` in, kept both lines, pushed;
auto-merge is still on. Its code merged cleanly.

**`main` is red, not from us:** `test_qa_art_lint::test_only_palette_hard_codes_colours` fails
on `main` itself (`node_props.gd: 15, allowed 11`), from world's #100 landing beside qa's #95.
That file is world's, so I left a request in world's backlog instead of touching it. Both my
open PRs will show a red Test until it is fixed; auto-merge waits, and the next run merges
`main` in.

**Why this item:** Milestone 1 part 2 is the top backlog item that isn't already in a PR (the
craft window is #101) and needs nothing from another stream: protocol v4's `level_up` and
`level_up_seen`, world's `LevelUpFx` and `SkillIcons` are all on `main`.

**Fun, in one sentence:** reaching a level now *feels* like a payoff, a gold "Felling 5" with
what you unlocked and what's next, a rising chord and a burst of ember light, instead of a
line of grey text in chat.

**Built:** `LevelUpBanner` (`game/client/level_up_banner.gd`), top centre under the compass:
skill badge, "Felling 5", the unlock line (or "Your gathers are a little quicker"), and "Next:
Felling 10, Clean cuts". Pops 0.6 -> ~1.08 -> 1.0 over 0.22 s (ease-out-back), holds, fades;
1.9 s in all; every Control ignores the mouse, so nothing blocks input. `Sfx.level_up()`: C-E-G-C
arpeggio in 0.21 s landing on a held C major chord with a shimmering high G, 1.5 s. Own level-up:
banner + chord + `LevelUpFx.play(own avatar)`. `level_up_seen`: the burst over that player only
(no banner, no sound yet: follow-up). Chat: the banner remembers `Skills.level_up_text(...)` for
the level-up and `_on_system` drops exactly that line once, so no gameplay change was needed to
clean chat; gameplay told it can drop the line later. Test hook `--show-level-up` (with
`--screenshot`) for a smoke shot.

**Decisions:** a second level-up while the banner shows replaces it rather than queueing; it
only happens if one craft levels Toolcraft twice, rare at these XP rates (follow-up added). I
skipped the XP meter "hold at full" follow-up to keep the run small.

**Tests:** unit `tests/unit/test_client_level_up.gd` (texts, pop overshoot, fade inside 2 s,
mouse-ignore on every child, badge set, chat-line swallow once, sound length, no clip, no end
click, rising notes). Bot `client_level_up.gd` is network-only (art bible section 7): level
matches the last XP total, unlocks match the shared table, banner texts, and the server's line
equals `LevelUpBanner.announcement(...)` so it would be kept out of chat.

**Notes to next run:** merge `main` into #101 and this PR once world fixes the palette lint.
Then part 3 (skills window on K + the next-goal line); `LevelUpBanner.next_text` already builds
the "Next: Felling 10, Clean cuts" string the goal line wants.

**Later run, 2026-11-23 (fix-up):** #101 landed, then #102 had conflicts in `client.gd` (both
added handlers next to each other), the client devlog and the client/gameplay/world backlogs.
Merged `main` in and kept both sides. World fixed the palette lint on `main` (#103), so I took
my request out of world's backlog. Gameplay's #104 made the old ember ash live, so the unit test
that expected "(coming soon)" on Felling 5 now checks the live text and tests the tag on a copy
with `soon` set. Unit tests (431), the 8-bot 180 s WebSocket bot test (8 of 8 levelled) and the
client smoke test pass locally.

## 2026-11-23: Budda Games intro replaces the Godot splash (owner request)

Run outside the schedule, on the owner's direct request in a project thread; took the
`client` claim like a worker run.

**Built:** `Intro` (`game/client/intro.gd`), a CanvasLayer with a `VideoStreamPlayer` in a
16:9 `AspectRatioContainer` over the video's background colour (#1d161a). `main.gd` awaits it
in the client branch before the updater. `project.godot` sets
`boot_splash/show_image=false` and `boot_splash/bg_color` to the same colour, so launch goes
background → video with no logo or flash. Any key press (not echo), mouse button or pad button
fades it out in 0.25 s; a 10 s timer guards against a stalled stream. It never plays headless
or with `--no-intro`, `--updated` (relaunch after a self-update already showed it),
`--screenshot`, `--autoconnect`, `--bot`, `--server`; `--intro` forces it for tests.

**Asset:** the owner's mp4 (1920x1080, 60 fps, H.264/AAC, 0.95 MB) converted with ffmpeg to
Theora/Vorbis at 1920x1080, 30 fps, `-q:v 8 -q:a 4`: 1.15 MB, so updates stay small. 720p was
0.7 MB but softened the pixel-art logo. Added `client/intro/*.ogv` to the three client presets'
include filters (the server preset already excludes `client/*`). The owner-approved exception
to the procedural rule is written into the design bible ("Studio intro").

**Tests:** unit `test_client_intro.gd` (plays on a normal launch, every automated flag skips,
`--intro` forces, skip events, the file loads as Theora and stays under 2 MB, client presets
pack it and the server leaves it out, boot splash off with the matching colour). By hand under
xvfb: the real client plays the whole clip and lands on login; a scripted key press ends it in
285 ms. No bot behaviour: bots never boot the client role, and bot behaviours must stay art-free.

**Known:** after the clip, its dark last frame stays up while the client builds the world
(about 5 s on llvmpipe). Follow-up added.

**Follow-up (same run):** after merging `main`, `test_goal_skips_unlocks_not_in_the_world_yet`
failed: it hard-coded Toolcraft as the "coming soon" example, and #110 built Toolcraft 5. The
test now finds a soon unlock from `Skills` data, so it keeps working as unlocks get built.
Then the 45 s ENet bot run failed in `client_craft_window` ("window would say 1 pine wood and
1 ember sap, server said 1 ember sap"), about one run in two locally. Cause: another
behaviour's instant `/gather` landed in the same server tick as the Craft press, and the pack
is only flushed at the end of the tick, so the window judged an older pack. The behaviour now
re-checks a disagreeing prediction against the pack the server judged (rebuilt from the next
`s2c_inventory`) and fails only if that disagrees too; a new `raced` stat counts the excused
ones. 7 ENet runs passed after it.

**Scheduled run, 2026-11-23 ~14:30 UTC (looking after #111):** #111 was red (fun metric
`longest_dead_s_median` 49.9 s vs baseline 35, nothing to do with the intro since bots never
boot the client role) and in conflict with `main`. qa's #114 landed in the meantime: it fixed
the same `client_craft_window` race its own way (a `raced_presses` stat that excuses presses a
pack-changing chat line may have overtaken) and re-baselined dead time to 40 s. Another session had already merged `main` the same way (8341772); I
and took qa's version of `client_craft_window.gd` over this branch's re-check, because two
fixes for one race in one file would fight and qa owns `tests/`; the PR is back to just the
intro. Did not start a second item this run: the intro PR getting green is the useful thing.
Unit (456), 8-bot 180 s WebSocket bot test (PASSED, dead-time median 35.05 s) and client smoke test pass locally after the merge.

## 2026-11-23, scheduled run: level requirements in prompts (ws/client/level-requirements)

**Picked:** the two gameplay requests at the top of "Requests from other streams" (tier-2
node prompts, Toolcraft 5 recipes), which together are backlog item "Milestone 1, part 4:
level requirements in prompts". Requests first per the worker procedure; the pack window (I)
is the item above it but the requests are bugs players hit today: the workbench lit Craft for
an ember axe you can't make, and E on an old ash said nothing centre screen.

**Fun:** a tier-2 node stops being a silent wall and becomes a goal you are standing next to:
"Old Ember Ash · Felling 5 (1,205 XP to go)", greyed, and the moment you hit the level it reads
"[E] Chop Old Ember Ash". The workbench shows the same for the ember tools.

**Built:**
- `GatherPrompt.target` takes your skills (new 6th arg), names nodes with `ResourceNodes.info`
  (so "Old Ember Ash", "Rich Stone Seam" and the bar's "Chopping Old Ember Ash"), and walls a
  node `Gathering.can_work` says no to: `can` false, `needs_level` true, `need_text` with the XP
  to go (`SkillsWindow._grouped` for the comma). `doing_for(node)` replaces `doing_text(kind)`
  inside the prompt; `doing_text` stays for kind-only callers.
- `"level"` in `NOTICES`, and `notice_for(reason, node_id)` words it "Needs Felling 5".
- `CraftWindow.row` takes skills (4th arg, null = unknown, server decides, as before) and a
  `"level"` reason shows "Needs Toolcraft 5 · N XP to go" with the name dimmed and Craft off.
  `on_skills` feeds it; `reset` forgets them.
- `client.gd` `_share_skills()` after every `skills_changed` / `xp_gained`.
- The prompt is 380 px wide now (was 300): "Rich Stone Seam · Quarrying 5 (1,680 XP to go)" was
  355 px at 16 pt. The gather bar stays 150 px (`BAR_WIDTH`). A unit test measures the longest
  need line against `WIDTH` so a longer node name can't overflow silently.

**Tests:** unit tests for the walled prompt, agreement with `Gathering.check` at levels 1/4/5/9
on every tier-2 node, the level notice, the width, and the gated workbench rows (static rows
against `Crafting.check` with skills at Toolcraft 1/4/5/8, and a live window that greys then
lifts). `test_prompt_agrees_with_the_server_rules` now checks `can` equals the server's
verdict both ways, not just "offered implies allowed". New bot behaviour
`client_level_walls.gd`, network-only (no art classes, per qa's lint): it keeps the skills from
the wire and checks every tier-2 prompt and gated row against the shared rules on every change,
and that any "level" refusal of our gathers was for a node the prompt showed as walled.

**Didn't do:** a real Craft press on an ember axe from a bot. `client_craft_window`'s
`_on_craft_result` fails on an answer for a recipe it didn't press while its own press is out,
so a second presser would race it. Left the end-to-end refusal to gameplay's own bot.

**Next run:** the pack window on I is now the top client item.

First 8-bot run failed 16 times in `client_gather_prompt`: gameplay's bots do press E on tier-2
nodes and get "level" refusals, and that behaviour compared the centre notice with
`notice_text(reason)` ("Your level is too low") while the prompt now says "Needs Felling 5".
It now compares with `notice_for(reason, node_id)`. Good news hidden in it: the level refusal
path is exercised on the real server every run, so `client_level_walls`' refusal check runs too.

**Workbench fit (bug, same PR):** a screenshot with `--open-workbench` at 1280x720 showed six
recipes pushing the window's title and Close button off screen (gameplay's ember tools made it
six). The recipe rows now sit in a `ScrollContainer` (`LIST_HEIGHT` 410 px, vertical only) in a
600 px window; a unit test checks the window's minimum height stays under 700 px. Screenshot
after: the title, four rows, a scroll bar and Close all on screen, the ember rows below.
Second 8-bot run PASSED (client_level_walls: ~170 checks, 2 real "level" refusals per bot).

## 2026-11-23, scheduled run: the pack window on I (ws/client/pack-window)

**Fun in one sentence:** you press I and see your haul as a grid of real icons with counts,
and the stack you just added to glows gold with "+2", so a gather pays off a second time when
you look at it, without typing `/bag`.

**Built:** `PackWindow` (`game/client/pack_window.gd`), opened by I (`toggle_pack` in
`ControlsOverlay.DEFAULT_BINDS`, listed in F1) or a "Pack" button left of "Skills". Fed only by
the server: the login character's `inventory` and every `inventory_changed`, same as the craft
window. Five columns, at least two rows; slots in `Inventory.held` order so nothing shuffles.
Count turns red at `Inventory.MAX_STACK` (a full stack is why a gather stops adding). Hover
tooltip: name, "N of 99", and "Used in: stone axe, campfire" from `Crafting.RECIPES`, or a tool
note. A slot that rose glows gold for 1.4 s with "+N" (a second haul while glowing adds to the
+N). The first pack after login never glows. Icons at a new `IconShelf.SLOT_SIZE` (44 px), drawn
ahead on the icon thread like the others. The corner hint moved 60 px left to make room for the
button. Windows stay mutually exclusive (pack, skills, F1, workbench, settings), Esc closes it.

**Tests:** `test_client_pack_window.gd` (slots, texts, glow and +N, reset, I key, icon size).
Bot behaviour `client_pack_window.gd` is network-only: on every real `s2c_inventory` it checks
the slots match the server's pack exactly, the header total adds up, and each glow equals the
rise (15-22 updates per bot in the 8-bot run, which PASSED). Unit tests 482 passed with Postgres;
client smoke passed. Screenshot with a test hook `--open-pack=ash_wood:12,stone:99,...` (display
only, never sent; one more of the first item arrives just before the shot to catch the glow).

**Didn't do:** a sound for a slot filling while the window is open (follow-up), and the smoke
screenshot in qa's `run.sh` (qa's file; follow-up).

**Next run:** the players panel (O) is the next piece of "every slash command gets real UI",
then left-click gather.

## 2026-11-23, scheduled run: the players panel on O (ws/client/players-panel)

**Picked:** the players panel, next piece of "every slash command gets real UI" and part (1) of
gameplay's v5 request (`s2c_roster` was on `main` with nothing on the client reading it).
Return to Spawn Meadow (part 2) is a separate backlog item: one feature per run.

**Fun in one sentence:** you press O and see who else is in the valley with how far along they
are, and when an ember burst goes up across the meadow the matching row glows gold "+1", so
other players stop being anonymous avatars; the "Players 5" button shows the valley's size
without opening anything.

**Built:** `PlayersPanel` (`game/client/players_panel.gd`), on O (`toggle_players` in
`ControlsOverlay.DEFAULT_BINDS`, listed in F1 under "Who is online") or a "Players N" button
left of Pack (the corner hint moved 90 px further left). Fed only by `roster_changed`; rows in
the server's order (by name), you in ember orange with "(you)", each with "Total level N".
`changes(old, new)` gives joined ids and level rises: a newcomer's row glows "just arrived",
a rise glows "+N" (a second rise while glowing adds up), 1.6 s fade. The first roster after a
login never glows, nor does your own arrival. `set_me(id)` at login re-marks you in case the
roster beat the login answer. Malformed entries and a second row for one id are skipped. The
list sizes to its rows (30 px each, scrolls past ~11) and the panel shrinks back around it.
Windows stay mutually exclusive (pack, skills, players, F1, workbench, settings); Esc closes.

**Tests:** `test_client_players_panel.gd` (10 tests: rows, bad entries, texts, changes, glow
and +N stacking and fade, reset, roster-before-login, O bound once and in F1, 40 players fit
under 700 px). Bot behaviour `client_players_panel.gd`, network-only: on every real roster the
rows equal the entries, exactly one is us, header and button agree, every "just arrived" is
new and every "+N" equals the rise. 8-bot run PASSED (26-29 rosters, 9-14 arrivals and 7-8 level
glows per bot, 8 online at most). Unit tests 517 passed with Postgres; client smoke passed.

**Didn't work first time:** the `--open-players=Ash:9,...` screenshot hook gave its made-up
players ids from 900 and kept real ids below 900, but real peer ids are large random ints, so
your own row vanished from the shot. Made-up ids are negative now. The first shot also showed a
fixed 330 px list with three rows in a mostly empty box, hence the sizing to rows.
Screenshot: `/mnt/project-files/client/players-panel.png`.

**Next run:** Return to Spawn Meadow in the Esc menu (v5 `c2s_unstuck`), or left-click gather.

## 2026-11-23, scheduled run: the time dial tooltip (ws/client/time-dial-tooltip)

**Picked:** the time dial tooltip, the next unticked piece of "every slash command gets real
UI" (it replaces `/time`). Chosen over Return to Spawn Meadow and left-click gather because it
is the last reply of `/time`, `/who`, `/bag`, `/help` with no UI, and it fits one run with
room to test it properly.

**Fun in one sentence:** you see night coming instead of being surprised by it: hover the dial
for "Dusk in about 9 minutes, then night in about 13", and in the last 90 s of a phase the
readout itself says "· Night soon", so you can choose to head for the bench lantern or stay
out for the ember glow.

**Built (all in `game/client/time_dial.gd`):** `tooltip_text_at(world_seconds)` (four lines:
exact time, next phase with countdown, the phase after with countdown, day length),
`until_text` ("in less than a minute" / "about a minute" / "about N minutes"), `soon_text`
and `label_text` (the readout plus "· Dusk soon" in a phase's last `SOON_SECONDS` = 90 s;
`state().text` itself is unchanged so `ChatFeed`'s timestamp test still holds). The dial is
now `MOUSE_FILTER_PASS` with `_get_tooltip` (text built when the tooltip opens) and
`_has_point` limiting the hover to the disk and the readout, not the whole 460 px strip; the
tooltip is a custom dark panel edged in the current phase's sky colour. Hover only works with
the cursor free (chat open, or any window up): that is fine, chat open is exactly when your
eyes are next to the dial, and the "soon" warning covers play with the cursor captured.

**Tests:** 4 new unit tests in `test_client_time_dial.gd` (tooltip lines at noon and late
night, every 15 in-game minutes the next phase is right; rounding; the warning shows for
exactly 90 s per change, 4 changes a day; hover area and panel). Bot behaviour
`client_time_dial` now checks on every `s2c_world_time` that the tooltip agrees with the
readout, names the server clock's next phase with a matching countdown, and that the warning
shows iff that phase is 90 s or less away. Unit tests 521 passed with Postgres; 8-bot 180 s
WebSocket run PASSED (5 tooltips checked per bot; no warnings hit that run, the window is
90 s of every 40 min, so the unit test covers it); client smoke passed.

**Didn't work first time:** the hand screenshot set `_state` directly and the dial's first
`refresh` overwrote it with the real clock; pinning `DayNight.pinned_fraction` is the right
way (it is what `current_seconds` reads). Screenshot:
`/mnt/project-files/client/time-dial-tooltip.png`.

**Told gameplay** (its Requests) that `/time` can go behind the dev gate once this lands.

**Next run:** move system notices to centre screen (last piece of the chat-to-UI item), or
Return to Spawn Meadow, or left-click gather.

## 2026-11-23: system notices centre screen (`ws/client/centre-notices`)

**Fun:** a refusal ("Chat is for talking", "this ash is spent, back in about 3 minutes, the
next one is 23 m north-east") now pops up just above the reticle where your eyes already are,
with a soft low "nope", instead of scrolling past in a chat box you weren't reading. Chat is
left with only what people say and who arrives or leaves. Last piece of the "chat is for
talking" item (owner direction 1).

**Built:** `NoticeLine` (`game/client/notice_line.gd`): a centre notice 150 px above screen
centre, first sentence as a 20 px warm headline, the rest as a 15 px detail line; pops (1.12
-> 1.0 in 0.14 s), holds 2.4 to 6 s by length, fades over 0.6 s; a new notice replaces the
old one, the same notice again just holds longer. `NoticeLine.route(text, paired_reason)`:
"X has arrived." / "X has left." and lines over 220 chars or with newlines (dev command
answers) stay in chat; a server line arriving within 1 s of a gather refusal whose toast
already says it all (full, day, busy, cooldown, level, far, unknown) is dropped; everything
else is centre screen. "depleted" is the one refusal whose server line adds something (when
it comes back, where the next node is), so it shows centre. The login welcome is a centre
notice (gold, no nope) instead of the first chat line. `Sfx.nope()`: D4 then B-flat 3,
0.34 s, quiet, played on every gather refusal toast and every unpaired centre refusal (never
twice for one refusal). Test hook `--show-notice[=text]` for screenshots.

**Why drop rather than show the toast-paired lines:** the bottom toast is where your eyes are
while gathering; saying "Your pack is full" there and "Your pack can't hold any more ash
wood" centre screen is the same thing twice. Only new information earns the centre.

**Tests:** 6 unit tests in `test_client_notice_line.gd` (routing, toast pairing, splitting,
hold/fade/pop, the node replacing/repeating/fading, the nope's length and level), plus
`test_client_chat_feed` now checks joins stay in chat and a refusal goes centre. New bot
behaviour `client_notices` runs NoticeLine on every real `s2c_system` in the client's order,
pairs it with the bot's own `s2c_gather_end`, and fails on a non-presence line in chat, a
notice not showing its headline, a drop with no toast behind it, or a notice up past its
hold. Unit tests 545 passed with Postgres; client smoke passed; 8-bot 180 s WebSocket bot
test PASSED (per bot about 55 system lines: ~30 centre, ~22 in chat (joins/leaves and long
dev answers), 2 dropped behind a toast, 12 to 18 gather refusals).

**Didn't work first time:** `test_client_chat_feed` builds a bare `client.gd` without `_ready`,
so `notice_line` was null in `_on_system`; it now falls back to chat when the notice isn't set
up (only ever in that test). The first bot run failed on two test bugs of mine: the "stayed up
past its hold" check counted from when the notice first appeared, not from the newest
notice that replaced it, and the behaviour's NoticeLine was never freed, so its labels leaked
at exit (Godot's leak lines count as error logs). Both fixed; the second run passed.

**Next run:** left-click gather (action camera follow-up), or Return to Spawn Meadow, or
client-side prediction.

## 2026-11-23: left-click gathering (ws/client/left-click-gather)

**Built:** the action camera's "E or left-click" (owner direction 3). A new `click_use`
action (left mouse button) lives in `ControlsOverlay.DEFAULT_MOUSE` and is installed next to
the keys; F1 shows it as "Left click" beside E. `GatherPrompt.target` now says whether its
node is `aimed` (under the reticle) and `decide` takes `click_held` / `click_pressed`.

**Calls I made, and why:**
- A click only takes the node under the reticle, never the nearest-node fallback E uses.
  Clicking at the sky to look around shouldn't start chopping the tree beside you.
- A click never cancels. Players mash the button in action games; mashing should keep you
  chopping, not toggle the swing on and off. E or moving still stops.
- Only a click the game itself took counts: `_unhandled_input` sets `_click_tap` /
  `_click_down` when the cursor is captured. `Input.is_action_just_pressed` alone would also
  fire for the click on a window's Close button or the Pack button, and start a gather the
  same frame the window shut.
- Holding the button after a refusal or after E stopped you waits until you let go (shares
  `_hold_blocked` with E).

**Tests:** 4 unit tests in `test_client_click_gather.gd` (decide rules, `aimed` on real nodes,
the widget's click/hold/E-stop sequence, binding and F1 row); `test_client_controls_overlay`
accepts mouse defaults. New bot behaviour `client_click_gather`: on every server-begun gather
of the bot's own, it aims a camera at that node and checks the click path asks for that very
node and that a click mid-gather wouldn't stop it; it sends nothing. Unit tests 584 passed with
Postgres; 8-bot 180 s WebSocket bot test PASSED (21 to 28 gathers checked per bot, 0 skipped);
client smoke passed.

**Didn't work first time:** nothing failed this run. Known gap: the bot check builds its own
camera eye 2.2 m above the bot, not the real `ActionCamera` arm, so it proves the aim rules,
not the exact shoulder offset (that path is unit tested in `test_client_action_camera`).

**Next run:** client-side prediction (unblocked since v3's `ack_seq`), or the art-check move
out of the bot behaviours, or Return to Spawn Meadow once v5 is on `main`.

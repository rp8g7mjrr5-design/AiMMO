# Devlog: world workstream

Newest entries at the bottom. Each run appends what it built, what didn't work, and notes to its next run.

## 2026-11-22: day and night sky
**Built.** `game/procgen/sky_clock.gd` (pure maths: day fraction, sun and moon direction, sky/fog/light colours keyed on sun height, star fade, phase name) and `game/procgen/day_night.gd` (a node WorldBuilder adds that repaints the world 4 times a second, plus a code-only sky shader with gradient, sun disk and glow, hashed twinkling stars, and a moon). The old `ProceduralSkyMaterial` is replaced because it can't draw stars or a moon.

**Decisions.**
- One day = 2400 s, from the roadmap. Fraction 0 is midnight, 0.25 sunrise, 0.5 noon.
- Clock source is local Unix time behind `DayNight.now_fraction()`. Every machine's Unix time is near-identical, so players already share the same sky before the server clock exists. Gameplay only has to call `DayNight.sync_to_server()` (request filed in their backlog).
- One DirectionalLight serves as sun by day and moon by night; its energy drops to 0 at the horizon on both sides so the swap is invisible. Moonlight is 0.22 energy with a blue tint and ambient never drops below 0.18, so night is moody but you can still see where you walk.
- Day keys keep the bible's late-afternoon palette (the old sky colours are the 0.30 key); dusk leans ember orange.
- `AIMMO_TIME_OF_DAY` env var pins time for screenshots and tests.

**Tested.** 37 unit tests (4 new, in `tests/unit/test_world_daynight.gd`) with Postgres, 8-bot 180 s websocket bot test passed, client smoke test passed at noon, dusk, and midnight; I looked at all three screenshots. No bot behaviour: the behaviour hook doesn't exist yet (asked qa).

**Didn't do / known.** No lamps yet (nothing to light). Noon sky is a touch pale near the horizon; tune if it reads washed out on a real GPU. Shadows at very low sun angles can get long; the 0.12 energy ramp hides the worst of it.

**Next run.** Biome variety (birch meadows, mossy boulders, wildflowers) is now top of the backlog.

## 2026-11-22: the sky reads the one shared clock
**Built.** `SkyClock` no longer keeps time. Its `DAY_LENGTH`, `day_fraction`, tilted sun path, and `phase_name` are gone; it now maps a day fraction onto `WorldClock` (via `seconds_for_fraction`) and only owns the colour/light keys and star fade. `DayNight` drops `clock_offset`/`sync_to_server` for `set_world_seconds(s)` (store the value and `Time.get_ticks_msec()`, extrapolate with `WorldClock.extrapolate`), `clear_sync()`, `is_synced()`, and `now_world_seconds()`. Before the first sync it uses `WorldClock.now_seconds()`, which has the server's epoch, so the sky no longer jumps when server time arrives (the old Unix-epoch clock ran exactly a quarter day behind WorldClock: midnight on one was sunrise on the other).

**Decisions.**
- The sun direction now comes straight from `WorldClock.sun_direction` (rises +x, 0.35 south lean) instead of my own 28° tilt / -35° azimuth path, because the director ruled one source of truth and gameplay will reason about sun position (night danger, lamps). Shadows point a little differently than yesterday; nothing else depends on it.
- Sky colours key on `WorldClock.sun_elevation` (sin of the angle), not on the light vector's y. Both are 0 at the horizon so dawn/dusk timing is unchanged; noon is a touch brighter at the top key.
- I deleted `SkyClock.phase_name` rather than keep a second set of phase boundaries. Use `WorldClock.phase`.
- The `AIMMO_TIME_OF_DAY` pin stays a fraction (0 midnight) so screenshot scripts keep working.
- The bot behaviour `world_day_night.gd` ships with this, since it is this feature's test: each bot feeds s2c_world_time into DayNight and checks sky time matches server time, never runs backwards, and samples sane colours.

**Tested.** 60 unit tests with Postgres (6 in `test_world_daynight.gd`, rewritten), 8-bot 180 s websocket bot test passed (every bot: 5 sky syncs, ~36 sky checks, 8/8 characters persisted), client smoke test passed; I looked at the world screenshot (live clock, afternoon).

**Known / not done.** The client doesn't call `set_world_seconds` yet (client owns that; request filed in `docs/workstreams/client.md`). Until it does, players see the local wall-clock sky, which matches the server to within clock skew.

**Next run.** Lamps and ember-ash glow at night, driven by `WorldClock.daylight`.

## 2026-11-22: avatars get arms and short legs
**Built.** Answered client's request first (requests before backlog). `AvatarBuilder.build` now adds `ArmL`, `ArmR`, `LegL`, `LegR` as bare `Node3D` pivots, direct children of the root, pivot at shoulder (y 1.04, x ±0.40) or hip (y 0.40, x ±0.14), meshes hanging below: sleeve capsule plus a skin-tone hand, trouser capsule plus a dark boot. The tunic capsule shrank (height 1.2 → 0.96, centre 0.6 → 0.78) so it sits on the legs instead of hiding them. The client's `WalkAnim` swings them with no client change. The name tag is still a direct child of the root.

**Decisions.**
- Left is +X: an avatar faces +Z, so its own left hand is on +X. `WalkAnim` swings ArmL and LegR together, which is the natural gait either way.
- Limbs take no draws from the appearance rng and the existing draw order is unchanged, so every saved character keeps their skin tone and hat (unit-tested by recomputing the old draws).
- Sleeves are the tunic darkened 12%; trousers are the tunic darkened and pulled halfway to a brown so they never clash; boots are one shared dark brown. Limbs use 6 radial segments (bible: 5 to 8).
- I split `build` into pure `parts(seed)` (every mesh as data) and `rig()` (root plus empty pivots). On the headless dummy renderer, freeing a MeshInstance3D with a primitive mesh, an ArrayMesh with a surface, or a Label3D each logs `Parameter "m" is null` (that's why `test_procgen::test_avatar_builds` skips headless). The pure halves let the unit tests and bots check the avatar shape headless with zero engine errors.

**Didn't work.** First try baked every primitive into an ArrayMesh to dodge the headless errors; ArrayMeshes log the same error when freed, so I reverted that.

**Tested.** 84 unit tests with Postgres (5 new in `tests/unit/test_world_avatar.gd`), 8-bot 180 s websocket bot test passed (new behaviour `world_avatar_limbs.gd`: each bot lays out every joining player's real avatar and walks a rig, ~20 avatars and 7 looks per bot, 8/8 characters persisted), client smoke test passed at midday; I looked at the screenshot and the arms, hands, and boots read clearly.

**Known / not done.** No elbows or knees; the limbs are stiff pendulums. Hands don't hold anything yet (tools come with gathering).

**Next run.** Lamps and ember-ash glow at night, driven by `WorldClock.daylight`.

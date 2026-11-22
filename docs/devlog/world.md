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

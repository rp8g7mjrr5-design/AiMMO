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

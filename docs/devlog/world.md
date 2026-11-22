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

## 2026-11-22: resource-node props
**Built.** Answered gameplay's request (requests before backlog). New `game/procgen/node_props.gd`: `NodeProps.parts(node, depleted)` lays out one node's prop as pure data, `layout(nodes)` packs both looks of every node into six MultiMesh layers with a per-node slot table, `build()` makes the `ResourceNodes` node that `WorldBuilder` adds, and `set_depleted(root, id, on)` swaps a node's look by showing/hiding its instances (collapsed basis), so nothing is created or freed in play. `Props.scatter` now skips decorative trees and rocks within 3 m of a node.

**Looks.** Ember ash: thick trunk, big crown plus a smaller lifted crown, brighter orange than decoration. Pine: four tiers, slightly brighter green. Stone outcrop: a big 2 m boulder, two side chunks and a pale quartz seam on top. Ember-sap seep: a ring of dark stones around a glowing (emissive, shadowless) pool with three glowing shards. Depleted: stumps with a pale cut face, low rubble, a dried dark seep with the rim stones left.

**Decisions.**
- Node props are drawn from `ResourceNodes.all()` exactly (pos/rot/scale), never placed by world, so the server and the picture always agree.
- The scatter clearance check runs after all rng draws for a spot, so the remaining decoration is the same forest minus the spots next to nodes, plus a few extra trees at the end of the list. Nothing is saved from decoration, so this is safe.
- Small per-node variation (crown tint, rubble angles, shard heights) is seeded from the node id, not from the placement rng, so it can never disturb gameplay's list.
- MultiMesh show/hide rather than per-node MeshInstances: 397 nodes, about 3.5k instances in 6 draw calls.

**Didn't work.** First version made the outcrop and seep too small: at 15 m in the smoke shot the outcrop read as an ordinary pebble and the seep was invisible. Scaled the outcrop about 1.5x, raised the seep and added the glowing shards; checked with close-up renders of each kind, live and depleted.

**Tested.** 106 unit tests with Postgres (5 new in `tests/unit/test_world_node_props.gd`: every kind's live and depleted look, props stand on their node, determinism, layout slots, scatter clearance), 8-bot 180 s websocket bot test passed (new behaviour `world_resource_nodes.gd`: 36 nearest-node checks per bot, all 4 kinds seen, 8/8 characters persisted), client smoke test passed (day and night). Rendered close-ups of all four kinds with everything depleted via `set_depleted` on the real renderer; no errors.

**Known / not done.** The decorative ash and a node ash still look alike from far away; the "can gather" hint (follow-up in backlog) should fix that properly. No collision on props (nothing has collision yet). The client has to call `set_depleted` once node state is on the wire (request filed in client backlog).

**Next run.** Lamps and ember-ash glow at night, driven by `WorldClock.daylight` (the sap seeps' emissive material is a natural thing to brighten at night too).

## 2026-11-22: lanterns and the ember ash's night glow
**Built.** New `game/procgen/lamps.gd`. `Lamps.positions()` puts 8 lanterns in a ring about 9 m round spawn (turned by the world seed, on the ground, nudged outward if a resource node is within 2.5 m; none are today). Each lantern is a stone foot, a wooden post, a short arm and a hanging iron-capped glass, drawn as three MultiMesh layers plus one shadowless `OmniLight3D` per lantern. `Lamps.night_glow(frac)` (0 by day, 1 at night) drives everything that glows after dark through `Lamps.apply_glow(world, glow)`, which `DayNight.apply` calls on every repaint: lamp lights and glass, a faint ember emission on the decorative `AshCrowns` and on `NodeAshCrowns`, and the sap seeps (0.9 by day, as before, up to 1.6 at night; they are night-only to gather, so they should be easy to find then). WorldBuilder applies once after building so the first frame is already right.

**Decisions.**
- Lamps key on the sun's height with their own curve (`smoothstep(0.14, -0.06, sun_height)`) rather than `WorldClock.daylight`, because settlers light lanterns *before* it gets dark: at sunset (0.75) they are already about half lit. It still comes from the one shared clock (`SkyClock.sun_height` -> `WorldClock.sun_elevation`), so a unit test checks it is identical from world seconds.
- Ring radius 9 m: decoration keeps 10 m clear and resource nodes 12 m, so the ring sits in open meadow and every new player spawns inside it.
- Lantern lights have no shadows: 8 shadowed omni lights would hurt low-end laptops, and at 11 m range nobody notices.
- Leaf glow is deliberately faint (0.10 emission, 0.14 on gatherable ash): it should feel like warmth, not fairy lights, and it is a quiet hint toward the bible's mystery (the trees are the warm roots of something asleep).
- One `apply_glow` entry point that looks nodes up by name and skips anything missing, so a partial world (tests, bots) never errors.

**Didn't work.** First version used `Basis.scaled()` for part sizes, which scales in world axes after the rotation, so the arm would have stretched wrongly on turned lanterns; switched to `rotation * Basis.from_scale(size)`. Glass at emission 2.4 burned to pure white in the night screenshot and the light pools looked greenish on grass; toned glass down to 1.3 and warmed the flame colour.

**Tested.** 130 unit tests with Postgres (5 new in `tests/unit/test_world_lamps.gd`: ring placement and spacing, determinism, lantern parts and light position, glow follows the clock, glow values), 8-bot 180 s websocket bot test (new behaviour `world_lamps.gd`: lanterns on the ground and off nodes, glow agrees with the server's phase on every time sync, nearest lantern each bot walked past), client smoke test passed; I looked at the midnight and noon screenshots.

**Known / not done.** No flicker yet. Lamps only exist at spawn; once there is a town or paths, extend `positions()` (follow-up in the backlog). Night luminance in the smoke shot rose from about 0.08 to about 0.13, still far below day (0.73); about 0.12 after toning the glass down.

**Next run.** Biome variety (birch meadows near water, mossy boulders, wildflowers).

## 2026-11-22: biome variety (shore birches, mossy boulders, wildflowers)
**Built.** New `game/procgen/flora.gd` (`Flora`). `spots()` (cached) is a second scatter on its own seed (`WORLD_SEED + 401..404`): 260 birches on lake shores, 150 mossy boulders in the pine band, 220 wildflower patches of 12 flowers in the grasslands. `parts(spot)` and `layout()` are pure data; `build()` makes the "Flora" node with seven MultiMesh layers, added by `WorldBuilder` right after the decorative props.

**Looks.** Birch: a slim chalk-white trunk with three dark bark bands and two tall yellow-green crowns, leaning up to about 6° (from a position hash). Boulder: a big squashed grey rock with a green moss hemisphere on top, and on about half of them a small mossy companion. Flowers: thin stems with a little bloom; each patch has one colour from five (yellow, violet, white, ember red, sky blue) with a couple of odd ones mixed in, and each flower sits on its own bit of ground so patches on slopes don't float.

**Decisions.**
- A separate scatter instead of new kinds inside `Props.scatter`, because changing that loop would shift every existing tree. A unit test pins the old scatter at 1800 entries.
- "Near water" means open water (height below the water line) within 9 m in one of 8 directions, plus a height band just above the shore. Height alone would have put birches all over the 0.5 m-high Spawn Meadow.
- Wildflowers cluster where a low-frequency noise mask is high, so they come in meadows, not evenly sprinkled.
- Flora keeps 3 m off resource nodes, 11 m off spawn (outside the lantern ring), 2.2 m off decorative trees/rocks, and off other flora. No collision (nothing has collision yet).
- Flower layers cast no shadows and stop drawing past 90 m: 2,640 tiny instances that nobody can see from further away.
- The look's small variation comes from a hash of the position, never from the placement rng.

**Didn't work.** First probe hung: GDScript couldn't infer types from `Variant` math inside the `match`, the script failed to compile, and a SceneTree script that never reaches `quit()` sits there forever. Always run probes under `timeout`. First flower patches (7 flowers) looked sparse in a close-up render; went to 12 and slightly bigger blooms.

**Tested.** 151 unit tests with Postgres (6 new in `tests/unit/test_world_flora.gd`: every kind grows, each in its biome, clearances, determinism, old forest unchanged, parts), 8-bot 180 s websocket bot test passed (new behaviour `world_flora.gd`: ~58 look-arounds per bot, nearest flora 1.3 m, 8/8 characters persisted), client smoke test passed (day 0.727, night 0.123 luminance). I rendered a close-up of each kind on the real renderer and looked at them: birches around a lake read clearly as a different tree.

**Known / not done.** Flora has no night glow (deliberately: only the ash is warm). The lake water still renders quite pale/white in software GL; worth a look when animated water is built.

**Next run.** Gentle animated water (shader in code), unless a request comes in.

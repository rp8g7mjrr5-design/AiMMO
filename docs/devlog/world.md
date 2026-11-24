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

## 2026-11-22: gathering feedback art (node glow and hit reactions)
**Built.** New `game/procgen/node_fx.gd` (`NodeFx`, a Node3D that `NodeProps.build()` adds as `ResourceNodes/Fx`). Public API stays on `NodeProps` as the director asked: `set_highlight(root, id, on)`, `highlighted(root)`, `play_hit(root, id)`. `set_depleted` now records depleted ids in the root's `depleted` meta and tells Fx so a lit or shaking node follows its new look. Layout slots also carry `kind`, `pos`, `scale` so Fx never has to look nodes up.

**Looks.**
- Highlight: a shell made of the node's own current parts, grown 7% about each part's centre, drawn with an unshaded additive fresnel shader in ember gold (`HIGHLIGHT`), with a slow pulse and a 0.15 s fade. Six small MultiMeshes (one per layer, 10 slots each), hidden when nothing is lit.
- Hit: ash and pine shudder from the base (~2.5°, ringing down over 0.6 s; sway axis turned per node by the golden angle so neighbours differ). Ash sheds 7 warm, faintly glowing leaves that drift down with a sway; pine drops 7 needle tufts. Stone jolts (2.5 cm, slight squash, 0.35 s) and throws 6 chips on arcs, one of them pale seam quartz. Sap seeps keep their rim still; the pool swells and settles while 8 glowing droplets splash up. Bits shrink away over their last 0.25 s and never go below the ground.
- All bits share one 64-instance MultiMesh (one draw call) with a tiny shader using `INSTANCE_CUSTOM.r` for glow; the oldest bit is reused when the pool is full.

**Decisions.**
- One lit node at a time: the bible says the prompt shows one target, and it keeps `set_highlight` a no-op when called every frame with the same id.
- No CPUParticles/GPUParticles: my own bits are pure maths (`spawn_bits`, `bit_xform`, `shake`, `shell_xform`), so unit tests and bots check every bit headless, and the headless dummy renderer's free errors never come up.
- Fx only processes while something is fading, shaking or flying; idle it costs nothing.
- Hits on a depleted ash/pine/seep shudder but throw nothing (nothing left to shed); depleted rubble still chips. Bits are seeded per node and hit number, so they are deterministic but vary hit to hit.

**Didn't work.** First leaves spawned inside the crown sphere (radius 1.9 × scale), so a close-up 0.2 s after the hit showed nothing; they now start just outside the crown's lower edge and are a bit bigger. First rim was nearly white against the sky (additive saturating); toned it to `0.08 + 0.6 * rim^2.6`.

**Tested.** 166 unit tests with Postgres (6 new in `tests/unit/test_world_gather_fx.gd`), 8-bot 180 s websocket bot test passed (new behaviour `world_gather_fx.gd`: 45 hits played, 308 bits followed through their whole life, all 4 kinds, 8/8 characters persisted), client smoke test passed (day 0.727, night 0.124). I rendered close-ups of every kind lit, just after a hit and half a second later on the real (software GL) renderer and looked at them: the rim reads, leaves/needles/chips/droplets are visible.

**Known / not done.** Nothing calls this yet: the client wires it to `GatherPrompt.target` and `s2c_gather_result` (request filed in the client backlog). No tool-contact flash; that needs the client's swing (follow-up in my backlog). Pine needle bits are small and dark against a dark forest floor.

**Next run.** Close-up read for the action camera (second backlog item), then item icons.

## 2026-11-23: the Spawn Meadow workbench
**Why this, not the close-up pass.** The worker procedure puts requests from other streams first, and gameplay's workbench request was the oldest open one. It is also a real gap players hit today: `/craft` tells them "the workbench is at the heart of Spawn Meadow" and there was nothing there. The close-up read for the action camera stays next.

**Built.** New `game/procgen/workbench.gd` (`Workbench`), split like `Lamps`: `spot()` (always `Crafting.workbench_pos()`, yaw so local +Z faces spawn), `parts()` and `layout()` are pure data, `build()` makes the "Workbench" node from three MultiMesh layers (wood boxes, stone boxes, log cylinders). `WorldBuilder` adds it after the lanterns.

**Looks.** Three pale ash-wood planks (different tints, slight end offsets) on four squat stone legs with wider feet, side rails and a low back rail, a stone-headed hammer and three stone chips on the top, a chopping block with a pale cut top and a split log leaning on it at the right end, and a woodpile of three logs with cut ends behind. Planks top out at 0.92 m. Each leg and pile sits on the terrain under it so nothing floats on a slope.

**Decisions.**
- Placement comes only from `Crafting.workbench_pos()`, never a copy of the numbers; a unit test and the bot behaviour both check this.
- Faces spawn so a new player sees the long side and the tools first.
- No glow at night yet: the lantern ring is 5 to 12 m away and lights it. Small lantern on the bench is a follow-up if night players can't find it.
- No collision, like everything else so far.

**Didn't work.** First woodpile had two logs overlapping each other along their length and only one cut face; it read as two dark blobs in a close-up render. Rebuilt it as two side by side plus one on top, with cut faces on both ends, and lightened the bark a shade. The first cut-face colour was almost yellow; warmed it down. The split log poked past the 1.7 m footprint the test checks; footprint is now 2.0 m (clearance 2.5 m).

**Tested.** 183 unit tests with Postgres (4 new in `tests/unit/test_world_workbench.gd`: at the crafting spot and on the ground, faces spawn, parts hold together and sit at the right heights, clear of nodes/lanterns/trees/flora/spawn, deterministic). 8-bot 180 s websocket bot test passed twice (new behaviour `world_workbench.gd`: every bot's bench matches the crafting rule, ~173 position checks per bot, all 8 bots stood in crafting range at some point, 8/8 characters persisted). Client smoke test passed (day 0.725, night 0.123); the bench is in the spawn screenshot. I rendered three close-ups (front, back three-quarter, from the lantern ring) on the real renderer and looked at them.

**Next run.** Close-up read for the action camera (backlog item 2), then item icons.

## 2026-11-23: close-up read for the action camera
**Built.** The camera now sits about 3.5 m behind the shoulder, so I looked at what it sees up close and fixed what read flat or broke.
- New `NodeDetail` layer in `NodeProps` (one BoxMesh MultiMesh, shadowless): three root flares on every node ash and pine (and on their stumps), so trees grow out of the slope instead of standing on it like posts; four bark ridges per live trunk (dark fissures on the ash, lighter reddish plates on the pine); six pale quartz studs set along a rising seam across the outcrop's big stone, each laid on the ellipsoid's surface along its normal. Detail parts are appended after every older part and use their own rng (`WORLD_SEED + 227`), so older parts, their order and colours are unchanged (unit test).
- Sap pools: roughness 0.35 -> 0.14, clearcoat on, so they look wet with a moving highlight.
- Avatars: a belt, a small leather pack and a rolled blanket on the back (root parts appended last, no rng draws, so every saved look is unchanged). `parts()` entries now carry an optional `rot`.
- **Seeing inside meshes.** The camera's prop clearance (`ActionCamera.PROP_COLUMNS`, client) was smaller than the props and ignored node scale: ash crowns are 1.9 m round vs a 1.6 m column, the lowest pine tier starts at 1.15 m vs a column from 2.6 m, the stone is taller than its 1.2 m column, seeps have none. A probe found vertices of every kind outside those columns. World now owns the exact shape: `NodeProps.SOLID_COLUMNS`, `solid_columns(kind, scale)` and `inside_solid(p, node, margin)`. A unit test transforms every vertex of every part of every node (live and depleted) and checks it is inside; the tightest miss is about 1.7 cm inside. Request filed in the client backlog to make `inside_prop` call `inside_solid`. I didn't edit `action_camera.gd` myself because it is client-owned.

**Decisions.**
- Hand-made stepped columns (the crown band is split at 2.5 m, pine per tier) rather than one fat column, so the camera isn't pushed in under a canopy for no reason; the vertex test keeps them honest.
- Depleted looks fit inside the live columns, so the camera needs no depleted state.
- Detail boxes cast no shadow: about 2,600 tiny instances that no one would see shadows of.

**Didn't work.** My first seam studs were squarish (0.2 x 0.12) and near-white; in the close-up render they looked like stickers on the rock. Making them long and thin along the seam (0.26–0.32 x 0.08) and a little greyer made them read as a quartz vein. My first probe render put the test avatar in front of the ash. Also, `WorldBuilder.has_method` on a class is a parse error in 4.3, so call static functions directly.

**Tested.** 209 unit tests with Postgres (6 new in `tests/unit/test_world_closeup.gd`; the avatar headwear test now expects 3 more root parts). The 8-bot 180 s websocket bot test passed twice. The new behaviour `world_closeup.gd` looks round in 8 directions every second and checks node detail and the pack on every avatar that joins. It reports `camera_inside_mesh_with_client_columns`: 25 to 59 of about 1,384 looks per bot (2 to 4%) in the second run, which shows the client bug is real. Client smoke test passed (day 0.695, night 0.108, the same as `main` today on this machine: 0.696 / 0.109). I rendered close-ups of the ash, pine, stone, seep and an avatar from behind on the real renderer and looked at them.

**Known / not done.** Decorative scatter trees still have plain trunks and no camera clearance; the same goes for flora, lanterns and the workbench (follow-ups in the backlog). From straight behind, the bedroll mostly hides under the head.

**Next run.** Item icons for the inventory UI, unless the client asks for decoration clearance first.

## 2026-11-23: procedural item icons (and the close-up stat fix)
**Why this.** Item icons were next in my backlog, and the gather toast and the coming inventory window both want them: "+2 ash wood" as plain text is a weaker payoff than a little stack of logs popping up. Client's request (skip ARM_MIN looks in `world_closeup`'s stat) came first as a small bug fix in the same PR.

**Built.**
- New `game/procgen/item_icons.gd` (`ItemIcons`). `shapes(item)` is pure data: a short back-to-front list of circles, capsules, rounded boxes and polygons in a 0..1 square. `image(item, size)` rasterises them with signed distance fields (one anti-aliased edge per shape, a top-left light gradient across each shape, a dark outline round the union of the outlined shapes, a soft drop shadow, a warm halo behind glowing shapes). `texture(item, size)` caches an `ImageTexture`; `tint(item)` gives a matching colour; `has_icon(item)`.
- Icons: ash wood (two pale logs with growth rings and an ember leaf), pine wood (two reddish logs and a needle sprig), stone (a faceted chunk with the outcrop's quartz seam and studs), ember sap (a glowing amber drop with a highlight), stone axe, stone pickaxe (both with lashing), torch (handle, wrap, flame with halo), campfire (stone ring, crossed pine and ash logs, flame). Unknown ids get a cloth bundle, so a retired item in an old save still shows a picture.
- `world_closeup` bot behaviour: the client-column count now skips looks where the client's arm is already at `ARM_MIN` (the bot stands inside a prop's footprint), and the header comment says the columns are shared now. The stat reads 0 on all 8 bots.

**Decisions.**
- SDF maths on an `Image`, not a SubViewport render: it runs headless, so unit tests and bots check every pixel, and there are no imported fonts or textures (hard rule 3).
- Flat shapes with a light gradient and an outline, rather than tiny 3D renders: reads at 24 to 32 px, and it is in our own style (soft, warm, low-poly) rather than any other game's.
- Cost: about 90 ms for a 64 px icon the first time (GDScript per-pixel; a bounding-circle early-out took it from ~135 ms with identical pixels). Cached after that. I asked the client to warm the cache after login instead of on the first toast.

**Didn't work.** The new margin test caught four icons touching the edge on my first try (wood logs' right ends, the pine sprig's top, torch handle, campfire stones; outline plus drop shadow add about 0.06 of the square). Pulled them in; every icon now leaves 3+ px clear at 64 px. First try also failed to compile because `s.h - Vector2(...)` on a Dictionary value can't be type-inferred; typed it explicitly.

**Tested.** 227 unit tests with Postgres (6 new in `tests/unit/test_world_item_icons.gd`: every item has its own icon, sensible coverage and nothing clipped, all icons distinct from each other, glowing items glow and cold ones don't, deterministic and cached, unknown ids get the bundle). 8-bot 180 s websocket bot test passed (new behaviour `world_item_icons.gd`: each bot draws all 8 icons plus every id in its pack at every login, 16 per bot; `camera_inside_mesh_with_client_columns=0` on every bot). Client smoke test passed (day 0.695, night 0.108, same as before). I rendered a sheet of all icons at 128 and 48 px and looked at it: each reads clearly at small size.

**Known / not done.** Nothing shows the icons yet; the client wires them up (request filed). No "selected" variant or slot frame.

**Next run.** Decoration clearance (camera columns for scatter trees, rocks, flora, lanterns, workbench) or roots on scatter trees, unless a request comes in.

## 2026-11-23: the bench lantern and the bench highlight
**Why this.** The client's crafting window shipped ("[E] Use Workbench"), so the workbench follow-up in my backlog is now unblocked, and it is the shortest path to a felt change: a player stepping up to the bench sees it light up the same way a tree in reach does, and a player coming back to the meadow after dark finds the bench by its own lantern instead of hunting for it between the ring lamps. Decoration camera clearance stays next; it only helps once the client calls it, and the bench is something people use every session.

**Built.**
- `Workbench` grows a small iron lantern on the top's back-left corner: foot, glass (new `BenchGlass` layer, emissive in the meadow lanterns' `FLAME`), four corner rods, cap, finial and a carry handle. Lantern parts are appended after every older part, so the bench's old parts keep their index (unit test).
- An `OmniLight3D` "Light" at the glass (range 6 m, energy 1.1 at full night, no shadows). `Workbench.glow_values(glow)` / `apply_glow(bench, glow)`; `Lamps.apply_glow` calls it, so it runs from the one shared clock with no client change.
- `Workbench.set_highlight(bench, on)` / `highlighted(bench)`: a "Highlight" node holding a shell of every bench part grown about its centre (`NodeFx.shell_xform`, two MultiMeshes: boxes and logs), drawn with NodeFx's rim shader (new public `NodeFx.rim_shader()`) at strength 0.8. Fades over 0.15 s with a tween when the bench is in the tree, switches at once otherwise; the same value twice is a no-op. Request filed in the client backlog to call it from `_update_bench`.

**Decisions.**
- A lantern standing on the bench, not a post beside it: it stays inside the footprint and clearance the tests already hold, and it reads as "someone works here at night".
- The shell is always built (35 or so instances, hidden): cheaper than building on demand, and nothing draws while it is hidden.
- Highlight strength 0.8, not 1.0: the bench is large and close to the camera, so a full-strength rim looked louder than a node's.

**Didn't work.** I first tested the in-tree fade from a unit test by adding the bench to `Engine.get_main_loop().root`, but unit tests run during the runner's `_init`, where there is no main loop yet, so it crashed and leaked the bench. Checked the tween path in a throwaway SceneTree script instead (lit to 0.8, back to 0 and hidden) and kept the unit tests on the out-of-tree path.

**Tested.** 243 unit tests with Postgres (6 new in `tests/unit/test_world_bench_lantern.gd`). 8-bot 180 s websocket bot test: the first run failed once in the client's `client_craft_window` behaviour ("window thought the pack was {ash_wood 6, stone 2}, server says 3 ash wood, 1 stone axe", a craft racing the pack update, nothing my change touches); the second run passed clean. Client smoke test passed (day 0.695, night 0.105). New bot behaviour `world_bench_lantern.gd` (lights the bench through `Lamps.apply_glow` on every server time sync and checks lit at night / out in broad day; toggles the highlight whenever the bot enters or leaves crafting range and checks the shell follows). Rendered the bench at noon, at midnight, and at midnight highlighted on the real renderer and looked at them: the glass glows, warm light pools on the planks and the block, the rim reads gold on every edge.

**Known / not done.** Nothing calls `set_highlight` until the client wires it. No flicker yet (follow-up).

**Next run.** Decoration camera clearance (scatter trees, rocks, flora, lanterns, workbench) or roots on scatter trees, unless a request comes in.

## 2026-11-23: camera clearance for decoration
**Why this.** Next in my backlog, and a real thing players see: the client's camera keeps out of resource nodes now, but walk through the forest and it still swings straight through the 1,800 scatter trees and rocks, the birches and boulders, the meadow lanterns and the workbench, and you stare at the inside of a trunk. After this, once the client passes the new solids, the camera slides in in front of a tree the same way it already does for a node.

**Built.**
- New `game/procgen/world_solids.gd` (`WorldSolids`): a solid per decorative thing (2,219 in all: scatter ash/pine/rock, birches, boulders, 8 lanterns, the bench), each one column per drawn part, `[radius, y_from, y_to, offset_x, offset_z]` around that part's own centre. Columns are worked out from the very parts and meshes the world draws (upright, evenly scaled parts from the mesh's own profile; tilted or squashed ones from every vertex), so they can't drift from the art. `near(pos, radius)` reads a 16 m grid (~20 µs per call); `inside(p, solid, margin)`.
- `NodeProps.inside_solid` now accepts these solids too (anything with `columns`), so the client's existing `ActionCamera.clear_arm` works with them as-is; the client only has to add `WorldSolids.near()` to the list it passes (request filed in the client backlog, I didn't touch client files).
- The scatter forest's parts are now pure data: `WorldBuilder.scatter_meshes()` and `scatter_parts(items)`, which `_props()` uses. Same rng, same draw order, so the forest is unchanged.
- `WorldBuilder.build()` warms the solids (~0.15 s on this machine) so the first camera frame doesn't hitch.

**Decisions.**
- Derived columns, not hand-made like the nodes': there are seven kinds of decoration and the vertex test would have to chase every tweak. Derived is exact for the widest vertex and needs no upkeep.
- One column per part rather than stepped bands inside a part: banding by vertex isn't safe (a face between two bands pokes out of the narrower one).
- Wildflowers get no solid: 40 cm stems near the ground, which the camera already keeps clear of.

**Didn't work.** My first fast path treated every upright part as round in plan and took the widest horizontal scale, but a scatter rock is squashed (1.3 x 1.0) and then turned, so its axes skew and a vertex poked out. The every-vertex test caught it on the first run; squashed parts now take the vertex path.

**Tested.** 266 unit tests with Postgres (7 new in `tests/unit/test_world_deco_solids.gd`: a solid per decoration, every vertex of every part inside (over 200k checked), not much fatter than the meshes, near() matches brute force, NodeProps agrees, the client's own clear_arm keeps out of them from beside 300 trees, scatter unchanged and deterministic). 8-bot 180 s websocket bot test passed. New bot behaviour `world_deco_solids.gd` looks round in 8 directions every second with the client's own `clear_arm`, nodes only and nodes plus decoration: with decoration the camera never ended inside anything; nodes only, it ended inside decoration 54 times in 1,392 looks for one bot (about 4%), which is the bug the client's one-line change fixes. Client smoke test passed (day 0.695, night 0.105, same as before).

**Known / not done.** Nothing changes for players until the client passes the solids. The bench's planks get round 0.9 m columns (see the follow-up). Decorative trees still have no roots.

**Next run.** Roots on the scatter trees, or the lantern flame flicker, unless a request comes in.

## 2026-11-23: the level-up burst (Milestone 1, part 1)
**Why this.** Milestone 1 is now current and the director put the level-up burst at the top of my backlog. It is the payoff moment of the whole skills loop: you have been chopping for a minute, the bar fills, and the game should say so loudly enough that you and everyone near you notice. A player will feel their level-up as an event in the world, not a line of text.

**Best in class first (owner direction 6).** The level-up moment players remember is the one that is public: a burst of light others can see across a town makes levelling social and gives newcomers something to want. What people dislike is when it is long or blinding and blocks play, or when it is the same tiny sparkle as every other effect. Ours: short (2 s, you never stop to watch it), warm (the ash leaves' and lanterns' colours, so it belongs to Ashgrove), seen by others, with a ground ring so it reads from above the action camera too, and a light that actually lights the grass around you at night.

**Built.**
- New `game/procgen/level_up_fx.gd` (`LevelUpFx`). Pure maths: `column_at(t)` (shoots up to 5.5 m in a fifth of a second with a pop, holds, thins and fades), `ring_at(t)` (rolls out to 3.2 m in 0.9 s), `light_at(t)`, `sparks(seed)` / `spark_at(s, t)` (28 sparks swirling up from a ring at the feet past the head, streaked, winking out). The node copies those into a column, a disc, a spark MultiMesh and a shadowless OmniLight (range 9 m, peak 2.4).
- `LevelUpFx.play(avatar, seed)` adds or restarts one "LevelUpFx" child on the avatar; it frees itself at the end. A second call mid-burst restarts it rather than stacking.
- Request filed in the client backlog to call it on level-ups (gameplay's skills/XP messages are not there yet).

**Decisions.**
- Column and ring are one-instance MultiMeshes rather than MeshInstance3Ds: on the headless dummy renderer a MeshInstance3D with a mesh logs `mesh_get_surface_count` errors, which fail unit tests and would fail bots. Same trick NodeFx uses.
- Alpha-blended column, not additive (see below). Sparks stay unshaded in their own colour, so they read on any background.

**Didn't work.** My first column was additive like NodeFx's rim glow. At night it looked great; at noon on the real renderer it burnt out to a flat white tube (additive over a bright sky clips). A pale gold alpha-blended column was then almost invisible by day. Mostly lantern orange with a pale core only in the very middle, alpha up to 0.92, reads as a gold pillar by day and still glows by night. From 45 m by broad day it is a thin gold stroke with sparks: visible, not loud (follow-up in the backlog).

**Tested.** 283 unit tests with Postgres (5 new in `tests/unit/test_world_level_up_fx.gd`: column curve, ring and light go out, every spark rises round the avatar and burns out inside the burst, deterministic sparks, play/restart/finish on a real avatar rig with one burst only). 8-bot 180 s websocket bot test passed; new behaviour `world_level_up_fx.gd` plays a burst on the bot's own avatar rig at login and every 9 s, runs it frame by frame, checks sparks, light and clean finish, and restarts every other burst mid-way (21 bursts, 10 restarts, 1,450 frames per bot). Client smoke test passed (day 0.695, night 0.106). Rendered two bursts (0.3 s and 0.9 s in) in the Spawn Meadow at noon, midnight and from 45 m on the real renderer and looked at them; copies in the project files (`world/level-up-day.png`, `world/level-up-night.png`).

**Known / not done.** Nothing plays it until gameplay sends level-ups and the client calls it. No sound (client owns `sfx.gd`).

**Next run.** Milestone 1 part 2: the tier-2 node props (old ember ash, rich stone seam).

## 2026-11-23: Emberlight part 1, the shared shader
**Why this.** Top of my backlog (owner direction 7, the art bible). The level-up burst is waiting in PR #79 (red only because gameplay's v3 bot behaviours starve on emptied nodes, which the integrator flagged for gameplay; nothing for world to fix), and this item doesn't need its code. What a player feels: the valley stops looking like flat-shaded primitives and starts looking painted, with warm sunny sides, blue-leaning shade, darker hollows, and ash leaves that breathe together at night.

**Built.**
- New `game/procgen/emberlight.gd` (`Emberlight`): one shader source, three variants (`solid`, `foliage` with height-weighted wind sway, `glow` with ember veins marked by vertex alpha below 1). Custom `light()`: two soft ramp bands, warm key (`warmth`), `SHADE`-tinted shadow side (`shade_strength`), a rim when looking towards the light. `fragment()`: albedo from vertex colours (instance colours multiply in) with a two-octave world-position value noise ("brush", +-7%), emission swelling with the heartbeat. No texture lookups anywhere (unit test).
- `material(variant, name = "")`: built once, the same instance every call. Five in use after this PR: `solid` (scatter trunks and rocks), `solid/terrain` (rim kept at 0.05 so grazing ground doesn't light up), `foliage` (pine tiers), `foliage/ash_leaf` (ash crowns, with the night glow). `count()` for the 24 budget.
- The heartbeat: global shader parameter `ember_pulse`, registered at runtime by `Emberlight.ensure_globals()` (project.godot is client's), set every frame by `DayNight._process` from `Emberlight.pulse(world_seconds)`: one beat every 4 s of world time, so every client beats together.
- Palette tokens `EMBER`, `EMBER_CORE`, `SMOULDER`, `COLD_ASH`, `SOOT`, `SHADE`, `HAZE` in `palette.gd`.
- Terrain: baked AO per vertex (`TerrainMesh.ao_factor`, from how far a vertex sits below the average of the heights 8 m around it; up to 32% darker in hollows, up to 6% lighter on ridges), still one ground colour per triangle. The chunk now samples a height grid once (441 samples per chunk, down from 1,024).
- Scatter meshes: `Emberlight.bake(mesh, ao, curve)` gives each primitive an ArrayMesh copy with a bottom-dark gradient (trunks 45%, rocks 40%, pine tiers 40%, crowns 35%). Same vertices, so `WorldSolids` and the forest are unchanged (unit test compares).
- `Lamps._set_emission` understands Emberlight materials (sets `emission_energy`), `Lamps.ember_leaf_material()`.

**Decisions.**
- Named variants (`solid/terrain`, `foliage/ash_leaf`) instead of instance uniforms: the ash leaves' night glow is driven from one number for the whole layer, and Godot instance uniforms don't reach MultiMesh instances anyway. Still 4 materials where there were 5 before (terrain plus four scatter StandardMaterial3Ds).
- The pulse goes through a global uniform set each frame rather than a TIME-based sine in the shader: TIME is per-client uptime, and the bible wants the whole valley to beat together.
- Divided light by PI in `light()` to match Godot's own Lambert; the noon smoke shot came out at the same brightness as before (0.703 vs 0.697), which confirms it.
- No new bot behaviour: the art bible (section 7) says art checks belong in unit tests and the smoke test, not in the 8-bot loop, and a shader isn't something a player does over the network. The smoke test covers the real render.

**Didn't work.** My first `ensure_globals()` asked `RenderingServer.global_shader_parameter_get_list()` whether the name existed; in a running game that logs "should never be used outside the editor". Replaced with a static flag. The first bake test compared normals exactly; the ArrayMesh round-trip compresses normals (differences around 1e-5), so it now checks within 0.001. First tuning had shadows too light and crowns too flat; moved the ramp's dark band up (`smoothstep(0.0, 0.15)`) and nudged warmth to 0.10 and shade to 0.30.

**Tested.** 299 unit tests with Postgres (7 new in `tests/unit/test_world_emberlight.gd`: shared materials, scatter on Emberlight within budget, no textures in any variant, the heartbeat's shape and period, bake keeps vertices and darkens the base, terrain AO and gradients, the pulse parameter). 8-bot 180 s websocket bot test passed (8/8 characters persisted). Client smoke test passed (day 0.703, night 0.164; night was 0.103 before, the blue shade term and the wider ramp lift the moonlit side). Rendered noon, golden hour (0.31), midnight and a pine slope on the real renderer before and after and looked at them (copies in the project's `world/emberlight-*.png`).

**Known / not done.** Flora, node props, lamps, workbench, avatars and NodeFx are still StandardMaterial3D (part 2). Nights read green-black, not yet blue-and-ember (part 4's re-key; follow-up filed). Nothing uses the `glow` variant yet; veins come with part 2.

**Next run.** Emberlight part 2 (everything else onto the shared materials, veins on gatherables), unless #79 needs a fix.

## 2026-11-23: Emberlight part 2a, ember veins on every gatherable
**Why this.** Next in my backlog (owner direction 7, the art bible), and #79 (level-up burst) has merged, so nothing of mine was open. Part 2 as written (nodes, flora, lamps, workbench, avatars, NodeFx, a whole-world material count) is too big for one finished run, so I split it: this run moves the resource nodes and the flora onto the shared materials and adds the art bible's signature motif, ember veins on everything you can gather. Lamps, workbench, avatars and NodeFx are part 2b. What a player feels: a node you can use now *glows* (thin ember cracks beating with the valley's heartbeat), plain scenery doesn't, and an emptied node goes dark. "If it glows ember, you can use it" becomes true in the world, not just in the bible.

**Built.**
- `NodeProps` veins: a new `NodeVeins` layer, appended after every older part with its own rng (old parts, order and colours unchanged; the close-up test now checks veins come last). Ash: 3 zig-zag cracks up the trunk between the root flares and the crown; pine: 2; outcrop: 2 lines over the big stone on the faces the quartz seam leaves free; seep: a crack over 3 of the 5 rim stones running in towards the pool. Each crack is two thin boxes between points on the part's real surface (`_crack`), with the flat face along the surface normal. Live look only. `vein_cracks(kind, tier)`: one more crack per tier above 1, read from an optional node `tier` (gameplay's tier-2 nodes can just set it), capped at NodeFx's 10 shell slots.
- Veins are instance colour alpha 0 on the shared `glow` material, so the shader's `vein = 1 - COLOR.a` lights them and the heartbeat swells them. No new material per kind.
- Node layers on Emberlight (`NodeProps.layer_material`): bark, stones, stumps and close-up detail on the forest's `solid`; pine tiers on its `foliage`; ash leaves on a named `foliage/node_ash_leaf` (their night glow is a different number from the decorative leaves', set by `Lamps.apply_glow` as before); sap pools on a named `glow/sap` (whole-surface glow, now beating with the heartbeat); veins on `glow`. Meshes baked with AO like the scatter's.
- Flora (birches, marks, boulders, moss, flowers) all on `solid` with baked AO.
- Materials after this: 8 named Emberlight materials (solid, solid/terrain, foliage, foliage/ash_leaf, foliage/node_ash_leaf, glow, glow/sap), down from 7 StandardMaterial3Ds for nodes plus 7 for flora.

**Decisions.**
- Veins as separate thin boxes, not vertex alpha painted into the trunk/stone meshes: these meshes are 5 to 8 segments round, so a per-vertex vein would smear into a whole glowing face. Boxes give a crisp crack and cost 6 to 10 instances per node in one MultiMesh (about 3,000 instances, one draw call, no shadows).
- Named materials configure themselves once (a `configured` meta), because `layer_material` is called again by tests and by build, and resetting `emission_energy` there would undo `apply_glow` (my first test caught exactly that: sap stuck at its day value).
- Birch crowns stay on `solid`, not `foliage`: the sway is in mesh units, flora uses unit meshes scaled to size, so a birch crown would slide off its trunk. Follow-up filed.
- Vein energy 1.4 instead of the shader's 2.0: at 2.0 the noon render clipped veins to white; 1.4 reads ember orange-gold by day and bright at night.
- No new bot behaviour: art bible section 7 says art checks live in unit tests and the smoke test, not the 8-bot loop, and veins change nothing on the network.

**Didn't work.** First draft had `var ak := a + [...][k]` (an untyped array index), which GDScript can't infer; typed it. The sap pool on Emberlight lost its clearcoat gloss (the shader has no specular) and reads a flatter yellow at noon than before; same brightness, compared side by side with main. Follow-up filed.

**Tested.** 340 unit tests with Postgres (7 new in `tests/unit/test_world_ember_veins.gd`: every live node has veins and every emptied one none, tier 2 has more, veins sit on the bark / stone / rim stone surface, deterministic, every node and flora layer on Emberlight within budget, baking keeps vertices, `apply_glow` still reaches the node leaves and the sap). The existing vertex-by-vertex camera-solid test covers the veins too (it walks every layer). 8-bot 180 s websocket bot test passed (9/9 characters persisted, fun metrics unchanged in kind: median first reward 8.5 s). Client smoke test passed (day 0.703, night 0.167, same as part 1). Rendered an ash, outcrop, seep and pine close up at noon and midnight on the real renderer and looked at them.

**Known / not done.** Lamps, workbench, avatars and NodeFx's bits are still StandardMaterial3D (part 2b). No whole-world material-count test yet (needs part 2b).

**Next run.** Emberlight part 2b (lamps, workbench, avatars, NodeFx onto the shared materials, and the whole-world material count), unless this PR needs a fix.

## 2026-11-23: chunked instancing (Emberlight part 3, qa's render-budget request)
**Why this.** Requests from other streams come first, and qa's render-budget request (primitives 1.98M at the spawn shot against the art bible's 600k) is the top open one; it is also Emberlight part 3 in my backlog. Nothing of mine was open (#88 ember veins merged). What a player feels: smoother frames, especially on the integrated-graphics laptops the art bible targets, with the same forest in the same places.

**Measured first.** On main the spawn shot was 1,998k primitives, 206 to 213 draw calls, 18 materials (part 2a already brought materials from 30 to 18). The scene is ~600k triangles; the frame was 3.3x that because every scatter and flora layer was one MultiMesh spanning the whole 512 m world, so the camera could never cull it and each of Godot's 4 default shadow cascades drew all of it again.

**Built.**
- `game/procgen/chunks.gd` (`Chunks`): `split()` groups a layer's [Transform3D, Color] instances by area; `build()` makes a Node3D named after the layer with one MultiMeshInstance3D per chunk (`c<x>_<z>`), all sharing the layer's mesh and material. Each chunk node sits at its chunk's centre and holds its instances relative to it, so "distance to the chunk" means the same to every renderer.
- Per-layer draw distances from the art bible (flowers 90 m, small props 160 m, trees 300 m), padded by half a chunk diagonal (`cut_of`) so nothing closer than its layer's range ever disappears.
- Chunk sizes per layer: trees 128 m, small props (rocks, moss, birch marks, mossy boulders) 64 m, flowers 32 m.
- No shadows from flower stems and blooms (as before), birch marks and moss.
- The sun uses 2 shadow cascades (`SHADOW_PARALLEL_2_SPLITS`) instead of 4.
- The scatter forest (`WorldBuilder._props`, new `scatter_layout()`) and every flora layer (`Flora.build`) use it. `Lamps.apply_glow` finds the shared material through the first chunk (`Chunks.first_geometry`).
- Ceilings in `tests/client_smoke/render_baseline.json` lowered as qa asked: primitives 2.05M to 650k, materials 30 to 20; baseline reset (with the reason in its `_doc`).

**Result (spawn shot, llvmpipe).** Primitives 2.0M to 613k night / 587k noon (-69%). Draw calls 213 to 273 night / 206 to 257 noon (still under 300). Materials 18. Screenshots side by side with main: same trees, rocks, lamps; shadows a touch softer with 2 cascades.

**What I tried.** 64 m chunks everywhere with 4 cascades: 716k primitives but 342 draw calls (over 300). 64 m with 2 cascades: 525k primitives (under target!) but 326 draw calls. 96 m: 553k / 266. 128 m: 614k / 236, but then a rock 70 m away could vanish because the cut is measured to the chunk, which is why the small layers got smaller chunks and the cut got padded. Every chunk is a draw call in the main pass and in each shadow cascade, so chunk size is a straight trade between triangles and draw calls; I kept draw-call headroom for chunking the node props next.

**Didn't work.** My first "never moves a prop" test read the instances back from the MultiMesh; the headless dummy renderer doesn't keep MultiMesh data (every transform reads back as identity), so the test checks the split the build is made from instead (every instance, same transform and colour, input order within each chunk, chunk node at its centre with the right count).

**Probably also fixed.** Flowers had one `visibility_range_end = 90` on a world-wide MultiMesh, which Godot measures from one point for the whole layer (the world centre), so wildflowers far from the middle of the valley were likely never drawn. Now each 32 m patch is judged on its own. Not verified with a far-away render, so not in the changelog.

**Tested.** 363 unit tests with Postgres (6 new in `tests/unit/test_world_chunks.gd`: split keeps every instance in its chunk; scatter and flora chunked without moving a prop; shadows as set; ranges follow the art bible; the padded cut covers a far-corner prop; night glow still reaches the chunked ash crowns). Client smoke test passed with the new ceilings. 8-bot 180 s websocket bot test: see the PR. No new bot behaviour: art bible section 7 keeps render checks in unit tests and the smoke test, and chunking changes nothing on the network.

**Known / not done.** Node props are still world-wide MultiMeshes (165k triangles, the biggest piece left; follow-up filed with the id-to-chunk mapping it needs). No mid-distance tree mesh yet. Draw-call headroom is 27 at night.

**Next run.** Chunk `NodeProps` (gets the spawn shot under 600k), unless this PR needs a fix.

## 2026-11-23: skill badges (Milestone 1 part 3, first half)
**Run start.** #92 (chunked instancing) had a merge conflict with main in my backlog's "Requests from other streams" (client's new Graphics quality request landed next to my qa line). Merged main in, kept both lines, unit tests and the 8-bot test passed locally, pushed; auto-merge was already on.

**Why this.** Two open PRs are allowed, so I took a new item that doesn't need #92's code. Emberlight 2b touches `lamps.gd`, which #92 also edits, and client's `Quality.flora_density()` request edits the flora placement #92 rewrote, so both wait for #92 to land. Tier-2 node props wait on gameplay (no `tier` in `ResourceNodes` yet). Skill icons are Milestone 1, unblocked (`Skills.ORDER` is on main) and touch nothing #92 does. Fun in one sentence: when a level-up toast or the skills window says Quarrying, the player sees a slate badge with a pick and knows which road moved before reading.

**Built.** `SkillIcons` (`game/procgen/skill_icons.gd`): one round badge per skill (felling green disc with a stump, a stone axe and an ash leaf; quarrying slate-blue with a pick over a seamed stone and chips; tapping deep ember-red with a glowing drop falling from a spout into a bowl, the only badge with a halo; toolcraft warm wood with a hammer across the bench plank and a spark). `texture(skill)` (cached, 64 px default), `image`, `shapes`, `tint`, plain star badge for unknown ids. Drawn through a new public `ItemIcons.rasterise(shapes, size)` (ItemIcons.image now calls it; output unchanged, its tests still pass), so items and skills share one hand. Preview: `/mnt/project-files/world/skill-badges.png`.

**Decisions.**
- Badges are always round discs, unlike the free-standing item icons, so "a road I'm on" and "a thing I carry" never look alike.
- Colour does the work at 24 px (the unit test checks the mean colours are apart); the emblem does it up close.
- No bot behaviour: art bible section 7 and the director's follow-up say art checks live in unit tests, and icons change nothing on the network.
- SkillIcons calls ItemIcons' underscore shape helpers (`_circle`, `_poly`, ...) rather than copying them; GDScript allows it and one copy is better than two.

**Didn't work.** First draft's felling axe head was too small to read next to the stump; enlarged it after looking at the preview.

**Tested.** Unit tests all pass (6 new in `tests/unit/test_world_skill_icons.gd`), 8-bot 3-minute websocket bot test, client smoke test.

**Known / not done.** Item icons for tier-2 materials and new tools wait on gameplay adding them (the item-icon test fails if an `Inventory.ITEMS` id has no icon, so it will be caught). The client has to show the badges (request filed in its backlog).

**Next run.** If #92 has landed: Emberlight part 2b, then client's `Quality.flora_density()` request. Otherwise fix whichever of my PRs needs it.

## 2026-11-23: tier-2 node props (old ember ash, rich stone seam)
**Built.** Milestone 1 part 2, built ahead of gameplay's tier-2 node data (not on `main` yet; the director said to build behind a `tier` field). `NodeProps.parts()` now draws a node with `"tier": 2` and kind `ash` as an **old ember ash** (trunk 1.5x wider and 1.25x taller in older grey bark, two gnarled boughs leaning out at ~40 degrees into two side crowns, a 1.3x main crown and a top knot in a brighter gold `OLD_ASH_LEAF`, five glowing ember pods hanging under the crown rim on the sap glow layer, five long root flares, five bark fissures, four vein cracks; felled: a wide stump with a pale cut), and kind `stone` as a **rich stone seam** (four stones in deep plum-grey `RICH_STONE`, a 3 m by 2.3 m big stone, ten gold `RICH_FLECK` flecks scattered over it, three ember crystals leaning out of its top, three vein cracks; worked out: five dark rubble stones). Both reuse the tier-1 layers and materials, so no new material and no new draw calls. Tier is read once by `NodeProps.tier_of(node)` (kinds without a tier-2 look, pine and seep, stay tier 1 but keep the extra veins). The tier rides through: `solid_columns(kind, scale, tier)` and `inside_solid` (own columns `ash:2`, `stone:2`, so the action camera is right with no client change), `layout()` slots carry `tier`, and NodeFx's hit bits start under the bigger crown / outside the bigger stone (gold leaves from an old ash, gold flecks from a rich seam). Tier-1 nodes are unchanged part for part (unit test).

**Decisions.**
- Landmark by silhouette by day (7 m tall, 3 m crown radius, gold against the orange forest) and by glow at night (pods and crystals on the sap glow material, which already beats with the heartbeat). No extra light: lights are the expensive thing in the render budget.
- No item icons: gameplay hasn't named the two material ids yet, and guessing ids would leave dead icons. The icon unit test fails the moment an id has no icon, so whoever adds them can't miss it; follow-up in my backlog.
- No bot behaviour: tier-2 nodes don't exist in the world yet, and the director moved art checks to unit tests. Once gameplay's data lands, `world_resource_nodes` will lay them out like every other node.
- Wrote the request to gameplay (`tier: 2` on `ash`/`stone` entries, keep ~4 m from other nodes, tell me the item ids).

**Didn't work.** First `RICH_STONE` (0.45, 0.39, 0.45) read black under Emberlight's ramp at noon; (0.62, 0.52, 0.62) went cartoon purple; settled on (0.58, 0.50, 0.57). A local variable `tier` clashed with the pine loop's `for tier in 4` (GDScript forbids shadowing in one function); renamed to `look_tier`.

**Tested.** New `tests/unit/test_world_tier2_props.gd` (9 tests: bigger than tier 1, glow and colours, every vertex inside the tier-2 columns for 60 nodes, columns snug, `inside_solid` reads the tier, highlight-shell and vein budgets per look, veins and flecks on the surface, tier 1 untouched, layout and hit bits carry the tier). Full unit suite with Postgres, 8-bot 180 s websocket bot test, client smoke test. Preview rendered on llvmpipe at noon and night (tier-2 nodes swapped in near the meadow by a scratch script): `/mnt/project-files/world/tier2-node-props.png`.

**Next run.** If gameplay's tier-2 data has landed: icons for the two materials, then look at the real spots from the meadow. Otherwise Emberlight part 2b (lamps, workbench, avatars, NodeFx).

## 2026-11-23 — flora follows the Graphics quality (ws/world/flora-quality)

**Picked** client's request (art bible section 7): read `Quality.flora_density()` when placing flora. Requests come before the top backlog item, and tier-2 icons are still blocked (gameplay hasn't added the tier-2 item ids to `Inventory.ITEMS`). Fun: on an old laptop the grasslands no longer stutter on Low, and the setting answers on the spot when you change it.

**Also fixed red `main`.** My own #100 put four tier-2 colours as literals in `node_props.gd` (15, allowance 11), so qa's art lint failed on `main` after it landed. Moved `OLD_ASH_LEAF`, `OLD_ASH_BARK`, `RICH_STONE`, `RICH_FLECK` into `palette.gd` (same values, the NodeProps constants now point at them). `node_props.gd` is back to exactly 11; no allow-list change needed. Lesson for next run: run the full unit suite *after* the last colour tweak, not before.

**Built.**
- Only the wildflowers thin (`Flora.THINNED`: `FlowerStems`, `FlowerBlooms`). They are most of flora's triangles and have no camera solid. Birches and boulders stay whole on every level: hiding one would leave an invisible wall for `WorldSolids`, and they are landmarks.
- Each flower patch has a stable `Flora.rank()` in 0..1 from its position. `ranked_layout` puts the flower instances in rank order, so inside every chunk the low ranks come first and density is a single `MultiMesh.visible_instance_count` per chunk: no rebuild, no extra draw calls, and a patch is shown or hidden whole (never a stem without its bloom). Each chunk keeps its ranks as `meta("ranks")`.
- `Flora.apply_density(node, d)` sets it; a tiny `QualityWatch` child polls `quality_density()` every 0.5 s, so a Settings change applies live, and the world-build-before-settings order in `client.gd` doesn't matter.
- `quality_density()` loads `res://client/quality.gd` by path rather than naming `Quality`, because the server export leaves `client/` out and procgen scripts must still parse there. Falls back to 1.0.
- `motes_scale()` isn't read yet: there are no motes until part 4. Noted as a follow-up.

**Tested.** New `tests/unit/test_world_flora_quality.gd` (5 tests: rank stable and ~half under 0.5, `shown_count`, ranked layout keeps every part in rank order, Low draws about half with whole patches and birches untouched, the watcher follows `Quality.level` both ways). Full unit suite with Postgres (420 pass), 8-bot 180 s websocket bot test (passed), client smoke test (passed; Medium shot unchanged: night 613k primitives, 273 draw calls). No new bot behaviour: this is a client-only render setting, nothing on the network, and qa's art lint forbids procgen in new behaviours.

**Not measured.** The Low spawn shot: the smoke test only renders Medium. By counting, Low hides ~2,600 of the 5,300 flower instances (about 45k triangles in the scene, more where the flowers are near spawn). Follow-up filed.

**Next run.** Tier-2 icons if gameplay's item ids landed; otherwise Emberlight part 2b (lamps, workbench, avatars, NodeFx + the material-count test).

## 2026-11-23: tier-2 material icons (ws/world/tier2-material-icons)

**Picked** the top backlog item's last piece: gameplay's tier-2 nodes are on `main` and named their materials (`ember_heartwood`, `veinstone`, parked in `Inventory.NEW_ITEMS` until they have icons). A request from another stream, so it comes first. Fun: the first rare thing a player levels toward now pops up in the toast and the pack as its own glowing prize instead of a grey cloth bundle.

**Built.** Two recipes in `ItemIcons`. Ember heartwood: one fat log in the old ash's grey bark (`Palette.OLD_ASH_BARK`), a thin ember crack along it, the cut end's rings around a live coal (`EMBER` with an `EMBER_CORE` centre and a warm halo), and two gold leaves from the old crown (`OLD_ASH_LEAF`). Veinstone: a wider, rounder chunk in `RICH_STONE`, a darker top facet, a zig-zag ember vein with a small halo and a hot core line, and four `RICH_FLECK` gold flecks. `tint()` gives them the old ash's gold and the fleck gold. Every colour comes from `Palette`, so `item_icons.gd` adds no literals for the art lint.

**Decisions.**
- One log, not two: ash wood is two logs, so a single fatter log reads "different and denser" even at 24 px.
- Both glow (unlike stone and pine): the rich seam and old ash glow in the world, and the glow is the "this is worth more" signal.
- `test_world_item_icons` now runs its checks over `ITEM_ORDER` plus `NEW_ITEMS` (deduplicated), so it already covers the move gameplay makes next. New test: each tier-2 icon has more warm pixels than its tier-1 cousin and its own tint.

**Didn't work.** The first heartwood log ran to x 0.99 and clipped (the margin test caught it); shortened it and shrank the cut end.

**Tested.** Unit suite with Postgres (428 pass), 8-bot 180 s websocket bot test (passed, 8 of 8 levelled), client smoke test (passed). Icon sheet checked by eye at 128 px next to ash wood, stone and sap. The night spawn shot is now 624k primitives (613k last run): the tier-2 ring is on `main` now. Chunked `NodeProps` is still the fix; follow-up filed.

**Next run.** Emberlight part 2b (lamps, workbench, avatars, NodeFx, the material-count test), unless a PR of mine needs fixing.

## 2026-11-23, run: ember tool icons (ws/world/ember-tool-icons)

**Picked.** Requests from other streams come first: gameplay asked for icons for `ember_axe` and `ember_pickaxe` (Toolcraft 5). Until now they showed the cloth fallback bundle, which made the biggest crafting reward so far look like junk. Fun: the moment you craft your first ember tool, the pack and the craft toast show a coal-black head with a glowing edge next to your old stone one, so the upgrade reads at a glance.

**Built.** Two recipes in `ItemIcons`, using the stone tools' silhouettes (same hand, same handle angle) so they read as the same tool, upgraded: an `ember_axe` with a broader, bearded coal head, smoulder veins and an ember-hot cutting edge with a small halo, and an `ember_pickaxe` with coal prongs whose tips burn. Both tint toasts `Palette.EMBER`. Every colour comes from `palette.gd` (`SOOT` lightened for the head, `SMOULDER`, `EMBER`, `EMBER_CORE`), so the art lint's allowance for `item_icons.gd` doesn't move. `COAL` is a `static var` because `lightened()` isn't allowed in a const (and `SOOT * 1.6` would also have scaled alpha).

**Didn't work.** First pass: the axe edge's halo (radius 0.26) reached the right border (alpha 0.21, test fails over 0.15); 0.18 keeps it in. The pick's hot tips were too small to count as glowing at 48 px (9 warm pixels); bigger tip triangles and a core line fixed it.

**Tests.** `test_world_item_icons::_all_items` now also covers any `Inventory.UNDRAWN` item that `ItemIcons` has drawn, so the margin and distinctness checks run on the ember tools today, before gameplay moves them into `ITEMS`. New test: each ember tool has its own icon, a halo, more warm pixels than its stone twin and its own tint, and every `UNDRAWN` item is drawn. No new bot behaviour: per art bible section 7 and qa's art lint, art checks live in unit tests and new behaviours must stay art-free. Preview sheet: `/mnt/project-files/world/ember-tool-icons.png` (project files).

**Main was red when I started.** `test_client_skills_window::test_goal_skips_unlocks_not_in_the_world_yet` fails on `main` (bb48678): it expects Toolcraft 5 to stay a "coming soon" unlock, but the ember tools are real now, so the goal picks it. That is client's test (and qa may fix red main), not a world path, so I left it alone; this PR's auto-merge waits until it is fixed. Every other unit test passed.

**Next run.** Emberlight part 2b (lamps, workbench, avatars, NodeFx, the material-count test), unless a PR of mine needs fixing.

## 2026-11-23, run: Emberlight part 2b, everything on the shared materials (ws/world/emberlight-everything)

**Picked.** The top backlog item (tier-2 props) was finished by #100 and #108, so I ticked it; next was Emberlight part 2b: lamps, workbench, avatars and NodeFx on the shared materials, plus the material-count test over the whole built world. Folded in qa's small request to move the skill badge colours into `palette.gd`. Fun: the wanderers, lanterns and bench were the last things still drawn in flat plastic StandardMaterial; now everything a player looks at, starting with their own character, is painted in the same warm light and cool blue shadow as the forest, and the lanterns breathe with the valley.

**Built.**
- `Emberlight.paint(mesh, color, ao, curve)`: like `bake()`, but the vertex colours also carry a colour (stored linear) and an alpha (vein mark). `bake()` now calls the same core with a white tint (as `Vector3.ONE`: `Color.WHITE` would trip the art lint, and `Color.WHITE.srgb_to_linear()` came out 0.996, which broke `test_bake_keeps_vertices`).
- Lanterns: wood and iron on `solid` with baked meshes; glass on one named `solid/lantern_glass` (FLAME emission, `pulse_depth` 0.12 so it breathes gently). The bench lantern shares it, so `Workbench.GLASS_DAY/NIGHT` now equal Lamps' (bench night glass 1.5 -> 1.3; side by side they now match).
- Workbench: all layers on `solid` with baked meshes; the highlight shell still uses NodeFx's rim shader.
- Avatars: each part's mesh painted with its colour and `PART_AO` 0.18, all on `Emberlight.material("solid")`. Before, every part of every avatar made its own StandardMaterial3D (~17 per player).
- NodeFx hit bits: on the veins' shared `glow` material. The old private shader glowed `colour * glow`; now glow goes in instance alpha as a vein, `vein = sqrt(glow / 2)` so the brightness at rest matches (2 x vein^2). Glowing bits now glow ember-orange rather than their own colour (sap droplets and gold flecks were already that colour; ash leaves at 0.25 are faint either way).
- Skill badges: 7 colour literals moved into `Palette.SKILL_*`, `BADGE_INK`, `BADGE_STAR`.

**Decisions.** NodeFx's highlight rim shell stays on its own rim shader: it is an additive overlay, not a surface, and the art bible's budget is about surfaces. Water stays on its own StandardMaterial3D until "gentle animated water". The material-count test builds the real world headless, which logs `Parameter "m" is null` from the dummy renderer for each MeshInstance3D (terrain, water); the test declares that with `expect_error` rather than counting a hand-picked subset. Avatars can't be built headless cleanly for the same reason, so their test checks `material()`, the painting and that `avatar_builder.gd` makes no materials.

**Tested.** Unit suite with Postgres (468 pass), client smoke test (passed: world materials 18 -> 11, night 625k primitives and 277 draw calls, about where main is), 8-bot 180 s websocket bot test (see PR). Ceiling for materials lowered to 12 in `render_baseline.json`. No new bot behaviour: a render-only change, and qa's lint forbids procgen in new behaviours.

**Next run.** Chunked `NodeProps` (the night spawn shot is still 625k, over 600k), or part 4 (golden-hour light and motes), whichever the director has on top.

## 2026-11-23, run: chunked resource-node props (ws/world/chunked-node-props)

**Picked** the top backlog item: chunk `NodeProps`, the biggest thing left in the render budget (night spawn shot 625k primitives against the art bible's 600k). Fun: a lighter frame is smoother camera turns and swings on the machines that were struggling, and it leaves room for part 4's ember motes without going over budget. Nothing on screen changes (before/after noon and night shots are identical by eye: `/mnt/project-files/world/chunked-node-props-*-before-after.png`).

**Built.**
- Each node layer is now a Node3D of chunk MultiMeshes ("c<x>_<z>", like `Chunks.build`). Every part goes in the chunk of its *node's* position, so a tree is never split, and the grid is shifted half a chunk so Spawn Meadow sits in the middle of chunk (0, 0) rather than on the corner of four.
- `layout()` is unchanged (world-space parts indexed by layer and index), so `parts`, slots, NodeFx's shells and every test that reads the layout still work. `build()` records where each part went (meta `where`); `NodeProps.put_xform` / `part_xform` / `part_chunk` / `part_shown` address a part by layout index. NodeFx's shake now writes through `put_xform`.
- Each chunk counts how many of its parts are shown; a chunk with none is hidden. Today that means every stump chunk is off until something is felled. Before, the hidden stumps still cost 20k degenerate triangles in the main pass and both shadow cascades.

**Measured, not guessed** (client smoke test spawn shot, night; main was 277 draw calls / 625k primitives):
- 128 m chunks for every layer: 345k primitives but 335 draw calls (over 300).
- 256 m for every layer: 388k / 302.
- Kept: close-up layers (detail, veins) 128 m with 60 m / 110 m ranges, stones and stumps 256 m with 220 m, tree parts and glows whole: **461k / 286** (noon 435k / 270). Chunks pay where a layer is heavy and short-ranged; the tree layers are light and seen from far off, so chunking them only bought draw calls.
- Primitives ceiling in `render_baseline.json` lowered 650k -> 500k, baseline reset.

**Tested.** Unit suite with Postgres (481 pass; new `test_world_node_chunks.gd`: every part drawn once in its node's chunk, spawn centred, ranges and whole layers, stump chunks hide and come back, gather feedback still runs on chunks). Client smoke test passed. 8-bot 180 s websocket bot test (see PR). No new bot behaviour: render-only, nothing on the network, and qa's lint forbids procgen in new behaviours.

**Next run.** Emberlight part 4 (golden-hour light, night re-key, motes); draw-call headroom is 14, so motes must be one pooled MultiMesh.

## 2026-11-23, run: Emberlight part 4, golden hour, blue nights and ember motes (ws/world/golden-hour-motes)

**Picked** the top unblocked item: Emberlight part 4, with the "nights read green-black" follow-up folded in as the director asked. Fun: the valley now *feels* like a time of day. Mornings and afternoons are long and golden, nights are moonlit blue with the ember things glowing against it, and from dusk on, sparks rising over every ember ash and seep tell you at a glance where the gatherable things are.

**Built.**
- `SkyClock.KEYS` re-keyed (7 keys, was 6). Warm keys now reach up to sun height 0.65 (`Palette.GOLDEN_LIGHT` at 0.30, a warm key at 0.65), so most of the day has warm light; noon is a short, still-warm top of the arc. `WorldClock` (gameplay's) is untouched: the "golden-hour bias" is in the colours, not the sun path, so the server's phases never disagree with the sky. Night keys use new `Palette.MOONLIGHT` (blue key) and `NIGHT_HAZE` (blue fog, never black); moonlight energy 0.22 -> 0.26.
- `ember_night`, a second Emberlight global (0 by day, 1 at night, `SkyClock.night_amount`, eases in through the blue hour after the lamps are lit). The shader drains only *green* paint by it (weighted by g - r) and adds `SHADE` to the shadows, so grass and pines go moonlit blue while ash crowns, bark and lanterns keep their warmth. My first try drained everything and the ash crowns went mauve; the green weighting fixed it.
- Height haze: `fog_height` 3 m, `fog_height_density` 0.035 (Godot's height fog is `1 - exp((y - h) * d)`, independent of distance: about 7% on the meadow floor, 17% at the lake surface, so it reads as haze in the hollows without hiding anything close), plus `fog_sun_scatter` 0.22 so looking into a low sun lights the haze gold. Colour still comes from SkyClock's fog key (HAZE by day, NIGHT_HAZE by night).
- `Motes` (`game/procgen/motes.gd`): one MultiMesh of billboard quads anchored on every gatherable ember ash and ember-sap seep (177 anchors). Rise, drift, twinkle, shrink and fade are all in the vertex shader from TIME and per-instance custom data, so the CPU does nothing per frame. Ash motes start in a ring just outside the crown (2.0 to 2.8 m x scale; the crown is 1.9 m) because motes inside the crown were hidden by the leaves; tier-2 ashes get a plume twice as tall and a wider ring. The pool is built at High (9 per anchor) and interleaved so any prefix covers every anchor; `Quality.motes_scale()` only changes `visible_instance_count` (Low 3, Medium 6, High 9), live on every repaint. Hidden by day (no draw call), one draw call at dusk and night, no shadow pass, `fog_disabled` (fog greyed them).
- Tuning notes: an emission energy of 3 made the filmic tonemapper wash the sparks to a pale grey-green; 1.4 keeps them ember gold. A hard `spot * spot` dot was too small to read at 15 m; a smoothstep halo with an `EMBER_CORE` centre reads as a spark.

**Screenshots** (client, spawn view; motes close up): `/mnt/project-files/world/emberlight4-{golden,dusk,night,noon}-before-after.png`, `/mnt/project-files/world/emberlight4-motes-night.png`. Noon is nearly unchanged by design; golden hour is warmer; night is the big change.

**Decisions.** Motes anchor on gatherable nodes only, not the decorative scatter ashes: "if it glows ember, you can use it", and sparks are a signal, so they only rise over things you can gather. They don't yet know a node is depleted (follow-up). The motes material makes 12 world materials, exactly the ceiling; noted in qa's backlog.

**Tested.** Unit suite with Postgres: everything passes except `test_qa_fun_metrics::test_behaviours_send_play_requests_through_the_bot`, which is red on `main` too (gameplay_roster_v5, fixed by open PR #125, not mine). New `test_world_golden_hour.gd` (9 tests: golden most of the day, warm noon, blue moonlight and haze, night paint in the shader, height haze and sun scatter, motes anchored on ember things only, quality counts and prefix layout, rise and fade maths match the shader, node hidden by day and live quality). Client smoke test passed: night 289 draw calls / 463k primitives (main 286 / 461k; the motes are one draw call and ~3k triangles), noon 272 / 435k, 12 world materials (ceiling 12), day/night luminance 0.712 / 0.214. 8-bot 180 s websocket bot test passed (first reward median 7.3 s, 8 of 8 bots levelled). No new bot behaviour: render-only, nothing on the network, and qa's lint forbids procgen in new behaviours.

**Next run.** The level-up burst readable by day from 45 m (director's note on that item), or moving the `world_*` art checks out of the bot loop.

## 2026-11-23, run: level-up burst readable by day (ws/world/level-up-daylight)

**First, #127 (golden hour and motes).** Its CI run was red only because `main` was red at the time (`gameplay_roster_v5.gd` called a `c2s_` RPC directly; fixed on main by #125). Merged `main` in (one conflict in `docs/workstreams/qa.md`: kept both request lines), re-ran unit tests (526), the 8-bot bot test and the client smoke test locally, all green, pushed. Auto-merge stays on.

**Fun.** When anyone levels up at noon you now see it from across the meadow: before, a level-up 45 m away by day was invisible (I rendered it; the column was lost against the bright grass and haze).

**Built.** `LevelUpFx` reads the sky clock when a burst starts (`sky_daylight()`, from `DayNight.now_fraction()`, so the `AIMMO_TIME_OF_DAY` pin works) or takes an explicit `day` in `play(avatar, seed, day)`. The client call is unchanged.
- `column_at(t, day)`: up to 1.5x wider and 1.2x taller by day; the shader's `day` uniform raises its opacity floor and uses less of the pale core, so it reads deep gold instead of a ghost.
- `beam_at(t, day)`: a slim 24 m beam that shoots up in 0.35 s and fades by 1.6 s; full by day, 0.35 strength at night. It is instance 1 of the column's MultiMesh, strength per instance in custom data, so **no new draw call or material**.
- `column_now` / `beam_now` hold what the last frame drew.

**Didn't work.** First tests read the MultiMesh's instance transforms: the headless dummy renderer doesn't store MultiMesh instance data at all (every transform reads as identity), so those checks were silently meaningless. The old bot behaviour's spark checks have the same blind spot (they "pass" on identity transforms). Tests now read `column_now` / `beam_now` and the pure functions. Next run, a cheap fix for the spark checks: keep the last spark transforms on the node too.

**Looked at.** Rendered main and this branch side by side at noon and midnight from 45 m and 15 m (llvmpipe). At noon from 45 m main shows nothing; the branch shows a gold beam over the treetops. Widened the beam 0.22 -> 0.3 m after the first look; it was a hairline in the haze. Copies in the project files (`world/level-up-daylight-*.png`).

**Tested.** Unit suite with Postgres (520 pass; 3 new in `test_world_level_up_fx.gd`: day column wider/taller with the same timing and bounded, beam height/strength/timing by day and night, `play` reads the pinned sky and an explicit day wins, beam in the column MultiMesh). Bot behaviour `world_level_up_fx.gd` alternates day and night bursts and checks the beam passes 20 m by day and is gone by `BEAM_TIME` (11 day beams per bot). Client smoke test passed. 8-bot 180 s websocket bot test: first run failed once on `gameplay_gather_v3` ("gather ended moved while standing still", bot 2 at (73, 10, -15)), nothing this change touches; the rerun passed. Flagging it as a possible gameplay flake.

**Next run.** Golden hour (#127) should land on its own. Then the milestone-level variant needs the client to pass the level; otherwise the art checks out of the bot loop, or the gather-swing impact puff.

## 2026-11-23, run: art checks out of the bot loop (ws/world/art-free-bots)

**First, #133 (level-up by day).** It had a merge conflict in this devlog only (two entries from parallel runs); merged `main` in, kept both entries in date order, unit suite passed (542), reran the 8-bot test, pushed.

**Picked** the top backlog item: move the `world_*` art checks out of the bot loop (director, art bible section 7). Fun: none a player sees directly; it buys faster, steadier bot runs for every stream (8 bots no longer each build props, bits, lanterns, avatars and icons while "playing"), and the checks got stronger, so fewer broken looks reach players.

**Built.**
- `tests/unit/test_world_walked_world.gd` (10 tests, ~3 s): every resource node's live and depleted look on its spot, every node's close-up detail inside its solid columns, a hit on every node (shell, shake, bits stay near and vanish), 3000+ client camera looks on a 6 m grid round the meadow and a step off each node there (with nodes and decoration, never inside a solid, decoration never lengthens the arm), the lamps and the bench lantern over a whole day of `WorldClock` in 10 s steps, the bench highlight in and out of range, 300 avatar seeds (limbs, pack and bedroll, finite colours), every flora spot, the sky over 1001 fractions, 24 px icons for every item plus an unknown id. Mutation-checked: changing a detail count, the back-part count or the night threshold makes three of them fail.
- `tests/bot_test/behaviours/world_ground_truth.gd`, art-free: every position in every snapshot stands on `Terrain.height` (the server clamps to it, so a gap is a desync), the server clock never runs backwards, something gatherable within 40 m of every spot bots reach, bench passes, distinct appearance seeds.
- Removed 11 behaviours: avatar_limbs, bench_lantern, closeup, day_night, deco_solids, flora, gather_fx, item_icons, lamps, resource_nodes, workbench. Asked qa (their backlog) to drop them from `art_lint_allow.json`.

**Decisions.** Whole-world unit tests over "wherever bots walked": the bots only ever touched the ~60 m round spawn, so the unit tests see more. `world_level_up_fx.gd` stays: open PR #133 edits it and touching it here would conflict; follow-up added. The two camera stats (`camera_inside_*`) went with their behaviours; nothing read them in CI.

**Next run.** `world_level_up_fx.gd` once #133 lands, else the gather-swing impact puff.

## 2026-11-23, run: ember lantern icon (ws/world/ember-lantern-icon)

**Open PRs.** None: #133 and #135 both landed.

**Picked** gameplay's request at the top of "Requests from other streams" (requests come first): draw `ember_lantern` in `ItemIcons` for Toolcraft 3's "Bench sense" recipe, and stop `test_ember_tools_are_drawn_and_burn_hotter_than_stone` failing on any undrawn `Inventory.UNDRAWN` id. Fun: when gameplay ships the lantern, the craft toast and pack slot show a proper lantern on day one, not the grey cloth bundle that says "unfinished".

**Built.**
- `ItemIcons` "ember_lantern": stone foot, two pine posts, stone roof with a carry loop, ember glass with a smoulder-tipped flame inside and a warm halo. Upright and boxy so it reads apart from the slanted torch and the wide campfire at 32 px. Tint `Palette.EMBER_CORE`. No new colour literals (only palette and existing icon constants), so qa's art-lint allowance for `item_icons.gd` is unchanged.
- `test_world_item_icons`: the UNDRAWN loop is gone (only the ember tools are checked, as asked). A `DRAWN_AHEAD` list puts the lantern through every icon check (own icon, fills the square, no clipping, distinct from every other icon); a new test checks it glows and its silhouette differs from the torch and campfire.

**Didn't work.** First draft had a pine crossbar over the glass; at 128 px the crossbar plus the triangular flame read as a letter "A". Dropped the bar and gave the flame a lopsided tip.

**Decisions.** No bot behaviour: the item doesn't exist yet, so players can't do anything new, and icons are art checks, which belong in unit tests (art bible section 7, last run's art-free bots).

**Next run.** The `world_level_up_fx.gd` move into unit tests (#133 has landed), or the gather-swing impact puff.

## 2026-11-23, run: level-up burst checks out of the bot loop (ws/world/level-up-checks-unit)

**Open PRs.** None of world's open.

**Picked** the top unticked backlog item: move `world_level_up_fx.gd`'s checks into `test_world_level_up_fx.gd` now that #133 has landed. Fun: nothing new on screen; it keeps the loudest moment of Milestone 1 (the level-up burst) looking right by checking it far harder than the bots did, and takes one more art build out of every bot, so bot runs for every stream are lighter. Plumbing, kept small.

**Built.**
- `LevelUpFx.sparks_now`: the positions of the sparks the last frame actually drew. Last run found the dummy renderer reads MultiMesh transforms back as identity, so the old bot spark checks passed whatever the sparks did. Mutation-checked: pushing sparks out to 2.6 m fails the new tests (and the old pure one).
- Three unit tests: 64 bursts frame by frame (day and night, a restart mid-burst on a quarter of them, at the meadow, 11 node spots and the 8 tier-2 landmarks), the burst lasting `DURATION` at 15/30/60/144 fps with the beam clearing 20 m, and `sparks_now` matching what's drawn.
- `world_ground_truth.gd` keeps the network part: our own `s2c_level_up` names a real skill at a level above the last one (and at most `Skills.CAP`), and every `s2c_level_up_seen` is about a player we have a snapshot position for (so the client has an avatar to burst over) within `VIEW_RANGE` + 30 m. Removed `world_level_up_fx.gd`.

**Found.** Bots see other players' level-ups from 80 to 105 m, not the 45 m I tuned the daylight beam for. Follow-up added: look at a noon burst from 100 m.

**Decisions.** "Seen without avatar" is a stat, not a failure: a level-up can race a newly joined player's first snapshot, and a flaky world check would block every stream. It read 0 on all 8 bots. Asked qa to drop the behaviour from `art_lint_allow.json` (their file).

**Tested.** Unit suite with Postgres: 587 pass. 8-bot 180 s websocket bot test passed (7 of 8 bots levelled; 1 to 4 level-ups seen per bot). Client smoke test passed.

**Next run.** The gather-swing impact puff, or the far-away level-up look check.

## 2026-11-23, run: level-up beam seen from afar (ws/world/level-up-far-beam)

**Open PRs.** None of world's open. Budget: 28 of 40 world PRs this week before this one.

**Picked** the top unticked backlog item: the bot test sees other players' level-ups from 80 to 105 m, but the daylight beam was tuned at 45 m. Fun: when anyone in the valley levels up at noon you now see a gold stroke over the trees from 100 m and know someone just got stronger, which is the "you see others progress" pull of Milestone 1.

**Looked first, on main** (llvmpipe, 1280x720, bursts at 15, 45, 100 and 150 m, 0.45 s in): at 100 m the noon beam is a faint, haze-coloured 1 px line (0.6 m wide is 0.34 degrees); the 150 m one sat behind a hill. Also found a real bug: the ground ring is an additive quad with fog on, and Godot adds the fog colour over the whole quad, so from ~15 m on the ring drew as a pale flat **square** on the grass (and a white line at 45 m).

**Built.**
- Column shader (shared by column and beam, still one draw call): in the vertex stage it widens the unit cylinder so it is never thinner on screen than `MIN_SPREAD` = 0.007 rad (about 0.8 degrees, 8 px at 720p, 12 px at 1080p). The beam (0.3 m) starts widening at ~43 m; the day column (1.1 m) only past ~160 m, so the close-up look is unchanged. `MODEL_MATRIX` already holds the MultiMesh instance transform in 4.3 (compatibility too), so the radius is its x scale.
- `fog_disabled` on the column, with its own gentle fade (`far_fade`: 1.0 to 60 m, down to 0.65 at 220 m), so a far beam stays ember gold instead of turning haze-coloured. `extra_cull_margin` 1.2 m so a widened beam isn't culled at its old bounds.
- `fog_disabled` on the ring: it is a ring again from any distance.
- `LevelUpFx.drawn_radius` and `far_fade` mirror the shader for tests; the shader's uniforms are set from the same constants.

**Tests.** Three new unit tests: steady on-screen width from 100/150/200 m (and untouched below 40 m and for the day column), the fade only falls and never under its floor, and the column/ring shaders carry the rules (uniforms match the constants, `fog_disabled` on both, cull margin covers 170 m). Mutation check: `MIN_SPREAD` 0.002 fails 3 checks. Unit suite with Postgres: 593 pass. 8-bot 180 s websocket bot test passed (8 of 8 levelled). Client smoke test passed (render budget unchanged). No new bot behaviour: nothing new on the network, and art checks belong in unit tests (art bible section 7, qa's art lint).

**Looked at after.** Same shots: the 100 m beam is a clear gold stroke over the tree line at noon, the 45 m one is a deeper gold (no haze on it), and the ring is a ring. Before/after in the project files (`world/level-up-far-noon-*`, `world/level-up-far-night-*`).

**Didn't do.** The bigger burst for named unlocks and every 10th level still needs the client to pass the level (the backlog item stays). At night the far beam reads pale grey rather than ember; follow-up added.

**Next run.** The gather-swing impact puff, or the milestone burst once the client passes a level.

## 2026-11-23, run: ember night beam (ws/world/night-beam-ember)

**Open PRs.** None of world's open. Budget: 29 of 40 world PRs this week before this one.

**Picked.** The top item (milestone burst) still needs the client to pass the level; the gather impact puff needs the client to call world on each swing's contact. The next item world can do alone is the night beam follow-up. Fun: at night, a level-up across the valley now reads as an ember stroke over the stars (you see someone just got stronger, Milestone 1's "see others progress"), instead of a grey streak you'd take for haze.

**Looked first, on main** (llvmpipe, 1280x720, bursts at 15/45/100 m, 0.45 s in, own render script in a scratch dir): at midnight all three beams are beige-grey (pixel ~(151,145,114) at 100 m). The pale core is mixed in at low alpha, and navy sky shows through most of it.

**Built.**
- Column shader: custom data g flags the beam instance (column 0, beam 1; still one MultiMesh, one material, one draw call). `night = flag * (1 - day)`. At night the beam drops the pale core and leans `NIGHT_BEAM_EMBER` (0.7) towards `SPARK_EMBER`, and its alpha is x(1 + `NIGHT_BEAM_BOOST` 0.6), still under the 0.92 cap. By day `night` is 0, so the day beam and the column at every hour are exactly as before.
- `LevelUpFx.beam_tint(day, beam, body)` mirrors the shader (rgb = ALBEDO, a = alpha factor) for tests. `column_now`/`beam_now` carry the flag because the dummy renderer drops MultiMesh custom data.

**Didn't work.** First try boosted the beam's brightness at night (ALBEDO x2.1, HDR). Filmic clips red first, so the ember turned lemon/olive yellow. Switched the boost to opacity instead; the hue holds. Noted in a comment so nobody tries it again.

**Tests.** Two new unit tests in `test_world_level_up_fx.gd`: the column colour and opacity are unchanged at day 0/0.5/1, the day beam equals the column, the night beam composited over the navy sky at its real far alpha is clearly more saturated and ember-hued (hue < 0.11) than before, no HDR values, and the tint eases with no jump at dusk; and the shader carries the rule (beam flag 1, column 0, uniforms from the constants). Unit suite with Postgres: 607 pass. 8-bot 180 s websocket bot test passed (276 s). Client smoke test passed (render budget unchanged: 609,931 triangles). No new bot behaviour: nothing new on the network, and art checks belong in unit tests. No mutation run this time (the session blocked the scratch revert step); the hue check fails by construction if `NIGHT_BEAM_EMBER` is 0, since the old colour is the "was" side of the same comparison.

**Looked at after.** Midnight: the 15 m and 45 m beams are deep amber, the 100 m one an ember stroke (~(185,133,64), was (151,145,114)). Noon: no visible change (1.6k of 920k pixels differ by more than 8/255, all shimmer and motes timing). Before/after in the project files (`world/level-up-night-beam-*`).

**Next run.** The gather-swing impact puff needs a client call per swing: build world's half (`NodeProps.play_impact(root, id, point)` plus a pure contact-point helper) and file the client request, or the dusk look check added to follow-ups.

## 2026-11-24, run: depleted nodes breathe no sparks (ws/world/depleted-motes)

**Open PRs.** None of world's open. Budget: 30 of 40 world PRs this week before this one.

**Picked.** The milestone burst and the gather impact puff both still need a client call; the tier-2 landmark tuning needs playtest eyes more than code. The motes follow-up is world-only: a felled ember ash or a drained seep kept breathing sparks all night. Fun: at night the sparks over the valley now point only at things you can gather right now, so the motes become a real "go here" signal instead of a lie (art bible: "if it glows ember, you can use it").

**Built.**
- `Motes.set_dark(world, id, dark)`: shrinks that anchor's High-sized slots (`Motes.slots(a, count)`, index `m * count + a`) to size 0 in custom data, and restores the live custom data (kept in the node's `customs` meta) on regrowth. Still one MultiMesh, one draw call, nothing rebuilt, the quality count is untouched. `Motes.is_dark` reads the state (the dummy renderer drops custom data, so tests read the `dark` meta).
- `NodeProps.set_depleted` calls it on its parent (the World), so the client's existing calls (join sync and `s2c_node_state`) drive it with no client change. Safe for pines and outcrops (no anchor), unknown ids, and a NodeProps without a parent.

**Tests.** `test_world_depleted_motes.gd` (4 tests): slots partition the pool and sit by their anchor; depleting an ash, a seep and an old ember ash puts each out and regrowth relights only that one; non-ember nodes and missing worlds are safe; the pool, draw call and quality count are unchanged and the live look is kept. Mutation check: removing the call in `set_depleted` fails 4 checks. Unit suite with Postgres: 633 pass. 8-bot 180 s websocket bot test passed (275 s). Client smoke test passed (render budget ok). No new bot behaviour: nothing new on the network, art checks belong in unit tests.

**Looked at.** Midnight, felled old ember ash 397: on main a plume of sparks still rose over the stump; now none (`world/depleted-motes-night-before-after.png` in the project files). My scratch camera framing was off (far, not on the stump), but the plume's disappearance is the whole difference between the two frames.

**Didn't do.** The plume goes out at once on the last hit; NodeFx's burst covers it. A die-out (sparks in the air finish rising) needs a per-anchor time in the shader; follow-up added.

**Next run.** Still waiting on the client for the milestone burst and impact puff. Otherwise the noon grass saturation follow-up or the mid-distance tree mesh.

## 2026-11-24, owner-directed: grounded art direction (claude/grounded-art-direction)

**Why.** The owner played the build and said the look is "cheesy and looks silly"; they want it heavily inspired by the grounded survival-crafting MMO genre, in low poly, clearly ours, legally safe. Rewrote `docs/art_bible.md` around five pillars and a named "what reads as cheesy" list (section 11), and did a first pass on the worst offenders.

**Built.** Palette: olive and straw grass, dark moss forest floor, dark spruce pines, weathered bark, rust ash crowns (`ASH_LEAF_DRY` for variety), deeper water, old snow; `Palette.CLOTH`, `HAIR`, `skin()`. Ash scatter: thicker trunks, two lopsided lobes per crown (6x2 sphere, so triangles stay in budget). Avatars: earthy cloth, a hood instead of the pointed hat, hair on every non-hooded head (no rng draw added, old seeds keep their draws), head radius 0.24 -> 0.19, quiet eye sockets. Sky: dusty blue keys, `DAY_AMBIENT` 0.36, a whole-frame grade (saturation 0.92, contrast 1.10). Night: moonlit flat ambient (`ambient_color`, `NIGHT_SKY_SHARE`), `NIGHT_LIGHT` 0.55, shader `night_shade` 1.4 so figures turned from the moon are blue-grey, not black. Level-up column translucent (alpha cap 0.92 -> 0.62), 16 sparks, light 1.8.

**Didn't work.** One fat flattened crown lobe read as mushrooms; taller lobes plus a lower side lobe read as trees. 7x3 lobes x2 put night primitives at 518k (ceiling 500k); 6x2 lobes land at 480k. Shrinking the level-up column's radius breaks the "readable at 45 m" tests, so only its opacity changed. In the Compatibility renderer the sky ambient is near nothing at night, so ambient tweaks alone did not lift dark cloth; the shader's night shade did.

**Tests.** Unit 678 pass (no Postgres here). Client smoke passes: primitives 449k noon / 480k night, style baseline rewritten on purpose. Before/after shots in the project files (`art-direction/`).

**Next.** Backlog top item: ground cover patches, wilderness lanterns, level-up sparks, 6-head characters, node ash crowns. Check dark cloth at night on a real GPU (Forward+), CI only sees software GL.

## 2026-11-24, owner-directed: character overhaul (claude/character-overhaul, stacked on the grounded art direction)

**Why.** Owner: "our dudes look fat and silly". The wanderer was a 0.64 m wide capsule about 3.5 heads tall on stubby legs.

**Built.** `AvatarBuilder.parts()` rebuilt as a lean 1.78 m adult about 7 heads tall (constants at the top of the file): a tapered, flattened chest (parts carry `scl` now), a skirt and belt, two-piece arms (sleeve, bracer, hand) and legs (thigh, shin, tall boot, foot), neck, nose, eye sockets, a hood or hair with an optional felt cap, a wool mantle, a chest strap, a pouch and a knife, a framed pack and bedroll inside the arms' swing. The rng draws are unchanged (skin, then style), so every seed keeps its skin, headwear and cloth. `build()` merges each group (body, four limbs) into one mesh (`merged()`), so an avatar is 5 draw calls, not 16 or the 30 the new parts would have been; frame draw calls at spawn 289 to 265.

**Didn't work.** The first build made each part its own node: 316 draw calls at night, over the 300 ceiling with one avatar on screen. Merging fixed it. A hood centred on the head hides the face; set back 6 cm it frames it.

**Tests.** Unit 680 pass (new: lean-adult proportions, merged meshes keep every vertex and colour). Client smoke passes (draw calls 251 noon / 265 night, primitives 449k / 481k). Shots from five angles, day and night, in the project files (`art-direction/characters/`).

**Next.** Client: retune `WalkAnim` for long legs (filed). World: a little build and height variety, beards, two mantle cuts, inside the 5-mesh, 2,000-triangle budget.
## 2026-11-24, run: grazer models (ws/world/grazer-models)

**Picked.** "Procedural critter models" (grazer part). It sat low in the backlog as Milestone 2 build-ahead, but gameplay's two requests made it the top open request from another stream: the herds are on the wire since protocol v6 (#158) and the client has nothing to draw them with. Requests come first, and a living herd past the meadow is the most new fun on my list. **What a player will feel:** the hills outside the meadow are alive, and a herd reads at a glance: heads down means creep closer, a head snapping up means freeze, a white rump bounding over the hill means you rushed it.

**Built.** `Grazers` (`game/procgen/grazers.gd`), a small deer-like grazer, ~1.27 m at the withers, ~1.3 m long: fawn coat, cream belly and pale rump, dark hooves, muzzle and eyes (three new `Palette.GRAZER_*` colours, no literals in the file), tall ears, a short tail.
- Three MultiMesh layers (bodies, head-and-neck, legs with 4 instances per grazer) on Emberlight's shared `solid` material: 3 draw calls and no new material whatever the herd size; capacity 48 (21 today). 620 triangles a grazer (13k for every grazer in the world). Layers stay hidden until fed.
- Poses as pure maths (`pose_for`, `xforms`): graze (head down, slow nibble), alert (head high), amble (diagonal walk), return (bigger trot with a bob), flee (bound: front pair and back pair half a cycle apart, the body leaps and pitches), rest (body down, legs tucked and shortened). The body tilts with the slope front to back (`ground_basis`).
- Client API: `build()`, `feed(root, entries)` with the wire list as it arrives, `tick(root, delta)`. Smoothing lives here so the client's job is three calls: exponential follow (7/s) between the ~5 updates a second, snap past 12 m, facing turns at 6/s, gait phase advances by the distance really travelled (no foot sliding, no treading water when stopped), pose blends at 5/s, but `alert` at 14/s so the freeze cue is instant. Request filed in the client backlog.

**Tried.** First cut was 1,072 triangles (7x4 spheres, 6-sided cylinders with a middle ring); 6x3 spheres, 5-sided ring-less cylinders and a box muzzle tip brought it to 620 with no visible change at 7 m.

**Tests.** `test_world_grazers.gd` (9 tests): cheap and on the shared material; hooves on the ground in every standing pose; poses read (muzzle under 0.6 m grazing, over 1.5 m alert, lying body low with legs above ground); walk pairs and the bound; feed/tick follow the wire (glide, snap, removal, empty list, plain Arrays, unknown state); the head is up within a quarter second; legs don't move when the body doesn't; coat tints vary but stay near white; slopes tilt the body. Unit suite with Postgres: 661 pass. 8-bot 180 s websocket bot test passed (274 s). Client smoke test passed (nothing drawn there yet: night 289 draw calls, 463k primitives, unchanged). No new bot behaviour: nothing new on the network, and art checks belong in unit tests (art lint).

**Looked at.** Noon from 7 m and 22 m and midnight from 5 m, all six states side by side at the first herd's home (`world/grazers-noon.png`, `world/grazers-noon-22m.png`, `world/grazers-night.png` in the project files). Noon: warm fawn reads well against the green hill and the pines. Night: dark silhouettes whose pale rumps catch the moonlight, which is right for animals (no ember on living things).

**Next run.** Nothing shows in game until the client wires the three calls. Then: the dust kick on `flee` and an idle ear flick (follow-ups added), and check the smoke test's draw calls once a herd is in a spawn shot.

## 2026-11-24 (run 2): grazer PR #160 back in line with main

**Why.** #160 went into conflict: the client shipped its own placeholder grazers (#161, `HerdView` + `GrazerFigures`) while #160 waited, and both PRs edited the same request lines in `docs/workstreams/client.md` and `world.md`. Fixed it in this run rather than starting a new item, because a living herd is the biggest fun on the world list and it should land.

**What changed.** Merged `main` in (no rebase). Kept main's request text and marked gameplay's two and the client's one as done/answered. Answered the client's ask directly: `Grazers.part_xforms(pos, yaw, state, gait_phase, gait, size)` has the same signature and `{body, head, legs}` result as `GrazerFigures.part_xforms`, so the client can swap in `Grazers.meshes()` and keep `HerdView`, its dust and its snort. It calls the same `pose_for`/`xforms` maths, with the slope-following ground basis. No pose blending through that path (the client's `HerdView` owns smoothing), so a state change snaps there; `Grazers.feed/tick` still blends if the client prefers it. One test added (`test_part_xforms_is_a_drop_in_for_the_client_placeholder`).

**Tests.** Unit suite with Postgres: 688 pass. 8-bot 180 s websocket bot test passed (276 s). Client smoke test passed (render budget ok; `Grazers` isn't drawn by the client yet, so nothing on screen changed).

**Next run.** If #160 has landed, the client's swap is theirs. Otherwise: noon grass saturation or the mid-distance tree mesh.

## 2026-11-24 (run 3): lantern flames flicker (ws/world/lantern-flicker)

**Picked.** #160 (grazers) has landed. The two top items (milestone level-up burst, gather impact puff) still need a client call. Next on the list was the mid-distance tree mesh, but it adds one draw call per visible chunk and night headroom is 11 (289 of 300); it is a perf item players don't feel, and it needs a careful measuring run of its own. The lantern flicker is world-only, small, and finishable here. **What a player will feel:** coming back to the meadow at night, the eight lanterns and the bench lantern look like real flames: the light pools on the grass breathe, each on its own rhythm, instead of sitting there like electric bulbs.

**Built.**
- `Lamps.flicker(seconds, index)`: pure maths, three sine waves (7.3, 17.3 and 2.9 rad/s) with a golden-angle offset per lantern. Stays inside 1 +- 0.07 (`FLICKER_DEPTH` 0.14) and averages 1, so a night is exactly as bright as before.
- `Lamps.flicker_lights(world, seconds)`: sets `light_energy = steady * flicker` on every lit meadow lantern light and the bench light (index `COUNT`). `apply_glow` (both `Lamps` and `Workbench`) now stores the steady level as `steady_energy` meta on each light. Lights that are off, or that no repaint has set yet, are left alone.
- `DayNight._process` calls it every frame on the same clock as the heartbeat (`now_world_seconds`, so every player sees the same flames), and `apply` calls it right after `apply_glow` so a 0.25 s repaint never shows one steady frame (a ~5% blip four times a second would have read as a tick).
- Cost: 9 `light_energy` sets a frame at night, none by day. No new nodes, materials or draw calls; no colour literals (art lint unchanged).

**Decisions.** Lights only, not the glass: the lantern glass is one shared material across all nine lanterns, so wobbling `emission_energy` would make them all flicker in lock step, which looks worse than steady glass with the heartbeat. Per-lantern glass flicker needs a phase in instance custom data in the `glow` shader; follow-up added. No colour shift with the flicker, because a second flame colour would be a new literal for the art lint and the energy swing alone reads.

**Tests.** `test_world_lantern_flicker.gd` (5 tests): range and mean over 9 lanterns x 100 s; under 2% change per 60 fps frame (worst is about 1.1%); neighbouring lanterns aren't in step (correlation under 0.8); built world lights follow their own flame and re-flicker around a new steady level after a repaint; nothing changes by day or before the first repaint, nothing is created, safe on null and partial worlds. Mutation check: making `_flicker_one` a no-op fails 10 checks. Unit suite with Postgres: 716 pass. 8-bot 180 s websocket bot test passed (278 s). Client smoke test passed (render budget ok). No bot behaviour: nothing on the network.

**Didn't do.** No screenshot pair: a +-7% light swing doesn't show in two stills, and the smoke shots are stills. Worth a look in a real night playtest; if it reads too subtle, raise `FLICKER_DEPTH` to 0.2 (the strobe test allows it).

**Next run.** Milestone burst and impact puff still wait on the client. Otherwise the noon grass saturation follow-up (qa's noon style baseline exists now) or the mid-distance tree mesh with a draw-call measurement.

## 2026-11-24 (run 4): Low draws less far (ws/world/low-draw-distance)

**Picked.** qa's open request "Low barely draws less" (requests come before the backlog). The top backlog items (milestone burst, gather impact puff, ember-tool sparks) still need a client call. **What a player will feel:** on an old laptop with Graphics on Low, the game runs noticeably smoother (fewer hitches while turning the camera across the valley), and the meadow they actually play in looks the same.

**Built.**
- `Chunks.RANGE_SCALES` (Low 0.5, Medium and High 1.0) and `Chunks.range_scale(level)`. `cut_for(range, chunk, scale)` scales the layer's range but not the half-diagonal padding, so nothing inside the shorter range is ever cut.
- `Chunks.quality_range_scale()` reads `Quality.level` by path (`q.get("level")` on the loaded script works in 4.3), 1.0 where `client/` isn't exported, like `Flora.quality_density`.
- `Chunks.build` and `NodeProps._chunked` tag each chunk with its range and chunk size (`set_range`) and cut it for the current level. `Chunks.apply_range_scale(root, scale)` redoes every tagged chunk under a node.
- `Chunks.RangeWatch` (added by `WorldBuilder.build` under the world root) polls every 0.5 s and rescales the whole world when the Graphics setting changes.
- No new nodes drawn, no materials, no colour literals.

**Measured** (client smoke, noon spawn, Low vs Medium): at 0.7, primitives -3%, draw calls -7%, frame -15%. At 0.5, primitives -11% (440k -> 394k), draw calls -14% (275 -> 237), frame -25% (152 -> 114 ms software). I put the Medium, Low 0.7 and Low 0.5 shots side by side: the three look the same, because the far tree line is mostly the whole-world resource-node trees plus haze. So 0.5. The scene triangle count doesn't move (visibility ranges hide, they don't build less), which is why qa's `min_saving` on scene triangles still only sees flora's -11%.

**Didn't do.** The node tree layers are whole MultiMeshes and still draw everything on Low; chunking them costs draw calls, follow-up added. No bot behaviour: nothing on the network, and the art lint forbids procgen in bot behaviours.

**Tests.** `test_world_low_ranges.gd` (5 tests): scales per level and clamping; Low cuts nearer for every ranged chunk and node layer but keeps the padding; whole landmark layers never cut; `Chunks.build` and `NodeProps.build` on Low use the Low cut and `apply_range_scale` puts it back; `RangeWatch` follows Low and High within one poll. Unit suite with Postgres: 731 pass. 8-bot 180 s websocket bot test passed (277 s). Client smoke test passed (render budget ok, style check ok).

**Next run.** qa can raise its Low gate. Then the noon grass saturation follow-up or the mid-distance tree mesh.

## 2026-11-24, less blocky, low-res characters (PR #171 follow-up)
- Owner asked for characters that look less blocky and more "low res". Every body part is now a smooth `loft()` (rings of width/depth along y) or a low-segment ball, no boxes or cylinders. About 2,340 triangles a character, 5 draw calls, unchanged.
- Low-res feel comes from maths in the Emberlight shader: object-space texel grain (`texel_size` 0.055 m on bodies, 0.4 m on terrain, ±9%/±7% brightness). No textures imported.
- First loft pass had inverted winding (back faces drawn, faces looked like masks). The avatar test now checks winding and outward normals.
- The light ramp is now two soft steps instead of one hard band, so rounded shapes read as rounded.
- Next: animation thread builds on `AvatarBuilder.parts()/merged()/rig()`; upper arm/forearm and thigh/shin are separate parts ready for elbow and knee pivots.

## 2026-11-23 — night-lighting-fix

## Night lighting fix (owner playtest 2026-11-24, PR #181)
- Bug: a pale cyan, stair-stepped pool over Spawn Meadow at night on real GPUs. Emberlight's light() added SHADE for every light. In Forward+ a local light's light() runs over whole cluster tiles, including where ATTENUATION is 0, so lanterns tinted whole cluster cells. CI (opengl3, no clusters) only showed a general cyan wash. Now only directional lights paint SHADE. #169's night_shade 1.4 would have made the bug 4x worse.
- To see Forward+ locally: run the client with `--rendering-driver vulkan` and `VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json` (lavapipe). The CI smoke can't show cluster artefacts.
- Lanterns: attenuation 2.0, range 9, energy 2.6, so they make separate pools. Seeps: one shadowless, distance-faded OmniLight each (NodeProps.SEEP_LIGHTS), lit by Lamps.apply_glow, flickering, dark when depleted. Moon rim x2.5 at full night (`night_rim`). Draw calls unchanged (night 292).
- Next: the style baseline's night numbers are stale (luma 0.18 recorded, about 0.11 now). Re-baseline once the grounded look settles.
- After #169 merged: CI's night style check failed (sat_mean 0.68 -> 0.93). The old night baseline was measured with the lantern SHADE wash, which on the Compatibility renderer showed as a cyan-green cast that propped up the night. I rewrote the night baseline on purpose (see style_baseline.json _doc). In Compatibility the night is now near black for pines and figures. I tried weighting the lanterns' SHADE by ATTENUATION instead of dropping it, and that didn't change the Compatibility shot. I also turned every lantern off, and it was just as dark. So the moon and ambient are what's weak there (pines and avatars get no directional light() at all in a +3 red test), not light limits. Forward+ looks right.

## 2026-11-24 — ground-cover

## Ground cover patches (ws/world/ground-cover)

**Picked.** Top backlog item, owner direction 2026-11-24 (grounded art), step (1): ground cover. Steps (2) lanterns and (3) level-up sparks are next. **What a player will feel:** walking out of Spawn Meadow, the ground has a story (a damp mossy hollow, a sunny straw-coloured rise, a scuffed patch of earth), so the valley reads as a real, old place instead of a flat green carpet.

**Built.**
- `Palette.MOSS`, `DRY_GRASS`, `BARE_EARTH` (all under 0.45 saturation) and `Palette.ground_at(x, z, h, slope, jitter)`: `ground()` plus seeded cover. `Palette.ground()` is unchanged for its other callers.
- `Palette.cover_weights(x, z, h, slope)`: two FastNoiseLite fields seeded from `WORLD_SEED` (cover ~38 m, earth ~22 m). Moss and dry grass are the two ends of one field so they never fight; moss is biased up in the forest band (h 5 to 7 blend) and near the lake shore, dry grass up on the open valley. Bare earth is its own field with a small slope bonus. Each blend capped (`COVER_MAX` 0.65, `EARTH_MAX` 0.6) so the base grass always shows through. Shore, rock (slope > 0.55 or h > 13) and snow get nothing.
- `TerrainMesh._tri` calls `ground_at` with the face centre. Still flat-shaded per face, still one material; build time unchanged within noise (1.84 s).

**Tried.** First pass used narrow smoothstep bands (0.10 to 0.55) and a 14 m earth field: a 1 m step changed a weight by up to 0.43, which reads as hard-edged blotches. Wider bands and a 22 m earth field bring it under 0.2 per metre. `COVER_MAX` 0.55 was almost invisible at the spawn camera; 0.65 reads without turning into a quilt.

**Measured.** Over a +-300 m grid of grassland: moss on ~22%, dry on ~14%, earth ~11%, plain base grass ~25%. Smoke style: noon sat_mean 0.296 -> 0.286, warmth 0.113 -> 0.106, luma 0.536 -> 0.521 (a touch flatter and earthier, as intended; well inside the baseline, so not rewritten). Render budget unchanged (vertex colours only).

**Looked at.** Noon, golden hour (0.29) and midnight from the spawn camera, before and after (project files `world/ground-cover/`). The spawn view is subtle: a straw rise and an earth patch to the right of the bench. Honest note: from the low action camera the patches read most on the mid-ground; a higher shot over the valley would show them better.

**Tests.** `test_world_ground_cover.gd` (6 tests): tokens are muted earthy naturals; the meadow has moss, dry and earth patches in sensible shares with plenty of plain grass; under 0.2 change per metre and never full cover; forest mossier, open valley drier; shore, rock, cliff and snow untouched; deterministic and a built chunk shows several tones on one material. No bot behaviour: nothing on the network, and the art lint keeps procgen out of bots. Unit suite with Postgres: 780 pass. 8-bot 180 s websocket bot test passed (276 s). Client smoke passed (style and render budget ok).

**Next run.** Wilderness lanterns (timber posts, iron and horn lanterns), then rounder level-up sparks.

## 2026-11-24 — hunt-drop-icons

## Hunt drop icons (ws/world/hunt-drop-icons)

**Picked.** Gameplay's open request in `world.d/from-gameplay-first-hunt.md` (requests come before the backlog): icons for `hide` and `raw_meat`, which wait in `Inventory.UNDRAWN` and hold back the kill toast. The owner-direction art steps (wilderness lanterns, level-up sparks) are next. The client's knee/elbow pivot request touches `AvatarBuilder`, which two open owner PRs (#196 fuller characters, #192 skinned animation) are rewriting right now, so I left it for after they land rather than build on code about to move. **What a player will feel:** bringing down a grazer pays off on sight: the pack and the toast show a hide and a cut of meat, not two grey "unknown" bundles.

**Built.**
- `Palette.HIDE_FUR`, `HIDE_FLESH`, `RAW_MEAT`, `MEAT_FAT` (with comments). No colour literals added to `item_icons.gd` (art lint count unchanged).
- `ItemIcons` recipes: `hide` is a ragged fur-up pelt with two leg flaps, fur strokes, the top corner turned back to show the pale flesh side, and a dark hide tie. `raw_meat` is a thick cut with a fat rim, marbling streaks and a bone cross-section. Neither has a halo; `tint()` gives each its own colour.

**Tried.** The first meat put the bone top left with streaks below it, and at 128 px it read as a face (bone = eye, streaks = mouth). Moved the bone to the lower right edge and ran every streak one way. The first hide's flesh corner was too close to the fur at 48 px; lightened `HIDE_FLESH` and darkened `HIDE_FUR` a touch.

**Looked at.** Row of every icon at 128 and 48 px, plus a 256 px close-up: project files `world/hunt-drop-icons-row.png` and `world/hunt-drop-icons-close.png`. No world screenshots: nothing in the 3D world changed.

**Tests.** `test_world_item_icons::test_hunt_drops_are_drawn_earthy_and_never_glow` (own icon, no halo, no ember-bright pixels, own tint, meat dark red off ember's hue, hide muted). The existing fill, margin and distinctness tests pick both up automatically through `Inventory.UNDRAWN`. No bot behaviour: nothing new on the network (the drops are gameplay's, already in their bot test), and the art lint keeps procgen out of behaviours.

**Next run.** Gameplay moves the two into `ITEMS` (request filed). Then wilderness lanterns (owner art step 2), or the client's knee/elbow pivots if #196 and #192 have landed.

## 2026-11-24 — kingdom-generator

## Kingdom generator v1 (ws/world/kingdom-generator)

**Picked.** Top of the backlog: owner direction 8, Phase 1 part 1, the kingdom generator. Gameplay part 3, client parts 1 and 3 and qa part 3 all wait on it. The night-on-Compatibility bug is second; it stays next. **What a player will feel:** nothing yet on the live world (on purpose, it stays Ashgrove). This unblocks the day every world is a new kingdom to explore, with roads to follow and ruins whose danger you can read on the map before you go.

**Built.**
- `WorldGen` (`game/shared/worldgen.gd`, world owns it): the config `{seed, size_m, gen_version}` with `configure`, `apply`, `reset`, `config` and `parse("seed:gen:size")` (sizes by number or `small`/`medium`/`large`). Plain data and pure functions; nothing visual, so the server can read it (art lint passes).
- `gen_version` 0 is Ashgrove: `Terrain.height` keeps its exact old code path, so it is bit-identical (a test compares against a frozen copy of the old formula). Version 0 ignores seed and size. `Terrain.water_level()` and `clamp_to_world()` follow the config (unchanged numbers on 0).
- `gen_version` 1, the kingdom, built once per config in a fixed order: rim (60% coast on one side, else hills all round), spawn (inland, a quarter turn from the coast, the calmest of 24 candidates), lakes (in low ground, away from spawn), one river (a spring in the rim to the sea or the main lake, meandering, kept off the spawn plot), ruins (castle first on the far side, then grades 3, 2, 1 in distance bands from spawn; every world has a burned farmstead and an abandoned village), and roads (a spanning tree over spawn and ruins plus one loop). Height = uplift-driven lowlands and hills with ridges, rim hills, sea, lake beds and a river bed, land bumps fading along roads, then flat pads for spawn and each ruin.
- River and road distances are baked once into 4 m rasters by stamping each segment only into its own box, so `height()` stays cheap (a 1.5 km layout plus ~1,000 node spots in about 0.3 s).
- Biomes: forest, moor, farmland (wild fields), stone hills, plus water, shore and snow. `node_spots()` places nodes on a jittered 12 m grid by each biome's density and mix, off roads, rivers and ruin pads, 6 m apart, with the same 7-node starter ring around spawn as Ashgrove. Ordered and stable per config, so gameplay can use the index as the id.
- `WorldMap` (`game/procgen/world_map.gd`): paints the configured world as a small relief map (biome colours, north-west light, water, roads, ruin discs by grade, spawn). New `Palette.MAP_*` tokens; no colour literals outside the palette. Client's map item can show it as is.

**Tried and fixed.** First pass placed no castle at all: the river raster was capped at 60 m but the castle asked for 78 m of clearance, so every candidate "failed" the river check. Then larger worlds had dry river stretches near spawn, because the spawn plot's 70 m blend (and ruin pads' blends) lifted the river bed. Now the river keeps clear of the plot's blend, and each ruin's blend stops short of the nearest water. Swept seeds 1 to 40 plus two big ones at 1000, 1200 and 1500 m: every check passes on all of them.

**Looked at.** Maps of seeds 1 to 5 next to Ashgrove (project files `world/kingdom-generator/`). Reads like a kingdom: coast or ring of hills, one river, roads joining small pale grade 1 marks near spawn out to the big dark red castle. Honest notes: stone hills are about a quarter of the land and read as grey blobs with hard edges on the map; the highland worlds have little water (lakes only, ~2%); snow shows only on the rim's corners. No 3D shots yet: the world builder still sizes everything from `GameConfig.WORLD_HALF_SIZE` (part 2, chunks) and the client's `--world` flag isn't on `main`.

**Tests.** `test_world_worldgen.gd` (8 tests): Ashgrove default and bit-identical (also after visiting a kingdom); parse and apply; same seed same world, different seeds differ; five seeds each have a dry flat spawn, water, a river that holds water, every node kind (and all reachable on foot by flood fill), the full starter ring, a ruin of every grade, both must-have set pieces, grades further out in order, roads to every ruin, and every ruin reachable on foot; node spots stay off water, roads and pads and 6 m apart, ruin pads are flat; bigger worlds have more ruins and nodes; layout under 2.5 s; the map paints water and all four grade marks. No bot behaviour: nothing is on the wire or playable yet (gameplay's config bump and part 3 make it so; qa's part 3 runs bots on a generated world).

**Next run.** The Compatibility night bug. After that, part 2 (chunks), which also swaps `GameConfig.WORLD_HALF_SIZE` for `WorldGen.half_size()` in the world builder, so the client's `--world` flag can show a kingdom in 3D and I can tune ground colours and flora for its heights.

## 2026-11-24 — kingdom-dressing

## A generated kingdom dresses itself (ws/world/kingdom-dressing)

**Picked.** Requests from other streams come first, and gameplay's (`world.d/from-gameplay-kingdom-placement.md`) was open: the server now puts nodes, herds and the bench on a generated kingdom, but the meadow dressing still centred on `GameConfig.SPAWN_POINT` and sized itself by `GameConfig.WORLD_HALF_SIZE`. Rendering seed 11 from main showed how bad that is: the 512 m Ashgrove terrain chunk floating in fog, no ground at the kingdom's spawn at all, lanterns 330 m away at the origin. The Compatibility night bug stays next. **What a player will feel:** the first time a kingdom runs, they spawn in a lantern-lit meadow next to the bench, and look out over forests that sit where the map says forest, with roads and ruin grounds left open to walk to.

**Built.**
- `Lamps.positions()`, `Workbench.spot()`: centre and face on `WorldGen.spawn_point()`, seeded by the world's seed.
- `WorldBuilder`: terrain and water plane span `WorldGen.half_size()`.
- `Props.scatter()`: Ashgrove keeps its exact code path. A kingdom goes to `_scatter_kingdom`: count scaled by area (`count_for_world`: 0.55 of Ashgrove's density, capped at 9,000), kept per biome (forest 1.0, stone hills 0.32, moor 0.16, farmland 0.10), kind by biome (ash and pine in forest, pines higher up; pines and rocks on stone hills and moor; lone ashes on fields), never on water, shore, snow, within 24 m of spawn, on the king's roads (+2.5 m) or a ruin's pad (+4 m, room for the ruin kit). Seed 11 at 1.2 km: 5,438 items in 0.4 s.
- `Flora`: seed, half size and spawn from `WorldGen`; the cache follows the config (like `ResourceNodes`); on a kingdom, boulders go on forest and stone hills, flowers on fields and moor, roads and ruin pads stay clear, counts scale by area (birches by its square root: shores grow with the water's edge), and 20 tries per spot instead of 60.
- `Palette.ground_at`: on a kingdom, colour comes from the biome (`_kingdom_ground_at`): forest floor, straw-olive meadow on farmland, brown heath (`GRASS` toward `MAP_HEATH`) on moor, thin grass over stone on stone hills, rock on steep slopes, snow only past `WorldGen.SNOW_LINE`. Ground cover patches as on Ashgrove. Before, Ashgrove's height bands painted everything over 17 m (all of the 30 m rim) as snow.

**Ashgrove is bit-identical.** Hashed Props, Flora, Lamps and Workbench outputs on main before touching anything and froze them in `test_world_kingdom_dressing`; they match after a trip to a kingdom too.

**Looked at.** Seed 11, 1.2 km, noon, golden hour, night, from the lantern ring and from 45 m up, before and after: project files `world/kingdom-dressing/`. Spawn meadow with lanterns and bench, a forest edge on two sides, a dark-moss forest band against lighter fields from above, a thin strip of real snow on the far peaks. Night reads (Forward+ was not available here; the shots are opengl3).

**Honest notes / didn't work.**
- Birches: only 60 on seed 11 (Ashgrove has 260). Random sampling rarely lands on the thin shore band, and the 20-try cap stops it. Fine for now; better is to sample along `WorldGen.lakes()` and `rivers()` directly.
- Kingdom flora takes ~1.9 s (biome lookups on every try). With the terrain at 1.2 km (about 5x Ashgrove's chunks) a kingdom's world build is slow; part 2 (chunks) is what fixes startup. Not live yet, so not a player problem today.
- Biome edges are hard lines on the ground (the moisture threshold in `biome_for`), most visible from above. A soft blend over ~15 m in `_kingdom_ground_at` would help.
- No bot behaviour: nothing new is playable or on the wire; the client doesn't load a kingdom yet (client's `--world` flag).

**Next run.** The Compatibility night bug.

## 2026-11-24 — compat-night

## Night on the Compatibility renderer (ws/world/compat-night)

**Picked.** Next on the backlog after the generator and the kingdom dressing: night near black on opengl3 (CI's smoke shots and any player whose GPU has no Vulkan). **What a player will feel:** on an older or Vulkan-less machine, night is a moonlit blue meadow where you can see the pines, the path and your friends, instead of a black screen with lanterns floating in it.

**Root cause.** Not lighting. Godot 4.3's Compatibility renderer treats a spatial shader's `ALBEDO` and `EMISSION` as **sRGB** and linearises them itself (`drivers/gles3/shaders/scene.glsl`, "Convert colors to linear", a cubic approximation in `tonemap_inc.glsl`), and it leaves `source_color` uniforms in sRGB. Forward+ and Mobile take `ALBEDO`/`EMISSION` as linear, and linearise `source_color` uniforms on upload. Every one of our shaders writes linear colours (`Emberlight.paint()` stores vertex colours linear, palette constants are baked with `srgb_to_linear()`), so on Compatibility every colour was linearised twice: a mid tone kept about a fifth of its brightness. By day the bright key hid it (just darker, more saturated); at night everything sits in the tonemapper's toe and went near black.

How I found it: installed `mesa-vulkan-drivers` here, which gives a working **Forward+ on lavapipe** next to opengl3 on llvmpipe, same machine. Then bisected with a scratch scene: grey albedo matched on both renderers, vertex colours and constant emission did not; unshaded swatches (0.02 to 1.0) showed opengl3 putting out exactly `srgb_to_linear` of what Forward+ put out. Reading the 4.3 GLES3 shader source confirmed it.

**Built.**
- `Emberlight.srgb_output()`: true on Compatibility (no `RenderingDevice`, not headless). `RenderingServer.get_current_rendering_method()` doesn't exist in 4.3, and the shader preprocessor's `CURRENT_RENDERER` check broke `#endif` parsing in my test, so the choice is made in GDScript when the shader source is built: `compat_define()` prepends `#define COMPAT_SRGB`. Forward+ and Mobile get byte-identical shaders to before.
- `COMPAT_GLSL`: `compat_decode` (Godot's own cubic) and `compat_encode`, its exact inverse (quadratic first guess, three Newton steps). The usual pow approximation of linear to sRGB left the darks up to 60% off, which is exactly where night lives. A GDScript mirror is unit tested down to linear 0.0005.
- Emberlight (every world surface, terrain, avatars, node props): on Compatibility, `emission_color` is decoded to linear first, then `ALBEDO` and `EMISSION` are encoded once at the end of `fragment()`. Motes and the level-up sparks (linear constants and instance colours, unshaded) encode their `ALBEDO` too.
- `COMPAT_ALBEDO = 0.5`: even with colours right, lit surfaces still came out brighter on Compatibility than on Forward+ (its sky ambient differs; I didn't find exactly where). Scaling only the lit paint brings the spawn shot to Forward+'s brightness: centre luma at night 0.22 vs 0.26, golden hour 0.55 vs 0.54, noon 0.71 vs 0.64.

**Numbers (same night shot, centre luma).** opengl3 before 0.06, after 0.22; Forward+ 0.26. CI smoke night shot luma 0.05 -> 0.19. Before/after/Forward+ triptychs at night, golden hour and noon: project files `world/compat-night/`.

**Style baseline rewritten on purpose** (`tests/client_smoke/style_baseline.json`, as its `_doc` allows for a world PR that changes the look; reason appended there). Night luma 0.05 -> 0.19, noon 0.54 -> 0.67.

**Honest notes / didn't work.**
- Every earlier art pass that was tuned from opengl3 shots (all of mine since this container had no Vulkan) was tuned against colours that were too dark and too saturated. Players on Forward+ always saw the brighter, softer version. From now on the CI shots show what they see.
- Night `neon_share` is now 0.19 on CI (the art bible wants at most 0.10): the ember-ash crowns read saturated orange-red at night, on Forward+ too. It was hidden by the darkening. Follow-up filed.
- Noon on opengl3 is still a touch paler and its sky a touch bluer than Forward+ (sky and fog differ in the GLES3 sky shader, which treats sky `COLOR` as sRGB as well; our sky's colours come from `source_color` uniforms, which happen to come out right). Left alone.
- Not touched: `NodeFx`'s highlight rim and the level-up column and ring. They colour from `source_color` uniforms, which Compatibility already shows about right.
- No bot behaviour: nothing changed on the server or the wire; this is client rendering only. Unit tests cover the maths and the shader sources; the client smoke test covers the real render.

**Tip for next runs:** `apt-get install -y mesa-vulkan-drivers` gives Forward+ here (`--rendering-method forward_plus --rendering-driver vulkan`). Compare against it before trusting an opengl3 shot.

**Next run.** The ember-ash night saturation follow-up is small; then part 2 (chunks) or the material merge before the ruin kit, per the director's order.

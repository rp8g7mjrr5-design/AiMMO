# Biomes and real hills: island generator v3 (world)

Owner, 2026-11-28, with a screenshot of the flat meadow by a landing: "The map feels really
flat in my opinion. We need to have different types of biomes i think. Like forests and
flatlands and others let think of some." The biome list was posted in the thread (meadows,
broadleaf forest, pine hills, marsh, moor, rocky highlands, beaches) and built the same day.

## What shipped
- `WorldGen.ISLAND_HILLS` (3), now `LATEST`. `is_island()` is `gen >= ISLAND`; every
  `_gen == ISLAND` became `>=`. `L.v` carries the version into `IslandGen`.
- `IslandGen._land3` / `_biome3`: same shape, coast, lakes, rivers, landings, location plan,
  roads and carts as v2; only the land and the biomes change. New noises on seed offsets 20 to
  24 (hills, knolls, swell, fen, pool), built only for v3, so v2's noises and rng draws are
  untouched. `test_version_two_islands_are_untouched` pins 1126:2:3000 (heights on a 40 x 40
  grid, node count, biome hash, site count) to what main made before this PR.
  - Base rise 8 m shore to heart, broad swells 1.2 m by the sea to 9 m inland.
  - Pine hills: patches of a 1 km noise (inland 0.1+), billowed knolls at 200 m, 9 to 39 m.
  - Marsh: fen noise, mostly within 30 to 160 m of a river or lake (strong fen anywhere),
    inland 0.07 to 0.6, flattened to 1.0 m +- 2.4 m of pool noise: under the water is a pool.
  - Crags at the heart: 16 + 46 m (v2: 12 + 30).
  - Roads: only the small detail softens near a road now. v2's softening of the big relief
    would cut 30 m trenches through the hills; on v3 the roads climb.
  - Locations: `_site_ok`'s evenness check gets 0.28 x radius more slack on v3 (pads blend).
    Every must-have still lands on seeds 1126, 7, 42, 3 and 99.
  - Snow only where the heart is (`mount > 0.25`); a pine hill's crest above the snow line is
    bare rock ("stone_hills").
- Look: `Palette.PINE_FLOOR`, `MARSH`, `PEAT`; pine hills keep turf to slope 0.9 (rock above),
  marsh goes to peat by the pools and gets no sand fringe. Props: pine hills keep every scatter
  tree (pines to slope 1.4), marsh grows `snag` (a bare grey trunk and a broken limb, Trunks
  layer, no new mesh or draw call, no rng draw) and a few ashes. Grass 0.3 on pine hills, 0.95
  in marsh. Nodes: pine hills mostly pine and stone, marsh mostly scrub (fibre).
- Wipes: `WorldWipe.same_kind` lets a v2 island keep running when the server is configured
  for v3 (no surprise wipe), and `roll` (not first) moves every island to `WorldGen.LATEST`.
  So the live world (Dockerfile still `1126:2:3000`) moves to v3 at Thursday 3 Dec's wipe with
  no Railway change. The Dockerfile is left on 2 on purpose: changing it does nothing until
  the wipe anyway, and the first-world path still honours it.
- Numbers, seed 1126 (3 km): v2 land p50 5.5 m, p90 19 m; v3 p50 5.4 m, p90 33 m, steep
  (slope > 0.8) 1% -> 7.5%. Biomes v3: meadow 24%, forest 21%, pine hills 16%, moor 10%,
  stone 9%, marsh 6%, snow 2%, beach 12%. Layout build 170 ms both.
- Tools: `tests/client_smoke/biome_maps.gd` (top-down maps and numbers per version) and
  `biome_shots.gd` (the same views on v2 and v3, noon, golden, night).

## What didn't work
- First pass let the pine hills reach the snow line: white caps on hills all over the island.
  Snow is now the heart's alone.
- Marsh at 0.9 m +- 2.0 read as a lake from the ground; 1.0 +- 2.4 with the pool noise keeps
  more hummocks. Software GL draws every pool white (the sea shader's sky term), like the lakes.
- Pine hills looked bald: scatter pines stopped at slope 0.8 and the ground turned to rock at
  0.55. Both are raised on pine hills only.

## Known risks / notes to next week
- An installed client older than this PR clamps gen 3 to 2 and would draw the wrong ground.
  Clients self-update on launch and the wipe sends everyone off, so only a client left open
  since before this release and re-logging without a restart is at risk. If it bites, bump the
  protocol (owner PR #252 takes v14 first).
- Steeper ground: nothing limits climbing today; grazers keep under 14 m.

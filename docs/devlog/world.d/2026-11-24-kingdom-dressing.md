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

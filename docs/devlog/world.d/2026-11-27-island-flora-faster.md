## 2026-11-27: island flora in half the time (ws/builder/island-flora-faster)

Item: world backlog, "Basics 3: flora on the island in chunks" (fewer tries, or per chunk).
Fun: the island is there sooner after you land, with not one plant moved.

### What shipped
- `Flora._scatter` asks its cheap looks first: the spawn ring, then the ground's height and a
  per-kind `ground(x, z, y)` test (height band on Ashgrove and for birches; biome for kingdom
  boulders and flowers, with the flower-meadow noise mask before the biome), then road and ruin
  pads, then slope and the rest, then nodes and blockers, and the 50 us `near_sand` ring last.
  RNG draws are unchanged and every test is a pure filter, so the output is identical.
- `Props.ruin_pads()` / `Props.on_pad()`: the ruin-pad test on a flat `PackedFloat64Array`
  (64-bit on purpose, so the edge compares exactly like `_on_ruin`'s doubles). Used by Flora
  and by the kingdom prop scatter, which also now asks road and pads before `near_sand`.
- Measured warm, after Props and ResourceNodes are built (headless, this box):

  | World | Flora before | after | spots (same hash) |
  |---|---|---|---|
  | Ashgrove | 75 ms | 69 ms | 630 |
  | kingdom 77, 1400 m | 1884 ms | 1022 ms | 2258 |
  | island 1126, 1200 m (clamped to 1500) | 1728 ms | 1067 ms | 2293 |
  | island 1126, 3000 m (live) | 2047 ms | 987 ms | 2351 |

  `Props.scatter` and every `Flora.spots()` hash match before and after on all four.
- `tests/unit/test_world_flora_speed.gd`: a frozen copy of the old scatter must give the same
  spots, in order, on Ashgrove, a kingdom and an island; `on_pad` agrees with `_on_ruin` on
  4000 probes.

### Why not per chunk or fewer tries
Fewer tries (the item's other idea) would move or drop plants, and the solids the camera and
server read come from the same spots; identical output costs no review. Per-chunk flora is
client's warm-up item (WorkerThreadPool behind ShoreCover); this makes that thread's job
shorter. Didn't touch `worldgen.gd` or `island_gen.gd` because the owner's PR #253 changes them.

### Notes to next self
- Where the island's remaining load time goes (3 km, warm): `Props.scatter` about 3.1 s, most
  of it 43,891 tries each paying `Terrain.height` (12 us) plus `biome_for` (12 us), and about
  0.6 s in `near_sand` for 9,557 survivors; the first call also builds ResourceNodes. Flora
  about 1.0 s: birches still take 12,720 tries for 14 trees on an island (2,893 of them pay the
  eight-probe shore ring). Next wins: a coarse height/biome grid shared by both scatters as a
  pre-reject (needs care to stay identical), or let client's warm-up run them off the main
  thread.
- Per-call costs measured here: `Terrain.height` 12 us, `biome_for` 12 us, `near_sand` 50 us,
  `_on_ruin` 11 us (now ~2 us as `on_pad`), `road_distance` 1.6 us, `ResourceNodes.near` 3 us.

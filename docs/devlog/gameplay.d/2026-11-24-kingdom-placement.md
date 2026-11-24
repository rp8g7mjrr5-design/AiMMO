# Kingdom placement: nodes, ruins, herds, bench and spawn on a generated world (ws/gameplay/kingdom-placement)

**Why this item.** The top two backlog items needed a protocol bump (world config on the wire,
stance events), and PR #197 (character customization, owner thread) holds protocol v8 and
migration 0004 while it waits on #192. `docs/workstreams.md` allows one bump PR at a time, so a
second bump now would collide. Part 3 ("nodes, ruins and spawn on a generated world") was
waiting only on world's generator, which landed in #204, and it needs no wire change: so it
went first. Part 2 is next, the moment #197 lands (or as v9 on top of it).

**Fun it unblocks.** Every world a new kingdom: when the config goes on the wire and the live
world moves, a fresh character lands on a generated spawn plot with the starter ring around
them, the bench beside them, herds in the hills and graded ruins down the king's roads, and the
whole gather and craft loop already works there (proved end to end in a unit test).

## What changed
- `ResourceNodes.generate()`: on `gen_version` 1 the list is `WorldGen.node_spots()` in order
  (index = id), then a tier-2 ring of 8 (old ash / rich seam alternating) around the kingdom
  spawn with its own rng (`seed + TIER2_SEED_OFFSET`), avoiding roads, the river, ruins, water
  and snow. Ashgrove keeps its three passes and every id (the fingerprint test still pins it).
  `_place_wild` bounds by `WorldGen.half_size()` (256 on Ashgrove, so no change).
- The node and herd caches rebuild by themselves when `WorldGen.config()` changes, plus
  `ResourceNodes.reset()`. I chose auto-detect over reset-only because world's tests and the
  client's `--world=` flag configure WorldGen without knowing about ResourceNodes.
- `Wildlife`: herds ring `WorldGen.spawn_point()`, seed from the config's seed (Ashgrove's is
  `WORLD_SEED`, spawn the origin: identical herds), `good_ground` bounds by `half_size()`.
- `Crafting.workbench_xz()` / `workbench_pos()` / `near_bench()`: the bench is
  `WORKBENCH_XZ` from spawn. World's bench prop already draws at `workbench_pos()`.
- New `game/shared/ruins.gd` (`Ruins`): sites with grade name (Quiet, Uneasy, Grim, Deadly) and
  a label, `at(pos)`, `nearest(pos, grade)`, `title()`, `describe()`. Data only today.
- Server: `--world=seed:gen:size` / `AIMMO_WORLD` (WorldGen.parse; unset is Ashgrove),
  `use_world(cfg)` before anything else, a `world:` log line, new characters and "Return to
  Spawn Meadow" use `WorldGen.spawn_point()`, and `place_on_this_world(ch)` moves a character
  who would log in past the border or in water to spawn (never on Ashgrove).

## Tests
- `test_gameplay_kingdom_world.gd` (9 tests, seeds 11 and 2024): Ashgrove fingerprint, herds
  and bench survive a trip to a kingdom; caches follow the config; nodes follow WorldGen's
  spots in order and are stable over a rebuild; every kind within a minute's walk of spawn;
  tier-2 ring 48 to 140 m out with room round each; bench by spawn on dry land; herds on good
  ground; ruins of all four grades with the must-have kinds; a fresh character logs in, lands
  at the kingdom spawn, gathers ash and stone, crafts a stone axe at the bench; water and
  out-of-world characters move to spawn, inventory untouched.
- No new bot behaviour: the bot test runs Ashgrove (the live world), and nothing a player does
  changed there. When qa can start a server with `--world=`, a kingdom phase would be the real
  check (follow-up).

## Didn't work / watch
- First draft of the ruin test read `.id` from `Ruins.at()`'s empty result: fixed with `get`.
- The welcome line still says "Welcome to Ashgrove" on a kingdom. Change it with the move.
- Kingdom node counts are big (hundreds of spots on 1200 m): `ResourceNodes.describe()` now
  includes the tier-2 count; watch the snapshot of `s2c_nodes` size once a kingdom goes live.

## Next run
- Part 2 (config on the wire) as soon as #197 is merged or closed: put it in the next bump.
- The live move to a generated map stays a separate, announced step (follow-up in the backlog).

## Test runs
- Unit tests: 847 pass (with Postgres). Client smoke test passed (world build about 2 s).
- Bot test (8 bots, 180 s, WebSocket): the first run failed once on
  `[gameplay_wildlife] grazer 12 bolted but no herd-mate went with it`. That is the same flake
  week-00's devlog saw on #172 (a client-only PR); herds on Ashgrove are bit-identical here
  (unit test checks every herd position before and after a kingdom trip). The rerun passed.
  The flake is ours: see the follow-up in the backlog note.

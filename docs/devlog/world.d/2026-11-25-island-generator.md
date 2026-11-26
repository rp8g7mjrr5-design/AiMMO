# World: generator v2, the island (2026-11-25, owner thread "Plan randomly generated map")

The owner picked an island over the one-coast map, 3 km, beach landings, the Spawn Meadow as a
random place, every place rolling its own layout, and monthly automatic wipes. This PR is the
generator only; nothing changes for players until the official world moves onto an island.

What shipped:
- `game/shared/island_gen.gd` (`IslandGen`), `gen_version` 2. WorldGen still owns the config
  and API and hands the layout to IslandGen, which fills the same `_L` keys so WorldGen's pads,
  rasters, roads and node spots work unchanged. Version 1 is untouched (all its tests pass).
- New API on WorldGen: `is_island()`, `landings()`, `landing_for(key)`, `road_kinds()`;
  `rivers()` gives every river. `Ruins.all()` carries `layout_seed` and `rot` per site.
- `CharacterData.new_for` puts a new character on a landing picked by their name hash
  (`landing_for`); Ashgrove and v1 still give `spawn_point()`.
- `WorldMap` marks every landing. Map sheet of six seeds:
  `/mnt/project-files/world/map-design/island-6-seeds.png`.
- `tests/unit/test_world_island.gd`: sea at the border, landings dry and by the water and
  spread out, must-haves present, grades rise inland, flat pads, no overlaps, unique layout
  seeds, nodes on land and a starter ring at every landing, every place reachable on foot.

Numbers (3 km, this container): layout 0.12 to 0.3 s; node spots 1.7 to 2.1 s (about 4,100
spots); 30 to 38 locations; 7 landings; 2 rivers. A 4 km layout is still well under 2 s.

Tried and changed:
- First landing search rejected every beach: the beach band sits at 0.9 m and the check wanted
  1.0 m. Then a ray that crossed a river stopped there; it now walks over inland water and
  only stops at the sea, and gives up on cliff stretches.
- Mountains at the heart first read as a white starfish on the map (ridge noise at full
  strength); the ridge height now follows the uplift noise, so peaks vary.

Known gaps and notes to next time:
- The client still builds terrain for the whole map at once: a 3 km island is ~2,200 chunk
  meshes. Chunk streaming (world backlog, "a generated map that loads fast") must land before
  the official world moves.
- Roads cross rivers as fords (no bridges yet). Toll bridges sit beside a river, not on a road
  crossing.
- Node spots cost ~2 s at 3 km on the server and again on the client; cache or move to chunks.
- Set pieces should read `layout_seed` and `rot` from `Ruins.all()` so the same kind looks
  different on every site.

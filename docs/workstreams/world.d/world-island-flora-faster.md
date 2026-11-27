Done: **Basics 3: flora on the island in chunks** (ws/builder/island-flora-faster)
Flora's scatter runs cheap looks first: about half the time (2.0 s to 1.0 s on the live 3 km island), identical spots.

Follow-ups:
- [ ] **Basics 3: the prop scatter in half the time.** `Props.scatter` is now the island's biggest data cost (about 3.1 s on 3 km: 44k tries each paying `Terrain.height` and `biome_for`). A coarse pre-reject (sea, sand) shared with Flora, kept identical by a frozen-copy test like `test_world_flora_speed.gd`. Touches `worldgen.gd`/`island_gen.gd` only after owner PR #253 lands. *Fun: the island is there the moment you land.*

Note: **Basics 3: landmarks on the map** looks done by client's map window (#246): `MapWindow.marks()` names every ruin with its grade and every beach landmark, and `WorldMap` paints the roads. Integrator, please check and tick it.

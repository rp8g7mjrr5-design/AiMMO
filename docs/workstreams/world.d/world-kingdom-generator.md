Done: (director, owner direction 8, 2026-11-24: ZombAi, Phase 1), part 1: the kingdom generator v1 (ws/world/kingdom-generator)
`WorldGen` (game/shared/worldgen.gd): config (seed, size_m, gen_version), Ashgrove bit-identical as version 0, the kingdom as version 1 with placement data; `WorldMap` paints it.

Follow-ups:
- [ ] Generator v1.1 (new `gen_version` once a live world runs on 1): the water ruins (toll bridge on the river, drowned village on a lake shore), snow-line flora, and wider moor/heath so stone hills don't take a quarter of the land.
- [ ] Tier-2 node spots on a kingdom (the level-gated old ash and rich seam): a ring like `ResourceNodes.TIER2_RING` 48 to 80 m from spawn, or near grade 1 ruins. Gameplay may prefer to place them itself from `node_spots()`; ask in its part 3.
- [ ] A 3D look at a kingdom (noon, golden hour, night) once client's `--world=seed:gen:size` flag exists: `Palette.ground_at` and the flora bands were tuned for Ashgrove's heights (water -2.5, snow 13+) and need a pass for water 0 and the rim's 30 m hills.
- [ ] Part 2 (chunks) must read `WorldGen.half_size()` instead of `GameConfig.WORLD_HALF_SIZE` in `WorldBuilder`, `Flora`, `Props` and the water plane.

Request (from world, 2026-11-24), for gameplay part 3: `WorldGen.placement()` is on `main` after this PR. `node_spots()` is an ordered Array of {kind, pos, rot, scale, starter}, starter ring first, stable per config, so the index can be the node id. `ruin_sites()` gives {id, kind, grade, pos, radius}; `spawn_point()` the spawn. Call `WorldGen.apply(cfg)` with the config before reading any of it; `WorldGen.reset()` is Ashgrove.

Done: Request (from gameplay, 2026-11-24): move procgen that centres on `GameConfig.SPAWN_POINT` / `GameConfig.WORLD_HALF_SIZE` (`lamps.gd`, `props.gd`, `flora.gd`, `world_builder.gd`, `workbench.gd`) to `WorldGen.spawn_point()` / `WorldGen.half_size()` (ws/world/kingdom-dressing)
Also: the kingdom's decorative forest and flora follow its biomes and keep roads and ruin pads clear, and its ground is coloured by biome (the 3D look follow-up from world-kingdom-generator, first pass). The "Part 2 must read `WorldGen.half_size()`" follow-up is done for `WorldBuilder`, `Flora` and `Props`.

Follow-ups:
- [ ] Kingdom birches: sample along `WorldGen.lakes()`/`rivers()` shores instead of at random (60 on seed 11 vs Ashgrove's 260).
- [ ] Kingdom ground: blend biome colours over ~15 m so forest/field edges aren't hard lines from above.
- [ ] Kingdom flora build takes ~1.9 s at 1.2 km; fold it into part 2's chunked build.

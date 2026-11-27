# The coast dressed, dunes behind it (world)

Owner, 2026-11-27, with a screenshot from the whale-bones landing: "our beaches still look
empty :(". The live island's beaches are up to 100 m deep (the outline's beach band runs from
shape 0.94 to about 1.07), and only the 46 m either side of each landing had anything on it.

## What shipped
- `CoastDress` (procgen, pure, cached per world): walks the coast by bearing every 3 m
  (`WorldGen.coast_at`), finds each beach's cross-section (first dry ground walking in from
  120 m out, back of the "shore" biome), and lays kelp strips on the tide mark, shells and
  pebbles, drift logs (with branch stubs and root plates), rock clusters and boards. About
  12k parts on the live island, on BeachProps' existing layers, meshes and materials (no new
  material or draw-call layer), so BeachProps.parts() just appends them. Clear of the lantern
  ring (BeachGen.CLEAR + 2), landmarks, pickings, roads and river mouths. All rolls are
  drawn up front each step, so a skipped step never shifts the next. Adds ~1.1 s to the
  island world build.
- Dunes: `IslandGen.beach_depth` (0 where the sea starts, 1 at the back of the sand, with
  biome_for's wobble) and `Palette.dune_weight` (that, times "at least 0.7 m above the sea").
  The terrain paints `Palette.DUNE_GRASS` over the back of the beach and `Grass` grows marram
  there, both from the same weight, so the open sand is about the front half of the beach.

## Tried and dropped
- beach_depth from `inland` alone: inland is 0 everywhere past shape 1.0, which is half of
  these beaches, so the dunes never showed. Now from the raw shape.
- `Basis.scaled()` scales in world axes: the first drift logs stood on end like posts. Now
  `basis * Basis.from_scale()`.
- The sand band itself was not narrowed: biome_for decides node placement, and changing it
  re-rolls every node id after the first changed cell. Painting the back as dunes does it
  for the eye without touching gameplay.

## Notes to next run
- Real dune relief (height) would need a terrain change to gen v2. Nodes don't care about
  height, but saved campfires do, so it waits for a new gen_version or a wipe.
- Shots: `/mnt/project-files/beach-dressing/` (seed 1126, landings 2 and 6, before and after).

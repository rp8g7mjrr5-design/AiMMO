# Trees off the beach, palms on it (world)

Owner, 2026-11-27: "We need to make sure the map looks correct. Trees shouldnt be on the beach.
Palm trees maybe." Island (gen v2) only for anything that moves; Ashgrove is untouched.

## What shipped
- `WorldGen.near_sand(x, z, r = 5)`: true when "shore" or "water" lies within r (centre, 6 at
  r/2, 10 at r). Skips high ground and any point whose local slope can't reach sand height
  (`SAND_TOP` 2.2) within r, so it costs ~3 height reads for most land. False on Ashgrove.
- Decorative trees and rocks (`Props._scatter_kingdom`) and birches, boulders and flowers
  (`Flora`) skip spots near sand on generated worlds. Same rng draws, so only the beach-side
  ones go. Birches on islands drop from ~60 to ~15: most of them were on the sea beach,
  because their "water within 9 m" rule saw the sea. The rest stand by lakes and rivers; on
  generated worlds the birch looks 5 m further for its water.
- Tree nodes: `WorldGen._trees_off_sand` (island only) walks every ash or pine node spot near
  sand to the nearest free, dry spot within 100 m (rings of 2.5 m, 16 bearings; road, river,
  ruin, spacing and snow rules as for placement). Spots move but are never added or dropped,
  so ids, kinds and counts are unchanged; it draws nothing from the placement rng. The tier-2
  ring around the spawn plot skips sand for trees. Stones and scrub may stay on sand.
  Nothing about nodes is saved (only depletion, in memory), so moving them can't break a save.
  The live island's landing beaches are up to ~70 m deep, which is why the reach is 100 m (30
  and 60 left some starter trees on the sand).
- Palms (`Flora`, kind "palm", appended last so every other spot is where it was): the coast is
  walked by bearing from the island centre (`WorldGen.coast_at`, outline maths only), one look
  per 7 m of coast; a coast noise picks the groves; dry sand only (above the wet band, under
  3 m), clear of landings (`BeachGen.CLEAR` + 6), landmarks, nodes, roads, river mouths and
  ruins. ~115 palms on the live island. Parts: 6 trunk pieces leaning further each (curved,
  seaward), leaf-scar rings, 11 fronds (two dry ones hanging lowest), 3 nuts. New frond mesh
  built with SurfaceTool, both faces, because the shared material culls back faces. Colours
  in `Palette.PALM_*`. Chunked layers with tree draw distances; rings and nuts cast no shadow.
- Dune fringe: `IslandGen.sand_margin` (same rule and wobble as the "shore" biome) and
  `Palette.DUNE_FRINGE` lerp the first band of turf toward sand, so the 4 m terrain
  triangles don't show a hard green/sand staircase at the back of the beach.

## Tried and dropped
- Fronds 0.55 wide looked like spider legs; 0.95 wide with 11 fronds reads as a palm crown.
- Fringe at 0.8 over a 2% band turned whole meadows sandy; 0.65 over ~1.4% looks like dune grass.

## Notes to next run
- Palms are decoration only (no node). If the owner wants to chop them, a "palm" node kind with
  its own stump would fit the beach pickings.
- The blocky sand edge is softened, not gone: terrain colour is one flat colour per 4 m
  triangle. A real fix is per-vertex sand weight, which changes the faceted look everywhere.
- Before/after shots: `/mnt/project-files/beach-trees/` (seed 1126, the live world).

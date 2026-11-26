# The world fits the clean carved characters (world)

Owner, 2026-11-26: "We need to make sure the map now fits with our new characters", then mid-way
switched the characters from the goofy cartoon to direction B, "clean carved real proportions".

## What changed
- `Emberlight`: `texel_grain` defaults to 0 (was 0.09), `PAINT` mixes are all 0 (SurfaceTex
  detail off; the named bark/stone/ground materials stay so the material count and tests hold),
  brush noise is broader and softer (0.07 -> 0.035, lower frequency).
- New `facets` uniform (default 1.0): the fragment normal is `cross(dFdx(VERTEX), dFdy(VERTEX))`,
  so every triangle is lit as one flat plane. Free: no mesh rebuilt, no vertex added, works on
  Forward+ and Compatibility. It applies to the folk material too (the B characters are flat-lit
  anyway); a material that wants smooth normals sets `facets = 0.0`.
- `TerrainMesh.material()` no longer sets its own 40 cm grain.
- `Grass.blade_image()`: 16 straight-tapered blades on 128 x 64, two flat shades per blade (a
  folded leaf), read with `filter_linear_mipmap` instead of 28 one/two-texel lines with nearest.

## What I tried that didn't work
- First pass (before the owner switched to B) went the goofy-toy way: smooth-shaded terrain,
  rounder crowns and rocks with more segments, chunkier lamps. Round crowns cost ~200k scene
  triangles (render budget 560k primitives; it measured 700k at noon), and lean custom meshes
  (open trunks, fan-capped balls) won it back, but none of that fits clean carved, so it was
  dropped. Note: NodeProps' stone and crown ring counts are pinned by WorldSolids' columns
  (`test_world_closeup`, `test_world_tier2_props`); changing rings needs the columns refitted.

## Notes to self
- Shots: `world/clean-carved/island_look.gd` in the project files (scratch, not CI) renders the island at a landing with
  the carved B folk standing in it.
- The carved folk have their own material with flat per-face normals, so `facets` changes nothing on them.

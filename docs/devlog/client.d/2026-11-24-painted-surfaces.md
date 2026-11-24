# Painted surfaces and clearer days (ws/client/painted-surfaces)

**What:** first step of moving the owner-approved test-camp look into the game ("lets try it"), textures and lighting; grass and the new characters follow as their own PRs.
- `SurfaceTex` (procgen): four 64 px brightness-only detail images made in code (ground, bark, stone, wood), mean 0.5 so they never shift a colour's brightness, mipmapped.
- Emberlight: one optional `paint_tex` sampler, triplanar on the world normal, `paint_mix` 0 by default. `Emberlight.painted(kind)` gives one shared material per kind. Terrain is painted "ground"; scatter trunks, birch bark, node trunks and stumps "bark"; rocks, mossy rocks and node stones "stone". World materials 12 -> 14 (ceiling raised on purpose in render_baseline.json; same draw calls and primitives, +0.02 MB textures).
- Light: sun energy by day 1.0 -> 1.3 (`SkyClock.DAY_LIGHT`), noon sky keys bluer with a cooler horizon, fog 0.006 -> 0.0045 (still ~93% solid at the 600 m draw distance), height haze 0.035 -> 0.02. SSAO (half resolution, low quality) on Medium and High via `Quality.ambient_occlusion()`; Compatibility ignores it.

**Tried:** detail at 0.45 mix and 0.5 repeats/m was invisible on the CI (Compatibility) shot and barely there on Forward+; 0.7 / 0.6 reads. Plain nearest filtering shimmered in the distance, so the images are mipmapped (`filter_nearest_mipmap`).

**Known:** the noon style check now notes warmth 0.051 vs baseline 0.123 (-0.072, under the 0.08 "big" limit): the noon frame is cooler and bluer on purpose. Golden hour is unchanged. Workbench and campfire wood/stone are not painted yet (follow-up). Shots: `/mnt/project-files/art-direction/in-game-look/` (Forward+ on lavapipe, before on top).

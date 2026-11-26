# World: terrain streamed around the camera (2026-11-25, owner thread "Plan randomly generated map")

The second step toward the island going live: a big map must open at once.

Measured on a 3 km island in this container (headless), before -> after:
- Terrain: 29.2 s -> 0.29 s. `TerrainStream` builds the chunks within 160 m of the start up
  front and streams the rest on one background thread out to 680 m (camera far 600 m plus half
  a chunk diagonal), nearest first, and frees chunks past 820 m. The thread only runs
  `TerrainMesh.chunk_arrays` (maths, no RenderingServer); the main thread wraps at most 4
  finished chunks a frame.
- `Props.scatter` is cached per world: it was worked out three times (world, flora, camera
  solids), 1.7 s each on an island. Props build 1.8 s -> 0.17 s, solids 2.1 s -> 0.21 s.
- Ashgrove (64 chunks) is still built whole, in the same order, same props tree for tree.

Still slow on a 3 km island (about 8 s of pure data, all on the main thread today):
node spots 1.9 s, `Props.scatter` 1.6 s, `Flora.spots` 3.4 s, flora meshes 1.2 s, node props 1.0 s.
Next: the client follows `s2c_world` (it doesn't yet: `net.world_config` has no listener), works
those out on a thread behind a short "washing ashore" cover, then builds the world.

Gotcha: freeing a MeshInstance3D on the headless dummy renderer logs `Parameter "m" is null`
once per mesh; tests that free terrain call `expect_error` for it (as the material-budget test does).

Later the same day: `Terrain.height` on an island was 26 us a call, 11 us of it walking all ~40
flat pads. An island now keeps a pad lookup grid (`WorldGen._index_pads`, 64 m cells, pads in
their original order, so heights are identical): 8.7 us a call. That makes every placement pass
3x cheaper on a 3 km island: node spots 1.9 -> 1.1 s, props scatter 1.6 -> 0.9 s, flora spots
3.4 -> 1.7 s. Whole-world build data left: about 5.5 s (was about 42 s with whole terrain).
Version 1 and Ashgrove don't use the grid (their code path is untouched).

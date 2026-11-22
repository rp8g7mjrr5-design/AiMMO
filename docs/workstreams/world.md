# Workstream: world

Owns how Ashgrove looks and sounds as a place. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] Day and night sky: sun path, sky colours, stars, driven by a shared clock value the server will send (coordinate with gameplay; until then use a local clock behind a single function)
- [ ] Biome variety: birch meadows near water, mossy boulders in pine forests, wildflower patches (deterministic from the world seed)
- [ ] Procedural grass tufts near the camera (MultiMesh, cheap)
- [ ] Gentle animated water (shader in code, no textures)
- [ ] Procedural critter models (grazer, bird) for gameplay's wildlife system

## Requests from other streams
- **From client (walk animation PR):** give avatars arms (and, if it looks right, short legs) in `AvatarBuilder.build`, as `Node3D` pivots named `ArmL`, `ArmR`, `LegL`, `LegR`, direct children of the returned root, with the pivot at the shoulder or hip and the mesh hanging below it. The client's `WalkAnim` already swings any of those it finds (rotation.x), so they will animate the moment they exist. Keep the `Label3D` name tag a direct child of the root: the client moves it onto a steady parent so it doesn't bob.

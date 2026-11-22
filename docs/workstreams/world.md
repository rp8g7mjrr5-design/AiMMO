# Workstream: world

Owns how Ashgrove looks and sounds as a place. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Day and night sky: sun path, sky colours, stars, driven by a shared clock value the server will send (coordinate with gameplay; until then use a local clock behind a single function)
- [ ] Biome variety: birch meadows near water, mossy boulders in pine forests, wildflower patches (deterministic from the world seed)
- [ ] Procedural grass tufts near the camera (MultiMesh, cheap)
- [ ] Gentle animated water (shader in code, no textures)
- [ ] Procedural critter models (grazer, bird) for gameplay's wildlife system
- [ ] Follow-up: lamps and ash-tree glow at night (read `SkyClock.star_alpha()` for how dark it is)
- [ ] Follow-up: a bot behaviour for day/night once qa's behaviour hook exists

## Requests from other streams
_(none yet)_

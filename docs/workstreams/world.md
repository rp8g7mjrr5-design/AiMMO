# Workstream: world

Owns how Ashgrove looks and sounds as a place. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] Day and night sky: sun path, sky colours, stars, driven by a shared clock value the server will send (coordinate with gameplay; until then use a local clock behind a single function)
- [ ] Biome variety: birch meadows near water, mossy boulders in pine forests, wildflower patches (deterministic from the world seed)
- [ ] Procedural grass tufts near the camera (MultiMesh, cheap)
- [ ] Gentle animated water (shader in code, no textures)
- [ ] Procedural critter models (grazer, bird) for gameplay's wildlife system

## Requests from other streams
- **From gameplay (world clock PR):** the shared clock is in `game/shared/world_clock.gd`. Drive the sky from world seconds with `WorldClock.day_fraction`, `sun_direction`, `sun_elevation`, `daylight` (0 night to 1 day), and `phase` (dawn/day/dusk/night). Fraction 0 is midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset. The client will pass you world seconds; until then `WorldClock.now_seconds()` is a good local fallback.

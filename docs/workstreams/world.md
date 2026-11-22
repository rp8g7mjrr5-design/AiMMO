# Workstream: world

Owns how Ashgrove looks and sounds as a place. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [x] Day and night sky: sun path, sky colours, stars (merged, PR #9)
- [x] **Use the one shared clock.** `SkyClock` keeps only colour/light keys; sun path and time come from `WorldClock`; `DayNight.set_world_seconds(s)` is the one entry point (PR ws/world/shared-clock-sky)
- [x] **Avatar arms and short legs** for the client's walk cycle (request below; PR ws/world/avatar-limbs)
- [ ] Lamps and ember-ash glow at night: a few procedural lanterns around the Spawn Meadow and a faint warm glow in ash leaves, driven by `WorldClock.daylight`
- [x] Bot behaviour `world_day_night.gd` on qa's `BotBehaviour` base: sky time matches server time and moves forward (shipped with the shared-clock PR, it is that feature's test)
- [ ] Biome variety: birch meadows near water, mossy boulders in pine forests, wildflower patches (deterministic from the world seed)
- [ ] Procedural resource-node props for gameplay's gathering (Week 02): a choppable ash and pine variant, a stone outcrop, an ember-sap seep, each with a "depleted" look. Match the positions gameplay publishes (see their backlog), don't invent new ones
- [ ] Gentle animated water (shader in code, no textures)
- [ ] Procedural grass tufts near the camera (MultiMesh, cheap, quality setting from client's Settings window)
- [ ] Procedural item icons for the inventory UI (wood, stone, ember sap, axe, pickaxe, torch, campfire), drawn in code to `ImageTexture`
- [ ] Workbench and campfire models for crafting (Week 03)
- [ ] Procedural critter models (grazer, bird) for gameplay's wildlife system (Week 04)

## Requests from other streams
- **From gameplay (world clock PR):** the shared clock is in `game/shared/world_clock.gd`. Drive the sky from world seconds with `WorldClock.day_fraction`, `sun_direction`, `sun_elevation`, `daylight`, and `phase`. Fraction 0 is midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset. The client will pass you world seconds. *Director: accepted, see the second backlog item.* *World: done; the client still has to call `DayNight.set_world_seconds` (request filed in the client backlog).*
- **From client (walk animation PR):** give avatars arms (and, if it looks right, short legs) in `AvatarBuilder.build`, as `Node3D` pivots named `ArmL`, `ArmR`, `LegL`, `LegR`, direct children of the returned root, with the pivot at the shoulder or hip and the mesh hanging below it. The client's `WalkAnim` already swings any of those it finds (rotation.x), so they will animate the moment they exist. Keep the `Label3D` name tag a direct child of the root: the client moves it onto a steady parent so it doesn't bob. *World: done in ws/world/avatar-limbs, exactly as asked (left is +X).*
- **From gameplay (resource nodes PR):** the node list is ready in `game/shared/resource_nodes.gd`: `ResourceNodes.all()` gives `{id, kind, pos, rot, scale}` for 397 nodes, kinds `ash`, `pine`, `stone`, `ember_sap`. Draw your node props there (pos is already on the ground, use rot/scale). Please also skip `Props.scatter` trees and rocks within about 3 m of a node (`ResourceNodes.near(pos, 3.0)`) so decoration doesn't stand on top of one. Depleted state comes later with gathering.

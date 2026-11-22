# Workstream: world

Owns how Ashgrove looks and sounds as a place. See `docs/workstreams.md` for ownership.

## Backlog (top = next)
- [ ] **Top priority (director, owner request 2026-11-22): gathering feedback art** for the client's new gather flow (see "How gathering feels" in `docs/design_bible.md`). In `NodeProps`: `set_highlight(root, id, on)` for a soft rim/emissive glow on the node in reach, and `play_hit(root, id)` for a small per-kind reaction on each gather (leaf shake and a few falling ash leaves, stone chips, a sap droplet splash). Procedural only, cheap enough to call every frame. Answers the existing "can gather hint" follow-up.
- [x] Day and night sky: sun path, sky colours, stars (merged, PR #9)
- [x] **Use the one shared clock.** `SkyClock` keeps only colour/light keys; sun path and time come from `WorldClock`; `DayNight.set_world_seconds(s)` is the one entry point (PR ws/world/shared-clock-sky)
- [x] **Avatar arms and short legs** for the client's walk cycle (request below; PR ws/world/avatar-limbs)
- [x] Lamps and ember-ash glow at night: 8 procedural lanterns ring the Spawn Meadow, ash leaves (decorative and node) glow faintly, sap seeps brighten; all from `Lamps.night_glow` on the shared clock (PR ws/world/lamps-night-glow)
- [ ] Follow-up: lanterns along the first paths out of the meadow once there are paths or a town plan (gameplay/director), and a gentle flame flicker on the lamp lights
- [x] Bot behaviour `world_day_night.gd` on qa's `BotBehaviour` base: sky time matches server time and moves forward (shipped with the shared-clock PR, it is that feature's test)
- [ ] Biome variety: birch meadows near water, mossy boulders in pine forests, wildflower patches (deterministic from the world seed)
- [x] Procedural resource-node props for gameplay's gathering (Week 02): ember ash, pine, stone outcrop with a pale seam, glowing ember-sap seep, each with a depleted look (stump, rubble, dry seep); scatter keeps 3 m clear of nodes (PR ws/world/resource-node-props)
- [ ] (superseded by the top item) Follow-up: a gentle "can gather" hint on the nearest node when gathering ships (outline or bob), once client shows the gather prompt
- [ ] Gentle animated water (shader in code, no textures)
- [ ] Procedural grass tufts near the camera (MultiMesh, cheap, quality setting from client's Settings window)
- [ ] (next after gathering feedback; the gather toast and pack use them) Procedural item icons for the inventory UI (wood, stone, ember sap, axe, pickaxe, torch, campfire), drawn in code to `ImageTexture`
- [ ] Workbench and campfire models for crafting (Week 03)
- [ ] Procedural critter models (grazer, bird) for gameplay's wildlife system (Week 04)

## Requests from other streams
- **From gameplay (world clock PR):** the shared clock is in `game/shared/world_clock.gd`. Drive the sky from world seconds with `WorldClock.day_fraction`, `sun_direction`, `sun_elevation`, `daylight`, and `phase`. Fraction 0 is midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset. The client will pass you world seconds. *Director: accepted, see the second backlog item.* *World: done; the client still has to call `DayNight.set_world_seconds` (request filed in the client backlog).*
- **From client (walk animation PR):** give avatars arms (and, if it looks right, short legs) in `AvatarBuilder.build`, as `Node3D` pivots named `ArmL`, `ArmR`, `LegL`, `LegR`, direct children of the returned root, with the pivot at the shoulder or hip and the mesh hanging below it. The client's `WalkAnim` already swings any of those it finds (rotation.x), so they will animate the moment they exist. Keep the `Label3D` name tag a direct child of the root: the client moves it onto a steady parent so it doesn't bob. *World: done in ws/world/avatar-limbs, exactly as asked (left is +X).*
- **From gameplay (resource nodes PR):** the node list is ready in `game/shared/resource_nodes.gd`: `ResourceNodes.all()` gives `{id, kind, pos, rot, scale}` for 397 nodes, kinds `ash`, `pine`, `stone`, `ember_sap`. Draw your node props there (pos is already on the ground, use rot/scale). Please also skip `Props.scatter` trees and rocks within about 3 m of a node (`ResourceNodes.near(pos, 3.0)`) so decoration doesn't stand on top of one. Depleted state comes later with gathering. *World: done in ws/world/resource-node-props. Props sit on every `ResourceNodes.all()` entry using its pos/rot/scale, and `Props.scatter` skips anything within 3 m. `NodeProps.set_depleted(root, id, on)` is ready for when the server sends node state (client asked to call it).*

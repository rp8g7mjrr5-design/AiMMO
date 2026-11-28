# Camera solids for the ruins and beach landmarks (ws/builder/landmark-camera-solids)

Fun: searching a ruin or the wreck you woke beside, the camera slides in front of the wall or
hull instead of showing you the inside of a stone or a black hull from within. Backlog item
"Camera solids for the ruins and beach landmarks" (world), picked because it is world-only
files and every open owner PR (#252 thirst: server, client.gd, crafting, net) stays untouched.

### What shipped
- `WorldSolids.landmark_solids()`: one solid per `RuinKit.parts(r)` part (every ruin with a
  plan) and per `BeachProps.landmark_parts(lm, b)` part (every beach landmark), added to
  `all()` after the workbench, so the existing test's order and the camera's `near()` are
  unchanged for everything else. Ashgrove has none.
- `part_solid(source, xform, mesh)`: the mesh's vertex AABB under the part's transform, cut by
  `box_columns` into cells about `CELL_SIZE` (0.8 m) along each edge's plan length (an upright
  edge is not cut, a column has its own height), at most 16 per axis. One column per cell
  holding its eight corners, so the union holds the whole box and so every vertex (the kit's
  meshes are all unit box, cylinder and sphere, inside their AABB). Why not `solid_of`: one
  column per part round its centre makes a 5 m wall a 2.5 m-radius invisible pillar and the
  camera would pull in a metre off the wall. Cells keep a 0.5 m wall's columns under 0.45 m.
- Parts under 0.3 m every way (ropes, boots) get none. Base = the part's lowest corner under
  its centre.
- `tests/unit/test_world_landmark_solids.gd`: every vertex of every landmark part inside its
  solid on seed 1126, order matches, Ashgrove empty, a long wall cut thin (clear half a metre
  off its face, past its end and above), no column wider than a metre, the camera arm stops in
  front of a wall, and a sweep of camera spots round the real landmarks never ends inside one.

### Not done / notes to next self
- No bot behaviour: nothing a player does or sends changed; the camera is client-only and
  `client_camera_solids.gd` already reads every `WorldSolids` kind.
- Coast dressing (`CoastDress.parts()`) is left out on purpose (follow-up in the backlog note).
- Cost on seed 1126: 955 solids, 2694 columns, built in 17 ms inside the existing
  `WorldSolids.all()` warm-up in `WorldBuilder.build()`. The lying mast (6.5 m) raises
  `_max_reach` to 6.5 m, so `near()` reads a cell or so more per query; negligible.
- Players still walk through walls (no movement collision); that is a gameplay question, not
  this item.

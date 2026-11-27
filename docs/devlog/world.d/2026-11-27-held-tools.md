Builder run, world "Basics 2: held tools and weapons."

### Why this item
Top of the basics I could take without touching the owner's open work: PRs #245 to #248 and
recent owner branches touch `client.gd`, `server.gd`, `net.gd`, `palette.gd`, `flora.gd`,
`world_map.gd`, `item_icons.gd` and the node props, so the gameplay items (hunger is the owner's
#245; loot and the bench need `server.gd`) and most client items were out. This one is a new
file only, and it unblocks client's "weapon in your hand". Fun: you see the axe you just made
in your hand and in your friend's, and a stone tool looks like an upgrade.

### What shipped
- `game/procgen/held_items.gd` (`HeldItems`): wooden and stone axe and pickaxe, wooden club,
  stone maul, wooden and stone spear, torch. Low-poly solids, flat shaded on `Carved.material()`
  (no grain), colours derived from `Palette` (no literals, no palette.gd edit because the owner
  has three PRs on it). 1.2x real size (art bible section 3): axes 0.63 m, picks 0.72 m, club
  0.76 m, maul 0.78 m, spears 1.93 to 1.97 m, torch 0.81 m with flame. Each under 400 triangles,
  one surface; the torch has a second surface for its flame on the Emberlight glow material
  (vertex alpha 0), the only glow (direction 11).
- Item space: grip at the origin, haft along +Y, striking side +Z. `GRIP` maps it onto the
  RightHand bone so that with the arm raised forward (rotation.x = -PI/2) the haft points up and
  the edge faces forward: an overhead chop lands edge first. Checked in the unit test.
- `attach(skeleton, id)` adds one `BoneAttachment3D` "HeldItem" on RightHand; same id keeps the
  node (cheap every frame); "", "fists" or anything unknown empties the hand. `held(skeleton)`.
- `tests/unit/test_world_held_items.gd`: every tool, weapon and the torch from Crafting and
  Weapons has a shape, triangle budget, real lengths, heads on the striking side, grip fits the
  carved palm, flat facets, muted solids, only the torch glows, materials, attach and swap.

### Not done / notes to next self
- Nothing is drawn in game yet: client hangs it (request in the backlog note). No bot behaviour,
  because nothing a player does changed (same as the farmstead).
- The headless dummy renderer logs `Parameter "m" is null` for any MeshInstance3D; the attach
  test calls `expect_error` for it.
- Shots (`held-items/` in project files) are from a plain test scene, not the game's sky: the
  torch flame reads bright yellow there because the scene doesn't set the Emberlight heartbeat.
  Check it in game once client draws it; a flicker (scale the flame surface) is client's call.
- The spear is held a third of the way up (0.72 m of shaft behind the hand). If the thrust pose
  looks wrong, move the grip in `parts()` rather than the pose.

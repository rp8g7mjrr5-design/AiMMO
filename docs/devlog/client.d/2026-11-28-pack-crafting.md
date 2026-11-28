Owner request (2026-11-28, project thread): "basic crafting should be done from our inventory
menu ... see our character in this menu looking back at us so we can see our gear." Fun: you
open the pack on the beach, see three logs light the wooden axe row, press Craft, and the new
axe glows in your grid and appears in your figure's hand in the same second.

### What shipped
- `client/craft_panel.gd` (`CraftPanel`): the craft column. Rows come from `CraftWindow.row()`
  so the bench window and the pack never disagree. Order: hand recipes (`bench: false`) first,
  then a quiet "At a workbench" header and the bench recipes, both in `RECIPE_ORDER` so rows
  never jump. Parts as small icons with green/red have/need; a short word ("Carried", "At a
  workbench") when something else holds a row back. One request at a time, a 3 s timeout like
  the bench window. Success is quiet in the column (the chime, the toast and the gold glow on
  the new stack already say it); a refusal shows the server's words in red.
- `client/pack_preview.gd` (`PackPreview`): a SubViewportContainer with its own World3D, one
  `Carved.skinned` figure on your saved look, a warm key and cool fill light, idle breathing from
  `AvatarAnimator`, and `HeldItems.attach` with `held_for(pack)` (the weapon you swing, by
  `Weapons.ORDER`, else your best tool, else a torch). Rendered only while the pack is open
  (`UPDATE_DISABLED` otherwise). Drag to turn. Rebuilt only when the look changes.
- `PackWindow` lays out [figure | grid | craft] (about 1,100 px wide at 1280x720), emits
  `craft_requested`, and `step(delta, pos)` feeds the column where you stand. `client.gd` sends
  it as `c2s_craft` and routes `craft_result` to both the column and the bench window.
- No protocol or server change: crafting `bench: false` recipes anywhere was already allowed by
  `Crafting.check`; only the client never offered it away from the bench.

### Tried, didn't work
- `Carved.build` then freeing its Label3D name tag: the headless dummy renderer logs
  `Parameter "m" is null` on freeing any MeshInstance3D/Label3D, which fails the unit run.
  Used `Carved.skinned` (no tag) and `expect_error` in the one test that builds the figure.
  The bot behaviour never builds the figure for the same reason.

### Next
- The placeable workbench is the owner's third ask; it needs a protocol bump, and the owner's
  thirst PR #252 holds the open bump (one bump PR at a time, docs/workstreams.md). Do it as soon
  as #252 lands (backlog follow-up in client.d).
- The figure could show worn gear once there is gear to wear (armour, a pack on the back).

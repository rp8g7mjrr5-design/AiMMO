## Hunt drop icons (ws/world/hunt-drop-icons)

**Picked.** Gameplay's open request in `world.d/from-gameplay-first-hunt.md` (requests come before the backlog): icons for `hide` and `raw_meat`, which wait in `Inventory.UNDRAWN` and hold back the kill toast. The owner-direction art steps (wilderness lanterns, level-up sparks) are next. The client's knee/elbow pivot request touches `AvatarBuilder`, which two open owner PRs (#196 fuller characters, #192 skinned animation) are rewriting right now, so I left it for after they land rather than build on code about to move. **What a player will feel:** bringing down a grazer pays off on sight: the pack and the toast show a hide and a cut of meat, not two grey "unknown" bundles.

**Built.**
- `Palette.HIDE_FUR`, `HIDE_FLESH`, `RAW_MEAT`, `MEAT_FAT` (with comments). No colour literals added to `item_icons.gd` (art lint count unchanged).
- `ItemIcons` recipes: `hide` is a ragged fur-up pelt with two leg flaps, fur strokes, the top corner turned back to show the pale flesh side, and a dark hide tie. `raw_meat` is a thick cut with a fat rim, marbling streaks and a bone cross-section. Neither has a halo; `tint()` gives each its own colour.

**Tried.** The first meat put the bone top left with streaks below it, and at 128 px it read as a face (bone = eye, streaks = mouth). Moved the bone to the lower right edge and ran every streak one way. The first hide's flesh corner was too close to the fur at 48 px; lightened `HIDE_FLESH` and darkened `HIDE_FUR` a touch.

**Looked at.** Row of every icon at 128 and 48 px, plus a 256 px close-up: project files `world/hunt-drop-icons-row.png` and `world/hunt-drop-icons-close.png`. No world screenshots: nothing in the 3D world changed.

**Tests.** `test_world_item_icons::test_hunt_drops_are_drawn_earthy_and_never_glow` (own icon, no halo, no ember-bright pixels, own tint, meat dark red off ember's hue, hide muted). The existing fill, margin and distinctness tests pick both up automatically through `Inventory.UNDRAWN`. No bot behaviour: nothing new on the network (the drops are gameplay's, already in their bot test), and the art lint keeps procgen out of behaviours.

**Next run.** Gameplay moves the two into `ITEMS` (request filed). Then wilderness lanterns (owner art step 2), or the client's knee/elbow pivots if #196 and #192 have landed.

Builder run (world area), 2026-11-27: loot spots in the shipwreck and the fishing shack
(Basics 4, follow-up from #241, unblocked when owner PR #253 landed). Fun: the wreck you wake
next to pays out inside your first minute, the first rung of the ruin ladder.

### Why this item
Gameplay's top items (the workbench you build, a knock-down that costs something) and client's
HUD line all touch `server.gd`, `client.gd`, `crafting.gd` or `inventory.gd`, which the owner's
open thirst PR #252 changes, so I left them. This one needs none of those files: the server and
the client both read `RuinLayout.all_loot_spots()`, so appending the beach spots there is the
whole hook.

### What shipped
- `BeachGen.LOOT` / `BeachGen.loot_spots()`: two spots per shipwreck (a chest wedged in the
  hull between two frames, a body under a scrap of sail off the planked side) and per fishing
  shack (the shape under the sail the shack already drew, a sack inside the door). Local
  frame is BeachProps'. A spot still in the surf walks up the beach (against `b.sea`, 0.5 m
  steps, up to 20 m) until the sand is `LOOT_DRY` above the water. Reads no rng, so no beach
  moved (test).
- Ids: `ruin_id = BeachGen.LOOT_ID_BASE (1000000) + beach index * 10 + landmark slot`, so
  `Loot.key` never meets a ruin's and `Loot.grade_of` gives 1 (grade 1 table, as the backlog
  item asked). Gameplay: no table change needed; if the beach should get its own table later,
  key it on `spot.landmark`.
- `BeachProps.loot_parts(spot)`: the chest (tarred wood, rusted bands), the sack, and the body
  (sailcloth over a face-down shape, dark head, boots, a hand) on the shared beach layers. The
  shack's body is flagged `drawn` and drawn by `_shack` as before (test checks a part sits on
  the spot).
- `tests/unit/test_world_beach_loot.gd`: spots per landmark, dry, on the ground, apart, clear
  of the beach pickings (the first try put the chest on the stripped side, where the wreck
  crate already lies: 0.1 m apart; moved into the hull), unique keys, grade 1, drawn on the
  spots, beaches unchanged, and a server search at a wreck that pays and empties the spot.

### Not done / notes to next self
- No bot behaviour: CI's bot test plays Ashgrove, which has no beaches. qa's "the island in the
  bot test" item should search one wreck spot when it lands.
- The lifeboat, pier and whale bones have no spots; add them to `BeachGen.LOOT` if a beach
  feels thin (one line each plus a drawing, if any).
- `loot_command` (the /loot dev command) keys on `ruin_id >= 0`, which beach spots pass, so it
  works on them as on a ruin.
- Shots: `/mnt/project-files/beach-loot/` (seed 1126 landing 0's wreck, seed 3 landing 2's
  shack; noon, golden, night, before and after). The shack's spots are inside, so the outside
  shot barely changes.
- Camera solids for the wreck and shack are still open (separate item); searching inside the
  shack can put the camera in a wall until then.

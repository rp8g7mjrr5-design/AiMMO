Builder run, Basics 4: the ruin kit and the burned farmstead (grade 1).

### What shipped
- `game/shared/ruin_layout.gd` (`RuinLayout`): the farmstead's plan as plain data from the site
  alone (`layout_seed`, `rot`, pos): house, barn, well, cart, fence run, rubble, and four loot
  spots (chest by the hearth, crate at the barn's front, sack behind the cart, a body by the
  well). `loot_spots(r)` and `all_loot_spots()` give world points on the ground with
  `ruin_id` and `index`, ready for gameplay's "searchable loot in the ruins" item. Version 1
  kingdoms (no layout_seed) seed from the site position instead.
- `game/procgen/ruin_kit.gd` (`RuinKit`): the kit drawn from that plan in four MultiMesh layers
  (stone, wood, thatch, round) on the shared `Emberlight` solid material, ground-snapped per
  part. The chimney (7.2 m), gable end and the barn's standing frame are "Far" layers drawn to
  900 m, so the farmstead reads from the beach; the rest fades in at 220 m. Well under 400
  parts per farmstead. Colours are all worked out from `Palette` (static vars), so no new
  colour literals.
- `client.gd` adds `RuinKit.build()` to the world right after `WorldBuilder.build()` (both
  places). **Why not inside `WorldBuilder`:** the owner's open beach PR #241 changes
  `world_builder.gd` and `palette.gd`, so I stayed out of both. Once #241 lands, move the call
  into `WorldBuilder.build()` and give the ruins their own palette entries if wanted.

### Tried, didn't work
- First render had the barn's two roof slopes tilted the wrong way (a butterfly roof). Rotation
  about +X by +a takes local +z down, so the +z slope needs `+pitch`. Fixed before the PR.
- Hard-coded colours tripped `test_qa_art_lint` (palette only). Derived them from Palette.

### Known gaps / notes to next self
- No camera solids yet: the action camera can clip into the chimney and walls. Add the ruin parts
  to `WorldSolids` (needs `world_solids.gd`, not in #241) or a small `RuinKit.solids()`.
- No collision for players: you walk through walls, like trees today.
- No bot behaviour: this is art plus data; nothing a player does changed. The loot spots get a
  bot behaviour with gameplay's searchable-loot item (qa's "loot in the bot test").
- Shots: `ruins/` in the project files (seed 1126, the first farmstead, noon and night, plus one
  from 150 m). The 150 m shot shows the chimney and barn as a small silhouette between trees.

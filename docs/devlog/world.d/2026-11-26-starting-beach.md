# The starting beach (world)

Owner, 2026-11-26: "lets think of things to put on our starting beach. random landmarks things to
collect polish out the ocean", then "design the beach stuff and show it to me please". Built on
the island (gen v2) without touching its layout: everything is derived from the landings.

## What shipped
- `BeachGen` (shared, pure): per landing, the seaward direction (lowest ground in 24 directions),
  the waterline, 1 or 2 landmarks (45% two) rolled from shipwreck / lifeboat / old pier / whale
  bones / fishing shack by weight, never the same twice on a beach; 6 pickings; 2 or 3 tide
  pools; 46 shells, pebbles, wrack and sticks; one far wreck 240 to 380 m out on deep water.
  Seed = world seed * 7919 + landing * 131 + 4513.
- Pickings are real nodes (`ResourceNodes.BEACH_KINDS`), all by hand: driftwood (2 ash wood x 2),
  loose stones (1 stone x 3), kelp (2 fibre x 2), washed-up crate (2 pine wood x 2). Appended
  after the tier-2 ring on islands only, so every older id is unchanged (test pins it). A crate
  always sits by the wreck or lifeboat when the beach has one.
- `BeachProps` (client): the landmarks from 8 chunked MultiMesh layers on the shared bark, stone
  and solid materials, the tide pools on the sea material. No new material.
- `Sea` (client): the island's water plane gets a shader: depth-buffer surf that washes up and
  back every 6.5 s, a second band of broken water, shallow green-grey over the sand, a normal-only
  swell. Islands only; Ashgrove's lake keeps its StandardMaterial so the smoke test's shots and
  style baseline are untouched. Tide pools pass instance alpha 0.2 to calm the surf.
- `Palette.WET_SAND` on the last half metre of island beach (terrain vertex colour).

## Decisions
- **Zombai on the beach:** the owner left it open. No extra walkers on the beach: the first
  minute is for finding your feet (fun rule: first reward within 60 s). The dead fisher in the
  shack is the warning. Walkers still rise anywhere outside the world spawn's safe radius, so the
  other landings are not safe havens.
- **Food:** there is no hunger or eating yet, so no crabs, gulls or shellfish. When hunger lands,
  add a shellfish picking to BeachGen.NODE_PLAN (append-only: add it after the current kinds).
- Loose stones by hand do not break "bare hands can't break rock": nothing is broken. One stone a
  pull keeps the pickaxe the way to real stone.
- Landmarks have no camera solids yet (the action camera can clip into the wreck's ribs).

## Notes to self
- Old clients compute fewer nodes; ids past their list are unknown to them and ignored. A new
  client on an old server would show pickings the server refuses ("unknown"); the server deploys
  from the same main, so this only lasts minutes.
- Shots: `tests/client_smoke/beach_shots.gd` renders the real world builder on an island at
  noon, golden hour and night (wide, close and one view per landmark). Use Vulkan via lavapipe
  for Forward+ (`VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json ... --rendering-driver vulkan`).
- The surf reads `hint_depth_texture`; Compatibility's NDC depth runs -1..1, so `compat_ndc` is
  set from `Emberlight.srgb_output()` (no RenderingDevice).

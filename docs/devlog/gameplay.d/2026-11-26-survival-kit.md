# 2026-11-26: a grounded survival kit (owner direction 11)

The owner, looking at the ember recipes: remove them, go for basic zombie-survival tools, wood
then stone ("copy minecraft" read as the tier idea only), a wooden club, bandages, no magic.

What changed:
- Items: retired ember_axe, ember_pickaxe, ember_lantern, ember_heartwood, veinstone and
  ember_sap. `Inventory.RETIRED` maps each to a grounded item and `Inventory.convert_retired`
  runs in `CharacterData.normalize` and `PgStore._with_inventory`. It is idempotent and
  generous: a one-only tool is given only if none is carried, stacks cap at MAX_STACK.
- New items: plant_fibre, wooden_axe, wooden_pickaxe, wooden_club, wooden_spear, stone_maul,
  stone_spear (renamed from ash_spear, same numbers), bandage. Hand recipes (no bench):
  wooden tools and weapons, bandage, torch. Bench recipes upgrade the wooden one (it is used up)
  with stone and fibre.
- Tool tiers: `Gathering.TOOL_TIER` (wood 1, stone 2) and `min_tier(node)`; tier-2 nodes need
  tier 2. Stone nodes have `needs_tool`: bare hands are refused ("You need a pickaxe ...").
  Wooden tools: 0.75x time, +0. Stone tools: 0.5x, +1.
- The ember_sap node kind is now `scrub` (same ids and positions, so the node fingerprint pins
  changed; the tests check the old pins by mapping scrub back). It gives plant_fibre, day and
  night. No glow, no motes, no seep lights; a low mound of leaves and fibre stems.
- Healing: natural regen stops at 50% (`Vitals.HP_REGEN_CAP`). A bandage heals 35 over 4 s
  (`heal_left`). Used with H, sent through the existing v9 `c2s_place("bandage")` so there is no
  protocol bump; the answer comes back as `s2c_place_result` with item "bandage".
- Weapons: `Weapons.ORDER` is wooden_spear, wooden_club, stone_spear, stone_maul; the server
  swings the best one carried, as before.

Tried and changed: the first wooden icons were the stone shapes in another tint, and the
distinctness test (silhouette diff > 0.08) failed, so the wooden tools are drawn mirrored.
Wooden weapons at first missed the "1.4x fists" check; light damage went up to 8 (spear) and
11 (club).

Notes to next self / known gaps:
- The craft window still opens only at the bench; hand recipes can be made there or by /craft.
  A "craft anywhere" pack tab would make the first minute smoother.
- Held weapons and tools are not drawn in the hand yet.
- The ember veins on trees and stone and the old ash's glowing pods are still there (world).
- Iron/metal tier from ruins next; cloth as a step between fibre and bandage if bandages feel
  too cheap.

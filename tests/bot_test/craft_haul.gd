extends RefCounted
## Pure helpers for the craft-haul check (behaviour client_craft_window.gd in --craft-haul mode,
## seed_crafter.gd and run_bot_test.py's haul phase), split out so
## tests/unit/test_qa_craft_haul.gd can drive them without a server.
##
## The main bots press Craft with whatever they happen to carry, and they almost never carry a
## recipe's inputs (ember sap is night-only, one charge, ten-minute respawn), so in the 180 s
## run every press was refused "missing" and the ok path (the toast, the "+N Toolcraft" XP)
## was only proven in unit tests. The haul check is the player coming home from a haul: a
## character seeded at the workbench with exactly a campfire's and a torch's inputs presses
## Craft on the real client window: the campfire and the torches must both be made, each with
## its Toolcraft XP, and the pack must come back without the inputs and with the goods.

## Metres from the bench's centre, toward spawn: well inside Crafting.BENCH_RANGE (6 m) and
## clear of the behaviour's 1.5 m position-lag edge.
const BENCH_OFFSET := 2.0

## Recipes the haul bot makes, in the order it presses them (the behaviour picks the campfire
## first while it stands at the bench, then the torch, which can be made anywhere).
const RECIPES := ["campfire", "torch"]


## Where the crafter is seeded: on the ground, BENCH_OFFSET from the bench toward spawn.
static func spot() -> Vector3:
	var bench := Crafting.WORKBENCH_XZ
	var to_spawn := Vector2(GameConfig.SPAWN_POINT.x, GameConfig.SPAWN_POINT.z) - bench
	var dir := to_spawn.normalized() if to_spawn.length() > 0.01 else Vector2(1, 0)
	var xz := bench + dir * BENCH_OFFSET
	return Terrain.clamp_to_world(Vector3(xz.x, Terrain.height(xz.x, xz.y), xz.y))


## Exactly what RECIPES need, summed, so after both crafts the inputs are all gone.
static func pack() -> Dictionary:
	var inv := {}
	for id in RECIPES:
		for item in Crafting.RECIPES[id].needs:
			inv[item] = int(inv.get(item, 0)) + int(Crafting.RECIPES[id].needs[item])
	return inv


## The pack after both crafts: no inputs left, the goods in.
static func pack_after() -> Dictionary:
	var inv := {}
	for id in RECIPES:
		inv[id] = int(inv.get(id, 0)) + int(Crafting.RECIPES[id].makes)
	return inv


## Problems with a haul bot's client_craft_window stats ([] when it made everything).
static func verdict(stats: Dictionary) -> Array:
	var out := []
	var made: Array = stats.get("made", [])
	for id in RECIPES:
		if not made.has(id):
			out.append("never made a %s (made %s, %d presses)" % [id, made, int(stats.get("presses", 0))])
	var want := Inventory.to_wire(Inventory.normalize(pack_after()))
	var got: Variant = stats.get("haul_pack", null)
	if got == null:
		out.append("no pack reported after the crafts")
	elif Inventory.to_wire(Inventory.normalize(got)) != want:
		out.append("pack after the crafts %s, wanted %s" % [Inventory.to_wire(Inventory.normalize(got)), want])
	if int(stats.get("toolcraft_xp", 0)) < RECIPES.size():
		out.append("%d Toolcraft XP gains for %d crafts" % [int(stats.get("toolcraft_xp", 0)), RECIPES.size()])
	return out

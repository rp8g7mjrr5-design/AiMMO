extends TestCase
## Wood, then stone (owner direction, 2026-11-26: "Wooden pic and axe first. then stone"):
## the wooden axe and pickaxe are made in your hands from wood alone, stone needs the wooden
## pickaxe, and the bench turns each wooden tool into its stone version (the wooden one is used
## up and counts as owned afterwards). No levels: the materials and tools are the gate.
## Also how much better each tier gathers, and the whole craft through the real server
## functions (no network: messages land in test_outbox).

const ServerScript := preload("res://server/server.gd")
const AT_BENCH := Vector3(3.0, 0.0, -2.0)
const FAR := Vector3(60.0, 0.0, 60.0)


func _server(id: int, pos: Vector3, inv: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "P%d" % id, "inventory": inv})
	ch.x = pos.x
	ch.y = Terrain.height(pos.x, pos.z)
	ch.z = pos.z
	srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _first(kind: String, tier: int) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind and int(n.get("tier", 1)) == tier:
			return n
	return {}


func test_wooden_tools_are_made_by_hand_from_wood() -> void:
	for id in ["wooden_axe", "wooden_pickaxe"]:
		check(Crafting.is_recipe(id) and Crafting.makes_tool(id) and Inventory.is_item(id), id)
		check(not Crafting.RECIPES[id].bench, "%s is made anywhere" % id)
		for item in Crafting.RECIPES[id].needs:
			check(item in ["ash_wood", "pine_wood"], "%s needs only wood, not %s" % [id, item])
		check_eq(Crafting.check(Crafting.RECIPES[id].needs.duplicate(), id, FAR), "", "%s far from the bench" % id)
	check_eq(Crafting.parse_recipe("axe"), "wooden_axe", "plain 'axe' is the wooden one")
	check_eq(Crafting.parse_recipe("pick"), "wooden_pickaxe")
	check_eq(Crafting.parse_recipe("stone axe"), "stone_axe")


func test_stone_needs_a_pickaxe() -> void:
	var rock := _first("stone", 1)
	check(Gathering.needs_tool(rock), "an outcrop takes a tool")
	check(not Gathering.can_work(rock, {}), "bare hands can't break rock")
	check(not Gathering.can_work(rock, {"wooden_axe": 1}), "an axe doesn't mine")
	check(Gathering.can_work(rock, {"wooden_pickaxe": 1}), "a wooden pickaxe does")
	check(Gathering.can_work(rock, {"stone_pickaxe": 1}), "and a stone one")
	check_eq(Gathering.tool_text(rock), "You need a pickaxe to work this stone outcrop.")
	# Wood and scrub never need a tool: the first pickaxe is always within reach.
	for kind in ["ash", "pine", "scrub"]:
		check(Gathering.can_work(_first(kind, 1), {}), "%s by hand" % kind)


func test_the_stone_tools_upgrade_the_wooden_ones() -> void:
	var axe_pack := {"wooden_axe": 1, "stone": 3, "plant_fibre": 2}
	check_eq(Crafting.check(axe_pack, "stone_axe", AT_BENCH), "")
	check_eq(Crafting.check(axe_pack, "stone_axe", FAR), "bench")
	check_eq(Crafting.check({"stone": 3, "plant_fibre": 2}, "stone_axe", AT_BENCH), "missing", "the wooden axe goes into it")
	check_eq(Crafting.refusal("missing", {"stone": 3, "plant_fibre": 2}, "stone_axe", AT_BENCH),
		"You need 1 wooden axe more to make a stone axe.")
	var inv := {"stone_axe": 1, "ash_wood": 9}
	check_eq(Crafting.owned_tool(inv, "wooden_axe"), "stone_axe")
	check_eq(Crafting.check(inv, "wooden_axe", AT_BENCH), "owned", "no going back to wood")
	check(Crafting.refusal("owned", inv, "wooden_axe", AT_BENCH).begins_with("You already carry a stone axe"),
		Crafting.refusal("owned", inv, "wooden_axe", AT_BENCH))
	check_eq(Crafting.owned_tool(inv, "wooden_pickaxe"), "", "an axe is not a pickaxe")
	check_eq(Crafting.owned_tool(inv, "torch"), "", "only tools are owned")
	check(Crafting.recipes_text({}).contains("stone axe: 3 stone, 2 plant fibre and 1 wooden axe, at the workbench"), Crafting.recipes_text({}))


func test_each_tier_gathers_faster_and_richer() -> void:
	for kind in ["ash", "pine", "stone"]:
		var wood := {"wooden_axe": 1} if kind != "stone" else {"wooden_pickaxe": 1}
		var stone := {"stone_axe": 1} if kind != "stone" else {"stone_pickaxe": 1}
		var wood_s := GatherChannel.seconds_for(kind, wood)
		var stone_s := GatherChannel.seconds_for(kind, stone)
		check(stone_s < wood_s, "%s: stone bar %.2f < wood %.2f" % [kind, stone_s, wood_s])
		check(Gathering.amount_for(kind, stone) > Gathering.amount_for(kind, wood), "%s: stone gives more" % kind)
		check(Gathering.cooldown_for(kind, stone) < Gathering.cooldown_for(kind, wood), "%s: shorter cooldown" % kind)
		if kind != "stone":
			check(wood_s < GatherChannel.seconds_for(kind, {}), "%s: the wooden axe beats bare hands" % kind)
	check_eq(Gathering.tool_for("ash", {"wooden_axe": 1, "stone_axe": 1}), "stone_axe", "the best tool carried is used")
	check_eq(Gathering.tool_for("scrub", {"stone_axe": 1, "stone_pickaxe": 1}), "", "fibre is pulled by hand")


func test_server_crafts_the_wooden_pickaxe_then_the_stone_one() -> void:
	var srv := _server(2, FAR, {"ash_wood": 2, "pine_wood": 2})
	var r: Dictionary = srv.craft_request(2, "wooden_pickaxe")
	check(r.ok, "made in the field: %s" % r.text)
	var inv: Dictionary = srv.sessions[2].character.inventory
	check_eq(Inventory.count(inv, "wooden_pickaxe"), 1)
	check_eq(Inventory.count(inv, "ash_wood") + Inventory.count(inv, "pine_wood"), 0)
	check(str(r.text).contains("break stone"), r.text)
	srv.free()
	srv = _server(2, AT_BENCH, {"wooden_pickaxe": 1, "stone": 3, "plant_fibre": 2})
	r = srv.craft_request(2, "stone_pickaxe")
	check(r.ok, "made at the bench: %s" % r.text)
	inv = srv.sessions[2].character.inventory
	check_eq(Inventory.count(inv, "stone_pickaxe"), 1)
	check_eq(Inventory.count(inv, "wooden_pickaxe"), 0, "the wooden pick went into it")
	check_eq(Gathering.tool_for("stone", inv), "stone_pickaxe", "and the next strike uses it")
	check_eq(srv.craft_request(2, "wooden_pickaxe").reason, "owned")
	srv.free()


func test_tier2_nodes_need_a_stone_tool() -> void:
	for n in ResourceNodes.tier2():
		var wood := {"wooden_axe": 1} if n.kind == "ash" else {"wooden_pickaxe": 1}
		var stone := {"stone_axe": 1} if n.kind == "ash" else {"stone_pickaxe": 1}
		check(not Gathering.can_work(n, {}), "node %d: not by hand" % n.id)
		check(not Gathering.can_work(n, wood), "node %d: not with a wooden tool" % n.id)
		check(Gathering.can_work(n, stone), "node %d: a stone tool opens it" % n.id)
	var old_ash := _first("ash", 2)
	check_eq(Gathering.tool_text(old_ash), "You need a stone axe to work this old ash.")
	check_eq(str(ResourceNodes.info(old_ash).item), "ash_wood", "the old ash gives plain wood, lots of it")
	check(Gathering.amount_at(old_ash.id, {"stone_axe": 1}) > Gathering.amount_for("ash", {"stone_axe": 1}), "more per blow")

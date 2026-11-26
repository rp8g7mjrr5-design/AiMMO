extends TestCase
## The ember tools: the ember axe and ember pickaxe, made at the workbench from a stone tool,
## ember sap and a tier-2 material (only an axe or pickaxe gets those out of the old ashes and
## rich seams). No levels (owner direction, 2026-11-26): the materials are the gate.
## The recipes and their refusals, the upgrade (the stone tool is used up and counts
## as owned afterwards), how much better the tools gather, and the whole craft through the
## real server functions (no network: messages land in test_outbox).

const ServerScript := preload("res://server/server.gd")
const AT_BENCH := Vector3(3.0, 0.0, -2.0)
const FAR := Vector3(60.0, 0.0, 60.0)


func _axe_pack() -> Dictionary:
	return {"stone_axe": 1, "ember_heartwood": 4, "ember_sap": 1}


func _pick_pack() -> Dictionary:
	return {"stone_pickaxe": 1, "veinstone": 4, "ember_sap": 1}


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


func _sent(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[1] == method:
			out.append(m[2])
	return out


func test_ember_tools_are_real_items() -> void:
	for id in ["ember_axe", "ember_pickaxe"]:
		check(Crafting.is_recipe(id), "%s is a recipe" % id)
		check(Crafting.makes_tool(id), "%s is a tool" % id)
		check(Inventory.is_item(id), "%s can sit in a pack" % id)
		check_eq(Inventory.label(id), id.replace("_", " "))
		check(not Crafting.RECIPES[id].has("level"), "%s needs no level" % id)
		check(Crafting.RECIPES[id].bench, "%s is made at the workbench" % id)
	check_eq(Crafting.parse_recipe("ember axe"), "ember_axe")
	check_eq(Crafting.parse_recipe("ember pick"), "ember_pickaxe")
	check_eq(Crafting.parse_recipe("axe"), "stone_axe", "plain 'axe' is still the stone one")


func test_materials_are_the_gate() -> void:
	check_eq(Crafting.check(_axe_pack(), "ember_axe", AT_BENCH), "", "a fresh character with the parts makes it")
	check_eq(Crafting.check(_pick_pack(), "ember_pickaxe", AT_BENCH), "")
	check_eq(Crafting.check({"stone_axe": 1}, "ember_axe", AT_BENCH), "missing")
	check_eq(Crafting.check(_axe_pack(), "ember_axe", FAR), "bench")
	check_eq(Crafting.check(_axe_pack(), "torch", FAR), "missing")
	# And the materials take the stone tool to get: bare hands can't work the old ash or seam.
	for n in ResourceNodes.tier2():
		check(not Gathering.can_work(n, {}), "node %d needs a tool first" % n.id)
	check(Crafting.refusal("bench", {}, "ember_axe", FAR).begins_with("An ember axe needs the workbench."), "an, not a")
	check_eq(Crafting.refusal("missing", {"stone_axe": 1}, "ember_axe", AT_BENCH),
		"You need 1 ember sap and 4 ember heartwood more to make an ember axe.")


func test_the_upgrade_replaces_the_stone_tool() -> void:
	check_eq(Crafting.RECIPES.ember_axe.needs.get("stone_axe", 0), 1, "the stone axe goes into it")
	check_eq(Crafting.RECIPES.ember_pickaxe.needs.get("stone_pickaxe", 0), 1)
	var inv := {"ember_axe": 1, "ash_wood": 9, "stone": 9}
	check_eq(Crafting.owned_tool(inv, "stone_axe"), "ember_axe")
	check_eq(Crafting.check(inv, "stone_axe", AT_BENCH), "owned", "no going back to stone")
	check(Crafting.refusal("owned", inv, "stone_axe", AT_BENCH).begins_with("You already carry an ember axe"),
		Crafting.refusal("owned", inv, "stone_axe", AT_BENCH))
	check_eq(Crafting.check(inv, "ember_axe", AT_BENCH), "owned")
	check_eq(Crafting.owned_tool(inv, "stone_pickaxe"), "", "an axe is not a pickaxe")
	check_eq(Crafting.owned_tool(inv, "torch"), "", "only tools are owned")
	check(Crafting.recipes_text(inv).contains("stone axe: 3 ash wood and 2 stone, at the workbench (have it)"), Crafting.recipes_text(inv))
	check(Crafting.recipes_text({}).contains("ember axe: 1 ember sap, 4 ember heartwood and 1 stone axe, at the workbench"),
		Crafting.recipes_text({}))


func test_ember_tools_gather_faster_and_richer() -> void:
	var stone_axe := {"stone_axe": 1}
	var ember_axe := {"ember_axe": 1}
	var both := {"stone_axe": 1, "ember_axe": 1}
	check_eq(Gathering.tool_for("pine", ember_axe), "ember_axe")
	check_eq(Gathering.tool_for("ash", both), "ember_axe", "the best tool carried is used")
	check_eq(Gathering.tool_for("stone", {"ember_pickaxe": 1}), "ember_pickaxe")
	check_eq(Gathering.tool_for("stone", ember_axe), "", "an axe doesn't mine")
	check_eq(Gathering.tool_for("ember_sap", {"ember_axe": 1, "ember_pickaxe": 1}), "", "sap is by hand")
	for kind in ["ash", "pine", "stone"]:
		var stone_tool := {"stone_axe": 1} if kind != "stone" else {"stone_pickaxe": 1}
		var ember_tool := {"ember_axe": 1} if kind != "stone" else {"ember_pickaxe": 1}
		var bare_s := GatherChannel.seconds_for(kind, {})
		var stone_s := GatherChannel.seconds_for(kind, stone_tool)
		var ember_s := GatherChannel.seconds_for(kind, ember_tool)
		check(ember_s < stone_s and stone_s < bare_s, "%s: bar %.2f < %.2f < %.2f" % [kind, ember_s, stone_s, bare_s])
		check(ember_s <= stone_s * 0.75, "%s: the ember bar is clearly shorter (%.2f vs %.2f)" % [kind, ember_s, stone_s])
		check(Gathering.amount_for(kind, ember_tool) > Gathering.amount_for(kind, stone_tool), "%s: more per gather" % kind)
		check(Gathering.cooldown_for(kind, ember_tool) < Gathering.cooldown_for(kind, stone_tool), "%s: shorter cooldown" % kind)
	check_eq(Gathering.amount_for("pine", stone_axe), int(ResourceNodes.kind_info("pine").amount) + Gathering.TOOL_EXTRA)
	check_eq(Gathering.amount_for("pine", ember_axe), int(ResourceNodes.kind_info("pine").amount) + Gathering.EMBER_EXTRA)
	var ash2: Dictionary = {}
	for n in ResourceNodes.tier2():
		if n.kind == "ash":
			ash2 = n
			break
	check(GatherChannel.seconds_at(ash2.id, ember_axe) < GatherChannel.seconds_at(ash2.id, stone_axe), "old ash too")
	check_eq(Gathering.amount_at(ash2.id, ember_axe), int(ResourceNodes.info(ash2).amount) + Gathering.EMBER_EXTRA)


func test_server_crafts_the_ember_axe() -> void:
	var srv := _server(2, AT_BENCH, _axe_pack())
	var r: Dictionary = srv.craft_request(2, "ember_axe")
	check(r.ok, "made: %s" % r.text)
	var inv: Dictionary = srv.sessions[2].character.inventory
	check_eq(Inventory.count(inv, "ember_axe"), 1, "the ember axe is in the pack")
	check_eq(Inventory.count(inv, "stone_axe"), 0, "the stone axe went into it")
	check_eq(Inventory.count(inv, "ember_heartwood"), 0)
	check_eq(Inventory.count(inv, "ember_sap"), 0)
	check(str(r.text).contains("ember axe"), r.text)
	check(_sent(srv, "s2c_xp").is_empty(), "no XP: there are no levels")
	check_eq(Gathering.tool_for("ash", inv), "ember_axe", "and the next chop uses it")
	var again: Dictionary = srv.craft_request(2, "stone_axe")
	check_eq(again.reason, "owned", "no second stone axe once you carry the ember one")
	srv.free()


## World drew the ember tools (PR #112), so they are ordinary items now: in ITEMS and in pack
## order right after the stone tools, not trailing after the campfires as unknown extras.
func test_ember_tools_sit_with_the_stone_tools() -> void:
	for id in ["ember_axe", "ember_pickaxe"]:
		check(not Inventory.UNDRAWN.has(id), "%s no longer waits for an icon" % id)
		check(Inventory.ITEMS.has(id) and Inventory.ITEM_ORDER.has(id), "%s is a full item" % id)
		check(ItemIcons.has_icon(id), "%s has its own icon" % id)
	var o: Array = Inventory.ITEM_ORDER
	check_eq(o.find("ember_axe"), o.find("stone_pickaxe") + 1, "ember axe right after the stone tools")
	check_eq(o.find("ember_pickaxe"), o.find("ember_axe") + 1)
	var inv := {"campfire": 1, "torch": 2, "ember_pickaxe": 1, "ember_axe": 1, "ash_wood": 3}
	check_eq(Inventory.held(inv), ["ash_wood", "ember_axe", "ember_pickaxe", "torch", "campfire"], "pack order")
	check_eq(Inventory.to_wire(inv).keys(), ["ash_wood", "ember_axe", "ember_pickaxe", "torch", "campfire"], "wire order")
	# Saved before this change, the same ids load and count the same.
	var saved := Inventory.normalize({"ember_axe": 1, "ember_pickaxe": 1})
	check_eq(Inventory.count(saved, "ember_axe"), 1)
	check_eq(Inventory.label("ember_pickaxe"), "ember pickaxe")

extends TestCase
## Toolcraft unlocks (roadmap Milestone 1 part 4): the ember axe and ember pickaxe, made at
## the workbench from a stone tool, ember sap and a tier-2 material once Toolcraft is 5.
## The recipes and their "level" refusal, the upgrade (the stone tool is used up and counts
## as owned afterwards), how much better the tools gather, and the whole craft through the
## real server functions (no network: messages land in test_outbox).

const ServerScript := preload("res://server/server.gd")
const AT_BENCH := Vector3(3.0, 0.0, -2.0)
const FAR := Vector3(60.0, 0.0, 60.0)


func _skills_at(skill: String, level: int) -> Dictionary:
	return {skill: Skills.xp_for_level(level)}


func _axe_pack() -> Dictionary:
	return {"stone_axe": 1, "ember_heartwood": 4, "ember_sap": 1}


func _pick_pack() -> Dictionary:
	return {"stone_pickaxe": 1, "veinstone": 4, "ember_sap": 1}


func _server(id: int, pos: Vector3, skills: Dictionary, inv: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "P%d" % id, "skills": skills, "inventory": inv})
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
		check_eq(Crafting.required(id), ["toolcraft", 5])
		check(Crafting.RECIPES[id].bench, "%s is made at the workbench" % id)
	check_eq(Crafting.parse_recipe("ember axe"), "ember_axe")
	check_eq(Crafting.parse_recipe("ember pick"), "ember_pickaxe")
	check_eq(Crafting.parse_recipe("axe"), "stone_axe", "plain 'axe' is still the stone one")
	check(Crafting.required("stone_axe").is_empty(), "the stone tools need no level")


func test_level_gate() -> void:
	var t4 := _skills_at("toolcraft", 4)
	var t5 := _skills_at("toolcraft", 5)
	check_eq(Crafting.check(_axe_pack(), "ember_axe", AT_BENCH, t4), "level")
	check_eq(Crafting.check(_axe_pack(), "ember_axe", AT_BENCH, t5), "")
	check_eq(Crafting.check(_pick_pack(), "ember_pickaxe", AT_BENCH, {}), "level", "a fresh character is Toolcraft 1")
	check_eq(Crafting.check(_pick_pack(), "ember_pickaxe", AT_BENCH, t5), "")
	check_eq(Crafting.check({}, "ember_axe", FAR, t4), "level", "the level comes first: it doesn't depend on where you stand")
	check_eq(Crafting.check(_axe_pack(), "ember_axe", AT_BENCH), "", "no skills given: the level is not checked (the window)")
	check_eq(Crafting.check({"stone_axe": 1}, "ember_axe", AT_BENCH, t5), "missing")
	check_eq(Crafting.check(_axe_pack(), "ember_axe", FAR, t5), "bench")
	check_eq(Crafting.check(_axe_pack(), "torch", FAR, {}), "missing", "old recipes don't care about Toolcraft")
	check_eq(Crafting.refusal("level", {}, "ember_axe", AT_BENCH, _skills_at("toolcraft", 3)),
		"An ember axe needs Toolcraft 5. You're Toolcraft 3.")
	check_eq(Crafting.refusal("level", {}, "ember_pickaxe", AT_BENCH, {}),
		"An ember pickaxe needs Toolcraft 5. You're Toolcraft 1.")
	check(Crafting.refusal("bench", {}, "ember_axe", FAR).begins_with("An ember axe needs the workbench."), "an, not a")
	check_eq(Crafting.refusal("missing", {"stone_axe": 1}, "ember_axe", AT_BENCH),
		"You need 1 ember sap and 4 ember heartwood more to make an ember axe.")


func test_the_upgrade_replaces_the_stone_tool() -> void:
	check_eq(Crafting.RECIPES.ember_axe.needs.get("stone_axe", 0), 1, "the stone axe goes into it")
	check_eq(Crafting.RECIPES.ember_pickaxe.needs.get("stone_pickaxe", 0), 1)
	var inv := {"ember_axe": 1, "ash_wood": 9, "stone": 9}
	check_eq(Crafting.owned_tool(inv, "stone_axe"), "ember_axe")
	check_eq(Crafting.check(inv, "stone_axe", AT_BENCH, {}), "owned", "no going back to stone")
	check(Crafting.refusal("owned", inv, "stone_axe", AT_BENCH).begins_with("You already carry an ember axe"),
		Crafting.refusal("owned", inv, "stone_axe", AT_BENCH))
	check_eq(Crafting.check(inv, "ember_axe", AT_BENCH, _skills_at("toolcraft", 9)), "owned")
	check_eq(Crafting.owned_tool(inv, "stone_pickaxe"), "", "an axe is not a pickaxe")
	check_eq(Crafting.owned_tool(inv, "torch"), "", "only tools are owned")
	check(Crafting.recipes_text(inv).contains("stone axe: 3 ash wood and 2 stone, at the workbench (have it)"), Crafting.recipes_text(inv))
	check(Crafting.recipes_text({}).contains("ember axe: 1 ember sap, 4 ember heartwood and 1 stone axe, at the workbench, Toolcraft 5"),
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
	check(GatherChannel.seconds_at(ash2.id, ember_axe, 5) < GatherChannel.seconds_at(ash2.id, stone_axe, 5), "old ash too")
	check_eq(Gathering.amount_at(ash2.id, ember_axe, 5), int(ResourceNodes.info(ash2).amount) + Gathering.EMBER_EXTRA)


func test_server_refuses_below_toolcraft_5() -> void:
	var srv := _server(2, AT_BENCH, _skills_at("toolcraft", 4), _axe_pack())
	var r: Dictionary = srv.craft_request(2, "ember_axe")
	check(not r.ok, "refused")
	check_eq(r.reason, "level")
	check_eq(_sent(srv, "s2c_craft_result"), [["ember_axe", false, "An ember axe needs Toolcraft 5. You're Toolcraft 4."]])
	check_eq(srv.sessions[2].character.inventory, _axe_pack(), "nothing used up")
	check(srv.craft(2, "ember axe").begins_with("An ember axe needs Toolcraft 5"), "/craft says the same")
	srv.free()


func test_server_crafts_the_ember_axe_at_toolcraft_5() -> void:
	var srv := _server(2, AT_BENCH, _skills_at("toolcraft", 5), _axe_pack())
	var r: Dictionary = srv.craft_request(2, "ember_axe")
	check(r.ok, "made: %s" % r.text)
	var inv: Dictionary = srv.sessions[2].character.inventory
	check_eq(Inventory.count(inv, "ember_axe"), 1, "the ember axe is in the pack")
	check_eq(Inventory.count(inv, "stone_axe"), 0, "the stone axe went into it")
	check_eq(Inventory.count(inv, "ember_heartwood"), 0)
	check_eq(Inventory.count(inv, "ember_sap"), 0)
	check(str(r.text).contains("ember axe"), r.text)
	var xp := _sent(srv, "s2c_xp")
	check(not xp.is_empty() and xp[0][0] == "toolcraft" and int(xp[0][1]) == Skills.craft_xp("ember_axe"), "Toolcraft XP: %s" % [xp])
	check_eq(Skills.craft_xp("ember_axe"), 6 * Skills.CRAFT_XP_PER_ITEM, "pays per part, like every recipe")
	check_eq(Gathering.tool_for("ash", inv), "ember_axe", "and the next chop uses it")
	var again: Dictionary = srv.craft_request(2, "stone_axe")
	check_eq(again.reason, "owned", "no second stone axe once you carry the ember one")
	srv.free()


func test_level_up_names_a_real_unlock() -> void:
	var u = Skills.unlock_at("toolcraft", 5)
	check(u != null, "Toolcraft 5 has an unlock")
	check(not u.get("soon", false), "no longer 'coming soon'")
	var r := Skills.gain({"toolcraft": Skills.xp_for_level(5) - 1}, "toolcraft", 1)
	check(not Skills.level_up_text(r).contains("coming soon"), Skills.level_up_text(r))


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

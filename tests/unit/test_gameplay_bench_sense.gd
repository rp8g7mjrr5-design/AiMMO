extends TestCase
## Toolcraft 3 "Bench sense": the ember lantern, the first Toolcraft recipe you unlock. It
## pays 1.5x crafting XP (108) so Toolcraft 3 -> 5 is about a dozen lanterns instead of
## ~20 campfires, and it is a real sink for wood once the stacks hold 999.

const ServerScript := preload("res://server/server.gd")
const AT_BENCH := Vector3(3.0, 0.0, -2.0)
const FAR := Vector3(60.0, 0.0, 60.0)


func _pack(n: int = 1) -> Dictionary:
	return {"ash_wood": 3 * n, "pine_wood": 3 * n, "stone": 2 * n, "ember_sap": n}


func _t(level: int) -> Dictionary:
	return {"toolcraft": Skills.xp_for_level(level)}


func _server(skills: Dictionary, inv: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "Lamplighter", "skills": skills, "inventory": inv})
	ch.x = AT_BENCH.x
	ch.y = Terrain.height(AT_BENCH.x, AT_BENCH.z)
	ch.z = AT_BENCH.z
	srv.sessions[2] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func test_the_lantern_is_a_real_recipe_and_item() -> void:
	check(Crafting.is_recipe("ember_lantern"), "a recipe")
	check(Inventory.is_item("ember_lantern"), "an item a pack can hold")
	check(Inventory.ITEM_ORDER.has("ember_lantern"), "sorted in the pack")
	check(not Crafting.makes_tool("ember_lantern"), "not a tool: make as many as you like")
	check_eq(Crafting.required("ember_lantern"), ["toolcraft", 3])
	check(Crafting.RECIPES.ember_lantern.bench, "made at the workbench")
	check_eq(Crafting.parse_recipe("lantern"), "ember_lantern")
	check_eq(Crafting.parse_recipe("ember lantern"), "ember_lantern")
	check(Crafting.RECIPE_ORDER.find("ember_lantern") < Crafting.RECIPE_ORDER.find("ember_axe"),
		"listed before the Toolcraft 5 tools, in unlock order")
	check(ItemIcons.has_icon("ember_lantern"), "world drew it")


func test_bench_sense_is_no_longer_coming_soon() -> void:
	var u: Dictionary = Skills.UNLOCKS.toolcraft[3]
	check(not u.get("soon", false), "Bench sense is real")
	check(str(u.text).contains("lantern"), u.text)


func test_level_gate_and_refusals() -> void:
	check_eq(Crafting.check(_pack(), "ember_lantern", AT_BENCH, _t(2)), "level")
	check_eq(Crafting.check(_pack(), "ember_lantern", AT_BENCH, {}), "level", "fresh characters are Toolcraft 1")
	check_eq(Crafting.check(_pack(), "ember_lantern", AT_BENCH, _t(3)), "")
	check_eq(Crafting.check(_pack(), "ember_lantern", FAR, _t(3)), "bench")
	check_eq(Crafting.check({"ash_wood": 3}, "ember_lantern", AT_BENCH, _t(3)), "missing")
	check_eq(Crafting.refusal("level", {}, "ember_lantern", AT_BENCH, _t(2)),
		"An ember lantern needs Toolcraft 3. You're Toolcraft 2.")


func test_lanterns_pay_half_again_as_much() -> void:
	check_eq(Skills.craft_xp("ember_lantern"), 108, "9 items x 8 XP x 1.5")
	check_eq(Skills.craft_xp("campfire"), 64, "other recipes unchanged")
	check_eq(Skills.craft_xp("torch"), 16)
	check(Skills.craft_xp("ember_lantern", true) > 108, "company still pays more")
	var need := Skills.xp_for_level(5) - Skills.xp_for_level(3)
	var lanterns := ceili(float(need) / 108.0)
	check(lanterns >= 8 and lanterns <= 16, "Toolcraft 3 -> 5 in %d lanterns (want about a dozen)" % lanterns)


func test_crafting_lanterns_through_the_server() -> void:
	var srv := _server(_t(3), _pack(2))
	var before := int(srv.sessions[2].character.skills.get("toolcraft", 0))
	var r: Dictionary = srv.craft_request(2, "ember_lantern")
	check(r.ok, "made one: %s" % r.text)
	r = srv.craft_request(2, "ember_lantern")
	check(r.ok, "and a second: %s" % r.text)
	var inv: Dictionary = srv.sessions[2].character.inventory
	check_eq(Inventory.count(inv, "ember_lantern"), 2)
	check_eq(Inventory.count(inv, "ash_wood"), 0, "every ingredient used up")
	check_eq(Inventory.count(inv, "ember_sap"), 0)
	check_eq(int(srv.sessions[2].character.skills.toolcraft) - before, 216, "two lanterns, 108 XP each")
	r = srv.craft_request(2, "ember_lantern")
	check_eq(r.reason, "missing", "out of wood")
	srv.free()


func test_too_green_to_make_one() -> void:
	var srv := _server(_t(2), _pack())
	var r: Dictionary = srv.craft_request(2, "ember_lantern")
	check(not r.ok, "refused")
	check_eq(r.reason, "level")
	check_eq(Inventory.count(srv.sessions[2].character.inventory, "ash_wood"), 3, "nothing taken")
	srv.free()

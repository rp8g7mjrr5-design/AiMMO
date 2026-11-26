extends TestCase
## The ember lantern: a workbench recipe anyone can make once they have the materials (there
## are no levels, owner direction 2026-11-26), and a real sink for wood once stacks run deep.

const ServerScript := preload("res://server/server.gd")
const AT_BENCH := Vector3(3.0, 0.0, -2.0)
const FAR := Vector3(60.0, 0.0, 60.0)


func _pack(n: int = 1) -> Dictionary:
	return {"ash_wood": 3 * n, "pine_wood": 3 * n, "stone": 2 * n, "ember_sap": n}


func _server(inv: Dictionary, skills: Dictionary = {}) -> Node:
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
	check(not Crafting.RECIPES.ember_lantern.has("level"), "no level gate")
	check(Crafting.RECIPES.ember_lantern.bench, "made at the workbench")
	check_eq(Crafting.parse_recipe("lantern"), "ember_lantern")
	check_eq(Crafting.parse_recipe("ember lantern"), "ember_lantern")
	check(ItemIcons.has_icon("ember_lantern"), "world drew it")


func test_only_materials_and_the_bench_gate_it() -> void:
	check_eq(Crafting.check(_pack(), "ember_lantern", AT_BENCH), "", "a fresh character with the parts makes one")
	check_eq(Crafting.check(_pack(), "ember_lantern", FAR), "bench")
	check_eq(Crafting.check({"ash_wood": 3}, "ember_lantern", AT_BENCH), "missing")


func test_crafting_lanterns_through_the_server() -> void:
	var srv := _server(_pack(2))
	var r: Dictionary = srv.craft_request(2, "ember_lantern")
	check(r.ok, "made one: %s" % r.text)
	r = srv.craft_request(2, "ember_lantern")
	check(r.ok, "and a second: %s" % r.text)
	var inv: Dictionary = srv.sessions[2].character.inventory
	check_eq(Inventory.count(inv, "ember_lantern"), 2)
	check_eq(Inventory.count(inv, "ash_wood"), 0, "every ingredient used up")
	check_eq(Inventory.count(inv, "ember_sap"), 0)
	r = srv.craft_request(2, "ember_lantern")
	check_eq(r.reason, "missing", "out of wood")
	srv.free()


func test_crafting_never_touches_old_xp() -> void:
	var old := {"toolcraft": 420, "felling": 1700}
	var srv := _server(_pack(), old)
	var r: Dictionary = srv.craft_request(2, "ember_lantern")
	check(r.ok, r.text)
	check_eq(srv.sessions[2].character.skills, old, "old XP kept exactly, nothing earned")
	for m in srv.test_outbox:
		check(not str(m[1]) in ["s2c_xp", "s2c_level_up", "s2c_level_up_seen", "s2c_skills"], "never sends %s" % m[1])
	srv.free()

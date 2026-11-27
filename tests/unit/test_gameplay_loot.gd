extends TestCase
## Ruin loot (Loot, step 2 of the owner's survival plan, 2026-11-27): every loot spot in a ruin
## can be searched with E for a short bar, pays from its ruin grade's table (only items another
## system uses), stays empty for a day, and a washed-up crate now holds more than wood.

const ServerScript := preload("res://server/server.gd")
const SPOT_POS := Vector3(40.0, 0.0, 40.0)


func _server() -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true
	var ch := CharacterData.normalize({"name": "Finder"})
	ch.x = SPOT_POS.x + 1.0
	ch.z = SPOT_POS.z
	srv.sessions[1] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
		"channel": {}, "login_attempts": 0, "inv_dirty": false}
	srv.loot_spots = [{"ruin_id": 3, "index": 1, "kind": "chest", "pos": SPOT_POS, "rot": 0.0}]
	srv.loot_ruins = [{"id": 3, "grade": 1}]
	srv.loot_rng.seed = 5
	return srv


func _sent(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == 1 and m[1] == method:
			out.append(m[2])
	return out


func _run(srv: Node, seconds: float) -> void:
	for i in int(round(seconds / GameConfig.TICK_DT)):
		srv.test_now += GameConfig.TICK_DT
		srv._tick()


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


# --- the tables (Loot) ---

func test_every_table_holds_only_real_items_another_system_uses() -> void:
	var tables: Array = Loot.TABLES.values()
	tables.append(Loot.BEACH_CRATE)
	for t in tables:
		for e in t:
			var item := str(e[0])
			if item == "":
				continue
			check(Inventory.is_item(item), "%s is a real item" % item)
			check(int(e[1]) >= 1 and int(e[2]) >= int(e[1]) and int(e[3]) > 0, "%s has a sane range and weight" % item)
			var used := Needs.is_food(item) or Crafting.RECIPES.has(item) or item in [Vitals.BANDAGE_ITEM, "hide", "plant_fibre"]
			for r in Crafting.RECIPES.values():
				if r.get("needs", {}).has(item):
					used = true
			check(used, "%s is used by something (food, a recipe, a tool or a cost)" % item)
	for g in [1, 2, 3, 4]:
		check(Loot.TABLES.has(g), "grade %d has a table" % g)
	for k in RuinLayout.LOOT_KINDS:
		check(Loot.DRAWS.has(k) and Loot.BIAS.has(k), "%s has draws and a bias" % k)


func test_a_roll_is_deterministic_and_in_range() -> void:
	check_eq(Loot.roll(1, "chest", _rng(9)), Loot.roll(1, "chest", _rng(9)), "same seed, same find")
	var rng := _rng(1)
	for i in 300:
		var kind: String = RuinLayout.LOOT_KINDS[i % 4]
		var found := Loot.roll(1 + i % 4, kind, rng)
		var total := 0
		for item in found:
			check(Inventory.is_item(str(item)), "found a real item")
			total += int(found[item])
		check(total >= 1, "a %s always holds something in a ruin" % kind)
		check(total <= 3 * 5, "and never a flood")


func test_deadlier_ruins_pay_better() -> void:
	var rng := _rng(3)
	var tools := {1: 0, 4: 0}
	for g in [1, 4]:
		for i in 400:
			var found := Loot.roll(g, "chest", rng)
			for item in found:
				if str(item).begins_with("stone_"):
					tools[g] += 1
	check_eq(tools[1], 0, "no stone tools in a quiet ruin")
	check(tools[4] > 100, "a deadly ruin's chests hold stone tools and weapons (%d)" % tools[4])


func test_a_body_leans_to_bandages_and_torches() -> void:
	var rng := _rng(4)
	var counts := {"body": 0, "sack": 0}
	for kind in counts:
		for i in 500:
			var found := Loot.roll(1, kind, rng)
			if found.has("bandage") or found.has("torch"):
				counts[kind] += 1
	check(counts.body > counts.sack, "bodies carry bandages and torches more than sacks (%d vs %d)" % [counts.body, counts.sack])


func test_beach_crates_sometimes_hold_more() -> void:
	var rng := _rng(6)
	var extra := 0
	for i in 200:
		var found := Loot.roll_beach(rng)
		check(found.size() <= 1, "one draw at most")
		extra += 1 if not found.is_empty() else 0
	check(extra > 100 and extra < 190, "most crates hold a little more, not all (%d of 200)" % extra)


func test_searched_spots_refill_after_a_day() -> void:
	var st := Loot.new_state()
	check(not Loot.is_empty(st, "1:0", 0.0), "full to start")
	Loot.mark_searched(st, "1:0", 10.0)
	check(Loot.is_empty(st, "1:0", 10.0 + Loot.REFILL - 1.0), "empty for a day")
	check(not Loot.is_empty(st, "1:0", 10.0 + Loot.REFILL), "full again after")
	check(not Loot.is_empty(st, "1:1", 10.0), "other spots are untouched")


func test_the_lines() -> void:
	check_eq(Loot.list_text({"berries": 2, "bandage": 1}), "a bandage and 2 berries")
	check_eq(Loot.list_text({"cooked_meat": 1}), "some cooked meat")
	check_eq(Loot.list_text({"plant_fibre": 3, "torch": 1, "bandage": 1}), "3 plant fibre, a bandage and a torch")
	check_eq(Loot.found_text("body", {"torch": 1}), "You search the body and find a torch.")
	check(Loot.found_text("sack", {}).contains("nothing left"), "an empty find says so")
	check_eq(Loot.prompt("chest", "E"), "[E] Search the chest")


func test_nearest_spot_in_reach() -> void:
	var spots := [{"ruin_id": 1, "index": 0, "kind": "sack", "pos": Vector3(0, 0, 0)},
		{"ruin_id": 1, "index": 1, "kind": "crate", "pos": Vector3(2, 0, 0)}]
	check_eq(str(Loot.nearest(spots, Vector3(1.4, 5, 0)).kind), "crate", "the closer one")
	check(Loot.nearest(spots, Vector3(10, 0, 0)).is_empty(), "nothing out of reach")
	check_eq(Loot.grade_of(spots[0], [{"id": 1, "grade": 3}]), 3)
	check_eq(Loot.grade_of(spots[0], []), 1, "an unknown ruin reads as quiet")


# --- on the server ---

func test_search_takes_a_moment_then_pays() -> void:
	var srv := _server()
	srv._on_place(1, "search")
	check(_sent(srv, "s2c_place_result").is_empty(), "no answer until the search ends")
	check(not srv.sessions[1].get("search", {}).is_empty(), "the search runs")
	_run(srv, Loot.SEARCH_SECONDS * 0.5)
	check(_sent(srv, "s2c_place_result").is_empty(), "still searching")
	_run(srv, Loot.SEARCH_SECONDS * 0.6 + 0.1)
	var res := _sent(srv, "s2c_place_result")
	check_eq(res.size(), 1, "one answer")
	check_eq(res[0][0], "search")
	check(bool(res[0][1]), "found something")
	check(str(res[0][3]).begins_with("You search the chest and find"), str(res[0][3]))
	var toasts := _sent(srv, "s2c_gather_result")
	check(toasts.size() >= 1, "a haul toast per item")
	for t in toasts:
		check(Inventory.count(srv.sessions[1].character.inventory, str(t[0])) >= int(t[1]), "%s is in the pack" % t[0])
	srv.free()


func test_a_searched_spot_is_empty_until_tomorrow() -> void:
	var srv := _server()
	srv._on_place(1, "search")
	_run(srv, Loot.SEARCH_SECONDS + 0.2)
	srv.test_outbox.clear()
	srv.test_now += 1.0
	srv._on_place(1, "search")
	var res := _sent(srv, "s2c_place_result")
	check_eq(res.size(), 1, "refused at once")
	check(not bool(res[0][1]), "refused")
	check_eq(res[0][2], "empty")
	check(str(res[0][3]).contains("Come back tomorrow"), str(res[0][3]))
	srv.test_now += Loot.REFILL
	srv.test_outbox.clear()
	srv._on_place(1, "search")
	check(_sent(srv, "s2c_place_result").is_empty(), "a day later it can be searched again")
	srv.free()


func test_walking_off_stops_the_search_with_nothing() -> void:
	var srv := _server()
	srv._on_place(1, "search")
	srv.sessions[1].character.x += 2.0
	_run(srv, 0.2)
	var res := _sent(srv, "s2c_place_result")
	check_eq(res.size(), 1)
	check(not bool(res[0][1]), "nothing found")
	check_eq(res[0][2], "moved")
	check_eq(Inventory.total(srv.sessions[1].character.inventory), 0, "nothing found")
	check(not Loot.is_empty(srv.loot, "3:1", srv.test_now), "the spot is still full")
	srv.free()


func test_nothing_to_search_far_from_a_spot() -> void:
	var srv := _server()
	srv.sessions[1].character.x = 0.0
	srv._on_place(1, "search")
	var res := _sent(srv, "s2c_place_result")
	check_eq(res[0][2], "none")
	check_eq(res[0][3], Loot.text("none"))
	srv.free()


func test_the_dev_command() -> void:
	var srv := _server()
	srv.loot_spots = []
	var first: String = srv.loot_command(1, "")
	check(first.begins_with("You search the chest and find"), "a stand-in chest on a world without ruins: %s" % first)
	check(Inventory.total(srv.sessions[1].character.inventory) > 0, "and it fills the pack")
	check(str(srv.loot_command(1, "")).contains("Come back tomorrow"), "searched once")
	srv.loot_command(1, "refill")
	check(str(srv.loot_command(1, "")).begins_with("You search"), "refilled")
	srv.free()


func test_a_real_island_has_spots_the_server_knows() -> void:
	var srv: Node = ServerScript.new()
	srv.use_world(WorldGen.parse("1126:2:3000"))
	check(srv.loot_spots.size() >= 4, "the island's farmsteads have loot spots (%d)" % srv.loot_spots.size())
	for sp in srv.loot_spots:
		check(Loot.grade_of(sp, srv.loot_ruins) >= 1, "every spot has a grade")
	srv.use_world(WorldGen.parse(""))
	check(srv.loot_spots.is_empty(), "Ashgrove has none")
	srv.free()


func test_a_washed_up_crate_holds_more_than_wood() -> void:
	var srv := _server()
	srv.use_world(WorldGen.parse("1126:2:3000"))
	var node := {}
	for n in ResourceNodes.all():
		if str(n.kind) == "wreck_crate":
			node = n
			break
	check(not node.is_empty(), "the island has washed-up crates")
	if not node.is_empty():
		var s := 0 # a seed whose first draw holds something
		while Loot.roll_beach(_rng(s)).is_empty():
			s += 1
		var expect := Loot.roll_beach(_rng(s))
		srv.loot_rng.seed = s
		var ch: Dictionary = srv.sessions[1].character
		var p: Vector3 = node.pos + Vector3(1.0, 0, 0)
		ch.x = p.x
		ch.y = p.y
		ch.z = p.z
		var started: Dictionary = srv.gather_start(1, int(node.id))
		check(started.ok, "gather started: %s" % str(started))
		_run(srv, 8.0)
		check(Inventory.count(ch.inventory, "pine_wood") > 0, "the wood")
		for item in expect:
			check(Inventory.count(ch.inventory, str(item)) >= int(expect[item]), "and %s from the crate" % item)
			check(_sent(srv, "s2c_gather_result").has([str(item), int(expect[item])]), "with its own haul toast")
	srv.use_world(WorldGen.parse(""))
	srv.free()

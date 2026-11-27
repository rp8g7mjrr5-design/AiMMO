extends TestCase
## Hunger, the first survival need (the owner's survival plan, 2026-11-27; Needs): it drains
## while you play, low slows stamina, starving wears health down to a floor (never a knock-down
## on its own), food fixes it at once, raw meat cooks at a lit campfire, scrub gives berries,
## and it is saved with the character (old saves load full).

const ServerScript := preload("res://server/server.gd")


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true
	for id in players:
		var ch := CharacterData.normalize({"name": players[id]})
		ch.x = 40.0
		ch.z = 40.0
		srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _sent(srv: Node, id: int, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == method:
			out.append(m[2])
	return out


func _run(srv: Node, seconds: float) -> void:
	var n := int(round(seconds / GameConfig.TICK_DT))
	for i in n:
		srv.test_now += GameConfig.TICK_DT
		srv._tick()


# --- the rules (Needs) ---

func test_old_saves_load_full() -> void:
	var ch := CharacterData.normalize({"name": "Old"})
	check_eq(Needs.hunger_of(ch), Needs.MAX, "no hunger field: full")
	check_eq(Needs.tier_of(ch), "fine")
	var broken := CharacterData.normalize({"name": "Odd", "hunger": "nan"})
	check(Needs.hunger_of(broken) >= 0.0 and Needs.hunger_of(broken) <= Needs.MAX, "a bad value never crashes and stays in range")
	var stored := CharacterData.normalize({"name": "Fed", "hunger": "42.5"})
	check_near(Needs.hunger_of(stored), 42.5, 0.001, "a Postgres text value loads")


func test_tiers_and_what_they_do() -> void:
	check_eq(Needs.tier(100.0), "fine")
	check_eq(Needs.tier(Needs.LOW_AT), "fine")
	check_eq(Needs.tier(Needs.LOW_AT - 0.1), "low")
	check_eq(Needs.tier(Needs.BAD_AT), "low")
	check_eq(Needs.tier(Needs.BAD_AT - 0.1), "bad")
	var ch := {"hunger": 30.0}
	check_eq(Needs.stamina_regen(ch), 0.75, "low slows stamina")
	check(Needs.can_heal(ch), "low still heals")
	ch.hunger = 5.0
	check_eq(Needs.stamina_regen(ch), 0.5, "bad slows it more")
	check(not Needs.can_heal(ch), "starving stops natural healing")


func test_a_meal_about_every_half_hour() -> void:
	var ch := {"hunger": Needs.MAX}
	Needs.tick(ch, {}, 29.0 * 60.0)
	check_eq(Needs.tier_of(ch), "fine", "still fine after 29 minutes")
	Needs.tick(ch, {}, 2.0 * 60.0)
	check_eq(Needs.tier_of(ch), "low", "hungry after about half an hour")
	Needs.tick(ch, {}, 60.0 * 60.0)
	check_eq(Needs.hunger_of(ch), 0.0, "empty, never below")


func test_starving_wears_health_to_a_floor_only() -> void:
	var ch := {"hunger": 0.0}
	var v := Vitals.full()
	Needs.tick(ch, v, 10.0)
	check_near(float(v.hp), 100.0 - Needs.HP_DRAIN * 10.0, 0.001, "health wears down")
	Needs.tick(ch, v, 10000.0)
	check_eq(float(v.hp), Needs.HP_FLOOR, "but never below the floor: hunger alone never knocks you down")
	v.hp = 5.0
	Needs.tick(ch, v, 10.0)
	check_eq(float(v.hp), 5.0, "already under the floor: hunger takes nothing more")


func test_vitals_tick_takes_the_hunger_scales() -> void:
	var v := Vitals.full()
	v.stamina = 0.0
	Vitals.tick(v, 10.0, 1.0, 0.5, true)
	check_near(float(v.stamina), Vitals.REGEN * 0.5, 0.001, "half regen")
	v.hp = 20.0
	Vitals.tick(v, 20.0, 1.0, 1.0, false)
	check_eq(float(v.hp), 20.0, "no natural healing when not allowed")
	Vitals.tick(v, 30.0, 1.0)
	check(float(v.hp) > 20.0, "the default still heals")


func test_eating() -> void:
	var ch := {"hunger": 30.0, "inventory": {"raw_meat": 1, "berries": 2, "cooked_meat": 1}}
	var v := Vitals.full()
	check_eq(Needs.best_food(ch.inventory), "cooked_meat", "best food first")
	check_eq(Needs.eat_check(ch, v), "")
	var r := Needs.eat(ch, v, "cooked_meat")
	check_near(float(r.hunger), 70.0, 0.001, "a cooked meat is a big step up")
	r = Needs.eat(ch, v, "raw_meat")
	check_near(float(r.hunger), 85.0, 0.001, "raw meat feeds a little")
	check_near(float(v.hp), 100.0 - Needs.FOODS.raw_meat.hurt, 0.001, "and turns your stomach")
	v.hp = 3.0
	Needs.set_hunger(ch, 10.0)
	Needs.eat(ch, v, "raw_meat")
	check(float(v.hp) >= 1.0, "raw meat never knocks you down")
	Needs.set_hunger(ch, 99.0)
	check_eq(Needs.eat_check(ch, v), "full", "not when full")
	check_eq(Needs.eat_check({"hunger": 10.0, "inventory": {}}, v), "no_food")
	check_eq(Needs.eat_check({"hunger": 10.0, "inventory": {"stone": 3}}, v, "stone"), "no_food", "stone is not food")


func test_every_food_and_cook_is_a_real_item() -> void:
	for f in Needs.FOODS:
		check(Inventory.ITEMS.has(f), "%s is an item" % f)
		check(ItemIcons.has_icon(f), "%s has an icon" % f)
	for raw in Needs.COOKS:
		check(Inventory.ITEMS.has(raw) and Inventory.ITEMS.has(Needs.COOKS[raw]), "%s cooks into an item" % raw)
	check_eq(Needs.EAT_ORDER.size(), Needs.FOODS.size(), "every food is in the eat order")


# --- on the server ---

func test_hunger_drains_and_is_sent_and_told_once() -> void:
	var srv := _server({1: "Ash"})
	var ch: Dictionary = srv.sessions[1].character
	_run(srv, 0.2)
	check_eq(_sent(srv, 1, "s2c_needs").back(), [{"hunger": 100}], "sent full")
	Needs.set_hunger(ch, Needs.LOW_AT + 0.01)
	_run(srv, 2.0)
	check_eq(_sent(srv, 1, "s2c_system").back(), [Needs.text("low")], "told once when hunger arrives")
	var told := _sent(srv, 1, "s2c_system").size()
	_run(srv, 2.0)
	check_eq(_sent(srv, 1, "s2c_system").size(), told, "not told again")
	check_eq(_sent(srv, 1, "s2c_needs").back(), [{"hunger": 50}], "the bar follows")
	srv.free()


func test_eat_through_the_place_message() -> void:
	var srv := _server({1: "Ash"})
	var ch: Dictionary = srv.sessions[1].character
	Needs.set_hunger(ch, 20.0)
	var r: Dictionary = srv.place_request(1, "eat")
	check(not r.ok and r.reason == "no_food", "nothing to eat")
	srv.give_item(1, "cooked_meat", 2)
	srv._on_place(1, "eat")
	check_eq(_sent(srv, 1, "s2c_place_result").back(), ["eat", true, "", "You eat cooked meat."])
	check_eq(Inventory.count(ch.inventory, "cooked_meat"), 1, "one eaten")
	check_eq(Needs.shown(ch), 60)
	srv.test_now += 1.0 # past the play-request gap
	srv._on_place(1, "berries")
	check_eq(_sent(srv, 1, "s2c_place_result").back()[2], "no_food", "a named food you don't have")
	srv.free()


func test_cook_at_a_lit_fire_only() -> void:
	var srv := _server({1: "Ash"})
	var ch: Dictionary = srv.sessions[1].character
	srv.give_item(1, "raw_meat", 3)
	var r: Dictionary = srv.place_request(1, "cook")
	check(not r.ok and r.reason == "no_fire", "no fire, no cooking")
	var pos := CharacterData.position(ch)
	srv.campfires.fires[7] = {"id": 7, "pos": pos + Vector3(1.5, 0, 0), "owner": "ash", "lit_at": 0.0, "out_at": 1.0e9}
	srv._on_place(1, "cook")
	check_eq(_sent(srv, 1, "s2c_place_result").back(), ["cook", true, "", "You cook 3 meat over the fire."])
	check_eq(Inventory.count(ch.inventory, "raw_meat"), 0, "all the raw meat")
	check_eq(Inventory.count(ch.inventory, "cooked_meat"), 3, "became cooked meat")
	r = srv.place_request(1, "cook")
	check(not r.ok and r.reason == "no_raw", "nothing left to cook")
	srv.free()


func test_a_knock_down_never_wakes_you_starving() -> void:
	var srv := _server({1: "Ash"})
	var ch: Dictionary = srv.sessions[1].character
	Needs.set_hunger(ch, 3.0)
	srv.hurt(1, 500.0)
	check_eq(Needs.hunger_of(ch), Needs.AFTER_KNOCKDOWN)
	srv.free()


func test_the_dev_command_sets_hunger() -> void:
	var srv := _server({1: "Ash"})
	srv._on_chat(1, "/vitals hunger 10")
	check_eq(Needs.shown(srv.sessions[1].character), 10)
	check(str(_sent(srv, 1, "s2c_system").back()[0]).ends_with("Hunger 10/100 (bad)."), str(_sent(srv, 1, "s2c_system").back()))
	srv.free()


func test_scrub_gives_berries_with_its_fibre() -> void:
	var srv := _server({1: "Ash"})
	var node := {}
	for n in ResourceNodes.all():
		if str(n.kind) == "scrub":
			node = n
			break
	if node.is_empty():
		check(false, "no scrub in this world")
		srv.free()
		return
	var ch: Dictionary = srv.sessions[1].character
	var p: Vector3 = node.pos + Vector3(1.0, 0, 0)
	ch.x = p.x
	ch.y = p.y
	ch.z = p.z
	var started: Dictionary = srv.gather_start(1, int(node.id))
	check(started.ok, "gather started: %s" % str(started))
	_run(srv, 8.0)
	check(Inventory.count(ch.inventory, "plant_fibre") > 0, "fibre")
	check_eq(Inventory.count(ch.inventory, "berries"), 1, "and a handful of berries")
	check(_sent(srv, 1, "s2c_gather_result").has(["berries", 1]), "with their own haul toast")
	srv.free()


func test_a_wipe_feeds_you() -> void:
	check(FileAccess.get_file_as_string("res://server/world_wipe.gd").contains("Needs.set_hunger(ch, Needs.MAX)"), "a new island starts you full")


func test_the_migration_is_add_only() -> void:
	var sql := FileAccess.get_file_as_string("res://../db/migrations/0006_character_hunger.sql")
	if sql == "":
		return # not in a checkout
	check(sql.contains("ADD COLUMN IF NOT EXISTS hunger"), "adds the column")
	check(not sql.to_upper().contains("DROP") or sql.to_upper().contains("NEVER DROP"), "drops nothing")


func test_hunger_round_trips_through_postgres() -> void:
	if not has_db():
		return
	var pg := PgStore.new()
	pg.url = OS.get_environment("DATABASE_URL")
	pg.migrations_dir = Migrator.default_dir()
	check(pg.open(), "open: " + pg.last_error)
	var name_lc := "hungry%d" % (Time.get_ticks_usec() % 100000000)
	var acc := pg.create_account(name_lc, name_lc, "x")
	var ch := pg.load_or_create_character(acc)
	check_eq(Needs.hunger_of(ch), Needs.MAX, "a new character starts full")
	Needs.set_hunger(ch, 31.5)
	check(pg.save_character(ch), "save: " + pg.last_error)
	check_near(Needs.hunger_of(pg.find_character_by_name(name_lc)), 31.5, 0.01, "read back from characters.hunger")
	pg.close()


func test_hunger_round_trips_through_the_json_store() -> void:
	var path := OS.get_user_data_dir().path_join("hunger_test_%d.json" % (Time.get_ticks_usec() % 100000000))
	var js := JsonStore.new()
	js.path = path
	check(js.open(), "open")
	var acc := js.create_account("Peckish", "peckish", "x")
	var ch := js.load_or_create_character(acc)
	Needs.set_hunger(ch, 12.0)
	check(js.save_character(ch), "saved")
	var again := JsonStore.new()
	again.path = path
	check(again.open(), "reopen")
	check_near(Needs.hunger_of(again.find_character_by_name("Peckish")), 12.0, 0.01, "read back")
	DirAccess.remove_absolute(path)

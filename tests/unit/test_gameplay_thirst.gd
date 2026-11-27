extends TestCase
## Thirst, the second survival need (step 3 of the owner's survival plan; Needs): it drains
## faster than hunger, works on the same tiers without stacking into a double penalty, is fixed
## at a lake or river or from a waterskin (crafted from hide and fibre, filled at fresh water),
## and is saved with the character (old saves load full).

const ServerScript := preload("res://server/server.gd")


func _server() -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true
	var ch := CharacterData.normalize({"name": "Dry"})
	ch.x = 40.0
	ch.z = 40.0
	srv.sessions[1] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
		"channel": {}, "login_attempts": 0, "inv_dirty": false}
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


func _lake_shore() -> Vector3:
	var l: Dictionary = WorldGen.lakes()[0]
	var c: Vector2 = l.center
	var p := c + Vector2(float(l.radius) + 1.0, 0.0)
	return Vector3(p.x, Terrain.height(p.x, p.y), p.y)


# --- the rules (Needs) ---

func test_old_saves_load_quenched() -> void:
	var ch := CharacterData.normalize({"name": "Old"})
	check_eq(Needs.thirst_of(ch), Needs.MAX, "no thirst field: full")
	var stored := CharacterData.normalize({"name": "Dry", "thirst": "33.5"})
	check_near(Needs.thirst_of(stored), 33.5, 0.001, "a Postgres text value loads")


func test_thirst_drains_faster_than_hunger() -> void:
	var ch := {"hunger": Needs.MAX, "thirst": Needs.MAX}
	Needs.tick(ch, {}, 21.0 * 60.0)
	check_eq(Needs.thirst_tier_of(ch), "fine", "fine after 21 minutes")
	Needs.tick(ch, {}, 3.0 * 60.0)
	check_eq(Needs.thirst_tier_of(ch), "low", "thirsty after about 22")
	check_eq(Needs.tier_of(ch), "fine", "before you're hungry")
	Needs.tick(ch, {}, 60.0 * 60.0)
	check_eq(Needs.thirst_of(ch), 0.0, "empty, never below")


func test_the_worse_need_sets_the_pace_and_nothing_stacks() -> void:
	var ch := {"hunger": 30.0, "thirst": 100.0}
	check_eq(Needs.stamina_regen(ch), 0.75, "hungry only")
	ch.thirst = 5.0
	check_eq(Needs.stamina_regen(ch), 0.5, "parched is the worse")
	check(not Needs.can_heal(ch), "parched stops natural healing")
	ch.hunger = 5.0
	var v := Vitals.full()
	Needs.tick(ch, v, 10.0)
	check_near(float(v.hp), 100.0 - Needs.HP_DRAIN * 10.0, 0.01, "starving and parched wear health once, not twice")
	Needs.tick(ch, v, 10000.0)
	check_eq(float(v.hp), Needs.HP_FLOOR, "and never below the floor")


func test_drink_choices() -> void:
	var ch := {"thirst": 30.0, "inventory": {}}
	check_eq(Needs.drink_check(ch, {}, false), "no_water", "nothing to drink away from water")
	check_eq(Needs.drink_check(ch, {}, true), "fresh", "at water: drink")
	ch.inventory = {"full_waterskin": 1}
	check_eq(Needs.drink_check(ch, {}, false), "skin", "a full skin anywhere")
	ch.thirst = 99.0
	check_eq(Needs.drink_check(ch, {}, false), "not_thirsty")
	ch.inventory = {"waterskin": 2}
	check_eq(Needs.drink_check(ch, {}, true), "fresh", "not thirsty but empty skins to fill")
	check_near(Needs.drink({"thirst": 10.0}, "full_waterskin"), 55.0, 0.001, "a skin is a big swallow")


func test_the_waterskin_is_a_real_crafted_item() -> void:
	for item in ["waterskin", "full_waterskin"]:
		check(Inventory.ITEMS.has(item), "%s is an item" % item)
		check(ItemIcons.has_icon(item), "%s has an icon" % item)
		check(PackGrid.SHAPES.has(item), "%s has a shape in the pack" % item)
	check_eq(Crafting.RECIPES.waterskin.needs, {"hide": 2, "plant_fibre": 2}, "hide from the hunt, fibre from the scrub")
	check(not bool(Crafting.RECIPES.waterskin.bench), "no bench needed")
	check(Crafting.RECIPE_ORDER.has("waterskin"), "in the craft list")
	check_eq(Needs.FILLS.waterskin, "full_waterskin")
	check_eq(Needs.DRINKS.full_waterskin.leaves, "waterskin", "a drink leaves the skin")


func test_fresh_water_is_lakes_and_rivers_not_the_sea() -> void:
	WorldGen.configure(1126, 3000.0, WorldGen.ISLAND)
	check(WorldGen.lakes().size() > 0 and WorldGen.rivers().size() > 0, "the island has lakes and rivers")
	check(Needs.at_fresh_water(_lake_shore()), "a lake's shore")
	var river: PackedVector2Array = WorldGen.rivers()[0]
	var mid := river[river.size() / 2]
	check(Needs.at_fresh_water(Vector3(mid.x, 0, mid.y) + Vector3(2.0, 0, 0)), "beside a river")
	var land := WorldGen.landings()[0] as Vector2
	check(not Needs.at_fresh_water(Vector3(land.x, 0, land.y)), "a beach landing is salt water")
	WorldGen.reset()
	check(not Needs.at_fresh_water(Vector3(40, 0, 40)), "Ashgrove has none")


# --- on the server ---

func test_thirst_is_sent_and_told_once() -> void:
	var srv := _server()
	var ch: Dictionary = srv.sessions[1].character
	_run(srv, 0.2)
	check_eq(int(_sent(srv, "s2c_needs").back()[0].thirst), 100, "sent full")
	Needs.set_thirst(ch, Needs.LOW_AT + 0.01)
	_run(srv, 2.0)
	check_eq(_sent(srv, "s2c_system").back(), [Needs.text("thirst_low")], "told once when thirst arrives")
	var told := _sent(srv, "s2c_system").size()
	_run(srv, 2.0)
	check_eq(_sent(srv, "s2c_system").size(), told, "not told again")
	check_eq(int(_sent(srv, "s2c_needs").back()[0].thirst), 50, "the mark follows")
	srv.free()


func test_drink_from_a_waterskin_through_the_place_message() -> void:
	var srv := _server()
	var ch: Dictionary = srv.sessions[1].character
	Needs.set_thirst(ch, 20.0)
	srv._on_place(1, "drink")
	var res := _sent(srv, "s2c_place_result")
	check_eq(res[0], ["drink", false, "no_water", Needs.text("no_water")], "nothing to drink")
	srv.give_item(1, "full_waterskin", 1)
	srv.test_now += 1.0
	srv._on_place(1, "drink")
	res = _sent(srv, "s2c_place_result")
	check_eq(res[1], ["drink", true, "", Needs.text("drank_skin")])
	check_near(Needs.thirst_of(ch), 65.0, 0.01, "a big swallow")
	check_eq(Inventory.count(ch.inventory, "full_waterskin"), 0, "the full skin is drunk")
	check_eq(Inventory.count(ch.inventory, "waterskin"), 1, "and comes back empty")
	srv.free()


func test_drink_at_a_lake_fills_you_and_your_skins() -> void:
	var srv := _server()
	srv.use_world(WorldGen.parse("1126:2:3000"))
	var ch: Dictionary = srv.sessions[1].character
	var p := _lake_shore()
	ch.x = p.x
	ch.y = p.y
	ch.z = p.z
	Needs.set_thirst(ch, 10.0)
	srv.give_item(1, "waterskin", 2)
	var r: Dictionary = srv.drink_request(1)
	check(r.ok, str(r))
	check_eq(r.text, Needs.text("drank_fresh_filled") % 2)
	check_eq(Needs.thirst_of(ch), Needs.MAX, "drink your fill")
	check_eq(Inventory.count(ch.inventory, "full_waterskin"), 2, "both skins filled")
	check_eq(Inventory.count(ch.inventory, "waterskin"), 0)
	var again: Dictionary = srv.drink_request(1)
	check(not again.ok and again.reason == "not_thirsty", "full, nothing to fill: %s" % str(again))
	srv.use_world(WorldGen.parse(""))
	srv.free()


func test_a_knock_down_never_wakes_you_parched() -> void:
	var ch := {"hunger": 80.0, "thirst": 3.0}
	Needs.after_knockdown(ch)
	check_eq(Needs.thirst_of(ch), Needs.AFTER_KNOCKDOWN)
	check_eq(Needs.hunger_of(ch), 80.0, "hunger untouched when above the line")


func test_the_dev_command_sets_thirst() -> void:
	var srv := _server()
	var line: String = srv.vitals_command(1, "/vitals thirst 37")
	check(line.ends_with("Thirst 37/100 (low)."), line)
	srv.free()


func test_a_wipe_quenches_you() -> void:
	check(FileAccess.get_file_as_string("res://server/world_wipe.gd").contains("Needs.set_thirst(ch, Needs.MAX)"), "a new island starts you full")


func test_the_migration_is_add_only() -> void:
	var sql := FileAccess.get_file_as_string("res://../db/migrations/0008_character_thirst.sql")
	if sql == "":
		return # not in a checkout
	check(sql.contains("ADD COLUMN IF NOT EXISTS thirst"), "adds the column")
	check(not sql.to_upper().contains("DROP ") or sql.to_upper().contains("NEVER DROP"), "drops nothing")


func test_thirst_round_trips_through_postgres() -> void:
	if not has_db():
		return
	var pg := PgStore.new()
	pg.url = OS.get_environment("DATABASE_URL")
	pg.migrations_dir = Migrator.default_dir()
	check(pg.open(), "open: " + pg.last_error)
	var name_lc := "thirsty%d" % (Time.get_ticks_usec() % 100000000)
	var acc := pg.create_account(name_lc, name_lc, "x")
	var ch := pg.load_or_create_character(acc)
	check_eq(Needs.thirst_of(ch), Needs.MAX, "a new character starts full")
	Needs.set_thirst(ch, 41.5)
	check(pg.save_character(ch), "save: " + pg.last_error)
	check_near(Needs.thirst_of(pg.find_character_by_name(name_lc)), 41.5, 0.01, "read back from characters.thirst")
	pg.close()


func test_thirst_round_trips_through_the_json_store() -> void:
	var path := OS.get_user_data_dir().path_join("thirst_test_%d.json" % (Time.get_ticks_usec() % 100000000))
	var js := JsonStore.new()
	js.path = path
	check(js.open(), "open")
	var acc := js.create_account("Parched", "parched", "x")
	var ch := js.load_or_create_character(acc)
	Needs.set_thirst(ch, 12.0)
	check(js.save_character(ch), "saved")
	var again := JsonStore.new()
	again.path = path
	check(again.open(), "reopen")
	check_near(Needs.thirst_of(again.find_character_by_name("Parched")), 12.0, 0.01, "read back")
	DirAccess.remove_absolute(path)


# --- the client ---

func test_the_f_key_picks_the_worse_need() -> void:
	check_eq(NeedsIcon.f_word(30, 80, {"berries": 2}, false), "eat", "hungrier: eat")
	check_eq(NeedsIcon.f_word(80, 30, {"berries": 2, "full_waterskin": 1}, false), "drink", "thirstier with a skin: drink")
	check_eq(NeedsIcon.f_word(80, 30, {"berries": 2}, false), "eat", "thirstier but no water to hand: eat")
	check_eq(NeedsIcon.f_word(80, 30, {}, true), "drink", "at a lake: drink")
	check_eq(NeedsIcon.f_word(100, 60, {"full_waterskin": 1}, false), "drink", "no food, a skin and a little thirst: drink")
	check_eq(NeedsIcon.f_word(100, 100, {}, false), "eat", "nothing at all: eat (its refusal says what to do)")


func test_the_thirst_mark_reads_only_thirst() -> void:
	var n := NeedsIcon.new()
	n.configure("thirst", "full_waterskin", "Drink")
	n.setup(Theme.new())
	n.on_needs({"hunger": 10, "thirst": 90})
	check(not n.showing(), "quenched: nothing, whatever hunger says")
	n.on_needs({"hunger": 90, "thirst": 30})
	check(n.showing(), "thirsty: shown")
	n.step(0.5)
	check(n.hint.text.ends_with("] Drink"), "the hint says Drink: %s" % n.hint.text)
	n.free()

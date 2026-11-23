extends TestCase
## Skills and XP (game/shared/skills.gd): the curve hits the Milestone 1 time targets at
## today's gather timings, gains and unlocks, old saves load at level 1, the server pays XP
## on every completed gather and craft (more with company), levels make gathers quicker
## and richer, the level-up line follows the gather line, and both stores keep XP.

const ServerScript := preload("res://server/server.gd")

## Pace model for the time targets: one gather is its channel time plus a share of the walk
## to the next node (a node gives Gathering.CHARGES gathers; WALK_PER_NODE seconds between
## nodes is a short stroll inside a grove). Deliberately ignores the per-level speed gain,
## so the real game is a little quicker than this.
const WALK_PER_NODE := 6.0


func _seconds_to(level: int, kind: String, with_tool: bool) -> float:
	var inv := {"stone_axe": 1, "stone_pickaxe": 1} if with_tool else {}
	var per := GatherChannel.seconds_for(kind, inv) + WALK_PER_NODE / float(Gathering.charges(kind))
	var gathers := ceili(float(Skills.xp_for_level(level)) / float(Skills.gather_xp(kind)))
	return gathers * per


func test_curve_is_monotonic_and_capped() -> void:
	check_eq(Skills.xp_for_level(1), 0, "level 1 is free")
	var last := 0
	var last_step := 0
	for l in range(2, Skills.CAP + 1):
		var t := Skills.xp_for_level(l)
		check(t > last, "level %d needs more XP than %d" % [l, l - 1])
		check(Skills.xp_step(l - 1) >= last_step, "each level's step is at least the last one's (%d)" % l)
		last_step = Skills.xp_step(l - 1)
		last = t
	check_eq(Skills.xp_step(Skills.CAP), 0, "nothing to earn past the cap")
	check_eq(Skills.level_for(0), 1)
	check_eq(Skills.level_for(-50), 1, "negative XP is still level 1")
	check_eq(Skills.level_for(Skills.xp_for_level(2) - 1), 1, "one short of level 2")
	check_eq(Skills.level_for(Skills.xp_for_level(2)), 2, "exactly level 2")
	check_eq(Skills.level_for(Skills.xp_for_level(37)), 37)
	check_eq(Skills.level_for(Skills.xp_for_level(Skills.CAP) * 3), Skills.CAP, "capped at 100")
	check_eq(Skills.xp_to_next(0), Skills.xp_for_level(2))
	check_eq(Skills.xp_to_next(Skills.xp_for_level(Skills.CAP)), 0)
	check_near(Skills.progress(0), 0.0, 0.0001)
	check_near(Skills.progress(Skills.xp_for_level(2) / 2), 0.5, 0.01, "half way to 2")
	check_near(Skills.progress(Skills.xp_for_level(Skills.CAP)), 1.0, 0.0001)


func test_curve_hits_the_milestone_time_targets() -> void:
	# Roadmap Milestone 1: level 2 within 90 s of first gathering, level 5 in about 10
	# minutes, level 10 inside a first session, 50 in weeks, 100 in months.
	var l2 := _seconds_to(2, "pine", false)
	check(l2 >= 30.0 and l2 <= 90.0, "level 2 bare-handed in %.0f s (want 30..90)" % l2)
	var l5 := _seconds_to(5, "pine", false)
	check(l5 >= 6 * 60.0 and l5 <= 15 * 60.0, "level 5 bare-handed in %.1f min (want about 10)" % (l5 / 60.0))
	var l5_axe := _seconds_to(5, "pine", true)
	check(l5_axe < l5, "an axe gets you there sooner")
	var l10 := _seconds_to(10, "pine", true)
	check(l10 >= 20 * 60.0 and l10 <= 90 * 60.0, "level 10 with an axe in %.0f min (want inside one session)" % (l10 / 60.0))
	var hours_a_day := 2.0
	var l50_days := _seconds_to(50, "pine", true) / 3600.0 / hours_a_day
	check(l50_days >= 10.0 and l50_days <= 60.0, "level 50 in %.0f days at 2 h a day (want weeks)" % l50_days)
	var l100_days := _seconds_to(100, "pine", true) / 3600.0 / hours_a_day
	check(l100_days >= 90.0, "level 100 in %.0f days at 2 h a day (want months)" % l100_days)
	var l2_stone := _seconds_to(2, "stone", false)
	check(l2_stone <= 90.0, "Quarrying 2 in %.0f s" % l2_stone)
	# A seep gives once and only at night: a handful is enough for Tapping 2.
	check(ceili(150.0 / Skills.gather_xp("ember_sap")) <= 6, "Tapping 2 within a few seeps")


func test_every_node_kind_and_recipe_teaches_a_skill() -> void:
	for kind in ResourceNodes.KINDS:
		check(Skills.is_skill(Skills.skill_for_kind(kind)), "%s trains a skill" % kind)
		check(Skills.gather_xp(kind) > 0, "%s pays XP" % kind)
	for r in Crafting.RECIPES:
		check(Skills.craft_xp(r) > 0, "%s pays Toolcraft XP" % r)
	check_eq(Skills.craft_xp("stone_axe"), 40, "5 items x 8")
	check_eq(Skills.craft_xp("nope"), 0)
	check_eq(Skills.ORDER.size(), Skills.SKILLS.size(), "every skill has an order")
	for id in Skills.UNLOCKS:
		check(Skills.is_skill(id), "unlocks for a real skill: " + id)


func test_together_bonus() -> void:
	check_eq(Skills.gather_xp("pine", false), 10)
	check_eq(Skills.gather_xp("pine", true), 13, "25% more, rounded up")
	check_eq(Skills.craft_xp("stone_axe", true), 50)
	check_eq(Skills.with_bonus(0, true), 0)


func test_gain_levels_and_unlocks() -> void:
	var sk := {}
	var r := Skills.gain(sk, "felling", 10)
	check_eq(r.gained, 10)
	check_eq(r.level, 1)
	check_eq(sk.felling, 10)
	check(r.unlocks.is_empty(), "no unlock yet")
	r = Skills.gain(sk, "felling", Skills.xp_for_level(5) - 10)
	check_eq(r.level_before, 1)
	check_eq(r.level, 5, "jumps several levels at once")
	check_eq(r.unlocks.size(), 1, "passes the level 5 unlock")
	check_eq(r.unlocks[0].level, 5)
	check_eq(r.unlocks[0].name, "Old ember ash")
	check_eq(Skills.gain(sk, "felling", 0).gained, 0, "nothing for nothing")
	check_eq(Skills.gain(sk, "felling", -5).gained, 0, "never loses XP")
	check_eq(Skills.gain(sk, "juggling", 50).gained, 0, "unknown skill")
	check(not sk.has("juggling"), "unknown skill leaves no entry")
	check_eq(Skills.level_of(sk, "quarrying"), 1, "untouched skill is level 1")
	var nxt = Skills.next_unlock("felling", 5)
	check(nxt != null and nxt.level == 10, "after 5 the next unlock is at 10")
	check(Skills.next_unlock("felling", Skills.CAP) == null, "none past the cap")


func test_levels_make_gathers_quicker_and_richer() -> void:
	check_near(GatherChannel.seconds_for("pine", {}, 1), 2.0, 0.0001, "level 1 is the base time")
	check(GatherChannel.seconds_for("pine", {}, 2) < GatherChannel.seconds_for("pine", {}, 1), "level 2 a little quicker")
	check_near(GatherChannel.seconds_for("pine", {}, Skills.CAP), 2.0 * 0.703, 0.001, "level 100 is 30% quicker")
	check_near(GatherChannel.seconds_for("pine", {"stone_axe": 1}, 1), 1.0, 0.0001, "tool still halves it")
	check_eq(Gathering.amount_for("pine", {}, 1), 2)
	check_eq(Gathering.amount_for("pine", {}, 9), 2)
	check_eq(Gathering.amount_for("pine", {}, 10), 3, "Clean cuts: +1 wood")
	check_eq(Gathering.amount_for("pine", {"stone_axe": 1}, 25), 5, "2 + tool 1 + Clean cuts + Heartwood")
	check_eq(Gathering.amount_for("ember_sap", {}, 5), 2, "Patient hands: +1 sap")
	check_eq(Gathering.amount_for("stone", {}, 4), 2)


func test_normalize_and_old_characters() -> void:
	var sk := Skills.normalize({"felling": "1700", "quarrying": 12.0, "tapping": -4, "toolcraft": NAN, "old_lore": 55, "": 9, 3: 1})
	check_eq(sk.felling, 1700, "text XP from Postgres BIGINT")
	check_eq(sk.quarrying, 12, "float from JSON")
	check_eq(sk.tapping, 0, "negative floored")
	check_eq(sk.toolcraft, 0, "NaN floored")
	check_eq(sk.old_lore, 55, "unknown (retired) skill kept, never silently lost")
	check(not sk.has(""), "blank id dropped")
	check_eq(Skills.normalize("junk"), {})
	check_eq(Skills.normalize(null), {})
	var old := CharacterData.normalize({"id": 1, "name": "Old"})
	check_eq(old.skills, {}, "characters from before skills have none")
	for id in Skills.ORDER:
		check_eq(Skills.level_of(old.skills, id), 1, "and are level 1 in " + id)
	var other := CharacterData.normalize({"id": 2, "name": "Other"})
	Skills.gain(old.skills, "felling", 20)
	check_eq(other.skills, {}, "skills are never shared through the default")
	check_eq(CharacterData.DEFAULTS.skills, {}, "default untouched")
	check_eq(CharacterData.normalize({"id": 3, "skills": "garbage"}).skills, {}, "corrupt skills load empty")
	var with_both := CharacterData.normalize({"id": 4, "inventory": {"stone": 2}, "skills": {"quarrying": 300}})
	check_eq(with_both.inventory, {"stone": 2}, "inventory still normalized as a pack")
	check_eq(with_both.skills, {"quarrying": 300}, "skills normalized as XP, not capped like a stack")


func test_text() -> void:
	var r := Skills.gain({}, "felling", 150)
	var line := Skills.level_up_text(r)
	check_eq(line, "Felling is now level 2! Your gathers are a little quicker. Next: Felling 5, Old ember ash.")
	check(not line.begins_with("You"), "never mistaken for a gather or craft reply")
	var r10 := Skills.gain({"felling": Skills.xp_for_level(9)}, "felling", Skills.xp_step(9))
	check_eq(r10.level, 10)
	check(Skills.level_up_text(r10).contains("Unlocked: Clean cuts (+1 wood from every gather)."), Skills.level_up_text(r10))
	var r5 := Skills.gain({}, "quarrying", Skills.xp_for_level(5))
	check(Skills.level_up_text(r5).contains("Rich seam (work the rich stone seams past the meadow)."), Skills.level_up_text(r5))
	check(not Skills.level_up_text(r5).contains("coming soon"), "tier-2 nodes exist now: " + Skills.level_up_text(r5))
	var t3 := Skills.gain({}, "toolcraft", Skills.xp_for_level(3))
	check(Skills.level_up_text(t3).contains("coming soon"), "a 'soon' unlock says so: " + Skills.level_up_text(t3))
	var d := Skills.describe({"felling": 160})
	check(d.begins_with("Skills: Felling 2 (10/"), d)
	check(d.contains("Toolcraft 1 (0/150 XP)"), d)
	check_eq(ChatCommands.run("/skills", {"skills": {"felling": 160}}), d, "hidden /skills command")
	check(not ChatCommands.HELP.contains("/skills"), "not listed in /help (chat is for talking)")


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _server(positions: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	for id in positions:
		var ch := CharacterData.normalize({"name": "P%d" % id})
		var p: Vector3 = positions[id]
		ch.x = p.x
		ch.y = p.y
		ch.z = p.z
		srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _run(srv: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		srv.test_now += GameConfig.TICK_DT
		t += GameConfig.TICK_DT
		srv._tick_channels(srv.test_now)
		srv._flush_inventories()


func _lines(srv: Node, id: int) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == "s2c_system":
			out.append(str(m[2][0]))
	return out


func test_server_pays_xp_for_a_timed_gather() -> void:
	var pine := _first("pine")
	var srv := _server({1: pine.pos})
	check(srv.gather_request(1, pine.id).ok, "starts")
	_run(srv, 2.2)
	var ch: Dictionary = srv.sessions[1].character
	check_eq(Skills.xp_of(ch.skills, "felling"), 10, "one pine pays 10 Felling XP")
	check_eq(Inventory.count(ch.inventory, "pine_wood"), 2)
	srv.free()


func test_cancelled_gather_pays_nothing() -> void:
	var pine := _first("pine")
	var srv := _server({1: pine.pos})
	srv.gather_request(1, pine.id)
	_run(srv, 0.5)
	srv.gather_cancel(1, "stopped")
	_run(srv, 2.0)
	check_eq(srv.sessions[1].character.skills, {}, "no XP for a gather you let go of")
	srv.free()


func test_level_up_line_follows_the_gather_line() -> void:
	var pine := _first("pine")
	var srv := _server({1: pine.pos})
	srv.sessions[1].character.skills = {"felling": 145}
	srv.gather_request(1, pine.id)
	_run(srv, 2.2)
	var lines := _lines(srv, 1)
	var gi := -1
	var li := -1
	for i in lines.size():
		if lines[i].begins_with("You gather"):
			gi = i
		if lines[i].begins_with("Felling is now level 2!"):
			li = i
	check(gi >= 0, "gather line sent: %s" % [lines])
	check(li > gi, "level-up line right after it: %s" % [lines])
	check_eq(Skills.level_of(srv.sessions[1].character.skills, "felling"), 2)
	# The next gather at level 2 is a little quicker.
	srv.test_outbox.clear()
	var r: Dictionary = srv.gather_request(1, pine.id)
	check(r.ok and r.seconds < 2.0, "level 2 gathers in %.3f s" % r.seconds)
	srv.free()


func test_company_pays_more() -> void:
	var pine := _first("pine")
	var near: Vector3 = pine.pos + Vector3(Skills.TOGETHER_RANGE - 3.0, 0, 0)
	var srv := _server({1: pine.pos, 2: near})
	srv.gather_request(1, pine.id)
	_run(srv, 2.2)
	check_eq(Skills.xp_of(srv.sessions[1].character.skills, "felling"), 13, "a friend nearby: 13 instead of 10")
	srv.sessions[2].character.x = pine.pos.x + Skills.TOGETHER_RANGE + 5.0
	srv.gather_request(1, pine.id)
	_run(srv, 2.2)
	check_eq(Skills.xp_of(srv.sessions[1].character.skills, "felling"), 23, "alone again: 10")
	srv.free()


func test_instant_gather_and_craft_pay_xp() -> void:
	var stone := _first("stone")
	var srv := _server({1: stone.pos})
	var reply: String = srv.gather(1, "stone")
	check(reply.begins_with("You gather"), reply)
	check_eq(Skills.xp_of(srv.sessions[1].character.skills, "quarrying"), 12, "/gather pays Quarrying")
	var bench := Crafting.workbench_pos()
	srv.sessions[1].character.x = bench.x
	srv.sessions[1].character.z = bench.z
	srv.sessions[1].character.inventory = {"ash_wood": 3, "stone": 2}
	var r: Dictionary = srv.craft_request(1, "stone_axe")
	check(r.ok, "crafts: %s" % r.text)
	check_eq(Skills.xp_of(srv.sessions[1].character.skills, "toolcraft"), 40, "a stone axe pays 40 Toolcraft")
	var bad: Dictionary = srv.craft_request(1, "stone_axe")
	check(not bad.ok, "a second axe is refused")
	check_eq(Skills.xp_of(srv.sessions[1].character.skills, "toolcraft"), 40, "no XP for a refused craft")
	srv.free()


func test_json_store_keeps_xp() -> void:
	var path := OS.get_user_data_dir().path_join("unit_test_skills_%d.json" % Time.get_ticks_usec())
	var s := JsonStore.new()
	s.path = path
	check(s.open(), "opens")
	var ch := s.load_or_create_character(s.create_account("Wren", "wren", "h"))
	check_eq(ch.skills, {}, "starts with none")
	Skills.gain(ch.skills, "felling", 420)
	check(s.save_character(ch), "saved")
	var s2 := JsonStore.new()
	s2.path = path
	check(s2.open(), "reopens")
	var back := s2.load_or_create_character(s2.find_account("wren"))
	check_eq(Skills.xp_of(back.skills, "felling"), 420, "XP kept")
	check_eq(Skills.level_of(back.skills, "felling"), 2)
	DirAccess.remove_absolute(path)


func test_pg_store_keeps_xp() -> void:
	if not has_db():
		return
	var s := PgStore.new()
	s.url = OS.get_environment("DATABASE_URL")
	s.migrations_dir = Migrator.default_dir()
	check(s.open(), "open: " + s.last_error)
	var uname := "skilltest%d" % (Time.get_ticks_usec() % 100000000)
	var acct := s.create_account(uname, uname, "h")
	var ch := s.load_or_create_character(acct)
	check_eq(ch.skills, {}, "new character, no XP")
	check(s.save_character(ch), "saving no XP is fine: " + s.last_error)
	Skills.gain(ch.skills, "quarrying", 300)
	Skills.gain(ch.skills, "toolcraft", 40)
	check(s.save_character(ch), "save: " + s.last_error)
	var back := s.load_or_create_character(acct)
	check_eq(Skills.xp_of(back.skills, "quarrying"), 300, "quarrying kept")
	check_eq(Skills.xp_of(back.skills, "toolcraft"), 40, "toolcraft kept")
	Skills.gain(back.skills, "quarrying", 5)
	check(s.save_character(back), "save again: " + s.last_error)
	# A stale copy (from before the last gain) must never take XP away.
	check(s.save_character(ch), "stale save: " + s.last_error)
	var again := s.find_character_by_name(uname)
	check_eq(Skills.xp_of(again.skills, "quarrying"), 305, "a stale save never lowers XP")
	s.close()


func test_week01_skills_fixture_loads() -> void:
	if not has_db():
		return
	var store := PgStore.new()
	store.url = OS.get_environment("DATABASE_URL")
	store.migrations_dir = Migrator.default_dir()
	check(store.open(), "open: " + store.last_error)
	var db := PgClient.new()
	db.connect_url(store.url)
	var sql := FileAccess.get_file_as_string("res://tests/fixtures/week01_skills.sql")
	check(db.simple_query(sql) != null, "fixture applied: " + db.last_error)
	db.close()
	var acct := store.find_account("grove_feller")
	check(not acct.is_empty(), "account found")
	var ch := store.load_or_create_character(acct)
	check_eq(ch.name, "Grove_Feller")
	check_eq(Skills.xp_of(ch.skills, "felling"), 1700, "felling XP kept")
	check_eq(Skills.level_of(ch.skills, "felling"), 5)
	check_eq(Skills.xp_of(ch.skills, "old_lore"), 55, "unknown skill not lost")
	check_eq(Inventory.count(ch.inventory, "stone_axe"), 1, "pack still loads alongside")
	check(store.save_character(ch), "saves back: " + store.last_error)
	check_eq(store.load_or_create_character(acct).skills, ch.skills, "save + reload round-trips XP")
	# Characters saved before skills existed (week 00 fixtures) load at level 1 everywhere.
	for old in ["pack_carrier", "legacy_wanderer"]:
		var a := store.find_account(old)
		if not a.is_empty():
			check_eq(store.load_or_create_character(a).skills, {}, "%s has no XP yet" % old)
	store.close()

extends TestCase
## Character customization (protocol v8): the look a player chooses (Appearance), how it is
## checked and stored (CharacterData, characters.appearance from migration 0004), and how the
## server shares it (c2s_set_look -> s2c_look to everyone online).

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

const V8_RPCS := ["c2s_set_look", "s2c_look"]


func _server(ids: Array) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	for id in ids:
		srv.sessions[id] = {"logged_in": true, "character": CharacterData.normalize({"name": "p%d" % id}),
			"move": Vector2.ZERO, "yaw": 0.0, "seq": -1, "last_chat": -1000.0, "last_command": -1000.0,
			"last_too_fast": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _sent(srv: Node, id: int, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == method:
			out.append(m[2])
	return out


func _look() -> Dictionary:
	return {"body": 3, "height": 4, "skin": 6, "face": 3, "hair": 4, "hair_colour": 5, "beard": 3,
		"headwear": 2, "tunic": 7, "trousers": 4}


func test_v8_adds_the_look_rpcs_on_play_and_v7_is_frozen() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 8, "v8 or later")
	var expected := Array(ProtocolCompat.rpc_names("res://tests/protocol/net_play_v7.gd")) + V8_RPCS
	expected.sort()
	if GameConfig.PROTOCOL_VERSION == 8:
		check_eq(Array(ProtocolCompat.rpc_names("res://shared/net_play.gd")), expected, "v8 Play = v7 Play + the look")
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v7.gd"),
		"Net's own RPCs unchanged since v7")


func test_v8_rpcs_reemit_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.look_requested.connect(func(p, l): got.append(["set", p, l]))
	net.look_changed.connect(func(p, l): got.append(["look", p, l]))
	net.play.c2s_set_look({"body": 1})
	net.play.s2c_look(4, {"skin": 2})
	check_eq(got, [["set", 0, {"body": 1}], ["look", 4, {"skin": 2}]])
	net.free()


func test_option_counts_match_the_palette() -> void:
	check_eq(Appearance.count("skin"), Palette.SKIN_TONES.size(), "one skin tone per choice")
	check_eq(Appearance.count("hair_colour"), Palette.HAIR.size(), "one hair colour per choice")
	check_eq(Appearance.count("tunic"), Palette.CLOTH.size(), "one tunic dye per choice")
	check_eq(Appearance.count("trousers"), Palette.TROUSER_DYES.size(), "one trouser dye per choice")
	check_eq(Appearance.count("body"), AvatarBuilder.BUILDS.size(), "one build per choice")
	check_eq(Appearance.count("height"), AvatarBuilder.HEIGHTS.size(), "one height per choice")
	check_eq(Appearance.ORDER.size(), Appearance.OPTIONS.size(), "every option is listed once")
	check_eq(Appearance.DEFAULT.size(), Appearance.ORDER.size(), "a default for every option")
	check_eq(Appearance.check(Appearance.DEFAULT), "", "the default is a valid look")


func test_check_is_strict_about_what_a_client_sends() -> void:
	check_eq(Appearance.check(_look()), "")
	check(Appearance.check("hi") != "", "not a dictionary")
	check(Appearance.check({}) != "", "empty")
	var missing := _look()
	missing.erase("beard")
	check(Appearance.check(missing) != "", "a key missing")
	var extra := _look()
	extra.erase("beard")
	extra["wings"] = 1
	check(Appearance.check(extra) != "", "an unknown key")
	for bad in [-1, 99, "2", 1.5, null]:
		var lk := _look()
		lk.skin = bad
		check(Appearance.check(lk) != "", "skin = %s refused" % [bad])
	var as_json := _look()
	as_json.skin = 2.0
	check_eq(Appearance.check(as_json), "", "a whole float (JSON) is fine")


func test_normalize_never_throws_a_look_away() -> void:
	check_eq(Appearance.normalize({}), {}, "empty stays not chosen")
	check_eq(Appearance.normalize(null), {}, "null is not chosen")
	var n := Appearance.normalize({"skin": 99, "beard": "2", "wings": 3})
	check_eq(n.size(), Appearance.ORDER.size(), "complete")
	check_eq(n.skin, Appearance.count("skin") - 1, "out of range is clamped, not dropped")
	check_eq(n.beard, 2, "numbers in strings read")
	check(not n.has("wings"), "unknown keys dropped")
	check_eq(n.body, Appearance.DEFAULT.body, "missing keys take the default")


func test_json_round_trip_and_old_saves() -> void:
	check_eq(Appearance.from_json(Appearance.to_json(_look())), _look(), "round trip")
	check_eq(Appearance.to_json({}), "", "not chosen is stored as ''")
	check_eq(Appearance.from_json(""), {}, "'' (every save before migration 0004) is not chosen")
	check_eq(Appearance.from_json(null), {}, "a missing column is not chosen")
	check_eq(Appearance.from_json("{broken"), {}, "garbage is not chosen, never an error")
	check_eq(Appearance.from_json("[1,2]"), {}, "not an object")


func test_character_data_carries_the_look() -> void:
	check_eq(CharacterData.normalize({"name": "Old"}).look, {}, "an old character has no look")
	var ch := CharacterData.from_pg_row({"id": 1, "account_id": 1, "name": "Ash", "appearance": Appearance.to_json(_look())})
	check_eq(ch.look, _look(), "read from characters.appearance")
	var json_saved := CharacterData.normalize({"name": "Ash", "look": JSON.parse_string(JSON.stringify(_look()))})
	check_eq(json_saved.look, _look(), "the JSON store's floats come back as the same look")
	check_eq(CharacterData.from_pg_row({"id": 1, "name": "Old"}).look, {}, "a row from before 0004")


func test_from_seed_and_random_are_valid_and_deterministic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 50:
		check_eq(Appearance.check(Appearance.random(rng)), "", "random look %d is valid" % i)
		check_eq(Appearance.check(Appearance.from_seed(i * 7919)), "", "seed look %d is valid" % i)
	check_eq(Appearance.from_seed(1234), Appearance.from_seed(1234), "deterministic")


func test_stepped_wraps() -> void:
	var lk := Appearance.DEFAULT.duplicate()
	lk.beard = 0
	check_eq(Appearance.stepped(lk, "beard", -1).beard, Appearance.count("beard") - 1, "back past the first wraps")
	check_eq(Appearance.stepped(lk, "beard", 1).beard, 1)
	check_eq(Appearance.stepped({}, "skin", 1).skin, Appearance.DEFAULT.skin + 1, "from not chosen starts at the default")


func test_set_look_saves_and_tells_everyone() -> void:
	var srv := _server([1, 2, 3])
	check_eq(srv.set_look(1, _look()), "")
	check_eq(srv.sessions[1].character.look, _look(), "kept on the character (saved with it)")
	for id in [1, 2, 3]:
		check_eq(_sent(srv, id, "s2c_look"), [[1, _look()]], "peer %d told" % id)
	srv.free()


func test_set_look_refuses_bad_looks_and_floods() -> void:
	var srv := _server([1, 2])
	var bad := _look()
	bad.skin = 50
	check(srv.set_look(1, bad) != "", "out of range refused")
	check_eq(srv.sessions[1].character.look, {}, "nothing stored")
	check_eq(_sent(srv, 2, "s2c_look"), [], "nobody told")
	check_eq(_sent(srv, 1, "s2c_system"), [[Appearance.REFUSED]], "the sender hears why")
	check_eq(srv.set_look(1, _look()), "")
	check_eq(srv.set_look(1, Appearance.DEFAULT), "too soon", "a second save within LOOK_GAP")
	srv.test_now += srv.LOOK_GAP + 0.01
	check_eq(srv.set_look(1, Appearance.DEFAULT), "", "after the gap")
	check_eq(srv.sessions[1].character.look, Appearance.DEFAULT)
	check(srv.set_look(9, _look()) != "", "not logged in")
	srv.free()


func test_json_store_keeps_the_look() -> void:
	var path := OS.get_user_data_dir().path_join("test_look_store_%d.json" % Time.get_ticks_usec())
	var js := JsonStore.new()
	js.path = path
	check(js.open(), "open")
	var acc := js.create_account("Ash", "ash", "x")
	var ch := js.load_or_create_character(acc)
	check_eq(ch.look, {}, "a new character has not chosen")
	ch.look = _look()
	check(js.save_character(ch), "save")
	var again := JsonStore.new()
	again.path = path
	check(again.open(), "reopen")
	check_eq(again.load_or_create_character(acc).look, _look(), "the look survives a restart")
	DirAccess.remove_absolute(path)


func test_pg_store_keeps_the_look() -> void:
	if not has_db():
		return
	var pg := PgStore.new()
	pg.url = OS.get_environment("DATABASE_URL")
	pg.migrations_dir = Migrator.default_dir()
	check(pg.open(), "open: " + pg.last_error)
	var name_lc := "look%d" % (Time.get_ticks_usec() % 100000000)
	var acc := pg.create_account(name_lc, name_lc, "x")
	var ch := pg.load_or_create_character(acc)
	check_eq(ch.look, {}, "a new character has not chosen")
	ch.look = _look()
	check(pg.save_character(ch), "save: " + pg.last_error)
	check_eq(pg.find_character_by_name(name_lc).look, _look(), "read back from characters.appearance")
	pg.close()

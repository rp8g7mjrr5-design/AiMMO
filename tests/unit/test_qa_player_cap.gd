extends TestCase
## The bot test's player-cap phase (behaviour qa_player_cap, run_bot_test.run_player_cap):
## the text its bots expect is exactly what a full server says, and it is quiet without a cap.

const ServerScript := preload("res://server/server.gd")
const CapBehaviour := preload("res://tests/bot_test/behaviours/qa_player_cap.gd")


func _full_server(cap: int) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.max_players = cap
	var st := JsonStore.new()
	st.path = "user://test_qa_player_cap_%d/players.json" % Time.get_ticks_usec()
	st.open()
	srv.store = st
	for i in cap:
		srv._on_peer_connected(10 + i)
		srv._on_login(10 + i, GameConfig.PROTOCOL_VERSION, "Capper%s" % char(65 + i), "hunter22pass")
	return srv


func test_expected_text_is_the_servers_full_text() -> void:
	for cap in [3, 8]:
		var srv := _full_server(cap)
		check(srv.is_world_full(), "cap %d: full after %d logins" % [cap, cap])
		check_eq(CapBehaviour.full_text(cap), srv.world_full_text(), "cap %d" % cap)
		srv._on_peer_connected(99)
		srv._on_login(99, GameConfig.PROTOCOL_VERSION, "Latecomer", "hunter22pass")
		var r: Array = []
		for m in srv.test_outbox:
			if m[0] == 99 and m[1] == "s2c_login_result":
				r = m[2]
		check(r.size() >= 2 and not bool(r[0]), "cap %d: the extra login is refused" % cap)
		if r.size() >= 2:
			check_eq(str(r[1]), CapBehaviour.full_text(cap), "the refusal is the text the bots expect")
		srv.free()


class FakeBot:
	extends Node
	var args := {}
	var failures: Array = []

	func _fail(msg: String) -> void:
		failures.append(msg)


class FakeNet:
	extends Node
	signal login_result(ok: bool, message: String, my_id: int, character: Dictionary)


func _behaviour(args: Dictionary) -> Object:
	var b = CapBehaviour.new()
	var bot := FakeBot.new()
	bot.args = args
	b.bot = bot
	b.name = "qa_player_cap"
	var net := FakeNet.new()
	b.setup(net)
	_made.append_array([bot, net])
	return b


var _made: Array = []


func _free_fakes() -> void:
	for n in _made:
		n.free()
	_made.clear()


func _snapshot(players: int) -> Array:
	var e: Array = []
	for i in players:
		e.append_array([i + 1, 0.0, 0.0, 0.0, 0.0])
	return e


func test_quiet_without_a_cap() -> void:
	var b = _behaviour({})
	b.on_snapshot(1, _snapshot(20))
	b.on_finish()
	check_eq(b.cap, 0)
	check(b.bot.failures.is_empty(), "no cap: twenty players are fine")
	check(b.stats.is_empty(), "no cap: no stats")
	_free_fakes()


func test_one_too_many_fails_and_a_full_world_passes() -> void:
	var b = _behaviour({"player-cap": "8"})
	b.on_snapshot(1, _snapshot(8))
	check(b.bot.failures.is_empty(), "eight in a world for eight is fine")
	b.on_snapshot(2, _snapshot(9))
	check_eq(b.bot.failures.size(), 1, "a ninth player fails")
	b.on_finish()
	check_eq(b.stats.get("max_players_seen"), 9)
	_free_fakes()


func test_refusal_text_is_checked() -> void:
	var b = _behaviour({"player-cap": "8"})
	b._on_login_result(false, CapBehaviour.full_text(8), 0, {})
	check(b.bot.failures.is_empty(), "the polite text passes")
	b._on_login_result(false, "The world is full (8 / 9). Try again soon.", 0, {})
	check_eq(b.bot.failures.size(), 1, "a wrong count fails")
	b.on_finish()
	check_eq(b.stats.get("refusals"), 2)
	_free_fakes()

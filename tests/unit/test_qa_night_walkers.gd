extends TestCase
## The bot test's night phase (behaviour qa_night_walkers, run_bot_test.run_night): bots stand
## their watch where walkers may rise, go for the nearest one, face it the way swings aim, strike
## from inside bare-hand reach, and stay quiet on a normal run. The phase's clock constants
## must match WorldClock.

const NightBehaviour := preload("res://tests/bot_test/behaviours/qa_night_walkers.gd")


class FakeBot:
	extends Node
	var args := {}
	var failures: Array = []
	var bot_name := "botx_night1"
	var elapsed := 0.0
	var my_id := 7
	var my_pos := Vector3.ZERO
	var move := Vector2.ZERO
	var yaw := 0.0
	var rng := RandomNumberGenerator.new()
	var sent: Array = []

	func _fail(msg: String) -> void:
		failures.append(msg)

	func send_play(method: String, call_args: Array = []) -> bool:
		sent.append([method, call_args])
		return true


class FakeNet:
	extends Node
	signal gloam_changed(entries: PackedFloat32Array)
	signal gloam_struck(peer_id: int, kind: String, walker_ids: Array, downed: Array)
	signal vitals_changed(hp: int, max_hp: int, stamina: int, max_stamina: int)
	signal swing_landed(peer_id: int, kind: String, creature_ids: Array)
	signal attack_refused(kind: String, reason: String)
	signal system_message(text: String)


var _made: Array = []


func _behaviour(args: Dictionary) -> Array:
	var b = NightBehaviour.new()
	var bot := FakeBot.new()
	bot.args = args
	b.bot = bot
	b.name = "qa_night_walkers"
	var net := FakeNet.new()
	b.setup(net)
	_made.append_array([bot, net])
	return [b, bot, net]


func _free_fakes() -> void:
	for n in _made:
		n.free()
	_made.clear()


func _wire(walkers: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for w in walkers:
		out.append_array(PackedFloat32Array([w[0], w[1], w[2], 0.0, 2.0, 0.0])) # state "hunt"
	return out


func test_posts_are_where_walkers_may_rise() -> void:
	var seen := {}
	for i in 4:
		var name := "bot12345_night%d" % (i + 1)
		var p: Vector2 = NightBehaviour.post_for(name)
		check_eq(p, NightBehaviour.post_for(name), "a bot's post is stable across logins")
		var d := p.distance_to(Vector2(GameConfig.SPAWN_POINT.x, GameConfig.SPAWN_POINT.z))
		check(d > Gloam.SAFE_RADIUS + 5.0, "%s stands past Spawn Meadow's safe ring (%.1f m)" % [name, d])
		check(d + Gloam.RISE_MAX < GameConfig.VIEW_RANGE, "walkers rising near the post are in view")
		seen[str(p)] = true
	check_eq(seen.size(), 4, "four bots, four posts")


func test_nearest_and_facing() -> void:
	var walkers := Gloam.from_wire(_wire([[1, 10.0, 0.0], [2, 3.0, 4.0], [3, 100.0, 0.0]]))
	var w: Dictionary = NightBehaviour.nearest(walkers, Vector2.ZERO, 45.0)
	check_eq(int(w.id), 2, "the nearest walker is the one we go for")
	check(NightBehaviour.nearest(walkers, Vector2(500, 500), 45.0).is_empty(), "nothing within range")
	var yaw: float = NightBehaviour.yaw_to(Vector2.ZERO, Vector2(3, 4))
	check(Weapons.in_swing(Vector3.ZERO, yaw, Vector3(3, 0, 4) * 0.25, Gloam.radius("walker"), Weapons.FISTS, "heavy"),
		"the bot's facing is the way a swing aims")
	check(NightBehaviour.STRIKE_RANGE <= Weapons.reach(Weapons.FISTS, "heavy") + Gloam.radius("walker"),
		"the bot only swings once the walker is in bare-hand reach")


func test_quiet_on_a_normal_run() -> void:
	var made := _behaviour({})
	var b = made[0]
	b.on_login(false, {})
	b.on_play(0.1)
	b.on_finish()
	check(made[1].failures.is_empty(), "no --night-walkers: nothing is asked of the bot")
	check(b.stats.is_empty(), "no --night-walkers: no stats")
	check(made[1].sent.is_empty(), "no --night-walkers: no swings")
	_free_fakes()


func test_a_night_with_no_walkers_fails() -> void:
	var made := _behaviour({"night-walkers": true})
	var b = made[0]
	b.on_login(false, {})
	b.on_finish()
	check_eq(made[1].failures.size(), 1, "a whole night with no walker near is a failure")
	_free_fakes()


func test_hunt_swing_and_down() -> void:
	var made := _behaviour({"night-walkers": true})
	var b = made[0]
	var bot: FakeBot = made[1]
	var net: FakeNet = made[2]
	bot.my_pos = Vector3(55, 0, 0)
	b.on_login(false, {})
	bot.elapsed = 2.0
	net.gloam_changed.emit(_wire([[5, 65.0, 0.0]]))
	b.on_play(0.1)
	check(bot.move.length() > 0.9 and bot.move.x > 0.0, "walks at the walker")
	check(bot.sent.is_empty(), "no swing from 10 m")
	# In reach: the first walker of a login is let in to grab once, then the bot swings back.
	net.gloam_changed.emit(_wire([[5, 56.2, 0.0]]))
	b.on_play(0.1)
	check(bot.sent.is_empty(), "lets the first walker grab")
	net.vitals_changed.emit(100, 100, 10, 10)
	net.vitals_changed.emit(85, 100, 10, 10)
	b.on_play(0.1)
	check_eq(bot.sent.size(), 1, "grabbed: swings back")
	if bot.sent.size() == 1:
		check_eq(str(bot.sent[0][0]), "c2s_attack")
		check_eq(str(bot.sent[0][1][0]), "heavy")
	net.swing_landed.emit(bot.my_id, "heavy", [])
	net.gloam_struck.emit(bot.my_id, "heavy", [5], [5])
	b.on_finish()
	check_eq(int(b.stats.grabs), 1)
	check_eq(int(b.stats.downs), 1)
	check_eq(int(b.stats.hits), 1)
	check(bot.failures.is_empty(), "a clean fight: %s" % [bot.failures])
	# A walker we put down must leave the wire.
	bot.elapsed = 5.0
	net.gloam_changed.emit(_wire([[5, 56.2, 0.0]]))
	check_eq(bot.failures.size(), 1, "a downed walker still on the wire is a failure")
	_free_fakes()


func test_phase_clock_matches_world_clock() -> void:
	var text := FileAccess.get_file_as_string("res://tests/bot_test/run_bot_test.py")
	check(text != "", "run_bot_test.py is readable")
	for pair in [["WORLD_EPOCH_UNIX", WorldClock.WORLD_EPOCH_UNIX], ["DAY_SECONDS", WorldClock.DAY_SECONDS],
			["START_FRACTION", WorldClock.START_FRACTION]]:
		var re := RegEx.create_from_string("(?m)^%s = ([0-9.]+)" % pair[0])
		var m := re.search(text)
		check(m != null, "%s is set in run_bot_test.py" % pair[0])
		if m != null:
			check_eq(m.get_string(1).to_float(), float(pair[1]), pair[0])

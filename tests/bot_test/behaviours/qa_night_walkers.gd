extends "res://tests/bot_test/bot_behaviour.gd"
## QA (basics 2, zombie survival): the first night against walkers that rise on their own.
##
## Only active when the bot is started with `--night-walkers` (run_bot_test.py's night phase
## boots a server with `--gloam=1` and a clock offset that puts it at midnight, the way the
## live world runs after dark, and a few bots with `--only-behaviour=qa_night_walkers
## --night-walkers`). The main bot test keeps `--gloam=0` because its gather and persistence
## checks assume a quiet world; this phase is where natural rising meets a group of players.
##
## Each bot walks out of Spawn Meadow to its own post (POST_RADIUS from spawn, past
## Gloam.SAFE_RADIUS, where walkers may rise) and plays like a player caught out at night:
##   - no walker in view: hold the post and throw a light swing at the air every CALL_EVERY
##     seconds (fighting is loud: Gloam.NOISE_RADIUS draws them in);
##   - a walker in s2c_gloam within HUNT_RANGE: walk at the nearest, face it, and throw
##     haymakers (c2s_attack "heavy") once it is in reach, until s2c_gloam_hits says it's down;
##   - caught off guard: the first walker of each login is let in to grab once (or for
##     LET_GRAB_MAX seconds) before the bot swings back, so the grab, the hurt and the fight
##     after it are on the wire every run (a bot that always hits first is never grabbed);
##   - grabbed: s2c_vitals drops (counted); knocked down: the server's line, the bot comes to
##     in Spawn Meadow with full health and walks back out (counted, not a failure).
## Checked here: every walker on the wire has a finite position and a known state, a walker
## we put down leaves s2c_gloam, and walkers rose near this bot at all. run_bot_test.py checks
## the group as a whole (some grabs, some walkers put down) and the server log.

const POST_RADIUS := 55.0
const POST_SLACK := 3.0
const HUNT_RANGE := 45.0
const CALL_EVERY := 4.0
## Swing once the walker's centre is this close: bare-hand reach plus its body, less slack.
const STRIKE_RANGE := 1.6
const SWING_TIMEOUT := 3.0
const LET_GRAB_MAX := 6.0
const STALE_GLOAM := 1.0 ## s2c_gloam comes at 5 Hz; older than this, the view is empty
const GONE_AFTER := 1.0 ## a downed walker may linger in one in-flight s2c_gloam, not longer

var active := false
var _post := Vector2.ZERO
var _walkers: Array = [] ## the last s2c_gloam, from_wire
var _walkers_at := -INF
var _target := -1
var _swinging := false
var _swing_sent_at := 0.0
var _swing_kind := ""
var _next_swing := 0.0
var _hp := -1
var _let_grab := true ## this login's first walker gets one grab in before we swing
var _let_since := -1.0
var _downed_at := {} ## walker id -> bot.elapsed when our blow put it down

var seen := {} ## walker ids seen on the wire
var hunted := 0 ## walkers we went for
var heavies := 0
var calls := 0
var hits := 0 ## our blows that struck a walker
var downs := 0
var grabs := 0
var knockdowns := 0
var refusals := {}


func setup(net: Node) -> void:
	active = bot.args.has("night-walkers")
	if not active:
		return
	net.gloam_changed.connect(_on_gloam)
	net.gloam_struck.connect(_on_struck)
	net.vitals_changed.connect(_on_vitals)
	net.swing_landed.connect(_on_landed)
	net.attack_refused.connect(_on_refused)
	net.system_message.connect(_on_system)


## Where bot `bot_name` stands its watch: its own bearing, POST_RADIUS from spawn.
static func post_for(bot_name: String) -> Vector2:
	var a := float(hash(bot_name) % 3600) / 3600.0 * TAU
	return Vector2(GameConfig.SPAWN_POINT.x, GameConfig.SPAWN_POINT.z) + Vector2(cos(a), sin(a)) * POST_RADIUS


## The nearest walker in `walkers` (from_wire entries) within `radius` of `pos`, or {}.
static func nearest(walkers: Array, pos: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for w in walkers:
		var d := pos.distance_to(Vector2(float(w.x), float(w.z)))
		if d <= best_d:
			best = w
			best_d = d
	return best


## The yaw that faces `to` from `from` (Weapons: forward is (sin yaw, cos yaw)).
static func yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if not active:
		return
	_post = post_for(str(bot.bot_name))
	_walkers = []
	_target = -1
	_swinging = false
	_hp = -1
	_let_grab = true
	_let_since = -1.0
	_next_swing = bot.elapsed + 1.0


func on_play(_delta: float) -> void:
	if not active:
		return
	var me := Vector2(bot.my_pos.x, bot.my_pos.z)
	if _swinging:
		bot.move = Vector2.ZERO
		if bot.elapsed - _swing_sent_at > SWING_TIMEOUT:
			fail("a %s swing never landed" % _swing_kind)
			_swinging = false
		return
	var view: Array = _walkers if bot.elapsed - _walkers_at < STALE_GLOAM else []
	var w := nearest(view, me, HUNT_RANGE)
	if w.is_empty():
		_target = -1
		var to_post := _post - me
		if to_post.length() > POST_SLACK:
			bot.move = to_post.normalized()
			bot.yaw = yaw_to(me, _post)
		else:
			bot.move = Vector2.ZERO
			if bot.elapsed >= _next_swing:
				calls += 1
				_swing("light", bot.rng.randf() * TAU)
		return
	if int(w.id) != _target:
		_target = int(w.id)
		hunted += 1
	var at := Vector2(float(w.x), float(w.z))
	var face := yaw_to(me, at)
	bot.yaw = face
	if me.distance_to(at) > STRIKE_RANGE:
		bot.move = (at - me).normalized()
		return
	bot.move = Vector2.ZERO
	if _let_grab:
		if _let_since < 0.0:
			_let_since = bot.elapsed
		if bot.elapsed - _let_since < LET_GRAB_MAX:
			return
		_let_grab = false
	if bot.elapsed >= _next_swing:
		heavies += 1
		_swing("heavy", face)


func _swing(kind: String, face: float) -> void:
	bot.yaw = face
	_swinging = true
	_swing_kind = kind
	_swing_sent_at = bot.elapsed
	if not bot.send_play("c2s_attack", [kind, face]):
		_swinging = false
		_next_swing = bot.elapsed + 0.5


func _on_landed(peer: int, kind: String, _ids: Array) -> void:
	if peer != bot.my_id or not _swinging or kind != _swing_kind:
		return
	_swinging = false
	var recover := _swing_sent_at + Weapons.swing_seconds(Weapons.FISTS, kind) + 0.1
	_next_swing = recover if kind == "heavy" else bot.elapsed + CALL_EVERY


func _on_refused(kind: String, reason: String) -> void:
	if not _swinging:
		return
	refusals[reason] = int(refusals.get(reason, 0)) + 1
	_swinging = false
	_next_swing = bot.elapsed + 0.5
	if not reason in ["busy", "tired", "winded"]:
		fail("%s swing refused: %s" % [kind, reason])


func _on_gloam(entries: PackedFloat32Array) -> void:
	_walkers = Gloam.from_wire(entries)
	_walkers_at = bot.elapsed
	for w in _walkers:
		var id := int(w.id)
		seen[id] = true
		if not (is_finite(float(w.x)) and is_finite(float(w.z))):
			fail("walker %d has a non-finite position on the wire" % id)
		if int(Gloam.STATES.find(str(w.state))) < 0:
			fail("walker %d has an unknown state %s" % [id, str(w.state)])
		if _downed_at.has(id) and bot.elapsed - float(_downed_at[id]) > GONE_AFTER:
			fail("walker %d is still in s2c_gloam after we put it down" % id)
			_downed_at.erase(id)


func _on_struck(peer: int, _kind: String, ids: Array, downed: Array) -> void:
	if peer != bot.my_id:
		return
	hits += ids.size()
	for id in downed:
		downs += 1
		_downed_at[int(id)] = bot.elapsed
		if int(id) == _target:
			_target = -1


func _on_vitals(hp: int, _max_hp: int, _stamina: int, _max_stamina: int) -> void:
	if _hp >= 0 and hp < _hp:
		grabs += 1
		_let_grab = false
	_hp = hp


func _on_system(text: String) -> void:
	if text == Vitals.KNOCKED_DOWN_TEXT:
		knockdowns += 1
		_target = -1
		_hp = -1 # the full bar that follows is not a heal to judge


func on_finish() -> void:
	if not active:
		return
	stat("seen", seen.size())
	stat("hunted", hunted)
	stat("heavies", heavies)
	stat("calls", calls)
	stat("hits", hits)
	stat("downs", downs)
	stat("grabs", grabs)
	stat("knockdowns", knockdowns)
	stat("refusals", refusals)
	if seen.is_empty():
		fail("no walker rose near us all night (post %s)" % _post)

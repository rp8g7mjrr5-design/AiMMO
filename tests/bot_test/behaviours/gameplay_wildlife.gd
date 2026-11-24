extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): protocol v6, the grazers outside the meadow (s2c_wildlife).
##
## Every bot, every login: herds live 44-110 m from spawn and the view is 120 m, so an
## s2c_wildlife must arrive within FIRST_WITHIN seconds. Every one must be well formed: 5
## values per creature, known ids, no id twice, a real state, and every creature within
## GameConfig.VIEW_RANGE of us (plus a little for our own walking since). They come about 5
## times a second, never faster than MAX_RATE on average.
##
## One bot per run (the one named *_1, in long runs only) stalks a herd once, the way a player
## first meets one: after the reconnect, between two of gameplay_gather_v3's gathers
## (ready_to_lend), when a calm grazer is within STALK_MAX_START metres, it borrows the bot
## (bot meta "wildlife_stalking") and rushes straight at it. Short on purpose (a herd close by,
## STALK_TIMEOUT at most) so the stalker still levels up inside the run. The grazer must bolt
## ("flee" in s2c_wildlife) by the time we are within BOLT_SLACK of Wildlife.BOLT_RADIUS, and
## at least one herd-mate must bolt with it. Then the bot is handed back. A stalk that never
## gets close (a lake in the way, a herd too far off) is skipped and counted, not failed.
## The server only sends herd-mates within Wildlife.HERD_RADIUS of the bolter (and not down)
## running with it, so the herd check applies only when one stood clearly that close when it
## bolted; a lone grazer is counted (herd_alone), not failed. qa, 2026-11-24: CI failed once
## with "no herd-mate went with it" after gameplay_hunt's /lure and kill can take a herd-mate
## away from its herd in the same run.

const FIRST_WITHIN := 5.0
const MAX_RATE := 6.5 ## sends per second, averaged over a login (server: 5)
const VIEW_SLACK := 6.0 ## metres we may have walked since the server measured
const STALKER_SUFFIX := "_1"
const LONG_RUN := 120.0
const STALK_MAX_START := 45.0 ## don't start a stalk whose grazer is further than this
const STALK_TIMEOUT := 12.0
const BOLT_SLACK := 1.5 ## the grazer reacts on the server's tick; our position is a snapshot behind
const HERD_WAIT := 1.5 ## after the target bolts, its herd-mates must within this
const HERD_SLACK := 2.0 ## a herd-mate counts as "with it" only this far inside HERD_RADIUS (snapshots lag)
const QUIET_BEFORE := 20.0 ## no stalk this close to the end of the run
const LOGIN_SETTLE := 8.0
## gameplay_roster_v5's "Return to Spawn Meadow" moves us up to ~100 m in one tick; skip the
## view check until our own snapshot has caught up.
const TELEPORT_GRACE := 2.0

enum Stalk { WAIT, GO, HERD, DONE }

var _login_at := 0.0
var _logins := 0
var _got_this_login := 0
var _first_checked := false
var _login_elapsed_total := 0.0
var sends := 0
var empties := 0
var max_seen := 0
var _latest: Dictionary = {} ## id -> [x, z, yaw, state name]

var _stalker := false
var _stalk := Stalk.WAIT
var _target := -1
var _stalk_since := 0.0
var _bolted_at := -1.0
var _closest := INF
var stalks := 0
var bolts := 0
var herd_bolts := 0
var herd_alone := 0 ## the target bolted with no herd-mate within reach of it
var skipped := 0


func setup(net: Node) -> void:
	net.wildlife_changed.connect(_on_wildlife)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _logins > 0:
		_login_elapsed_total += bot.elapsed - _login_at
	_logins += 1
	_login_at = bot.elapsed
	_got_this_login = 0
	_first_checked = false
	_latest.clear()
	_stalker = str(bot.bot_name).ends_with(STALKER_SUFFIX) and float(bot.duration) >= LONG_RUN
	if _stalk == Stalk.GO or _stalk == Stalk.HERD:
		_end_stalk(false) # logged out mid-stalk: try again this login
	bot.set_meta("wildlife_stalking", false)


func _on_wildlife(entries: PackedFloat32Array) -> void:
	sends += 1
	_got_this_login += 1
	if entries.is_empty():
		empties += 1
		_latest.clear()
		return
	if entries.size() % Wildlife.WIRE_STRIDE != 0:
		fail("s2c_wildlife of %d values, not a multiple of %d" % [entries.size(), Wildlife.WIRE_STRIDE])
		return
	var count := Wildlife.spawns().size()
	var seen := {}
	_latest.clear()
	for i in range(0, entries.size(), Wildlife.WIRE_STRIDE):
		var id := int(entries[i])
		var state := int(entries[i + 4])
		if id < 0 or id >= count:
			fail("s2c_wildlife has unknown creature %d" % id)
			continue
		if seen.has(id):
			fail("s2c_wildlife lists creature %d twice" % id)
		seen[id] = true
		if state < 0 or state >= Wildlife.STATES.size():
			fail("creature %d in unknown state %d" % [id, state])
			continue
		var x := float(entries[i + 1])
		var z := float(entries[i + 2])
		var teleported := maxf(float(bot.get_meta("unstuck_at", -INF)), float(bot.get_meta("knocked_down_at", -INF)))
		if bot.have_pos and bot.elapsed - teleported > TELEPORT_GRACE:
			var d := Vector2(x - bot.my_pos.x, z - bot.my_pos.z).length()
			if d > GameConfig.VIEW_RANGE + VIEW_SLACK:
				fail("sent creature %d %.1f m away, beyond the view (%.1f s in, %s)" % [id, d, bot.elapsed, bot.phase])
		_latest[id] = [x, z, float(entries[i + 3]), Wildlife.STATES[state]]
	max_seen = maxi(max_seen, seen.size())
	_watch_stalk()


func _herd_in_view_of_spawn() -> bool:
	for s in Wildlife.spawns():
		var p: Vector3 = s.pos
		if Vector2(p.x - GameConfig.SPAWN_POINT.x, p.z - GameConfig.SPAWN_POINT.z).length() < GameConfig.VIEW_RANGE - 20.0:
			return true
	return false


func _gather_v3() -> Object:
	for b in bot.behaviours:
		if b.name == "gameplay_gather_v3":
			return b
	return null


func _gathering_busy() -> bool:
	for b in bot.behaviours:
		if b.name == "gameplay_gathering" and b._active:
			return true
	return false


func _quiet_left() -> float:
	var ends := float(bot.disconnect_at) if str(bot.phase) == "playing_1" else float(bot.duration)
	return ends - float(bot.elapsed)


func on_play(_delta: float) -> void:
	if not _first_checked and bot.elapsed - _login_at > FIRST_WITHIN:
		_first_checked = true
		if _got_this_login == 0 and _herd_in_view_of_spawn() \
				and Vector2(bot.my_pos.x, bot.my_pos.z).length() < 40.0:
			fail("no s2c_wildlife within %.0f s of login %d, with herds in view of spawn" % [FIRST_WITHIN, _logins])
	if not _stalker:
		return
	match _stalk:
		Stalk.WAIT:
			_maybe_start()
		Stalk.GO:
			_steer()
		Stalk.HERD:
			bot.move = Vector2.ZERO
			if bot.elapsed - _bolted_at > HERD_WAIT:
				fail("grazer %d bolted but no herd-mate went with it" % _target)
				_end_stalk(true)


func _maybe_start() -> void:
	if str(bot.phase) != "playing_2" or bot.elapsed - _login_at < LOGIN_SETTLE \
			or _quiet_left() < QUIET_BEFORE or _gathering_busy():
		return
	var g = _gather_v3()
	if g != null and not g.ready_to_lend():
		return
	var best := -1
	var best_d := INF
	for id in _latest:
		var e: Array = _latest[id]
		if e[3] not in ["graze", "amble", "rest", "return"]:
			continue
		var d := Vector2(e[0] - bot.my_pos.x, e[1] - bot.my_pos.z).length()
		if d < best_d:
			best_d = d
			best = id
	if best < 0 or best_d > STALK_MAX_START:
		return
	_target = best
	_stalk = Stalk.GO
	_stalk_since = bot.elapsed
	_closest = INF
	stalks += 1
	bot.set_meta("wildlife_stalking", true)


func _steer() -> void:
	if not _latest.has(_target):
		bot.move = Vector2.ZERO
		if bot.elapsed - _stalk_since > STALK_TIMEOUT:
			skipped += 1
			_end_stalk(true)
		return
	var e: Array = _latest[_target]
	var off := Vector2(e[0] - bot.my_pos.x, e[1] - bot.my_pos.z)
	_closest = minf(_closest, off.length())
	if off.length() > 0.5:
		bot.move = off.normalized()
		bot.yaw = atan2(bot.move.x, bot.move.y)
	if bot.elapsed - _stalk_since > STALK_TIMEOUT:
		if _closest <= Wildlife.BOLT_RADIUS - BOLT_SLACK:
			fail("rushed grazer %d to %.1f m and it never bolted" % [_target, _closest])
		else:
			skipped += 1 # never got close: water or a slope in the way
		_end_stalk(true)


## Called on every s2c_wildlife while stalking: did the target bolt, did its herd follow?
func _watch_stalk() -> void:
	if not _stalker or _target < 0 or not _latest.has(_target):
		return
	if _stalk == Stalk.GO and _latest[_target][3] == "flee":
		bolts += 1
		_bolted_at = bot.elapsed
		if not _mate_near(_target):
			herd_alone += 1
			_end_stalk(true)
			return
		_stalk = Stalk.HERD
	if _stalk == Stalk.HERD:
		var herd := int(Wildlife.spawns()[_target].herd)
		for id in _latest:
			if id != _target and _latest[id][3] == "flee" and int(Wildlife.spawns()[id].herd) == herd:
				herd_bolts += 1
				_end_stalk(true)
				return


## True when a herd-mate of `id` stood clearly within Wildlife.HERD_RADIUS of it in the
## latest s2c_wildlife (or is already running), so the server must send it running too.
func _mate_near(id: int) -> bool:
	var herd := int(Wildlife.spawns()[id].herd)
	var at := Vector2(_latest[id][0], _latest[id][1])
	for o in _latest:
		if o == id or int(Wildlife.spawns()[o].herd) != herd:
			continue
		if _latest[o][3] == "flee" or at.distance_to(Vector2(_latest[o][0], _latest[o][1])) <= Wildlife.HERD_RADIUS - HERD_SLACK:
			return true
	return false


func _end_stalk(done: bool) -> void:
	_stalk = Stalk.DONE if done else Stalk.WAIT
	_target = -1
	bot.move = Vector2.ZERO
	bot.set_meta("wildlife_stalking", false)


func on_finish() -> void:
	if _logins > 0:
		_login_elapsed_total += bot.elapsed - _login_at
	stat("sends", sends)
	stat("empties", empties)
	stat("most_in_view", max_seen)
	if _stalker:
		stat("stalks", stalks)
		stat("bolts", bolts)
		stat("herd_bolts", herd_bolts)
		stat("herd_alone", herd_alone)
		stat("stalks_skipped", skipped)
	if _login_elapsed_total > 10.0 and sends / _login_elapsed_total > MAX_RATE:
		fail("%.1f s2c_wildlife a second, the server sends 5" % (sends / _login_elapsed_total))

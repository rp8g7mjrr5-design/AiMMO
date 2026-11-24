extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): protocol v7, health and stamina on the wire and the first swing.
##
## Every login:
##   1. the server sends s2c_vitals right after login, and it must be a full bar;
##   2. a couple of seconds in (not while stalking a grazer), c2s_attack("heavy"): the answer
##      is s2c_swing for us (bare hands) or a refusal we can wait out ("gathering", "busy"),
##      then we try again; the swing's stamina must show at once in s2c_vitals;
##   3. a quarter second into that heavy swing, c2s_attack("light") must be refused "busy"
##      (or, on a very slow link, simply be the next swing);
##   4. the heavy blow must land: s2c_swing_hits for us (near spawn usually a whiff: []).
## Swings never cut a gather short (the server refuses them instead), so the gather
## behaviours running on the same bot are not disturbed.

const START_AFTER := 2.0
const ANSWER_TIMEOUT := 3.0
const RETRY_AFTER := 1.5
const MAX_TRIES := 12
const BUSY_PROBE_AFTER := 0.25
const NEEDED := 9.0 ## seconds of one login the whole check needs

enum Step { WAIT, SWING, SWUNG, PROBED, LANDED }

var _step := Step.WAIT
var _next_at := 0.0
var _sent_at := -1.0
var _tries := 0
var _swing_at := 0.0
var _login_at := -1.0
var _longest := 0.0
var _vitals_at := -INF ## bot.elapsed of the last s2c_vitals
var _last_vitals: Array = []
var swings := 0
var landed := 0
var busy := 0
var refusals := {}
var vitals_at_login := 0


func setup(net: Node) -> void:
	net.vitals_changed.connect(_on_vitals)
	net.swing_begun.connect(_on_swing)
	net.swing_landed.connect(_on_landed)
	net.attack_refused.connect(_on_refused)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_note_stretch()
	_login_at = bot.elapsed
	_step = Step.SWING
	_tries = 0
	_sent_at = -1.0
	_next_at = bot.elapsed + START_AFTER + bot.rng.randf_range(0.0, 1.5)


func _note_stretch() -> void:
	if _login_at >= 0.0:
		_longest = maxf(_longest, bot.elapsed - _login_at)


func on_play(_delta: float) -> void:
	match _step:
		Step.SWING:
			if _sent_at >= 0.0:
				if bot.elapsed - _sent_at > ANSWER_TIMEOUT:
					fail("c2s_attack(heavy) got no answer in %.0f s" % ANSWER_TIMEOUT)
					_step = Step.WAIT
				return
			if bot.elapsed < _next_at:
				return
			if bot.get_meta("wildlife_stalking", false):
				_next_at = bot.elapsed + 1.0
				return
			if _tries >= MAX_TRIES:
				stat("never_swung", true) # always mid-gather: not a failure of the swing
				_step = Step.WAIT
				return
			_tries += 1
			_sent_at = bot.elapsed
			bot.send_play("c2s_attack", ["heavy", bot.yaw])
		Step.SWUNG:
			if bot.elapsed - _swing_at >= BUSY_PROBE_AFTER:
				_step = Step.PROBED
				bot.send_play("c2s_attack", ["light", bot.yaw])
		Step.PROBED:
			if bot.elapsed - _swing_at > Weapons.swing_seconds(Weapons.FISTS, "heavy") + ANSWER_TIMEOUT:
				fail("the heavy swing never landed (no s2c_swing_hits)")
				_step = Step.WAIT


func _on_vitals(hp: int, max_hp: int, stamina: int, max_stamina: int) -> void:
	var fresh := _login_at < 0.0 or _vitals_at < _login_at - 0.5
	_vitals_at = bot.elapsed
	_last_vitals = [hp, max_hp, stamina, max_stamina]
	if max_hp <= 0 or max_stamina <= 0 or hp < 0 or hp > max_hp or stamina < 0 or stamina > max_stamina:
		fail("odd vitals %s" % [_last_vitals])
	if fresh and bot.elapsed - maxf(_login_at, 0.0) < ANSWER_TIMEOUT:
		vitals_at_login += 1
		if _last_vitals != [100, 100, 100, 100]:
			fail("the bar after login wasn't full: %s" % [_last_vitals])


func _on_swing(peer: int, weapon: String, kind: String, seconds: float) -> void:
	if peer != bot.my_id:
		return
	if _step == Step.SWING and kind == "heavy":
		swings += 1
		_sent_at = -1.0
		_swing_at = bot.elapsed
		_step = Step.SWUNG
		if weapon != Weapons.FISTS:
			fail("swung %s with an empty-handed character" % weapon)
		if absf(seconds - Weapons.swing_seconds(Weapons.FISTS, "heavy")) > 0.001:
			fail("odd swing time %.2f s" % seconds)
		var want := roundi(100.0 - Weapons.stamina_cost(Weapons.FISTS, "heavy"))
		# Our own bar answer comes in the same tick as the swing, just before it.
		if _last_vitals.size() == 4 and int(_last_vitals[2]) != want and bot.elapsed - _vitals_at < 0.5:
			fail("stamina after a heavy swing from full is %d, not %d" % [_last_vitals[2], want])
	elif _step == Step.PROBED and kind == "light":
		swings += 1 # a slow link: the probe came after the heavy swing ended, which is fine


func _on_landed(peer: int, kind: String, ids: Array) -> void:
	if peer != bot.my_id:
		return
	if kind == "heavy" and _step in [Step.SWUNG, Step.PROBED]:
		landed += 1
		_step = Step.LANDED
		var lands := Weapons.hit_at(Weapons.FISTS, "heavy")
		if bot.elapsed - _swing_at < lands - 0.15:
			fail("the blow landed %.2f s into a %.2f s windup" % [bot.elapsed - _swing_at, lands])
	for id in ids:
		if Wildlife.get_by_id({"creatures": Wildlife.spawns()}, int(id)).is_empty():
			fail("struck an unknown grazer %s" % id)


func _on_refused(kind: String, reason: String) -> void:
	refusals[reason] = int(refusals.get(reason, 0)) + 1
	if _step == Step.SWING and kind == "heavy":
		_sent_at = -1.0
		if reason in ["gathering", "busy"]:
			_next_at = bot.elapsed + RETRY_AFTER
		else:
			fail("heavy swing from a fresh login refused: %s" % reason)
			_step = Step.WAIT
	elif kind == "light":
		if reason == "busy":
			busy += 1
		elif reason != "gathering":
			fail("light swing mid-heavy refused %s, not busy" % reason)


func on_finish() -> void:
	_note_stretch()
	stat("swings", swings)
	stat("landed", landed)
	stat("busy", busy)
	stat("refusals", refusals)
	stat("vitals_at_login", vitals_at_login)
	if vitals_at_login == 0 and _login_at >= 0.0:
		fail("no s2c_vitals right after any login")
	if _longest >= NEEDED and landed == 0 and not stats.has("never_swung"):
		fail("no heavy swing landed in any login (swings %d, refusals %s)" % [swings, refusals])

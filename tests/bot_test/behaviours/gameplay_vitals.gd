extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): health on the server (Vitals, Milestone 2 build-ahead), driven by
## the hidden /hurt and /vitals dev commands until creatures fight.
##
## Once per bot, some seconds after a login (a logout part-way starts it over next login,
## because every login is full health):
##   1. /hurt 30: the answer must say health 70/100 and in combat;
##   2. /vitals right after: still in combat, no health back yet;
##   3. after the fight is over (Vitals.COMBAT_SECONDS) and a few seconds of regen, /vitals
##      must say full health, out of combat;
##   4. only while we aren't gathering or stalking: /hurt 1000 must knock us down
##      (Vitals.KNOCKED_DOWN_TEXT), and our next snapshots must put us back near spawn.
## Sets the bot meta "knocked_down_at" when the knock-down goes out, so gameplay_gather_v3 and
## gameplay_wildlife forgive the teleport.

const START_AFTER := 10.0 ## seconds after the login (in a full-length run)
const START_AFTER_MIN := 3.0 ## short runs (the image test's 40 s) start sooner
const SLACK := 6.0 ## answers, the queue and the trip home
const ANSWER_TIMEOUT := 4.0
const MAX_TRIES := 3
const QUEUED := 30.0 ## _sent_at sits this far ahead while our line waits in the bot's queue
const REGEN_WAIT := 5.0 ## past the end of the fight; 10 %/s brings 70 back to 100 in 3 s
const HOME_WITHIN := 4.0 ## metres from spawn after the knock-down
const HOME_TIMEOUT := 3.0

enum Step { WAIT, HURT, READ, HEAL, DOWN, HOME, DONE }

var _step := Step.WAIT
var _next_at := 0.0
var _sent_at := -1.0 ## when the open command went out (-1: none open; in the future: queued)
var _sends := 0 ## counts _send calls, so only the latest send's callback starts the clock
var _tries := 0
var _hurt_at := 0.0
var _down_at := 0.0
var _gathering := false
var hurts := 0
var heals := 0
var knockdowns := 0
var _login_at := -1.0 ## bot.elapsed at the current login, -1 before the first
var _longest := 0.0 ## longest stretch of play in one login, seconds


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	net.gather_begun.connect(func(peer: int, _node: int, _s: float):
		if peer == bot.my_id:
			_gathering = true)
	net.gather_ended.connect(func(peer: int, _node: int, _r: String):
		if peer == bot.my_id:
			_gathering = false)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_note_stretch()
	_login_at = bot.elapsed
	_gathering = false
	_sent_at = -1.0
	_tries = 0
	if _step != Step.DONE:
		_step = Step.HURT
		_next_at = bot.elapsed + _start_after() + bot.rng.randf_range(0.0, 2.0)


## 10 s into a login in the full 3-minute run (as before), sooner in a short one so the whole
## check still fits in a login of the image test's 40 s run.
func _start_after() -> float:
	return clampf(float(bot.duration) * 0.06, START_AFTER_MIN, START_AFTER)


## Seconds one login needs to finish the whole check.
func _needed() -> float:
	return _start_after() + 2.0 + Vitals.COMBAT_SECONDS + REGEN_WAIT + 1.0 + HOME_TIMEOUT + SLACK


func _note_stretch() -> void:
	if _login_at >= 0.0:
		_longest = maxf(_longest, bot.elapsed - _login_at)


func on_play(_delta: float) -> void:
	if _step == Step.WAIT or _step == Step.DONE:
		return
	if _step == Step.HOME:
		if bot.elapsed - _down_at > HOME_TIMEOUT:
			fail("knocked down but still %.1f m from spawn after %.0f s" % [_from_spawn(), HOME_TIMEOUT])
			_step = Step.DONE
		return
	if _sent_at >= 0.0:
		if bot.elapsed - _sent_at < ANSWER_TIMEOUT:
			return
		if _tries >= MAX_TRIES:
			fail("no answer to the %s step after %d tries" % [Step.keys()[_step], _tries])
			_step = Step.DONE
			return
		_sent_at = -1.0 # resend below
	if bot.elapsed < _next_at:
		return
	match _step:
		Step.HURT:
			_send("/hurt 30")
		Step.READ, Step.HEAL:
			_send("/vitals")
		Step.DOWN:
			if _gathering or bot.get_meta("wildlife_stalking", false):
				_next_at = bot.elapsed + 1.0
				return
			_send("/hurt 1000", func(): bot.set_meta("knocked_down_at", bot.elapsed))


func _send(line: String, on_sent: Callable = Callable()) -> void:
	_tries += 1
	_sends += 1
	var mine := _sends
	_sent_at = bot.elapsed + QUEUED # the clock starts when it actually goes out
	bot.send_command(line, func():
		if mine != _sends:
			return # a later send replaced this one: its going out says nothing about ours
		_sent_at = bot.elapsed
		if on_sent.is_valid():
			on_sent.call())


## True while our latest command sits in the bot's queue and hasn't gone to the server yet.
func _queued() -> bool:
	return _sent_at > bot.elapsed


func _answered(next: Step, wait: float) -> void:
	_step = next
	_tries = 0
	_sent_at = -1.0
	_next_at = bot.elapsed + wait


func _on_system(text: String) -> void:
	if _sent_at < 0.0:
		return
	if text == ChatCommands.TOO_FAST:
		if _queued():
			# Not ours: our line hasn't gone out yet, so this is another behaviour's line the
			# server dropped. Resending here put two /vitals (or two /hurt 30) in the queue,
			# and the spare answer failed the next step (CI, PR #175, 2026-11-24).
			return
		_tries = maxi(0, _tries - 1)
		_sent_at = -1.0
		_next_at = bot.elapsed + 0.6
		return
	match _step:
		Step.HURT:
			if text.begins_with("You take 30 damage."):
				if not text.contains("Health 70/100") or not text.contains("in combat"):
					fail("after /hurt 30 from full: %s" % text)
				hurts += 1
				_hurt_at = bot.elapsed
				_answered(Step.READ, 0.0)
		Step.READ:
			if text.begins_with("Health "):
				if not text.contains("Health 70/100") or not text.ends_with(", in combat."):
					fail("a second after the hit: %s" % text)
				_answered(Step.HEAL, maxf(_hurt_at + Vitals.COMBAT_SECONDS + REGEN_WAIT - bot.elapsed, 0.0))
		Step.HEAL:
			if text.begins_with("Health "):
				if not text.begins_with("Health 100/100") or not text.ends_with("out of combat."):
					fail("health didn't come back after the fight: %s" % text)
				heals += 1
				_answered(Step.DOWN, 1.0)
		Step.DOWN:
			if text == Vitals.KNOCKED_DOWN_TEXT:
				knockdowns += 1
				_down_at = bot.elapsed
				_answered(Step.HOME, 0.0)
			elif text.begins_with("You take "):
				fail("/hurt 1000 didn't knock us down: %s" % text)
				_step = Step.DONE


func on_snapshot(_tick: int, _entries: Array) -> void:
	if _step == Step.HOME and bot.have_pos and _from_spawn() <= HOME_WITHIN:
		_step = Step.DONE


func _from_spawn() -> float:
	return Vector2(bot.my_pos.x - GameConfig.SPAWN_POINT.x, bot.my_pos.z - GameConfig.SPAWN_POINT.z).length()


func on_finish() -> void:
	_note_stretch()
	stat("hurts", hurts)
	stat("heals", heals)
	stat("knockdowns", knockdowns)
	if _step == Step.DONE and knockdowns >= 1:
		return
	if _longest < _needed():
		# No login was long enough for the whole check (the image test's short run, cut by
		# its reconnect): what did run was checked step by step above.
		stat("vitals_cut_short", true)
		return
	fail("health check didn't finish (step %s; hurts %d, heals %d, knockdowns %d)" % [Step.keys()[_step], hurts, heals, knockdowns])

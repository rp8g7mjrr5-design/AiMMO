extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the Gloam walker. The bot raises one with the hidden /gloam dev
## command, feels it through its health bar, and since protocol v10 sees it on the wire:
## s2c_gloam (the walkers in view, with the grab's windup) and s2c_gloam_hits (our blows).
##
## One bot per run (the one named *_3, in long runs only), once, after the reconnect, when
## gameplay_vitals and gameplay_first_swing are finished with this login and between two of
## gameplay_gather_v3's gathers, borrows itself (bot meta "wildlife_stalking", which the
## gather, swing and vitals behaviours already respect), stands still and:
##   1. /gloam: a walker bound to us rises 7 m in front ("A Zombai rises ...");
##   2. waits for it: it shambles up and grabs, and s2c_vitals drops by exactly one grab
##      (Gloam.grab_damage) within GRAB_WITHIN seconds;
##   3. fights back with bare-handed haymakers, c2s_attack("heavy"), facing it, and asks
##      /gloam status every few swings until the answer is "Your walker N is down."
##      within MAX_SWINGS haymakers.
## On the wire (v10): our walker shows in s2c_gloam while it stands, its arms-up "grab" state
## with time left shows before the grab lands, every haymaker that connects comes back in
## s2c_gloam_hits naming it, the one that puts it down lists it as downed, and it drops out
## of s2c_gloam after that.
## A login too short to finish is counted, not failed.

const MY_SUFFIX := "_3"
const LONG_RUN := 120.0
const LOGIN_SETTLE := 8.0
const QUIET_BEFORE := 35.0 ## no fight this close to the end of the run
const ANSWER_TIMEOUT := 4.0
const GRAB_WITHIN := 12.0 ## 7 m at 1.8 m/s by day, plus the windup, plus slack
const SWINGS_PER_CHECK := 4
const MAX_SWINGS := 10
const SWING_TIMEOUT := 3.0

enum Step { WAIT, SUMMON, GRAB, FIGHT, STATUS, DONE }

var _me := false
var _step := Step.WAIT
var _next_at := 0.0
var _sent_at := -1.0
var _walker := -1
var _face := 0.0 ## the yaw we hold from /gloam to the end of the fight
var _hp := -1
var _summoned_at := 0.0
var _swinging := false
var _swing_sent_at := 0.0
var _since_check := 0
var summoned := 0
var grabs := 0
var swings := 0
var downs := 0
var skipped := 0
var refusals := {}
var wire_seen := 0 ## s2c_gloam sends naming our walker
var windup_seen := false ## our walker's "grab" state with time left, before the grab landed
var wire_hits := 0 ## s2c_gloam_hits naming our walker for our blows
var wire_downed := false
var _down_at := -1.0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	net.vitals_changed.connect(_on_vitals)
	net.swing_landed.connect(_on_landed)
	net.attack_refused.connect(_on_refused)
	net.gloam_changed.connect(_on_gloam)
	net.gloam_struck.connect(_on_gloam_struck)


func on_login(reconnect: bool, _character: Dictionary) -> void:
	_me = str(bot.bot_name).ends_with(MY_SUFFIX) and float(bot.duration) >= LONG_RUN
	_hp = -1
	if _step != Step.WAIT and _step != Step.DONE:
		skipped += 1 # logged out mid-fight: the walker crumbled with us
		_release(Step.DONE)
	if not reconnect:
		_step = Step.WAIT if _me else Step.DONE
	elif _me and _step == Step.WAIT:
		_step = Step.SUMMON
		_sent_at = -1.0
		_next_at = bot.elapsed + LOGIN_SETTLE


func _behaviour(behaviour_name: String) -> Object:
	for b in bot.behaviours:
		if b.name == behaviour_name:
			return b
	return null


## The other checks on this bot are done with this login, so a walker's grab can't upset them.
func _others_done() -> bool:
	var v = _behaviour("gameplay_vitals")
	if v != null and int(v._step) != int(v.Step.DONE):
		return false
	var f = _behaviour("gameplay_first_swing")
	if f != null and int(f._step) != int(f.Step.LANDED) and int(f._step) != int(f.Step.WAIT):
		return false
	var g = _behaviour("gameplay_gather_v3")
	return g == null or g.ready_to_lend()


func _release(next: Step) -> void:
	_step = next
	_sent_at = -1.0
	_swinging = false
	bot.set_meta("wildlife_stalking", false)


func on_play(_delta: float) -> void:
	if _step == Step.WAIT or _step == Step.DONE:
		return
	if _step != Step.SUMMON or _sent_at >= 0.0:
		# Stand and keep facing the way we faced at /gloam: the walker rose on that line and
		# comes straight down it (the bot's wander turns yaw every few seconds otherwise).
		bot.move = Vector2.ZERO
		bot.yaw = _face
	match _step:
		Step.SUMMON:
			if bot.elapsed < _next_at:
				return
			if _sent_at < 0.0:
				if float(bot.duration) - bot.elapsed < QUIET_BEFORE:
					skipped += 1
					_release(Step.DONE)
					return
				if bot.get_meta("wildlife_stalking", false) or not _others_done() or _hp < 0:
					_next_at = bot.elapsed + 0.5
					return
				bot.set_meta("wildlife_stalking", true)
				bot.move = Vector2.ZERO
				_face = bot.yaw
				_send("/gloam")
			elif bot.elapsed - _sent_at > ANSWER_TIMEOUT:
				fail("no answer to /gloam")
				_release(Step.DONE)
		Step.GRAB:
			if bot.elapsed - _summoned_at > GRAB_WITHIN:
				fail("walker %d never grabbed us in %.0f s" % [_walker, GRAB_WITHIN])
				_release(Step.DONE)
		Step.FIGHT:
			if _swinging:
				if bot.elapsed - _swing_sent_at > SWING_TIMEOUT:
					fail("a haymaker at walker %d never landed" % _walker)
					_release(Step.DONE)
				return
			if bot.elapsed < _next_at:
				return
			if _since_check >= SWINGS_PER_CHECK or swings >= MAX_SWINGS:
				_since_check = 0
				_step = Step.STATUS
				_send("/gloam status")
				return
			_swinging = true
			_swing_sent_at = bot.elapsed
			bot.send_play("c2s_attack", ["heavy", _face])
		Step.STATUS:
			if _sent_at >= 0.0 and _sent_at <= bot.elapsed and bot.elapsed - _sent_at > ANSWER_TIMEOUT:
				fail("no answer to /gloam status")
				_release(Step.DONE)


func _send(line: String) -> void:
	_sent_at = bot.elapsed + 30.0 # until it actually goes out of the queue
	bot.send_command(line, func(): _sent_at = bot.elapsed)


func _on_system(text: String) -> void:
	if _sent_at < 0.0 or _sent_at > bot.elapsed:
		return
	if _step == Step.SUMMON:
		if not text.begins_with("A Zombai rises"):
			return
		var at := text.rfind("walker ")
		_walker = int(text.substr(at + 7).trim_suffix(")."))
		summoned += 1
		_summoned_at = bot.elapsed
		_sent_at = -1.0
		_step = Step.GRAB
	elif _step == Step.STATUS:
		if text == "Your walker %d is down." % _walker:
			downs += 1
			_down_at = bot.elapsed
			_release(Step.DONE)
		elif text.begins_with("Zombai %d:" % _walker):
			_sent_at = -1.0
			if swings >= MAX_SWINGS:
				fail("walker %d still standing after %d haymakers: %s" % [_walker, swings, text])
				_release(Step.DONE)
				return
			_step = Step.FIGHT
			_next_at = bot.elapsed + 0.2
		elif text.begins_with("No walker"):
			fail("walker %d vanished without going down" % _walker)
			_release(Step.DONE)


func _on_vitals(hp: int, _max_hp: int, _stamina: int, _max_stamina: int) -> void:
	if _step == Step.GRAB and _hp >= 0 and hp < _hp:
		var drop := _hp - hp
		if absf(float(drop) - Gloam.grab_damage("walker")) > 1.0:
			fail("a grab took %d health, not %d" % [drop, roundi(Gloam.grab_damage("walker"))])
		grabs += 1
		_step = Step.FIGHT
		_next_at = bot.elapsed + 0.2
	elif _step == Step.FIGHT or _step == Step.STATUS:
		if hp < _hp:
			grabs += 1
	_hp = hp


func _on_landed(peer: int, kind: String, _ids: Array) -> void:
	if peer != bot.my_id or not _swinging or kind != "heavy":
		return
	_swinging = false
	swings += 1
	_since_check += 1
	# Recovery: the swing is done Weapons.swing_seconds after the press.
	_next_at = _swing_sent_at + Weapons.swing_seconds(Weapons.FISTS, "heavy") + 0.1


func _on_refused(kind: String, reason: String) -> void:
	if not _swinging:
		return
	refusals[reason] = int(refusals.get(reason, 0)) + 1
	_swinging = false
	if reason in ["busy", "tired", "winded", "gathering"]:
		_next_at = bot.elapsed + 0.5
	else:
		fail("%s swing at walker %d refused %s" % [kind, _walker, reason])
		_release(Step.DONE)


func _on_gloam(entries: PackedFloat32Array) -> void:
	if _walker < 0:
		return
	for w in Gloam.from_wire(entries):
		if int(w.id) != _walker:
			continue
		wire_seen += 1
		if _down_at >= 0.0 and bot.elapsed - _down_at > 1.0:
			fail("walker %d is still in s2c_gloam after it went down" % _walker)
			_down_at = -1.0
		if str(w.state) == "grab" and float(w.windup_left) > 0.0 and _step == Step.GRAB:
			windup_seen = true


func _on_gloam_struck(peer: int, _kind: String, ids: Array, downed: Array) -> void:
	if peer != bot.my_id or _walker < 0 or not (_walker in ids):
		return
	wire_hits += 1
	if _walker in downed:
		wire_downed = true


func on_finish() -> void:
	stat("summoned", summoned)
	stat("grabs", grabs)
	stat("swings", swings)
	stat("downs", downs)
	stat("skipped", skipped)
	stat("refusals", refusals)
	stat("wire_seen", wire_seen)
	stat("windup_seen", windup_seen)
	stat("wire_hits", wire_hits)
	stat("wire_downed", wire_downed)
	if summoned > 0 and wire_seen == 0:
		fail("walker %d never showed in s2c_gloam" % _walker)
	if grabs > 0 and summoned > 0 and not windup_seen:
		fail("walker %d grabbed us without its windup ever showing in s2c_gloam" % _walker)
	if downs > 0 and (wire_hits == 0 or not wire_downed):
		fail("walker %d went down but s2c_gloam_hits said hits=%d downed=%s" % [_walker, wire_hits, wire_downed])
	if _me and summoned > 0 and downs == 0 and skipped == 0:
		fail("summoned a walker and never put it down")

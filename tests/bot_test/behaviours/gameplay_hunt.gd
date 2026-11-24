extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the first hunt (2026-11-24). Grazers have health, a wounded one
## limps off, a downed one gives its hunter hide and raw meat and leaves the hills.
##
## One bot per run (the one named *_2, in long runs only), once, after the reconnect and
## between two of gameplay_gather_v3's gathers (ready_to_lend), borrows itself (bot meta
## "wildlife_stalking", which the gather, swing and vitals behaviours already respect) and:
##   1. /lure (hidden dev command): the nearest grazer lies down drowsy in front of us
##      ("Grazer N lies down in front of you.");
##   2. a bare-handed haymaker, c2s_attack("heavy"): s2c_swing_hits must name grazer N, and
##      it is not down yet (no hide in the pack);
##   3. /lure again: the wounded grazer N comes back first;
##   4. a jab, c2s_attack("light"): it lands on N and brings it down, so within a second the
##      pack (s2c_inventory) holds one more hide and two more raw meat, and no s2c_wildlife
##      after that lists N.
## A real night stalk takes a minute and depends on the clock, so the bot test lures instead;
## the stalk itself is unit tested (test_gameplay_hunt). A login too short to finish is
## counted, not failed.

const HUNTER_SUFFIX := "_2"
const LONG_RUN := 120.0
const LOGIN_SETTLE := 6.0
const QUIET_BEFORE := 25.0 ## no hunt this close to the end of the run
const ANSWER_TIMEOUT := 4.0
const RETRY_AFTER := 1.2
const MAX_TRIES := 6
const LOOT_WITHIN := 2.0
const GONE_CHECK := 1.5 ## seconds of s2c_wildlife after the down that must not list it

enum Step { WAIT, LURE, HEAVY, LURE2, LIGHT, LOOT, GONE, DONE }

var _hunter := false
var _step := Step.WAIT
var _login_at := 0.0
var _sent_at := -1.0
var _tries := 0
var _next_at := 0.0
var _target := -1
var _pack: Dictionary = {}
var _pack_before: Dictionary = {}
var _down_at := -1.0
var hunts := 0
var downs := 0
var skipped := 0
var refusals := {}


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	net.swing_landed.connect(_on_landed)
	net.attack_refused.connect(_on_refused)
	net.inventory_changed.connect(_on_pack)
	net.wildlife_changed.connect(_on_wildlife)


func on_login(reconnect: bool, character: Dictionary) -> void:
	_login_at = bot.elapsed
	_pack = Inventory.normalize(character.get("inventory", {}))
	_hunter = str(bot.bot_name).ends_with(HUNTER_SUFFIX) and float(bot.duration) >= LONG_RUN
	if _step != Step.WAIT and _step != Step.DONE:
		skipped += 1 # logged out mid-hunt
		_release(Step.WAIT)
	if not reconnect:
		_step = Step.DONE if not _hunter else Step.WAIT
	elif _hunter and _step == Step.WAIT:
		_step = Step.LURE
		_tries = 0
		_sent_at = -1.0
		_next_at = bot.elapsed + LOGIN_SETTLE


func _gather_v3() -> Object:
	for b in bot.behaviours:
		if b.name == "gameplay_gather_v3":
			return b
	return null


func _release(next: Step) -> void:
	_step = next
	_sent_at = -1.0
	bot.set_meta("wildlife_stalking", false)


func on_play(_delta: float) -> void:
	if _step == Step.WAIT or _step == Step.DONE:
		return
	if bot.get_meta("wildlife_stalking", false):
		bot.move = Vector2.ZERO # hold still while we hunt
	match _step:
		Step.LURE:
			if bot.elapsed < _next_at:
				return
			if float(bot.duration) - bot.elapsed < QUIET_BEFORE:
				skipped += 1
				_release(Step.DONE)
				return
			if _sent_at < 0.0:
				var g = _gather_v3()
				if bot.get_meta("wildlife_stalking", false) or (g != null and not g.ready_to_lend()):
					_next_at = bot.elapsed + 0.5
					return
				bot.set_meta("wildlife_stalking", true)
				bot.move = Vector2.ZERO
				_pack_before = _pack.duplicate()
				hunts += 1
				_send_lure()
			elif bot.elapsed - _sent_at > ANSWER_TIMEOUT:
				_retry_or_fail("no answer to /lure")
		Step.LURE2:
			if _sent_at < 0.0 and bot.elapsed >= _next_at:
				_send_lure()
			elif _sent_at >= 0.0 and bot.elapsed - _sent_at > ANSWER_TIMEOUT:
				_retry_or_fail("no answer to the second /lure")
		Step.HEAVY, Step.LIGHT:
			var kind := "heavy" if _step == Step.HEAVY else "light"
			if _sent_at < 0.0 and bot.elapsed >= _next_at:
				_tries += 1
				_sent_at = bot.elapsed
				bot.send_play("c2s_attack", [kind, bot.yaw])
			elif _sent_at >= 0.0 and bot.elapsed - _sent_at > ANSWER_TIMEOUT:
				_retry_or_fail("the %s swing at grazer %d never landed" % [kind, _target])
		Step.LOOT:
			if _got_loot():
				downs += 1
				_step = Step.GONE
			elif bot.elapsed - _down_at > LOOT_WITHIN:
				fail("brought grazer %d down but the pack never got its hide and meat (before %s, now %s)" % [_target, _pack_before, _pack])
				_release(Step.DONE)
		Step.GONE:
			if bot.elapsed - _down_at > LOOT_WITHIN + GONE_CHECK:
				_release(Step.DONE)


func _send_lure() -> void:
	_tries += 1
	_sent_at = bot.elapsed + 30.0 # until it actually goes out of the queue
	bot.send_command("/lure", func(): _sent_at = bot.elapsed)


func _retry_or_fail(why: String) -> void:
	if _tries >= MAX_TRIES:
		fail("%s after %d tries" % [why, _tries])
		_release(Step.DONE)
		return
	_sent_at = -1.0
	_next_at = bot.elapsed + RETRY_AFTER


func _on_system(text: String) -> void:
	if _step != Step.LURE and _step != Step.LURE2:
		return
	if _sent_at < 0.0 or _sent_at > bot.elapsed:
		return
	if text == ChatCommands.TOO_FAST:
		_retry_or_fail("/lure was too fast")
		return
	if text.begins_with("No grazer"):
		skipped += 1
		_release(Step.DONE)
		return
	if not text.begins_with("Grazer "):
		return
	var id := int(text.split(" ")[1])
	if _step == Step.LURE:
		_target = id
		_step = Step.HEAVY
	else:
		if id != _target:
			fail("the second /lure brought grazer %d, not the wounded %d" % [id, _target])
			_target = id
		_step = Step.LIGHT
	_tries = 0
	_sent_at = -1.0
	_next_at = bot.elapsed + 0.3 # let our facing settle on the server


func _on_landed(peer: int, kind: String, ids: Array) -> void:
	if peer != bot.my_id or _sent_at < 0.0:
		return
	if _step == Step.HEAVY and kind == "heavy":
		if not ids.has(_target):
			_retry_or_fail("the haymaker missed the lured grazer %d (hit %s)" % [_target, ids])
			if _step == Step.HEAVY:
				_step = Step.LURE2 # lure it back in front of us and go on with the jab
				_tries = 0
			return
		if Inventory.count(_pack, "hide") != Inventory.count(_pack_before, "hide"):
			fail("one haymaker already gave hide: a grazer has %.0f hp" % Wildlife.max_hp("grazer"))
		_step = Step.LURE2
		_tries = 0
		_sent_at = -1.0
		_next_at = bot.elapsed + GameConfig.CHAT_COOLDOWN + 0.2
	elif _step == Step.LIGHT and kind == "light":
		if not ids.has(_target):
			_retry_or_fail("the jab missed the lured grazer %d (hit %s)" % [_target, ids])
			if _step == Step.LIGHT:
				_step = Step.LURE2
				_tries = 0
				_next_at = bot.elapsed + GameConfig.CHAT_COOLDOWN + 0.2
			return
		_down_at = bot.elapsed
		_sent_at = -1.0
		_step = Step.LOOT


func _on_refused(kind: String, reason: String) -> void:
	if _sent_at < 0.0 or not (_step in [Step.HEAVY, Step.LIGHT]):
		return
	refusals[reason] = int(refusals.get(reason, 0)) + 1
	if reason in ["busy", "gathering", "tired", "winded"]:
		_retry_or_fail("%s swing refused %s" % [kind, reason])
	else:
		fail("%s swing at a lured grazer refused %s" % [kind, reason])
		_release(Step.DONE)


func _on_pack(items: Dictionary) -> void:
	_pack = Inventory.normalize(items)


func _got_loot() -> bool:
	for d in Wildlife.drops("grazer"):
		var item := str(d[0])
		var want := Inventory.count(_pack_before, item) + int(d[1])
		if Inventory.count(_pack, item) < mini(want, Inventory.MAX_STACK):
			return false
	return true


func _on_wildlife(entries: PackedFloat32Array) -> void:
	if _step != Step.GONE or entries.size() % Wildlife.WIRE_STRIDE != 0:
		return
	if bot.elapsed - _down_at < 0.3:
		return # one send may have left before the blow landed
	for i in range(0, entries.size(), Wildlife.WIRE_STRIDE):
		if int(entries[i]) == _target:
			fail("downed grazer %d still sent in s2c_wildlife %.1f s later" % [_target, bot.elapsed - _down_at])
			_release(Step.DONE)
			return


func on_finish() -> void:
	stat("hunts", hunts)
	stat("downs", downs)
	stat("skipped", skipped)
	stat("refusals", refusals)
	if _hunter and hunts > 0 and downs == 0 and skipped == 0:
		fail("hunted %d times and never brought a grazer down" % hunts)

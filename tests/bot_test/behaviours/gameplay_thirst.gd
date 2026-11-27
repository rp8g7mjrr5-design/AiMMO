extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): thirst, the second survival need (step 3 of the owner's survival
## plan; Needs, protocol v14 s2c_needs).
##
## Every bot: after each login, s2c_needs must arrive with a "thirst" between 0 and 100.
## One bot (the one named *_2), once, FIRST_DELAY seconds into its first login:
##   1. /vitals thirst 37: the answer ends "Thirst 37/100 (low)." and s2c_needs follows with 37;
##   2. /place drink: the bot test world (Ashgrove) has no fresh water and bots carry no
##      waterskin, so the answer is the "nothing to drink" line (a drink also counts);
## and after its reconnect, its thirst came back from the save (within a few points of 37,
## less what it lost while playing). A login too short to finish is counted, not failed.

const MY_SUFFIX := "_2"
const FIRST_DELAY := 30.0
const QUIET_BEFORE := 15.0
const ANSWER_TIMEOUT := 4.0
const SET_TO := 37

enum Step { WAIT, SET, EAT, DONE }

var _me := false
var _step := Step.WAIT
var _next_at := 0.0
var _sent_at := -1.0
var _logins := 0
var _needs_this_login := false
var _thirst := -1
var _set_seen := false
var _after_set := -1
var set_ok := 0
var drink_answers := 0
var reloaded := 0
var skipped := 0
var needs_msgs := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	net.needs_changed.connect(_on_needs)


func on_login(reconnect: bool, _character: Dictionary) -> void:
	if _logins > 0 and not _needs_this_login:
		fail("login %d never got s2c_needs" % _logins)
	_logins += 1
	_needs_this_login = false
	if _step != Step.WAIT and _step != Step.DONE:
		skipped += 1
		_step = Step.DONE
	if not reconnect:
		_me = str(bot.bot_name).ends_with(MY_SUFFIX)
		_step = Step.SET if _me else Step.DONE
		_next_at = bot.elapsed + FIRST_DELAY


func _on_needs(needs: Dictionary) -> void:
	needs_msgs += 1
	if not needs.has("thirst"):
		fail("s2c_needs without thirst: %s" % str(needs))
		return
	var h := int(needs.thirst)
	if h < 0 or h > 100:
		fail("thirst out of range: %d" % h)
	if not _needs_this_login:
		_needs_this_login = true
		if _me and _logins >= 2 and _after_set >= 0:
			# Back from the save: what we had at logout (no more than SET_TO + a drink).
			if h > SET_TO + 50 or h < SET_TO - 10:
				fail("thirst after the reconnect was %d, expected about %d" % [h, _after_set])
			else:
				reloaded += 1
	_thirst = h
	if _me and _set_seen:
		_after_set = h


func on_play(_delta: float) -> void:
	if _step == Step.WAIT or _step == Step.DONE or bot.elapsed < _next_at:
		return
	if _sent_at >= 0.0:
		if _sent_at <= bot.elapsed and bot.elapsed - _sent_at > ANSWER_TIMEOUT:
			fail("no answer to the %s line" % Step.keys()[_step].to_lower())
			_step = Step.DONE
		return
	if float(bot.duration) - bot.elapsed < QUIET_BEFORE:
		skipped += 1
		_step = Step.DONE
		return
	match _step:
		Step.SET:
			_send("/vitals thirst %d" % SET_TO)
		Step.EAT:
			_send("/place drink")


func _send(line: String) -> void:
	_sent_at = bot.elapsed + 30.0 # until it actually goes out of the queue
	bot.send_command(line, func(): _sent_at = bot.elapsed)


func _on_system(text: String) -> void:
	if _sent_at < 0.0 or _sent_at > bot.elapsed:
		return
	match _step:
		Step.SET:
			if not text.begins_with("Health "):
				return
			if not text.ends_with("Thirst %d/100 (low)." % SET_TO):
				fail("/vitals thirst %d answered: %s" % [SET_TO, text])
			else:
				set_ok += 1
			_set_seen = true
			_after_set = SET_TO
			_sent_at = -1.0
			_step = Step.EAT
		Step.EAT:
			if text == Needs.text("no_water") or text.begins_with("You drink"):
				drink_answers += 1
				_sent_at = -1.0
				_step = Step.DONE


func on_finish() -> void:
	stat("needs_msgs", needs_msgs)
	stat("set_ok", set_ok)
	stat("drink_answers", drink_answers)
	stat("reloaded", reloaded)
	stat("skipped", skipped)
	if needs_msgs == 0:
		fail("never got s2c_needs")
	if _me and set_ok > 0 and drink_answers == 0 and skipped == 0:
		fail("set thirst but never got an answer to drinking")

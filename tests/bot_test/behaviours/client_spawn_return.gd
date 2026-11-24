extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the Esc menu's "Return to Spawn Meadow" button (SpawnReturn). Network-only (art
## bible section 7: no window is built). gameplay_roster_v5 sends the asks (twice per bot);
## this behaviour keeps the button's state beside it, as the client's settings menu does, and
## checks that the button tells the truth about the server:
## - when the server took us home, the button would have been pressed while it showed ready;
## - when the server refused for its cooldown, the button had been counting down (we never
##   offer a press the server will turn away), and after any answer it counts down exactly
##   the server's wait;
## - every ask is answered before the button would give the press back (ANSWER_TIMEOUT_MS).
## The ask is noted the moment it goes out (bot.play_sent), not on our next on_play: the
## server can answer before then (it did on localhost, qa 2026-11-24), and an answer handled
## before the ask was noted left the button "asking" forever and failed the bot 5 s later.

const SpawnReturnScript := preload("res://client/spawn_return.gd")

var _ret = SpawnReturnScript.new()
var _ready_when_asked := true
var _answers := 0
var _countdowns := 0


func _now_ms() -> int:
	return int(round(float(bot.elapsed) * 1000.0))


func setup(net: Node) -> void:
	net.unstuck_result.connect(_on_unstuck)
	bot.play_sent.connect(_on_play_sent)


func _on_play_sent(method: String, _args: Array) -> void:
	if method != "c2s_unstuck":
		return
	# The button as the player would see it at the moment of the press.
	_ready_when_asked = _ret.enabled(_now_ms())
	_ret.asked_at_ms = _now_ms()
	_ret.asks += 1


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_ret.reset() # the client's settings_menu.set_in_game(false) on logout does the same


func on_play(_delta: float) -> void:
	if _ret.asked_at_ms >= 0 and not _ret.asking(_now_ms()):
		fail("no answer within %d ms: the button gave the press back" % SpawnReturnScript.ANSWER_TIMEOUT_MS)


func _on_unstuck(ok: bool, text: String, wait_seconds: float) -> void:
	_answers += 1
	var now := _now_ms()
	if ok and not _ready_when_asked:
		fail("the server took us home while our button showed %s" % _ret.label(now))
	var cooling := text.begins_with("You can return to Spawn Meadow again in")
	# A reconnect starts the button fresh while the server keeps its cooldown; only a refusal
	# inside our own session's countdown would mean the button lied.
	if cooling and _ret.homes > 0 and _ready_when_asked:
		fail("our button was ready but the server said: %s" % text)
	_ret.answered(ok, wait_seconds, now)
	if _ret.asking(now):
		fail("button still waiting after the answer")
	var want := maxi(0, ceili(wait_seconds)) if is_finite(wait_seconds) else 0
	if _ret.seconds_left(now) != want:
		fail("button counts %d s, server said %.2f s" % [_ret.seconds_left(now), wait_seconds])
	if want > 0:
		_countdowns += 1
		if _ret.label(now) != "%s (%d s)" % [SpawnReturnScript.LABEL, want]:
			fail("button reads %s for a %d s wait" % [_ret.label(now), want])
	elif _ret.label(now) != SpawnReturnScript.LABEL:
		fail("button reads %s with no wait" % _ret.label(now))


func on_finish() -> void:
	stat("answers", _answers)
	stat("homes", _ret.homes)
	stat("countdowns", _countdowns)
	if _ret.asks > 0 and _answers == 0:
		fail("asked %d times, never answered" % _ret.asks)

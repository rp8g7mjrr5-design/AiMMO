extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the pack.
##
## Every login must hand the client a character with an `inventory` Dictionary (bots start
## with an empty pack, since nothing gives items yet). A while after each login the bot
## types /bag and expects its pack described back to it alone. Commands share a 0.5 s
## cooldown with the other command behaviours; a dropped /bag is answered with
## ChatCommands.TOO_FAST and resent soon, and an unanswered one is retried.

const FIRST_DELAY := 7.0 ## after gameplay_chat_commands' /time and /who
const RETRY_AFTER := 3.0
const MAX_TRIES := 5
const MAX_TOO_FAST := 12

var _tries := 0
var _too_fast := 0
var _next_at := 0.0
var _waiting := false
var _done := true
var _logins := 0
var answers := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_logins += 1
	if typeof(character.get("inventory")) != TYPE_DICTIONARY:
		fail("login character has no inventory Dictionary: %s" % character.keys())
	_tries = 0
	_too_fast = 0
	_waiting = false
	_done = false
	_next_at = bot.elapsed + FIRST_DELAY + bot.rng.randf_range(0.0, 1.5)


func on_play(_delta: float) -> void:
	if _done or bot.elapsed < _next_at:
		return
	if _tries >= MAX_TRIES:
		fail("no reply to /bag after %d tries" % _tries)
		_done = true
		return
	_tries += 1
	_waiting = true
	_next_at = bot.elapsed + RETRY_AFTER
	bot.net.c2s_chat.rpc_id(1, "/bag")


func _on_system(text: String) -> void:
	if _waiting and text == ChatCommands.TOO_FAST and _too_fast < MAX_TOO_FAST:
		# The command cooldown dropped a line (maybe ours): resend soon, try refunded.
		_too_fast += 1
		_tries = maxi(0, _tries - 1)
		_next_at = minf(_next_at, bot.elapsed + 0.6 + bot.rng.randf_range(0.0, 0.3))
		return
	if not _waiting or not text.begins_with("Your pack"):
		return
	answers += 1
	_waiting = false
	_done = true


func on_finish() -> void:
	stat("bag_answers", answers)
	if answers < 1:
		fail("/bag answered %d times over %d logins" % [answers, _logins])

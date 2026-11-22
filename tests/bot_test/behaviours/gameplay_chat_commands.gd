extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): chat slash commands.
##
## A few seconds after each login, every bot types /time and then /who. The server must
## answer the sender alone with a system message, and must never broadcast a command line
## as ordinary chat. Chat has a 0.5 s cooldown shared with bot.gd's own chatter, so a
## command that gets no answer is retried a few times before it counts as a failure.

const COMMANDS := ["/time", "/who"]
const FIRST_DELAY := 2.0
const RETRY_AFTER := 3.0
const MAX_TRIES := 4

var _step := 0 ## index into COMMANDS for the current login
var _tries := 0
var _next_at := 0.0
var _waiting := false
var _logins := 0
var answered := {"/time": 0, "/who": 0}


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	net.chat_message.connect(_on_chat)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_logins += 1
	_step = 0
	_tries = 0
	_waiting = false
	_next_at = bot.elapsed + FIRST_DELAY + bot.rng.randf_range(0.0, 1.0)


func on_play(_delta: float) -> void:
	if _step >= COMMANDS.size() or bot.elapsed < _next_at:
		return
	if _waiting and _tries >= MAX_TRIES:
		fail("no reply to %s after %d tries" % [COMMANDS[_step], _tries])
		_step = COMMANDS.size()
		return
	_tries += 1
	_waiting = true
	_next_at = bot.elapsed + RETRY_AFTER
	bot.net.c2s_chat.rpc_id(1, COMMANDS[_step])


func _on_system(text: String) -> void:
	if not _waiting or _step >= COMMANDS.size():
		return
	var cmd: String = COMMANDS[_step]
	var ok := false
	if cmd == "/time":
		ok = text.begins_with("It is Day ") and text.contains(" comes in ")
	elif cmd == "/who":
		ok = text.contains(" online: ") and text.contains(bot.bot_name)
	if not ok:
		return # a join/leave notice, not our answer
	answered[cmd] += 1
	_step += 1
	_tries = 0
	_waiting = false
	_next_at = bot.elapsed + 1.0


func _on_chat(from_name: String, text: String) -> void:
	if text.begins_with("/"):
		fail("command from %s was broadcast as chat: %s" % [from_name, text])


func on_finish() -> void:
	stat("time_answers", answered["/time"])
	stat("who_answers", answered["/who"])
	if answered["/time"] < 1 or answered["/who"] < 1:
		fail("commands answered %s over %d logins" % [answered, _logins])

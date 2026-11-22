extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the pack.
##
## Every login must hand the client a character with an `inventory` Dictionary (bots start
## with an empty pack, since nothing gives items yet). A while after each login the bot
## types /bag and expects its pack described back to it alone. Chat shares a 0.5 s cooldown
## with bot.gd's chatter and the other command behaviour, so an unanswered /bag is retried.

const FIRST_DELAY := 7.0 ## after gameplay_chat_commands' /time and /who
const RETRY_AFTER := 3.0
const MAX_TRIES := 5

var _tries := 0
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
	if not _waiting or not text.begins_with("Your pack"):
		return
	answers += 1
	_waiting = false
	_done = true


func on_finish() -> void:
	stat("bag_answers", answers)
	if answers < 1:
		fail("/bag answered %d times over %d logins" % [answers, _logins])

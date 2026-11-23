extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): Toolcraft 3 "Bench sense", the ember lantern.
##
## Once per login the bot asks for an ember lantern with the hidden dev command "/craft
## lantern". A bot below Toolcraft 3 must be refused on the level in the words players see
## ("An ember lantern needs Toolcraft 3. You're Toolcraft N." with N below 3). A bot that
## somehow got there gets a real answer about the lantern instead (made, missing parts, or
## too far from the bench), which also counts. The real craft and its 108 XP are proven by
## tests/unit/test_gameplay_bench_sense.gd.

const FIRST_DELAY := 12.0 ## after gameplay_crafting's and gameplay_toolcraft's lines
const RETRY_AFTER := 2.0
const MAX_TRIES := 4
const PREFIX := "An ember lantern needs Toolcraft 3. You're Toolcraft "

var _waiting := false
var _next_at := INF
var _tries := 0
var answers := 0
var unanswered_logins := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _waiting and _tries > 0:
		unanswered_logins += 1
	_waiting = true
	_tries = 0
	_next_at = bot.elapsed + FIRST_DELAY + bot.rng.randf_range(0.0, 2.0)


func on_play(_delta: float) -> void:
	if not _waiting or bot.elapsed < _next_at:
		return
	if _tries >= MAX_TRIES:
		_waiting = false
		unanswered_logins += 1
		return
	_tries += 1
	_next_at = bot.elapsed + RETRY_AFTER
	bot.send_command("/craft lantern")


func _on_system(text: String) -> void:
	if not text.contains("ember lantern"):
		return
	if text.begins_with(PREFIX):
		var level := text.substr(PREFIX.length()).trim_suffix(".").to_int()
		if level < 1 or level >= 3:
			fail("refused at Toolcraft %d: %s" % [level, text])
	elif text.contains("Unknown") or text.contains("don't know"):
		fail("the server doesn't know the lantern: %s" % text)
	if _waiting:
		answers += 1
		_waiting = false


func on_finish() -> void:
	stat("answers", answers)
	stat("unanswered_logins", unanswered_logins)
	if answers < 1:
		fail("never got an answer to /craft lantern")

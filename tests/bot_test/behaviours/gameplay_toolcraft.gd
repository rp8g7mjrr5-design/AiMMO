extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): Toolcraft unlocks (Milestone 1 part 4).
##
## Once per login the bot asks for an ember axe with the hidden dev command "/craft ember
## axe". No bot reaches Toolcraft 5 in a 3-minute run, so the server must refuse on the
## level, wherever the bot stands, in the words players see: "An ember axe needs Toolcraft
## 5. You're Toolcraft N." with N below 5. The real craft at Toolcraft 5 (stone axe used up,
## ember axe in the pack, faster gathers) is proven by tests/unit/test_gameplay_toolcraft.gd.

const FIRST_DELAY := 8.0 ## after gameplay_crafting's own /craft lines
const RETRY_AFTER := 2.0 ## an unanswered line is sent again
const MAX_TRIES := 4
const PREFIX := "An ember axe needs Toolcraft 5. You're Toolcraft "

var _waiting := false
var _next_at := INF
var _tries := 0
var refusals := 0
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
	bot.send_command("/craft ember axe")


func _on_system(text: String) -> void:
	if not text.begins_with("An ember axe"):
		return
	if not text.begins_with(PREFIX):
		fail("ember axe refused for the wrong reason: %s" % text)
		return
	var level := text.substr(PREFIX.length()).trim_suffix(".").to_int()
	if level < 1 or level >= 5:
		fail("refused at Toolcraft %d: %s" % [level, text])
	if _waiting:
		refusals += 1
		_waiting = false


func on_finish() -> void:
	stat("refusals", refusals)
	stat("unanswered_logins", unanswered_logins)
	if refusals < 1:
		fail("never got the Toolcraft 5 refusal for /craft ember axe")

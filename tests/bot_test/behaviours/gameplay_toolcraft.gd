extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the ember axe is gated by things, never a level (owner, 2026-11-26).
##
## Once per login the bot asks for an ember axe with the hidden dev command "/craft ember
## axe". No bot carries heartwood and veinstone in a 3-minute run, so the server must refuse,
## wherever the bot stands, in the words players see: the bench ("An ember axe needs the
## workbench. ...") or the materials ("You need ... more to make an ember axe."), and never a level or a skill.
## The real craft (stone axe used up, ember axe in the pack, faster gathers) is proven by
## tests/unit/test_gameplay_toolcraft.gd.

const FIRST_DELAY := 8.0 ## after gameplay_crafting's own /craft lines
const RETRY_AFTER := 2.0 ## an unanswered line is sent again
const MAX_TRIES := 4
const PREFIX := "An ember axe needs "
const NEVER := ["Toolcraft", "level", "Level", "XP"]

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
	var bench := text.begins_with(PREFIX + "the workbench")
	var materials := text.begins_with("You need ") and text.ends_with(" to make an ember axe.")
	if not bench and not materials:
		if text.begins_with("An ember axe"):
			fail("ember axe refused for the wrong reason: %s" % text)
		return
	for word in NEVER:
		if text.contains(word):
			fail("ember axe refused on a level: %s" % text)
			return
	if _waiting:
		refusals += 1
		_waiting = false


func on_finish() -> void:
	stat("refusals", refusals)
	stat("unanswered_logins", unanswered_logins)
	if refusals < 1:
		fail("never got a bench or materials refusal for /craft ember axe")

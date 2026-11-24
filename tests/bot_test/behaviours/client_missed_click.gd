extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the "nothing there" tick on a real server. Every time the server begins one of
## this bot's own gathers, the bot checks what the client's click path would do around it:
## a click that starts it is not a miss, a click while it runs is not a miss, and a click
## straight at the sky from the same spot (which never takes the nearest-node fallback)
## does nothing and so ticks. It sends nothing and plays nothing, so it costs no more than a
## player looking around.

const PromptScript := preload("res://client/gather_prompt.gd")

var checked := 0
var sky_misses := 0


func _on_begun(peer: int, node_id: int, _seconds: float) -> void:
	if peer != int(bot.my_id):
		return
	var eye: Vector3 = bot.my_pos + Vector3(0.0, 2.2, 0.0)
	var t: Dictionary = PromptScript.target(bot.my_pos, WorldClock.now_seconds(), eye, Vector3.UP)
	checked += 1
	var op: Dictionary = PromptScript.decide(false, false, false, t, false, false, false, true, true)
	if not op.is_empty():
		fail("a click at the sky near node %d would send %s" % [node_id, str(op)])
	if PromptScript.missed_click(true, op, false, false):
		sky_misses += 1
	else:
		fail("a click at the sky near node %d did nothing but would not tick" % node_id)
	if PromptScript.missed_click(true, {}, true, false):
		fail("a click while gathering node %d would tick" % node_id)
	if PromptScript.missed_click(true, {"op": "start", "node": node_id}, false, false):
		fail("a click that starts node %d would tick" % node_id)


func setup(net: Node) -> void:
	net.gather_begun.connect(_on_begun)


func on_finish() -> void:
	stat("checked", checked)
	stat("sky_misses", sky_misses)

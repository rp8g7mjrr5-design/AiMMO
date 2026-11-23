extends "res://tests/bot_test/bot_behaviour.gd"
## Client: left-click gathering on a real server. Every time the server begins one of this
## bot's own gathers (gameplay_gather_v3 presses E for it), the bot puts the camera where a
## player would, looking at that node, and checks the client's click path would have asked
## for that very node: the prompt aims at it, and a click (or holding the button) starts it.
## It sends nothing itself, so it costs no more than a player looking around.

const PromptScript := preload("res://client/gather_prompt.gd")

var checked := 0
var skipped := 0
var own_gathers := 0


func _on_begun(peer: int, node_id: int, _seconds: float) -> void:
	if peer != int(bot.my_id):
		return
	own_gathers += 1
	var n := ResourceNodes.get_by_id(node_id)
	if n.is_empty():
		fail("server began a gather on unknown node %d" % node_id)
		return
	var eye: Vector3 = bot.my_pos + Vector3(0.0, 2.2, 0.0)
	var look: Vector3 = (n.pos + Vector3.UP) - eye
	if look.length() < 0.01:
		skipped += 1
		return
	var t: Dictionary = PromptScript.target(bot.my_pos, WorldClock.now_seconds(), eye, look.normalized())
	# Nodes the client wouldn't offer from here (a tier-2 node, a seep at the clock's edge,
	# positions a step apart) are the E path's business; count them and move on.
	if t.is_empty() or not bool(t.can) or int(t.id) != node_id:
		skipped += 1
		return
	checked += 1
	if not bool(t.aimed):
		fail("looking straight at node %d but the prompt says it isn't aimed" % node_id)
	var op: Dictionary = PromptScript.decide(false, false, false, t, false, false, false, true, true)
	if op != {"op": "start", "node": node_id}:
		fail("a click at node %d would send %s" % [node_id, str(op)])
	if PromptScript.decide(false, false, false, t, true, false, false, true, true) != {}:
		fail("a click while gathering node %d would stop it" % node_id)


func setup(net: Node) -> void:
	net.gather_begun.connect(_on_begun)


func on_finish() -> void:
	stat("own_gathers", own_gathers)
	stat("checked", checked)
	stat("skipped", skipped)
	if own_gathers >= 4 and checked == 0:
		fail("%d gathers began but none could be checked for a click" % own_gathers)

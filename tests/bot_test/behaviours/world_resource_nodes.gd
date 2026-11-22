extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): wherever a player stands, the gatherable things nearby are drawn.
##
## After each login, and every few seconds while walking, the bot finds the resource node
## nearest to where the server says it is, lays out that node's prop (NodeProps.parts,
## renderer-free) in both looks, and checks the prop is there, on the ground at the node,
## and that the depleted look is different. Once per bot it lays out every node.

const CHECK_EVERY := 5.0

var checked := 0
var kinds := {}
var since := 0.0


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if checked == 0:
		var lay := NodeProps.layout(ResourceNodes.all())
		if lay.slots.size() != ResourceNodes.count():
			fail("layout has %d slots for %d nodes" % [lay.slots.size(), ResourceNodes.count()])
	_check_near(bot.my_pos)


func on_play(delta: float) -> void:
	since += delta
	if since >= CHECK_EVERY:
		since = 0.0
		_check_near(bot.my_pos)


func _check_near(pos: Vector3) -> void:
	var n := ResourceNodes.nearest(pos, "", 256.0)
	if n.is_empty():
		fail("no resource node within 256 m of %s" % pos)
		return
	checked += 1
	kinds[n.kind] = true
	var live := NodeProps.parts(n, false)
	var dead := NodeProps.parts(n, true)
	if live.is_empty() or dead.is_empty():
		fail("node %d (%s) has no prop" % [n.id, n.kind])
		return
	if live.size() == dead.size() and live[0].layer == dead[0].layer and live[0].color == dead[0].color:
		fail("node %d (%s) looks the same depleted" % [n.id, n.kind])
	for p in live:
		var o: Vector3 = p.xform.origin
		if Vector2(o.x - n.pos.x, o.z - n.pos.z).length() > 2.0 or o.y < n.pos.y - 0.05:
			fail("node %d (%s) prop is not standing on its spot" % [n.id, n.kind])
			return


func on_finish() -> void:
	stat("nodes_checked", checked)
	stat("kinds_seen", kinds.size())
	if checked == 0:
		fail("never checked a resource node")

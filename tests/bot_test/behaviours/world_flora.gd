extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): biome variety around the bots as they walk.
##
## Each bot builds the flora list (birches, mossy boulders, wildflowers) the client draws,
## checks every spot stands on the ground and off the resource nodes, lays out the parts of
## the nearest few, and every few seconds notes which kinds grow within 40 m of where it is.
## The summary shows how much variety a wandering player actually passes.

var checks := 0
var kinds_seen := {}
var nearest := INF
var _since := 0.0


func setup(_net: Node) -> void:
	var spots := Flora.spots()
	for k in ["birch", "boulder", "flowers"]:
		if Flora.count(k) == 0:
			fail("no %s in the world" % k)
	for s in spots:
		var p: Vector3 = s.pos
		if absf(p.y - Terrain.height(p.x, p.z)) > 0.05:
			fail("%s at %s floats or sinks" % [s.kind, p])
			return
		if not ResourceNodes.near(p, Flora.NODE_CLEARANCE).is_empty():
			fail("%s at %s stands on a resource node" % [s.kind, p])
			return


func on_play(delta: float) -> void:
	_since += delta
	if _since < 3.0:
		return
	_since = 0.0
	checks += 1
	var me: Vector3 = bot.my_pos
	var here := Vector2(me.x, me.z)
	var close: Array = []
	for s in Flora.spots():
		var d := here.distance_to(Vector2(s.pos.x, s.pos.z))
		nearest = minf(nearest, d)
		if d < 40.0:
			kinds_seen[s.kind] = kinds_seen.get(s.kind, 0) + 1
			if close.size() < 3:
				close.append(s)
	for s in close:
		if Flora.parts(s).is_empty():
			fail("%s at %s has no parts" % [s.kind, s.pos])


func on_finish() -> void:
	stat("flora_checks", checks)
	stat("flora_kinds_near", kinds_seen.size())
	stat("nearest_flora_m", snappedf(nearest, 0.1) if is_finite(nearest) else -1.0)
	if checks == 0:
		fail("never looked around for flora")

extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): the Spawn Meadow workbench is drawn where crafting works.
##
## Each bot checks the bench it would draw stands at Crafting.workbench_pos(), on the ground,
## with every part inside its footprint and none under the terrain. While playing it notes
## how close it walks to the bench and how often it is in crafting range, so the summary
## shows bots really pass it (they all arrive a few steps away).

var nearest := INF
var in_range_checks := 0
var checks := 0
var _since := 0.0
var _bench := Vector2.ZERO


func setup(_net: Node) -> void:
	var s := Workbench.spot()
	if not s.pos.is_equal_approx(Crafting.workbench_pos()):
		fail("bench drawn at %s but crafting works at %s" % [s.pos, Crafting.workbench_pos()])
	if absf(s.pos.y - Terrain.height(s.pos.x, s.pos.z)) > 0.05:
		fail("bench at %s floats or sinks" % s.pos)
	var parts := Workbench.parts(s)
	if parts.size() < 10:
		fail("bench has only %d parts" % parts.size())
	for p in parts:
		var o: Vector3 = p.xform.origin
		if o.y < Terrain.height(o.x, o.z) - 0.05:
			fail("bench part %s is under the ground" % p.name)
		if Vector2(o.x - s.pos.x, o.z - s.pos.z).length() > Workbench.FOOTPRINT:
			fail("bench part %s strays from the bench" % p.name)
	if not ResourceNodes.near(s.pos, Workbench.CLEARANCE).is_empty():
		fail("a resource node stands at the bench")
	_bench = Vector2(s.pos.x, s.pos.z)


func on_play(delta: float) -> void:
	_since += delta
	if _since < 1.0:
		return
	_since = 0.0
	var me: Vector3 = bot.my_pos
	checks += 1
	nearest = minf(nearest, Vector2(me.x, me.z).distance_to(_bench))
	if Crafting.near_bench(me):
		in_range_checks += 1


func on_finish() -> void:
	stat("bench_checks", checks)
	stat("bench_in_range_checks", in_range_checks)
	stat("nearest_bench_m", snappedf(nearest, 0.1) if is_finite(nearest) else -1.0)
	if checks == 0:
		fail("never played near the bench")

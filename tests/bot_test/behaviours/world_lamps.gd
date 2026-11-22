extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): the Spawn Meadow lanterns light up by the server's clock.
##
## Each bot checks the lanterns it would see are on the ground around spawn and off the
## resource nodes, then on every s2c_world_time works out how bright the lamps would be and
## checks that agrees with the server's phase (lit at night, out by day). It also notes how
## close it walks to a lantern, so the summary shows bots actually pass them.

var syncs := 0
var lit_syncs := 0
var nearest := INF
var _since := 0.0
var _lamp_spots: Array = []


func setup(net: Node) -> void:
	var lamps := Lamps.positions()
	if lamps.size() != Lamps.COUNT:
		fail("expected %d lanterns, got %d" % [Lamps.COUNT, lamps.size()])
	for l in lamps:
		var p: Vector3 = l.pos
		if absf(p.y - Terrain.height(p.x, p.z)) > 0.05:
			fail("lantern at %s floats or sinks" % p)
		if not ResourceNodes.near(p, Lamps.NODE_CLEARANCE).is_empty():
			fail("lantern at %s stands on a resource node" % p)
		_lamp_spots.append(Vector2(p.x, p.z))
	net.world_time.connect(_on_world_time)


func _on_world_time(world_seconds: float) -> void:
	syncs += 1
	var g := Lamps.night_glow(WorldClock.day_fraction(world_seconds))
	if not is_finite(g) or g < 0.0 or g > 1.0:
		fail("lamp glow %s out of range" % g)
		return
	var phase := WorldClock.phase(world_seconds)
	if phase == "night" and g < 0.9:
		fail("lamps only %.2f lit at night (%s)" % [g, WorldClock.describe(world_seconds)])
	if phase == "day" and g > 0.5 and WorldClock.sun_elevation(world_seconds) > 0.2:
		fail("lamps %.2f lit in broad day (%s)" % [g, WorldClock.describe(world_seconds)])
	if g > 0.5:
		lit_syncs += 1


func on_play(delta: float) -> void:
	_since += delta
	if _since < 1.0:
		return
	_since = 0.0
	var me: Vector3 = bot.my_pos
	for p in _lamp_spots:
		nearest = minf(nearest, Vector2(me.x, me.z).distance_to(p))


func on_finish() -> void:
	stat("lamp_syncs", syncs)
	stat("lamp_lit_syncs", lit_syncs)
	stat("nearest_lamp_m", snappedf(nearest, 0.1) if is_finite(nearest) else -1.0)
	if syncs == 0:
		fail("never got the server's time to light the lamps")

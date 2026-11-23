extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): the workbench lantern lights by the server's clock, and the bench
## glows while a player stands at it.
##
## Each bot builds the bench it would see (no renderer needed) and checks its lantern sits
## on the top. On every s2c_world_time it lights the lantern through Lamps.apply_glow, like
## the client's DayNight does, and checks the light is on at night and out in broad day.
## While playing it turns the bench's highlight on whenever it stands in crafting range and
## off when it walks away, and checks the shell follows, so the summary shows real hand-offs.

var _bench: Node3D
var _world: Node3D
var syncs := 0
var lit_syncs := 0
var highlight_ons := 0
var highlight_offs := 0
var _since := 0.0


func setup(net: Node) -> void:
	_world = Node3D.new()
	_bench = Workbench.build()
	_world.add_child(_bench)
	var s := Workbench.spot()
	var glass := 0
	for p in Workbench.parts(s):
		if p.layer == Workbench.GLASS_LAYER:
			glass += 1
			if p.xform.origin.y < s.pos.y + Workbench.TOP_HEIGHT:
				fail("bench lantern glass is below the bench top")
	if glass != 1:
		fail("bench has %d lantern glasses, expected 1" % glass)
	if _bench.get_node_or_null("Light") == null or _bench.get_node_or_null("Highlight") == null:
		fail("bench is missing its lantern light or highlight shell")
	net.world_time.connect(_on_world_time)


func _on_world_time(world_seconds: float) -> void:
	syncs += 1
	var g := Lamps.night_glow(WorldClock.day_fraction(world_seconds))
	Lamps.apply_glow(_world, g)
	var omni := _bench.get_node("Light") as OmniLight3D
	var phase := WorldClock.phase(world_seconds)
	if phase == "night" and not (omni.visible and omni.light_energy > 0.9 * Workbench.LIGHT_ENERGY):
		fail("bench lantern dark at night (%s)" % WorldClock.describe(world_seconds))
	if phase == "day" and WorldClock.sun_elevation(world_seconds) > 0.2 and omni.visible:
		fail("bench lantern lit in broad day (%s)" % WorldClock.describe(world_seconds))
	if omni.visible:
		lit_syncs += 1


func on_play(delta: float) -> void:
	_since += delta
	if _since < 0.5:
		return
	_since = 0.0
	var at := Crafting.near_bench(bot.my_pos)
	if at != Workbench.highlighted(_bench):
		Workbench.set_highlight(_bench, at)
		if at:
			highlight_ons += 1
		else:
			highlight_offs += 1
	var shell := _bench.get_node("Highlight") as Node3D
	if shell.visible != at:
		fail("bench highlight shows %s while the bot is %s the bench" % [shell.visible, "at" if at else "away from"])


func on_finish() -> void:
	stat("bench_lantern_syncs", syncs)
	stat("bench_lantern_lit_syncs", lit_syncs)
	stat("bench_highlight_ons", highlight_ons)
	stat("bench_highlight_offs", highlight_offs)
	if syncs == 0:
		fail("never got the server's time to light the bench lantern")
	if _world:
		_world.free()
		_world = null

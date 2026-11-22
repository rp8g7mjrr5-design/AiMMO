extends TestCase
## World stream: lanterns ring the Spawn Meadow, and lamps, ember-ash leaves and sap seeps
## glow by night from the shared clock. Uses the pure halves of Lamps (no renderer).


func test_lanterns_ring_the_meadow() -> void:
	var lamps := Lamps.positions()
	check_eq(lamps.size(), Lamps.COUNT, "one entry per lantern")
	for l in lamps:
		var p: Vector3 = l.pos
		var r := Vector2(p.x, p.z).distance_to(Vector2(GameConfig.SPAWN_POINT.x, GameConfig.SPAWN_POINT.z))
		check(r > 7.0 and r < 16.0, "lantern %.1f m from spawn sits around the meadow" % r)
		check_near(p.y, Terrain.height(p.x, p.z), 0.01, "lantern stands on the ground")
		check(ResourceNodes.near(p, Lamps.NODE_CLEARANCE).is_empty(), "lantern is not on a resource node")
	for i in lamps.size():
		for j in range(i + 1, lamps.size()):
			check(lamps[i].pos.distance_to(lamps[j].pos) > 4.0, "lanterns %d and %d are spread out" % [i, j])


func test_positions_are_deterministic() -> void:
	var a := Lamps.positions()
	var b := Lamps.positions()
	for i in a.size():
		check(a[i].pos.is_equal_approx(b[i].pos) and is_equal_approx(a[i].rot, b[i].rot), "lantern %d same every time" % i)


func test_lantern_parts() -> void:
	var lamp: Dictionary = Lamps.positions()[0]
	var by := {}
	for p in Lamps.parts(lamp):
		by[p.layer] = by.get(p.layer, 0) + 1
		var o: Vector3 = p.xform.origin
		check(o.y >= lamp.pos.y - 0.01 and o.y <= lamp.pos.y + Lamps.POST_HEIGHT + 0.1, "part is between ground and post top")
		check(Vector2(o.x - lamp.pos.x, o.z - lamp.pos.z).length() < 0.8, "part stays by its post")
	check_eq(by.get(Lamps.GLASS_LAYER, 0), 1, "one glowing glass")
	check(by.get("LampWood", 0) >= 2, "post and arm")
	check(by.get("LampIron", 0) >= 2, "cap and foot")
	var lp := Lamps.light_position(lamp)
	var glass: Dictionary = Lamps.parts(lamp).filter(func(p): return p.layer == Lamps.GLASS_LAYER)[0]
	check(lp.is_equal_approx(glass.xform.origin), "the light sits inside the glass")
	var lay := Lamps.layout(Lamps.positions())
	check_eq(lay[Lamps.GLASS_LAYER].size(), Lamps.COUNT, "layout has every lantern's glass")


func test_lamps_follow_the_clock() -> void:
	check_near(Lamps.night_glow(0.5), 0.0, 0.001, "dark at noon")
	check_near(Lamps.night_glow(0.0), 1.0, 0.001, "fully lit at midnight")
	check(Lamps.night_glow(0.74) > 0.2, "already lit at sunset, before full dark")
	check(Lamps.night_glow(0.30) < 0.05, "out by mid-morning")
	var prev := -1.0
	for i in 21: # noon to midnight: never dims on the way into night
		var g := Lamps.night_glow(0.5 + i * 0.025)
		check(g >= prev - 0.0001, "glow rises through the evening")
		prev = g
	for f in [0.1, 0.25, 0.6, 0.8]:
		var at_server := Lamps.night_glow(WorldClock.day_fraction(SkyClock.seconds_for_fraction(f)))
		check_near(at_server, Lamps.night_glow(f), 0.0001, "same glow from world seconds")


func test_glow_values() -> void:
	var day := Lamps.glow_values(0.0)
	var night := Lamps.glow_values(1.0)
	check(not day.lights_on and night.lights_on, "lights off by day, on by night")
	check_near(day.ash, 0.0, 0.0001, "no leaf glow by day")
	check(night.ash > 0.0 and night.ash < 0.3, "leaf glow is faint")
	check(night.node_ash > night.ash, "gatherable ash glows a touch more")
	check(night.sap > day.sap, "sap seeps brighten at night")
	check_near(day.sap, 0.9, 0.0001, "daytime sap matches NodeProps")
	check(night.glass > day.glass, "lantern glass lights up")
	check_near(Lamps.glow_values(5.0).light_energy, Lamps.LIGHT_ENERGY, 0.0001, "glow is clamped")
	Lamps.apply_glow(null, 1.0) # a missing world is a no-op, not an error

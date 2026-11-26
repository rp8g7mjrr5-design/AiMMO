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


## Owner playtest 2026-11-24: at night the meadow had a pale, blocky, stair-stepped pool. In
## Forward+ a local light's light() runs over whole light-cluster tiles, so only the sun/moon
## may paint the cool SHADE tint; lanterns only add their own light, faded by ATTENUATION.
func test_only_the_moon_paints_shade() -> void:
	for variant in Emberlight.VARIANTS:
		var src := Emberlight.source(variant)
		var guard := src.find("if (LIGHT_IS_DIRECTIONAL)")
		var shade := src.find("DIFFUSE_LIGHT += vec3(", guard)
		check(guard > 0 and shade > guard, "%s: the SHADE tint is inside the directional-only branch" % variant)
		check(src.count("DIFFUSE_LIGHT += vec3(") == 1, "%s: SHADE is added in one place" % variant)


func test_lantern_pools_fall_off() -> void:
	# Near inverse-square falloff: separate warm pools, not one flat wash across the meadow.
	check(Lamps.LIGHT_ATTENUATION >= 1.8, "lantern light falls off steeply")
	check(Lamps.LIGHT_RANGE <= 10.0, "a lantern's reach stays near its post")
	var lamps := Lamps.build()
	var omni := lamps.get_node("Lights").get_child(0) as OmniLight3D
	check_near(omni.omni_attenuation, Lamps.LIGHT_ATTENUATION, 0.0001, "built lights use it")
	check(not omni.shadow_enabled, "no shadow (draw-call budget)")
	lamps.free()


func test_no_seep_lights_since_the_seeps_went() -> void:
	# The glowing ember-sap seeps became plain scrub (owner direction, 2026-11-26: no magic):
	# the SeepLights holder is still built (Lamps walks it) but holds no light.
	var root := NodeProps.build()
	var world := Node3D.new()
	world.add_child(root)
	check_eq(root.get_node(NodeProps.SEEP_LIGHTS).get_child_count(), 0, "no seep lights")
	var scrub: Array = ResourceNodes.all().filter(func(n): return n.kind == "scrub")
	check(NodeProps.seep_light(root, int(scrub[0].id)) == null, "scrub throws no light")
	Lamps.apply_glow(world, 1.0) # and a night repaint is fine without them
	world.free()


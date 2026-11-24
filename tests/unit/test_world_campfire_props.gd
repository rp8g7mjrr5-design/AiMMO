extends TestCase
## World stream: the placed campfire's look (CampfireProps), for gameplay's Campfires.
## Pure parts and states headless, plus the pooled node driven through sync/animate the way
## the client will drive it from s2c_campfires.


func _fire(id: int = 1) -> Dictionary:
	var sp := WorldGen.spawn_point() + Vector3(6.0, 0.0, -4.0)
	sp.y = Terrain.height(sp.x, sp.z)
	return {"id": id, "pos": sp}


func _count(ps: Array, kind: String) -> int:
	return ps.filter(func(p): return p.kind == kind).size()


func test_states_follow_the_time_left() -> void:
	var burn := Campfires.burn_seconds()
	check_eq(CampfireProps.state(burn), "lit", "a fresh fire is lit")
	check_eq(CampfireProps.state(burn * 0.5), "lit", "half burned is still lit")
	check_eq(CampfireProps.state(burn * 0.1), "low", "the last stretch is low")
	check_eq(CampfireProps.state(0.0), "ash", "out is ash")
	check(CampfireProps.light_energy("lit", 1.0) > CampfireProps.light_energy("lit", 0.0), "brighter at night")
	check(CampfireProps.light_energy("low", 1.0) < CampfireProps.light_energy("lit", 1.0), "a low fire dims")
	check_eq(CampfireProps.light_energy("ash", 1.0), 0.0, "ash gives no light")


func test_a_lit_fire_has_ring_logs_coals_and_flames() -> void:
	var f := _fire()
	var ps := CampfireProps.parts(f, "lit")
	check_eq(_count(ps, "stone"), CampfireProps.RING_STONES, "a ring of stones")
	check_eq(_count(ps, "log"), CampfireProps.LOG_COUNT, "logs leaned in")
	check_eq(_count(ps, "flame"), CampfireProps.TONGUES.size(), "flame tongues")
	check_eq(_count(ps, "coal"), CampfireProps.COALS, "coals")
	for l in CampfireProps.LAYERS:
		var n := ps.filter(func(p): return p.layer == l).size()
		check(n <= int(CampfireProps.PER_FIRE[l]), "%s fits its pool slot (%d)" % [l, n])
	for p in ps:
		var o: Vector3 = p.xform.origin
		var flat := Vector2(o.x - f.pos.x, o.z - f.pos.z).length()
		check(flat < 0.8, "%s stays inside the fire's footprint (%.2f m)" % [p.kind, flat])
		check(o.y > Terrain.height(o.x, o.z) - 0.1, "%s is not under the ground" % p.kind)
		check(o.y < f.pos.y + 0.8, "%s is not floating (a cooking fire, not a bonfire)" % p.kind)
		check(absf(p.xform.basis.determinant()) > 0.0000001, "%s has a real size" % p.kind)
		if p.kind == "flame":
			check_eq(p.color.a, 0.0, "a flame is all glow")
		elif p.kind == "stone" or p.kind == "bed":
			check_eq(p.color.a, 1.0, "stone never glows")
			check(p.color.s < 0.45, "stone stays a muted natural (art bible: under 0.45 saturation)")
	# Logs lean in: each log's top is nearer the middle than its foot.
	for p in ps:
		if p.kind != "log":
			continue
		var up: Vector3 = p.xform.basis.y.normalized()
		var to_mid := Vector3(f.pos.x - p.xform.origin.x, 0.0, f.pos.z - p.xform.origin.z)
		check(up.dot(to_mid) > 0.0, "log leans in towards the fire")
	check(CampfireProps.TONGUES[0][0] < 0.8, "the tallest flame is about knee height")


func test_low_and_ash_look_different() -> void:
	var f := _fire(4)
	var lit := CampfireProps.parts(f, "lit")
	var low := CampfireProps.parts(f, "low")
	var ash := CampfireProps.parts(f, "ash")
	var tallest := func(ps: Array) -> float:
		var h := 0.0
		for p in ps:
			if p.kind == "flame":
				h = maxf(h, p.h)
		return h
	check(float(tallest.call(low)) < float(tallest.call(lit)) * 0.6, "a low fire's flames are much shorter")
	check_eq(_count(ash, "flame"), 0, "no flame once it's out")
	check_eq(_count(ash, "log"), 0, "no standing logs once it's out")
	check(_count(ash, "stub") > 0, "charred stubs once it's out")
	check_eq(_count(ash, "stone"), CampfireProps.RING_STONES, "the stone ring stays")
	for p in ash:
		if p.kind == "stub":
			check_eq(p.color.a, 1.0, "charred stubs are cold")


func test_deterministic_per_fire() -> void:
	var a := CampfireProps.parts(_fire(7))
	var b := CampfireProps.parts(_fire(7))
	check_eq(a.size(), b.size(), "same parts")
	for i in a.size():
		check(a[i].xform.is_equal_approx(b[i].xform) and a[i].color.is_equal_approx(b[i].color), "part %d same every time" % i)
	var c := CampfireProps.parts(_fire(8))
	check(not a[0].xform.is_equal_approx(c[0].xform), "two fires are not stamped from one mould")


func test_from_wire_reads_gameplays_payload() -> void:
	var st := Campfires.new_state()
	var sp := WorldGen.spawn_point()
	st.fires[3] = {"id": 3, "pos": Vector3(sp.x + 5, 1.0, sp.z), "owner": "a", "lit_at": 0.0, "out_at": 100.0}
	st.fires[9] = {"id": 9, "pos": Vector3(sp.x - 5, 2.0, sp.z), "owner": "b", "lit_at": 0.0, "out_at": 40.0}
	var fires := CampfireProps.from_wire(Campfires.to_wire(st, 10.0))
	check_eq(fires.size(), 2, "two fires")
	check_eq(int(fires[0].id), 3, "first id")
	check_near(float(fires[0].left), 90.0, 0.01, "seconds left")
	check_near(float(fires[1].pos.y), 2.0, 0.001, "position")
	check_eq(CampfireProps.from_wire(PackedFloat32Array([1, 2, 3])).size(), 0, "a ragged payload gives no half fire")


func test_flame_grows_from_its_foot() -> void:
	var base := Vector3(1, 2, 3)
	for lean in [0.0, 0.1]:
		var x := CampfireProps.flame_xform(base, 0.5, 0.2, 0.7, lean)
		var foot := x * Vector3(0, -0.5, 0) # the cone mesh's foot, local y -0.5
		check(foot.is_equal_approx(base), "the flame's foot stays on the coals (lean %.1f)" % lean)


func test_pooled_node_syncs_animates_and_keeps_ash() -> void:
	var node := CampfireProps.build()
	check(not node.visible, "hidden with no fires")
	check_eq(CampfireProps.shown(node), 0, "shows nothing")
	for l in CampfireProps.LAYERS:
		var mmi := node.get_node(l) as MultiMeshInstance3D
		check_eq(mmi.multimesh.visible_instance_count, 0, "%s draws nothing" % l)
		check(Emberlight.is_emberlight(mmi.material_override), "%s is on a shared Emberlight material" % l)
	var burn := Campfires.burn_seconds()
	var a := _fire(1)
	var b := _fire(2)
	b.pos += Vector3(4, 0, 0)
	var t := 1000.0
	CampfireProps.sync(node, [{"id": 1, "pos": a.pos, "left": burn}, {"id": 2, "pos": b.pos, "left": burn * 0.1}], a.pos, t)
	check(node.visible, "shown once fires burn")
	check_eq(CampfireProps.shown(node), 2, "two fires")
	var flames := (node.get_node("FireFlames") as MultiMeshInstance3D).multimesh
	check_eq(flames.visible_instance_count, CampfireProps.COALS * 2 + CampfireProps.TONGUES.size() * 2, "coals and flames for both")
	CampfireProps.apply_glow(node, 1.0)
	var lights := node.get_node("Lights").get_children()
	check((lights[0] as OmniLight3D).visible and (lights[1] as OmniLight3D).visible, "both burning fires carry a light")
	check(not (lights[2] as OmniLight3D).visible, "a spare light stays off")
	check((lights[0] as OmniLight3D).position.distance_to(a.pos) < 1.0, "the nearest fire gets the first light")
	check(float(lights[1].get_meta("steady_energy")) < float(lights[0].get_meta("steady_energy")), "the low fire's light is dimmer")
	# Flicker: animate() writes flicker_xform for every tongue it drew (the headless renderer
	# doesn't keep MultiMesh transforms, so check the maths and the bookkeeping).
	var tongues: Array = node.get_meta("flames")
	check_eq(tongues.size(), CampfireProps.TONGUES.size() * 2, "every tongue is animated")
	check_eq(int(tongues[0].index), CampfireProps.COALS, "the first tongue follows fire 1's coals")
	var f0: Dictionary = tongues[0]
	var hs := []
	for s in [0.0, 0.2, 0.4, 12.3]:
		var x := CampfireProps.flicker_xform(f0, s)
		hs.append(x.basis.y.length())
		check((x * Vector3(0, -0.5, 0)).is_equal_approx(f0.base), "a flickering flame keeps its foot on the coals")
	check(absf(hs[0] - hs[1]) > 0.005 or absf(hs[1] - hs[2]) > 0.005, "flames flicker (%s)" % [hs])
	for h in hs:
		check(absf(h / float(f0.h) - 1.0) <= CampfireProps.FLAME_FLICKER + 0.001, "a flicker, not a flare")
	CampfireProps.animate(node, 12.3)
	# The low fire goes out on the server (drops from the list): it stays as ash.
	CampfireProps.sync(node, [{"id": 1, "pos": a.pos, "left": burn - 5.0}], a.pos, t + 5.0)
	check_eq(CampfireProps.shown(node), 2, "the burned-out fire stays as ash")
	check_eq(flames.visible_instance_count, CampfireProps.COALS * 2 + CampfireProps.TONGUES.size(), "no flame on the ash")
	check(not (lights[1] as OmniLight3D).visible, "the ash gives no light")
	# A fire that vanishes while still burning (a restart) just goes.
	CampfireProps.sync(node, [], a.pos, t + 6.0)
	check_eq(CampfireProps.shown(node), 1, "only the ash is left")
	# The ash fades after its time.
	CampfireProps.sync(node, [], a.pos, t + 6.0 + CampfireProps.ASH_SECONDS + 1.0)
	check_eq(CampfireProps.shown(node), 0, "the ash is gone")
	check(not node.visible, "hidden again")
	node.free()


func test_pool_caps_at_the_worlds_fire_limit() -> void:
	var node := CampfireProps.build()
	var fires: Array = []
	var sp := WorldGen.spawn_point()
	for i in Campfires.MAX_FIRES + 5:
		fires.append({"id": i + 1, "pos": Vector3(sp.x + i * 3.0, 0.0, sp.z), "left": 100.0 + i})
	CampfireProps.sync(node, fires, sp, 50.0)
	check_eq(CampfireProps.shown(node), Campfires.MAX_FIRES, "never more fires than the pool")
	var lit := 0
	for o in node.get_node("Lights").get_children():
		if (o as OmniLight3D).visible:
			lit += 1
	check(lit <= CampfireProps.LIGHT_POOL, "never more fire lights than the pool")
	node.free()


func test_world_builder_and_lamps_drive_it() -> void:
	# Lamps drives the fires from the shared clock; a world without the node is safe.
	var world := Node3D.new()
	var node := CampfireProps.build()
	world.add_child(node)
	CampfireProps.sync(node, [{"id": 1, "pos": _fire().pos, "left": Campfires.burn_seconds()}], _fire().pos, 10.0)
	Lamps.apply_glow(world, 1.0)
	check_near(float(node.get_meta("glow")), 1.0, 0.001, "apply_glow reaches the fires")
	Lamps.flicker_lights(world, 3.0)
	Lamps.apply_glow(null, 1.0)
	CampfireProps.animate(null, 1.0)
	CampfireProps.sync(null, [])
	world.free()
	check(FileAccess.get_file_as_string("res://procgen/world_builder.gd").contains("CampfireProps.build()"), "WorldBuilder adds the fires")

extends TestCase
## The grazers on screen (protocol v6): HerdView's smoothing and moments, GrazerFigures' poses,
## the dust clods and the snort.


func _wire(list: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in list:
		out.append(float(e[0]))
		out.append(float(e[1]))
		out.append(float(e[2]))
		out.append(float(e[3]))
		out.append(float(Wildlife.STATES.find(str(e[4]))))
	return out


func test_first_sighting_is_placed_not_slid_in() -> void:
	var h := HerdView.new()
	var ev := h.feed(_wire([[2, 50.0, 10.0, 0.5, "graze"]]), 1.0)
	check_eq(ev.size(), 1)
	check_eq(str(ev[0].event), "appear")
	var p := h.position(2, 1.0)
	check_near(p.x, 50.0, 0.001, "placed at once")
	check_near(p.y, Terrain.height(50.0, 10.0), 0.001, "stands on the ground")
	check_near(h.facing(2, 1.0), 0.5, 0.001)
	check_eq(h.state(2), "graze")


func test_updates_blend_from_where_it_is_drawn() -> void:
	var h := HerdView.new()
	h.feed(_wire([[1, 0.0, 0.0, 0.0, "amble"]]), 0.0)
	h.feed(_wire([[1, 1.0, 0.0, 0.0, "amble"]]), 1.0)
	check_near(h.position(1, 1.0).x, 0.0, 0.001, "starts where it was drawn")
	check_near(h.position(1, 1.0 + HerdView.BLEND * 0.5).x, 0.5, 0.001, "halfway through the blend")
	check_near(h.position(1, 1.0 + HerdView.BLEND).x, 1.0, 0.001, "lands on the server's spot")
	# A new update mid-blend starts from the drawn point, so there is never a jump back.
	h.feed(_wire([[1, 2.0, 0.0, 0.0, "amble"]]), 1.0 + HerdView.BLEND * 0.5)
	check_near(h.position(1, 1.0 + HerdView.BLEND * 0.5).x, 0.5, 0.001, "no jump on a new update")
	var last := -INF
	for i in 30:
		var x := h.position(1, 1.0 + HerdView.BLEND * 0.5 + i * 0.01).x
		check(x >= last - 0.0001, "moves forward only")
		check(x <= 2.0001, "never overshoots")
		last = x


func test_a_long_jump_snaps() -> void:
	var h := HerdView.new()
	h.feed(_wire([[1, 0.0, 0.0, 0.0, "return"]]), 0.0)
	h.feed(_wire([[1, HerdView.SNAP_DIST + 5.0, 0.0, 0.0, "return"]]), 1.0)
	check_near(h.position(1, 1.0).x, HerdView.SNAP_DIST + 5.0, 0.001, "a jump is a jump, not a slide across the hill")


func test_bolt_and_alert_moments() -> void:
	var h := HerdView.new()
	h.feed(_wire([[1, 0.0, 0.0, 0.0, "graze"], [2, 3.0, 0.0, 0.0, "graze"]]), 0.0)
	var ev := h.feed(_wire([[1, 0.0, 0.0, 0.0, "alert"], [2, 3.0, 0.0, 0.0, "graze"]]), 0.2)
	check_eq(ev, [{"id": 1, "event": "alert"}])
	ev = h.feed(_wire([[1, 1.0, 0.0, 0.0, "flee"], [2, 4.0, 0.0, 0.0, "flee"]]), 0.4)
	check_eq(ev.size(), 2, "both bolt")
	check_eq(h.bolts, 2)
	ev = h.feed(_wire([[1, 2.0, 0.0, 0.0, "flee"], [2, 5.0, 0.0, 0.0, "flee"]]), 0.6)
	check_eq(ev, [], "still fleeing is not a second bolt")
	var fresh := HerdView.new()
	ev = fresh.feed(_wire([[4, 0.0, 0.0, 0.0, "flee"]]), 0.0)
	check_eq(str(ev[0].event), "appear", "one that comes into view already running isn't a bolt we saw")
	check_eq(fresh.bolts, 0)


func test_leaving_view() -> void:
	var h := HerdView.new()
	h.feed(_wire([[1, 0.0, 0.0, 0.0, "graze"], [2, 3.0, 0.0, 0.0, "graze"]]), 0.0)
	var ev := h.feed(_wire([[2, 3.0, 0.0, 0.0, "graze"]]), 0.2)
	check_eq(ev, [{"id": 1, "event": "leave"}], "missing from a non-empty list has left")
	check_eq(h.ids(), [2])
	ev = h.feed(PackedFloat32Array(), 0.4)
	check_eq(ev, [{"id": 2, "event": "leave"}], "an empty list means none in view")
	check_eq(h.ids(), [])
	h.feed(PackedFloat32Array([1.0, 2.0]), 0.6)
	check_eq(h.ids(), [], "a malformed list changes nothing")


func test_poses_read_at_a_glance() -> void:
	# World's model through the client's hook: the reads a player needs from across a field.
	var p := Vector3(40.0, Terrain.height(40.0, 12.0), 12.0)
	var stand := GrazerFigures.part_xforms(p, 0.0, "amble", 0.0, 0.0)
	var graze := GrazerFigures.part_xforms(p, 0.0, "graze", 0.0, 0.0)
	var alert := GrazerFigures.part_xforms(p, 0.0, "alert", 0.0, 0.0)
	var rest := GrazerFigures.part_xforms(p, 0.0, "rest", 0.0, 0.0)
	check(_muzzle(graze).y < _muzzle(stand).y - 0.1, "grazing: nose down in the grass")
	check(_muzzle(alert).y > _muzzle(graze).y + 0.4, "alert: head well up")
	check(rest.body.origin.y < stand.body.origin.y - 0.3, "resting: lying down")
	var at := Vector3(5, Terrain.height(5, 5), 5)
	var turned := GrazerFigures.part_xforms(at, PI * 0.5, "amble", 0.0, 0.0)
	check(_muzzle(turned).x > 5.3, "yaw PI/2 looks along +x, as on the wire")
	check_eq((stand.legs as Array).size(), Grazers.LEGS)


func test_legs_swing_only_when_moving() -> void:
	var p := Vector3(40.0, Terrain.height(40.0, 12.0), 12.0)
	var a := GrazerFigures.part_xforms(p, 0.0, "amble", 0.0, 1.0)
	var b := GrazerFigures.part_xforms(p, 0.0, "amble", PI * 0.5, 1.0)
	var still := GrazerFigures.part_xforms(p, 0.0, "amble", PI * 0.5, 0.0)
	check((b.legs[0] as Transform3D).basis.y.distance_to((a.legs[0] as Transform3D).basis.y) > 0.1, "legs swing on the move")
	check((still.legs[0] as Transform3D).basis.y.distance_to((a.legs[0] as Transform3D).basis.y) < 0.02, "no swing at rest")


func test_gait_follows_the_ground_and_poses_blend() -> void:
	var p := Vector3(40.0, 0.0, 12.0)
	var g := GrazerFigures.new_gait(3, p, "graze")
	check_near(float(g.pose.head), float(Grazers.pose_for("graze", g.t, g.phase, 0.0).head), 0.001, "appears already in its pose")
	# Walking 1 m at amble turns the legs by a walk's share of a cycle; a bound's is longer.
	var walked := GrazerFigures.step_gait(g, p + Vector3(0, 0, 1.0), "amble", 0.5)
	var bounded := GrazerFigures.step_gait(g, p + Vector3(0, 0, 1.0), "flee", 0.5)
	check_near(fposmod(walked.phase - g.phase, 1.0), Grazers.cycles_per_metre("amble"), 0.001, "a walk's stride")
	check_near(fposmod(bounded.phase - g.phase, 1.0), Grazers.cycles_per_metre("flee"), 0.001, "a bound's stride")
	check(float(walked.speed) > 0.0, "the speed it really moved")
	var jumped := GrazerFigures.step_gait(g, p + Vector3(HerdView.SNAP_DIST + 1.0, 0, 0), "amble", 0.2)
	check_near(float(jumped.phase), float(g.phase), 0.0001, "a snap doesn't spin the legs")
	# Graze -> alert snaps the head up within a few frames; graze -> rest lies down gently.
	var up := g
	var down := g
	for i in 6:
		up = GrazerFigures.step_gait(up, p, "alert", 1.0 / 60.0)
		down = GrazerFigures.step_gait(down, p, "rest", 1.0 / 60.0)
	var alert_head := float(Grazers.pose_for("alert", 0.0, 0.0, 0.0).head)
	var rest_lift := float(Grazers.pose_for("rest", 0.0, 0.0, 0.0).lift)
	var head_k := (float(up.pose.head) - float(g.pose.head)) / (alert_head - float(g.pose.head))
	var lie_k := float(down.pose.lift) / rest_lift
	check(head_k > 0.7, "alert: head most of the way up in 0.1 s (%.2f)" % head_k)
	check(lie_k > 0.2 and lie_k < 0.6, "rest: partway down in 0.1 s, not a snap (%.2f)" % lie_k)


func _muzzle(x: Dictionary) -> Vector3:
	return (x.head as Transform3D) * Vector3(0, 0.38, 0.55)


func test_sizes_vary_a_little() -> void:
	var lo := INF
	var hi := -INF
	for id in 30:
		var s := GrazerFigures.size_of(id)
		lo = minf(lo, s)
		hi = maxf(hi, s)
		check_eq(s, GrazerFigures.size_of(id), "steady per id")
	check(lo >= 1.0 - GrazerFigures.SIZE_SPREAD and hi <= 1.0 + GrazerFigures.SIZE_SPREAD, "within the spread")
	check(hi - lo > 0.1, "not all the same")


func test_dust_pops_and_goes() -> void:
	var o := Vector3(1, 2, 3)
	var v := Vector3(0, 1, -2)
	check_near(GrazerFigures.dust_xform(o, v, 0.0).basis.get_scale().x, 0.0, 0.001, "starts small")
	check(GrazerFigures.dust_xform(o, v, GrazerFigures.DUST_LIFE * 0.3).basis.get_scale().x > 0.15, "puffs up")
	check_near(GrazerFigures.dust_xform(o, v, GrazerFigures.DUST_LIFE).basis.get_scale().x, 0.0, 0.001, "gone at the end")
	check(GrazerFigures.dust_xform(o, v, 0.3).origin.z < o.z, "kicked backwards")


func test_figures_draw_hide_and_kick_dust() -> void:
	var f := GrazerFigures.new()
	f.setup()
	check_eq(f.count, Wildlife.spawns().size())
	check_eq(f.get_child_count(), 4 + GrazerFigures.SNORT_VOICES, "four MultiMeshes, the snort voices, nothing else")
	for c in f.get_children():
		if c is MultiMeshInstance3D:
			check((c as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no sun shadow (draw-call budget)" % c.name)
			check(Emberlight.is_emberlight((c as MultiMeshInstance3D).material_override), "%s on the shared Emberlight material" % c.name)
	var h := HerdView.new()
	h.feed(_wire([[0, 50.0, 10.0, 0.0, "graze"], [1, 52.0, 10.0, 0.0, "graze"]]), 0.0)
	f.sync(h, 0.0, 0.016)
	check_eq(f.drawn, 2)
	check((f.get_node("Bodies") as MultiMeshInstance3D).visible, "herd layers shown while any grazer is in view")
	check(not (f.get_node("Dust") as MultiMeshInstance3D).visible, "no dust layer drawn without dust")
	check((f.bodies[0] as Transform3D).origin.x > 49.0, "slot 0 drawn at its grazer")
	check(absf((f.bodies[0] as Transform3D).origin.y - Terrain.height(50.0, 10.0)) < 0.5, "standing on the ground")
	check(f.poses[0].head > 1.0, "drawn grazing, head down")
	for n in ["Bodies", "Heads", "Legs"]:
		var mm := (f.get_node(n) as MultiMeshInstance3D).multimesh
		check(mm.use_colors, "%s carries each grazer's coat tint" % n)
		check(mm.mesh == Grazers.meshes()[{"Bodies": "body", "Heads": "head", "Legs": "leg"}[n]], "%s uses world's grazer model" % n)
	check(Grazers.coat_tint(0) != Grazers.coat_tint(1), "two grazers side by side aren't the same coat")
	check_eq(f.bodies.keys().size(), 2, "only grazers in view are drawn")
	var ev := h.feed(_wire([[0, 51.0, 10.0, 0.0, "flee"], [1, 53.0, 10.0, 0.0, "flee"]]), 0.2)
	check_eq(f.play_events(ev, h, 0.2), 2, "a bolt snorts (two per wave at most)")
	check_eq(f.live_puffs(), 2 * GrazerFigures.DUST_PER_BOLT, "and kicks dust")
	f.sync(h, 0.2 + GrazerFigures.DUST_LIFE + 0.1, 0.016)
	check_eq(f.live_puffs(), 0, "the dust settles")
	h.feed(PackedFloat32Array(), 1.5)
	f.sync(h, 1.5, 0.016)
	check_eq(f.drawn, 0)
	check(not (f.get_node("Bodies") as MultiMeshInstance3D).visible, "nothing in view: no draw calls")
	check(not (f.get_node("Dust") as MultiMeshInstance3D).visible, "dust layer hidden once it settles")
	check(not f.bodies.has(0), "a grazer that left is hidden")
	f.free()


func test_snort_is_short_and_audible() -> void:
	var w := Sfx.snort()
	var seconds := float(w.data.size()) / 2.0 / Sfx.RATE
	check(seconds > 0.3 and seconds < 0.7, "about half a second, got %f" % seconds)
	var peak := 0
	for i in range(0, w.data.size(), 2):
		var s := w.data.decode_s16(i)
		peak = maxi(peak, absi(s))
	check(peak > 4000, "loud enough to hear")
	check(peak < 32767, "no clipping")

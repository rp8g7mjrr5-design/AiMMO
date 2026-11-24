extends TestCase
## World stream: the grazers' look (Grazers, for gameplay's Wildlife herds). A herd must read
## at a glance: head down while grazing, head up when it has seen you, legs that really walk,
## a bound when it bolts, lying folded at night. Cheap: three layers whatever the herd size,
## all on Emberlight's shared solid material.


func _lowest(xfs: Dictionary) -> float:
	# The lowest hoof tip: a leg hangs LEG_LENGTH below its hip.
	var lo := INF
	for xf in xfs.legs:
		lo = minf(lo, ((xf as Transform3D) * Vector3(0, -Grazers.LEG_LENGTH, 0)).y)
	return lo


func _muzzle(xfs: Dictionary) -> Vector3:
	return (xfs.head as Transform3D) * Vector3(0, 0.38, 0.55)


func _entries(list: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in list:
		out.append_array(e)
	return out


func _home() -> Vector3:
	return Wildlife.spawns()[0].home


func test_the_model_is_cheap_and_on_the_shared_material() -> void:
	var m := Grazers.meshes()
	for l in ["body", "head", "leg"]:
		check(m.has(l) and (m[l] as ArrayMesh).get_surface_count() == 1, "one baked mesh for the %s layer" % l)
		var cols: PackedColorArray = (m[l] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(cols.size() > 0, "%s is painted into vertex colours" % l)
		for c in cols:
			check(c.a >= 0.999, "no ember on a grazer: they are alive, not usable")
			break
	var tris := Grazers.triangles()
	check(tris > 200 and tris < 1200, "one grazer is low-poly but not a box (%d triangles)" % tris)
	print("[world] grazer triangles: %d (x21 today = %d)" % [tris, tris * 21])
	var root := Grazers.build()
	check_eq(root.get_child_count(), 3, "three layers, whatever the herd size")
	for c in root.get_children():
		var mmi := c as MultiMeshInstance3D
		check(mmi != null, "%s is a MultiMesh layer" % c.name)
		check(mmi.material_override == Emberlight.material("solid"), "%s uses the shared solid material" % c.name)
		check(not mmi.visible, "%s hides until a grazer is fed in" % c.name)
	root.free()


func test_standing_on_its_hooves_at_shoulder_height() -> void:
	var base := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	for state in ["graze", "alert", "amble", "return"]:
		var x := Grazers.xforms(base, Grazers.pose_for(state, 0.0, 0.0, 0.0))
		check_near(_lowest(x), 0.0, 0.08, "%s: hooves on the ground" % state)
	var body: PackedVector3Array = (Grazers.meshes().body as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top := -INF
	var front := -INF
	var back := INF
	for v in body:
		top = maxf(top, v.y)
		front = maxf(front, v.z)
		back = minf(back, v.z)
	check(top > 1.1 and top < 1.4, "about a small deer at the withers (%.2f m)" % top)
	check(front - back > 1.1, "a long body, so a grazer reads side-on from far away (%.2f m)" % (front - back))


func test_poses_read_at_a_glance() -> void:
	var base := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var graze := Grazers.xforms(base, Grazers.pose_for("graze", 0.0, 0.0, 0.0))
	var alert := Grazers.xforms(base, Grazers.pose_for("alert", 0.0, 0.0, 0.0))
	var amble := Grazers.xforms(base, Grazers.pose_for("amble", 0.0, 0.0, 0.0))
	var rest := Grazers.xforms(base, Grazers.pose_for("rest", 0.0, 0.0, 0.0))
	check(_muzzle(graze).y < 0.6, "grazing: the muzzle is down in the grass (%.2f m)" % _muzzle(graze).y)
	check(_muzzle(alert).y > 1.5, "alert: head high (%.2f m)" % _muzzle(alert).y)
	check(_muzzle(alert).y > _muzzle(amble).y + 0.1, "alert stands taller than a walking grazer")
	check((rest.body as Transform3D).origin.y < -0.4, "resting: the body is down on the ground")
	check(_lowest(rest) > -0.1, "resting: folded legs stay above ground")
	var rest_top := ((rest.body as Transform3D) * Vector3(0, 1.27, 0)).y
	check(rest_top < 0.8, "lying down it is low in the grass (back at %.2f m)" % rest_top)


func test_legs_walk_and_bound() -> void:
	# Walking: diagonal pairs move together, the other pair opposite.
	var walk := Grazers.pose_for("amble", 0.0, 0.25, 1.3)
	check(absf(walk.legs[0]) > 0.2, "walking legs swing")
	check_near(walk.legs[0], walk.legs[3], 0.001, "left front with right back")
	check_near(walk.legs[0], -walk.legs[1], 0.001, "and the other pair opposite")
	var still := Grazers.pose_for("amble", 0.0, 0.25, 0.0)
	check_near(still.legs[0], 0.0, 0.001, "legs rest when the grazer stops")
	# Fleeing: wider swings and a body that leaves the ground over a cycle.
	var swing := 0.0
	var lift := 0.0
	for i in 16:
		var p := Grazers.pose_for("flee", 0.0, i / 16.0, 8.5)
		swing = maxf(swing, absf(p.legs[0]))
		lift = maxf(lift, p.lift)
	check(swing > 0.5, "a bolt is a bound, not a walk (%.2f rad)" % swing)
	check(lift > 0.08, "the body leaps (%.2f m)" % lift)
	# The gait follows the ground: a bound covers more ground per cycle than a step.
	check(Grazers.cycles_per_metre("flee") < Grazers.cycles_per_metre("amble"), "long strides when fleeing")


func test_feed_and_tick_follow_the_wire() -> void:
	var root := Grazers.build()
	var h := _home()
	Grazers.feed(root, _entries([[3, h.x, h.z, 0.0, 0], [4, h.x + 2.0, h.z, 1.0, 5]]))
	var shown := Grazers.shown(root)
	check_eq(shown.size(), 2, "both grazers are drawn")
	check_near(shown[3].y, Terrain.height(h.x, h.z), 0.001, "on the ground")
	var bodies := root.get_node("GrazerBodies") as MultiMeshInstance3D
	var legs := root.get_node("GrazerLegs") as MultiMeshInstance3D
	check_eq(bodies.multimesh.visible_instance_count, 2, "two bodies")
	check_eq(legs.multimesh.visible_instance_count, 8, "eight legs")
	check(bodies.visible, "layers show once fed")
	# A new position glides in over the next frames rather than jumping.
	Grazers.feed(root, _entries([[3, h.x, h.z + 2.0, 0.0, 1], [4, h.x + 2.0, h.z, 1.0, 5]]))
	check_near(Grazers.shown(root)[3].z, h.z, 0.001, "no jump on the update itself")
	Grazers.tick(root, 1.0 / 60.0)
	var z1: float = Grazers.shown(root)[3].z
	check(z1 > h.z and z1 < h.z + 1.0, "it starts to move toward the new spot")
	for i in 60:
		Grazers.tick(root, 1.0 / 60.0)
	check_near(Grazers.shown(root)[3].z, h.z + 2.0, 0.05, "and gets there within a second")
	# A long way off (a respawn, a lost update) snaps instead of sliding across the hills.
	Grazers.feed(root, _entries([[3, h.x + 30.0, h.z, 0.0, 0], [4, h.x + 2.0, h.z, 1.0, 5]]))
	check_near(Grazers.shown(root)[3].x, h.x + 30.0, 0.001, "far moves snap")
	# Missing from a non-empty list: gone. An empty list: all gone, layers hidden.
	Grazers.feed(root, _entries([[4, h.x + 2.0, h.z, 1.0, 5]]))
	check(not Grazers.shown(root).has(3), "a grazer that left the view is taken away")
	check_eq(bodies.multimesh.visible_instance_count, 1, "one body left")
	Grazers.feed(root, PackedFloat32Array())
	check(Grazers.shown(root).is_empty(), "an empty list clears the herd")
	check(not bodies.visible, "and hides the layers")
	Grazers.tick(root, 0.1) # nothing to do, nothing breaks
	# Plain Arrays work as well as packed ones, and an unknown state falls back to grazing.
	Grazers.feed(root, [7, h.x, h.z, 0.0, 99])
	check_eq(Grazers.shown(root).size(), 1, "a plain Array feeds too")
	Grazers.tick(root, 0.1)
	root.free()


func test_alert_snaps_up_faster_than_other_poses_blend() -> void:
	var root := Grazers.build()
	var h := _home()
	Grazers.feed(root, _entries([[1, h.x, h.z, 0.0, 0], [2, h.x + 3.0, h.z, 0.0, 0]]))
	for i in 120:
		Grazers.tick(root, 1.0 / 60.0)
	var down := _muzzle(Grazers.xforms_of(root, 1)).y
	Grazers.feed(root, _entries([[1, h.x, h.z, 0.0, 2], [2, h.x + 3.0, h.z, 0.0, 5]]))
	for i in 15: # a quarter of a second
		Grazers.tick(root, 1.0 / 60.0)
	var up := _muzzle(Grazers.xforms_of(root, 1)).y
	var rest_mid: float = (Grazers.xforms_of(root, 2).body as Transform3D).origin.y - Terrain.height(h.x + 3.0, h.z)
	for i in 120:
		Grazers.tick(root, 1.0 / 60.0)
	var full := _muzzle(Grazers.xforms_of(root, 1)).y
	check(full - down > 0.8, "alert lifts the head well clear of the grass")
	check((up - down) / (full - down) > 0.9, "the head is up within a quarter second (the freeze cue)")
	check(rest_mid > -0.5, "lying down is a gentle settle, not a drop")
	var rest_end: float = (Grazers.xforms_of(root, 2).body as Transform3D).origin.y - Terrain.height(h.x + 3.0, h.z)
	check(rest_end < rest_mid, "and it keeps settling")
	root.free()


func test_legs_move_with_the_ground_not_the_clock() -> void:
	var root := Grazers.build()
	var h := _home()
	Grazers.feed(root, _entries([[1, h.x, h.z, 0.0, 1]]))
	for i in 60:
		Grazers.tick(root, 1.0 / 60.0)
	var g: Dictionary = root.get_meta("herd")[1]
	var phase: float = g.phase
	for i in 60:
		Grazers.tick(root, 1.0 / 60.0)
	check_near(g.phase, phase, 0.0001, "standing still in 'amble' does not tread water")
	check(absf(g.pose.legs[0]) < 0.05, "and its legs come to rest")
	root.free()


func test_coats_vary_but_stay_close() -> void:
	var seen := {}
	for id in 21:
		var c := Grazers.coat_tint(id)
		check(c.r > 0.8 and c.r < 1.15 and c.b > 0.75 and c.b < 1.12, "tint %d stays near white" % id)
		seen[c.to_html()] = true
	check(seen.size() > 15, "a herd is not one copied animal")
	check_eq(Grazers.coat_tint(5), Grazers.coat_tint(5), "the same grazer keeps its coat")


func test_slopes_tilt_the_body() -> void:
	# Find a sloped spot near a herd and check the grazer pitches with it.
	var best := Vector3.ZERO
	var steep := 0.0
	for s in Wildlife.spawns():
		var p: Vector3 = s.pos
		var d := absf(Terrain.height(p.x, p.z + 0.45) - Terrain.height(p.x, p.z - 0.45))
		if d > steep:
			steep = d
			best = p
	var b := Grazers.ground_basis(best.x, best.z, 0.0)
	var fwd := b * Vector3(0, 0, 1)
	var rise := Terrain.height(best.x, best.z + 0.45) - Terrain.height(best.x, best.z - 0.45)
	check(signf(fwd.y) == signf(rise) or absf(rise) < 0.01, "nose up a hill, down a slope")
	check_near((b * Vector3(1, 0, 0)).y, 0.0, 0.001, "no sideways roll from the ground")


func test_part_xforms_is_a_drop_in_for_the_client_placeholder() -> void:
	# Same signature and result keys as GrazerFigures.part_xforms (#161), so the client can
	# swap its meshes for ours and keep HerdView, the dust and the snort.
	var p := _home()
	var x := Grazers.part_xforms(p, 0.7, "graze", 0.0, 0.0, 1.0)
	check(x.has("body") and x.has("head") and x.has("legs"), "body, head and legs")
	check_eq((x.legs as Array).size(), 4, "four legs")
	check(absf(_lowest(x) - p.y) < 0.12, "hooves on the ground (%.2f vs %.2f)" % [_lowest(x), p.y])
	var alert := Grazers.part_xforms(p, 0.7, "alert", 0.0, 0.0, 1.0)
	check(_muzzle(alert).y > _muzzle(x).y + 0.4, "alert lifts the head well above grazing")
	var rest := Grazers.part_xforms(p, 0.7, "rest", 0.0, 0.0, 1.0)
	check((rest.body as Transform3D).origin.y < (x.body as Transform3D).origin.y - 0.3, "resting lies down")
	# Legs swing with the gait and stand still without it.
	var a := Grazers.part_xforms(p, 0.7, "amble", 0.0, 1.0, 1.0)
	var b := Grazers.part_xforms(p, 0.7, "amble", PI * 0.5, 1.0, 1.0)
	var c := Grazers.part_xforms(p, 0.7, "amble", PI * 0.5, 0.0, 1.0)
	var swung: Vector3 = (b.legs[0] as Transform3D).basis.y
	check(swung.distance_to((a.legs[0] as Transform3D).basis.y) > 0.1, "a quarter gait moves the front leg")
	check((c.legs[0] as Transform3D).basis.y.distance_to((a.legs[0] as Transform3D).basis.y) < 0.02, "no gait, no swing")
	# Size scales the whole animal about its feet.
	var big := Grazers.part_xforms(p, 0.7, "graze", 0.0, 0.0, 1.1)
	var h1 := (x.head as Transform3D).origin.y - p.y
	var h2 := (big.head as Transform3D).origin.y - p.y
	check(absf(h2 / h1 - 1.1) < 0.05, "size 1.1 is 10%% taller (%.3f)" % (h2 / h1))

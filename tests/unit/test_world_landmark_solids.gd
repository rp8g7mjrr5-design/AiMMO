extends TestCase
## World stream: the action camera keeps out of the landmarks. Every ruin part and beach
## landmark part big enough to matter gets a solid in WorldSolids, cut into thin cells so it
## hugs a long wall instead of standing round it like a fat pillar. Every vertex of every such
## part must be inside its solid, the solids must stay thin, and the camera arm must stop in
## front of a farmhouse wall and a wreck's hull. Renderer-free. Puts the world back to Ashgrove.

const Cam := preload("res://client/action_camera.gd")
const SEED := 1126


func _island() -> void:
	WorldGen.configure(SEED, 3000.0, WorldGen.ISLAND)


## [source, xform, mesh] for every landmark part, the long way, in landmark_solids() order.
func _parts() -> Array:
	var out: Array = []
	var rm := RuinKit._meshes()
	for r in Ruins.all():
		if RuinLayout.has_plan(str(r.kind)):
			for p in RuinKit.parts(r):
				out.append(["ruin", p.xform, rm[p.layer], p])
	var bm := BeachProps.meshes()
	for b in BeachGen.all():
		for lm in b.landmarks:
			for p in BeachProps.landmark_parts(lm, b):
				out.append(["beach", p.xform, bm[p.layer], p])
	return out


func _verts(mesh: Mesh) -> Array:
	var out: Array = []
	for s in mesh.get_surface_count():
		out.append_array(Array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]))
	return out


func test_every_landmark_part_has_a_solid_holding_every_vertex() -> void:
	_island()
	var solids := WorldSolids.landmark_solids()
	var parts := _parts()
	check(solids.size() > 50, "the island's ruins and beaches have solids (%d)" % solids.size())
	var by := {}
	for s in solids:
		by[s.source] = by.get(s.source, 0) + 1
	check(by.get("ruin", 0) > 20, "the farmsteads have solids")
	check(by.get("beach", 0) > 20, "the beach landmarks have solids")
	var i := 0
	var outside := ""
	for p in parts:
		var s := WorldSolids.part_solid(p[0], p[1], p[2])
		if s.is_empty():
			continue
		check_eq(solids[i], s, "landmark_solids() keeps the parts' order")
		i += 1
		if outside != "":
			continue
		for v in _verts(p[2]):
			var w: Vector3 = (p[1] as Transform3D) * v
			if not WorldSolids.inside(w, s, 0.005):
				outside = "%s %s vertex %s" % [p[0], p[3].get("name", p[3].layer), w]
				break
	check_eq(i, solids.size(), "one solid per part big enough")
	check(outside == "", "every vertex is inside its solid (%s)" % outside)
	WorldGen.reset()


func test_ashgrove_has_no_landmark_solids() -> void:
	WorldGen.reset()
	check_eq(WorldSolids.landmark_solids(), [], "no ruins or beaches on Ashgrove")


func test_a_long_wall_is_cut_thin() -> void:
	# A 5 m stone wall, 0.5 m thick and 2 m high, turned 30 degrees: no fat pillar beside it.
	var mesh := BoxMesh.new()
	var turn := Basis(Vector3.UP, 0.52)
	var xf := Transform3D(turn * Basis.from_scale(Vector3(5.0, 2.0, 0.5)), Vector3(10.0, 1.0, 4.0))
	var s := WorldSolids.part_solid("ruin", xf, mesh)
	check(s.columns.size() >= 6, "cut into cells along its length (%d)" % s.columns.size())
	var widest := 0.0
	for c in s.columns:
		widest = maxf(widest, c[0])
	check(widest < 0.5, "every cell is thin (widest %.2f m)" % widest)
	var face := turn.z.normalized()
	check(WorldSolids.inside(Vector3(10.0, 1.0, 4.0), s), "the middle of the wall is solid")
	check(WorldSolids.inside(Vector3(10.0, 1.0, 4.0) + turn.x.normalized() * 2.4, s), "near its end is solid")
	check(not WorldSolids.inside(Vector3(10.0, 1.0, 4.0) + face * 0.75, s), "half a metre off its face is clear")
	check(not WorldSolids.inside(Vector3(10.0, 2.4, 4.0), s), "above the wall is clear")
	check(not WorldSolids.inside(Vector3(10.0, 1.0, 4.0) + turn.x.normalized() * 3.0, s), "past its end is clear")
	check_eq(WorldSolids.part_solid("ruin", Transform3D(Basis.from_scale(Vector3(0.2, 0.1, 0.2)), Vector3.ZERO), mesh), {}, "a small part has none")


func test_landmark_solids_are_not_much_fatter_than_their_parts() -> void:
	_island()
	var fat := ""
	for s in WorldSolids.landmark_solids():
		for c in s.columns:
			if c[0] > 1.0:
				fat = "%s at %s has a %.2f m column" % [s.source, s.pos, c[0]]
				break
		if fat != "":
			break
	check(fat == "", "no landmark column is wider than a metre (%s)" % fat)
	WorldGen.reset()


func _arm_against(solid: Dictionary, target: Vector3, from_dir: Vector3) -> Array:
	# Stand 1.2 m off the part on the `from_dir` side.
	var feet := target + from_dir.normalized() * 1.2
	feet.y = solid.pos.y
	# Look away from the part, so the arm behind you runs back into it.
	var yaw := atan2(-from_dir.x, -from_dir.z)
	var shoulder := feet + Vector3(0.0, 1.6, 0.0)
	var flat := func(_x: float, _z: float) -> float: return feet.y - 5.0
	var arm := Cam.clear_arm(shoulder, yaw, 0.0, Cam.DIST_MAX, flat, [solid])
	var back := -Cam.look_dir(yaw, 0.0)
	return [arm, shoulder + back * arm]


func test_the_camera_stops_in_front_of_a_wall() -> void:
	var mesh := BoxMesh.new()
	var xf := Transform3D(Basis.from_scale(Vector3(6.0, 2.4, 0.5)), Vector3(0.0, 1.2, 0.0))
	var s := WorldSolids.part_solid("ruin", xf, mesh)
	# You stand 1.2 m in front of the wall's +Z face, looking away from it: the camera behind
	# you would be inside the wall, so the arm stops short of it.
	var got := _arm_against(s, Vector3(0.0, 1.2, 0.25), Vector3(0.0, 0.0, 1.0))
	check(got[0] < Cam.DIST_MAX, "the arm is shortened (%.2f m)" % got[0])
	check(not WorldSolids.inside(got[1], s, 0.0), "the camera is not inside the wall")
	check(got[1].z > 0.25, "the camera stays on your side of the wall (z %.2f)" % got[1].z)


func test_the_camera_keeps_out_of_a_real_farmhouse_and_wreck() -> void:
	_island()
	var solids := WorldSolids.landmark_solids()
	var checked := 0
	var bad := ""
	# Every landmark camera spot near a part: wherever clear_arm leaves the camera, it is
	# outside every landmark solid around it.
	for s in solids.slice(0, solids.size(), 7):
		var near := solids.filter(func(o): return (o.pos as Vector3).distance_to(s.pos) < 12.0)
		for k in 4:
			var yaw := k * PI * 0.5
			# Stand off the part with the camera arm (behind you) pointing back at it.
			var feet: Vector3 = s.pos - Vector3(sin(yaw), 0.0, cos(yaw)) * (s.reach + 1.0)
			var shoulder := feet + Vector3(0.0, 1.6, 0.0)
			var ground := func(_x: float, _z: float) -> float: return feet.y - 5.0
			var arm := Cam.clear_arm(shoulder, yaw, -0.2, Cam.DIST_MAX, ground, near)
			if arm <= Cam.ARM_MIN + 0.001:
				continue # pressed against something: the minimum arm is the camera's rule
			var cam := shoulder - Cam.look_dir(yaw, -0.2) * arm
			checked += 1
			for o in near:
				if WorldSolids.inside(cam, o):
					bad = "%s near %s" % [o.source, cam]
	check(checked > 40, "many camera spots checked (%d)" % checked)
	check(bad == "", "the camera never ends inside a landmark (%s)" % bad)
	WorldGen.reset()

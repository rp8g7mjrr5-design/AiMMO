extends TestCase
## World stream: camera clearance for decoration. WorldSolids gives every decorative tree,
## rock, birch, boulder, lantern and the workbench a solid made of columns, worked out from the
## parts and meshes the world draws. Every vertex must be inside its solid, the solids must not
## be much fatter than the meshes, near() must find them, and the client's camera arm
## (ActionCamera.clear_arm) must keep out of them when handed them. Renderer-free.

const Cam := preload("res://client/action_camera.gd")


func _verts(mesh: Mesh) -> Array:
	return Array(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])


## [solid, parts, meshes] for every decorative thing, built the long way (independent of
## WorldSolids' own loop), in the same order as WorldSolids.all().
func _sources() -> Array:
	var out: Array = []
	var all := WorldSolids.all()
	var i := 0
	var items := Props.scatter()
	var per_item := WorldBuilder.scatter_parts(items)
	var sm := WorldBuilder.scatter_meshes()
	for k in items.size():
		out.append([all[i], per_item[k], sm])
		i += 1
	var fm := Flora._meshes()
	for spot in Flora.spots():
		if spot.kind == "flowers":
			continue
		out.append([all[i], Flora.parts(spot), fm])
		i += 1
	var lm := Lamps._meshes()
	for lamp in Lamps.positions():
		out.append([all[i], Lamps.parts(lamp), lm])
		i += 1
	out.append([all[i], Workbench.parts(), Workbench._meshes()])
	return out


func test_every_decoration_has_a_solid() -> void:
	var all := WorldSolids.all()
	var by := {}
	for s in all:
		by[s.source] = by.get(s.source, 0) + 1
	var scatter := Props.scatter()
	check_eq(by.get("ash", 0) + by.get("pine", 0) + by.get("rock", 0), scatter.size(), "one solid per scatter tree or rock")
	check_eq(by.get("birch", 0), Flora.count("birch"), "one solid per birch")
	check_eq(by.get("boulder", 0), Flora.count("boulder"), "one solid per boulder")
	check_eq(by.get("lantern", 0), Lamps.COUNT, "one solid per meadow lantern")
	check_eq(by.get("workbench", 0), 1, "the workbench has one")
	check(not by.has("flowers"), "wildflowers have none")
	for s in all:
		check_eq(s.kind, WorldSolids.KIND, "solid kind is deco")
		if s.columns.is_empty():
			check(false, "%s at %s has no columns" % [s.source, s.pos])
			break


func test_every_vertex_is_inside_its_solid() -> void:
	var checked := 0
	var outside := ""
	var cache := {}
	for src in _sources():
		var solid: Dictionary = src[0]
		for p in src[1]:
			var mesh: Mesh = src[2][p.layer]
			if not cache.has(mesh):
				cache[mesh] = _verts(mesh)
			for v in cache[mesh]:
				var w: Vector3 = p.xform * v
				checked += 1
				if outside == "" and not WorldSolids.inside(w, solid, 0.005):
					outside = "%s at %s, %s vertex %s" % [solid.source, solid.pos, p.layer, w]
	check(checked > 200000, "checked %d vertices" % checked)
	check(outside == "", "a vertex is outside its solid: %s" % outside)


func test_solids_are_not_much_fatter_than_the_meshes() -> void:
	# Spot-check against the mesh sizes: an ash crown is 1.6 m round at scale 1, a pine's
	# lowest tier 1.4 m, a rock 0.8 x 1.3 m, so columns should stay close to those.
	for s in WorldSolids.all():
		var widest := 0.0
		var top := 0.0
		for c in s.columns:
			widest = maxf(widest, c[0])
			top = maxf(top, c[2])
		match s.source:
			"ash", "pine", "rock":
				check(widest < 2.4, "%s column %.2f m is no wider than a big crown" % [s.source, widest])
			"lantern":
				check(widest < 0.7 and top < 2.6, "lantern columns stay slim (%.2f m wide, %.2f m tall)" % [widest, top])
			"workbench":
				check(s.reach < Workbench.FOOTPRINT + 0.3, "bench solid stays inside its footprint (reach %.2f)" % s.reach)
				check(top < 1.6, "bench solid stays low (%.2f m)" % top)
	# The point 2.5 m beside a scale-1 ash trunk at knee height is open air.
	var ash := {}
	for s in WorldSolids.all():
		if s.source == "ash":
			ash = s
			break
	check(not WorldSolids.inside(ash.pos + Vector3(1.2, 0.6, 0.0), ash), "beside an ash trunk, under the crown, is clear")
	check(WorldSolids.inside(ash.pos + Vector3(0.0, 1.0, 0.0), ash), "inside the trunk is solid")


func test_near_finds_solids_and_only_those_in_range() -> void:
	var probe: Vector3 = WorldSolids.all()[42].pos + Vector3(2.0, 0.0, 1.0)
	var near := WorldSolids.near(probe, 12.0)
	check(near.has(WorldSolids.all()[42]), "the solid next door is found")
	var want := 0
	for s in WorldSolids.all():
		if Vector2(s.pos.x - probe.x, s.pos.z - probe.z).length() <= 12.0 + s.reach:
			want += 1
	check_eq(near.size(), want, "near() matches a brute-force search")
	var bench := WorldSolids.near(Crafting.workbench_pos(), 1.0).filter(func(s): return s.source == "workbench")
	check_eq(bench.size(), 1, "the bench is found from its own spot")


func test_node_props_inside_solid_understands_deco() -> void:
	var s: Dictionary = WorldSolids.all()[7]
	for p in [s.pos + Vector3(0, 0.5, 0), s.pos + Vector3(0.6, 1.2, -0.3), s.pos + Vector3(3, 2, 3)]:
		check_eq(NodeProps.inside_solid(p, s, 0.2), WorldSolids.inside(p, s, 0.2), "NodeProps agrees at %s" % p)


func test_client_camera_arm_keeps_out_of_decoration() -> void:
	# Hand the client's own clear_arm decoration solids (no client change needed beyond
	# passing them) and the camera never ends inside one, from a spot right next to a tree.
	var tested := 0
	for s in WorldSolids.all().slice(0, 300):
		if s.source == "rock":
			continue
		var feet: Vector3 = s.pos + Vector3(2.4, 0.0, 0.0)
		feet.y = Terrain.height(feet.x, feet.z)
		var props := WorldSolids.near(feet, Cam.DIST_MAX + 3.0)
		for i in 8:
			var yaw := TAU * i / 8.0
			var shoulder := Cam.shoulder_point(feet, yaw, 1.0)
			var arm := Cam.clear_arm(shoulder, yaw, Cam.PITCH_DEFAULT, Cam.DIST_DEFAULT, Callable(Terrain, "height"), props)
			if arm <= Cam.ARM_MIN:
				continue
			tested += 1
			var cam := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, arm)
			for n in props:
				if WorldSolids.inside(cam, n):
					check(false, "camera at %s ends inside %s at %s" % [cam, n.source, n.pos])
					return
	check(tested > 500, "tested %d camera looks" % tested)


func test_deterministic_and_scatter_unchanged() -> void:
	var a := WorldBuilder.scatter_parts(Props.scatter())
	var b := WorldBuilder.scatter_parts(Props.scatter())
	check_eq(a.size(), b.size(), "same item count")
	for i in range(0, a.size(), 37):
		for j in a[i].size():
			check(a[i][j].xform.is_equal_approx(b[i][j].xform) and a[i][j].color == b[i][j].color, "item %d part %d same every time" % [i, j])
	var counts := {"ash": 2, "pine": 4, "rock": 1}
	var items := Props.scatter()
	for i in range(0, items.size(), 53):
		check_eq(a[i].size(), counts[items[i].kind], "%s has its usual parts" % items[i].kind)

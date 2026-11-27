extends TestCase
## World stream: the starting beaches drawn (BeachProps, the beach pickings in NodeProps, the
## Sea). The pickings keep every vertex inside their solid columns and fit NodeFx's highlight
## shell; the landmarks are built from the shared layers on the shared materials (no new
## material); the sea shader only goes on islands, so Ashgrove's lake is unchanged.
## Renderer-free, like the other prop tests.


func _island(seed: int) -> void:
	WorldGen.configure(seed, 3000.0, WorldGen.ISLAND)
	ResourceNodes.reset()
	BeachGen.reset()


func _done() -> void:
	WorldGen.reset()
	ResourceNodes.reset()
	BeachGen.reset()


func _beach_nodes() -> Array:
	var out: Array = []
	for n in ResourceNodes.all():
		if ResourceNodes.BEACH_KINDS.has(n.kind):
			out.append(n)
	return out


func test_every_picking_vertex_is_inside_its_solid_columns() -> void:
	_island(3)
	var meshes := NodeProps._meshes()
	var verts := {}
	for l in NodeProps.LAYERS:
		verts[l] = (meshes[l] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var checked := 0
	var kinds := {}
	for n in _beach_nodes():
		kinds[n.kind] = true
		var cols := NodeProps.solid_columns(n.kind, n.scale)
		check(not cols.is_empty(), "%s has solid columns" % n.kind)
		for depleted in [false, true]:
			var parts := NodeProps.parts(n, depleted)
			check(not parts.is_empty(), "%s has a %s look" % [n.kind, "depleted" if depleted else "live"])
			var per := {}
			for p in parts:
				per[p.layer] = per.get(p.layer, 0) + 1
				for v in verts[p.layer]:
					var w: Vector3 = p.xform * v
					var h: float = w.y - n.pos.y
					if h < 0.0:
						continue
					checked += 1
					var d := Vector2(w.x - n.pos.x, w.z - n.pos.z).length()
					var inside := false
					for c in cols:
						if h >= c[1] - 0.01 and h <= c[2] + 0.01 and d <= c[0] + 0.01:
							inside = true
					if not inside:
						check(false, "%s node %d: a %s vertex sticks out (h %.2f, d %.2f)" % [n.kind, n.id, p.layer, h, d])
						return
			for l in per:
				check(per[l] <= NodeFx.SHELL_SLOTS, "%s %s has %d parts, the shell holds %d" % [n.kind, l, per[l], NodeFx.SHELL_SLOTS])
	check_eq(kinds.size(), ResourceNodes.BEACH_ORDER.size(), "every kind of picking checked")
	check(checked > 2000, "checked %d vertices" % checked)
	_done()


func test_pickings_shake_and_throw_bits() -> void:
	_island(3)
	for n in _beach_nodes().slice(0, 8):
		check(NodeFx.shake(n.kind, 0.1) != Transform3D.IDENTITY, "%s shakes when hit" % n.kind)
		var bits := NodeFx.spawn_bits(n)
		check(bits.size() > 0, "%s throws bits" % n.kind)
		for b in bits:
			check(b.has("p0") and b.has("v") and b.has("color"), "%s bits are whole" % n.kind)
	_done()


func test_landmarks_are_built_from_the_shared_layers() -> void:
	_island(3)
	var parts := BeachProps.parts()
	check(parts.size() > 300, "the beaches are dressed (%d parts)" % parts.size())
	var layers := {}
	for p in parts:
		check(BeachProps.LAYERS.has(p.layer), "known layer " + str(p.layer))
		layers[p.layer] = true
		check((p.xform as Transform3D).basis.determinant() > 0.0, "a real part, not a collapsed one")
	for l in ["BeachPlanks", "BeachBits", "BeachRocks", "BeachPools", "BeachFar"]:
		check(layers.has(l), "%s is used" % l)
	for lm in BeachGen.landmarks():
		var b := BeachGen.beach(lm.beach)
		var lp := BeachProps.landmark_parts(lm, b)
		check(lp.size() >= 8, "%s is more than a box (%d parts)" % [lm.kind, lp.size()])
		for p in lp:
			var d := Vector2(p.xform.origin.x - lm.pos.x, p.xform.origin.z - lm.pos.z).length()
			check(d < BeachGen.PIER_LENGTH + 6.0, "%s parts stay at the landmark (%.1f m)" % [lm.kind, d])
	_done()


func test_every_landmark_kind_draws() -> void:
	_island(3)
	var b := BeachGen.beach(0)
	for kind in BeachGen.LANDMARK_ORDER:
		var lm := {"kind": kind, "pos": Vector3(b.landing.x, 1.0, b.landing.y), "rot": 0.3, "seed": 99}
		var a := BeachProps.landmark_parts(lm, b)
		check(a.size() >= 8, "%s draws (%d parts)" % [kind, a.size()])
		check_eq(var_to_str(BeachProps.landmark_parts(lm, b)), var_to_str(a), "%s draws the same every time" % kind)
	_done()


func test_no_new_materials() -> void:
	for l in BeachProps.LAYERS:
		var m := BeachProps.layer_material(l)
		if l == "BeachPools":
			check(m == Sea.material(), "tide pools share the sea")
		else:
			check(Emberlight.is_emberlight(m), "%s is on a shared Emberlight material" % l)
	check(NodeProps.layer_material(NodeProps.BOX_LAYER) == Emberlight.painted("bark"), "crates share the bark")


func test_sea_only_on_islands() -> void:
	# The headless dummy renderer can't size a PlaneMesh (as in the materials test).
	expect_error("Parameter \"m\" is null")
	WorldGen.reset()
	var w := WorldBuilder._water()
	check(w.material_override is StandardMaterial3D, "Ashgrove's lake keeps its plain water")
	w.free()
	_island(3)
	w = WorldBuilder._water()
	check(w.material_override == Sea.material(), "the island's sea has surf")
	w.free()
	check(Sea.source(false).contains("hint_depth_texture"), "the surf reads the depth")
	check(not Sea.source(false).contains("$"), "every placeholder filled")
	check(Sea.source(true).contains("#define COMPAT_SRGB"), "the Compatibility fix is in")
	_done()


func test_nothing_built_off_the_island() -> void:
	WorldGen.reset()
	check(BeachProps.parts().is_empty(), "Ashgrove has no beach props")
	var root := BeachProps.build()
	check_eq(root.get_child_count(), 0, "and builds nothing")
	root.free()

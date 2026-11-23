extends TestCase
## World stream: the close-up read for the over-the-shoulder action camera. Resource-node
## props get small detail (root flares, bark ridges, quartz seam studs) without changing any
## older part, every vertex of every prop fits inside NodeProps.solid_columns() (so a camera
## kept outside them never sees inside a mesh), and avatars carry a pack on their back.
## Renderer-free: primitive meshes build their arrays headless.


func _first_of(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _detail(node: Dictionary, depleted: bool = false) -> Array:
	return NodeProps.parts(node, depleted).filter(func(p): return p.layer == NodeProps.DETAIL_LAYER)


func test_trees_and_outcrops_get_close_up_detail() -> void:
	check_eq(_detail(_first_of("ash")).size(), 7, "ash: 3 root flares and 4 bark ridges")
	check_eq(_detail(_first_of("pine")).size(), 7, "pine: 3 root flares and 4 bark ridges")
	check_eq(_detail(_first_of("ash"), true).size(), 3, "ash stump keeps its roots")
	check_eq(_detail(_first_of("stone")).size(), 6, "outcrop: 6 seam studs")
	check(_detail(_first_of("stone")).all(func(p): return p.color.r > 0.75), "seam studs are pale quartz")
	check_eq(_detail(_first_of("stone"), true).size(), 0, "rubble has no seam")
	check_eq(_detail(_first_of("ember_sap")).size(), 0, "seeps need no detail boxes")
	for kind in ResourceNodes.KIND_ORDER:
		var per_layer := {}
		for depleted in [false, true]:
			for p in NodeProps.parts(_first_of(kind), depleted):
				per_layer[p.layer] = per_layer.get(p.layer, 0) + 1
		for l in per_layer:
			check(per_layer[l] <= NodeFx.SHELL_SLOTS, "%s %s fits the highlight shell" % [kind, l])


func test_older_parts_are_unchanged() -> void:
	# Detail is appended after every older part, and ember veins after the detail, so the
	# first parts are the old ones in the old order, on the old layers. Spot-check the old
	# counts per kind.
	var old := {"ash": 3, "pine": 5, "stone": 4, "ember_sap": 9}
	for kind in old:
		var parts := NodeProps.parts(_first_of(kind))
		for i in old[kind]:
			check(parts[i].layer != NodeProps.DETAIL_LAYER and parts[i].layer != NodeProps.VEIN_LAYER, "%s part %d is an old part" % [kind, i])
		var seen_vein := false
		for i in range(old[kind], parts.size()):
			if parts[i].layer == NodeProps.VEIN_LAYER:
				seen_vein = true
			else:
				check(not seen_vein, "%s part %d: veins come after all detail" % [kind, i])
				check_eq(parts[i].layer, NodeProps.DETAIL_LAYER, "%s part %d is new detail" % [kind, i])


func test_every_vertex_is_inside_the_solid_columns() -> void:
	var meshes := NodeProps._meshes()
	var verts := {}
	for l in NodeProps.LAYERS:
		verts[l] = (meshes[l] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var checked := 0
	var worst := 0.0
	var worst_at := ""
	for n in ResourceNodes.all():
		var cols := NodeProps.solid_columns(n.kind, n.scale)
		for depleted in [false, true]:
			for p in NodeProps.parts(n, depleted):
				for v in verts[p.layer]:
					var w: Vector3 = p.xform * v
					var h: float = w.y - n.pos.y
					if h < 0.0:
						continue # below the node's ground: the terrain hides it
					checked += 1
					var d := Vector2(w.x - n.pos.x, w.z - n.pos.z).length()
					var miss := INF
					for c in cols:
						if h >= c[1] - 0.01 and h <= c[2] + 0.01:
							miss = minf(miss, d - c[0])
					if miss > worst:
						worst = miss
						worst_at = "%s node %d %s (h %.2f)" % [n.kind, n.id, p.layer, h]
	check(checked > 100000, "checked %d vertices" % checked)
	check(worst <= 0.01, "a vertex sticks %.3f m out of the solid columns at %s" % [worst, worst_at])


func test_inside_solid_follows_the_columns_and_scale() -> void:
	var ash := _first_of("ash")
	var base: Vector3 = ash.pos
	var s: float = ash.scale
	check(NodeProps.inside_solid(base + Vector3(0, 1.0, 0), ash), "inside the trunk")
	check(NodeProps.inside_solid(base + Vector3(1.8 * s, 3.5 * s, 0), ash), "inside the crown's edge")
	check(not NodeProps.inside_solid(base + Vector3(1.0, 1.0, 0), ash), "beside the trunk is clear")
	check(NodeProps.inside_solid(base + Vector3(1.0, 1.0, 0), ash, 0.7), "but not with a wide margin")
	var pine := _first_of("pine")
	check(NodeProps.inside_solid(pine.pos + Vector3(1.4 * pine.scale, 1.3 * pine.scale, 0), pine), "inside the lowest pine tier")
	var big := ash.duplicate()
	big.scale = 1.2
	check(NodeProps.inside_solid(base + Vector3(2.2, 3.5 * 1.2, 0), big), "a bigger tree is bigger")
	check(not NodeProps.inside_solid(base + Vector3(2.2, 3.5 * 1.2, 0), ash) or s > 1.15, "...than a normal one")
	check(not NodeProps.inside_solid(base + Vector3(0, 9.0, 0), ash), "above the tree is clear")


func test_detail_is_deterministic() -> void:
	for kind in ResourceNodes.KIND_ORDER:
		var a := _detail(_first_of(kind))
		var b := _detail(_first_of(kind))
		check_eq(a.size(), b.size(), "%s same detail count" % kind)
		for i in a.size():
			check(a[i].xform.is_equal_approx(b[i].xform), "%s detail %d same place" % [kind, i])


func test_avatar_carries_a_pack_on_its_back() -> void:
	var back := AvatarBuilder.parts(42).filter(func(p): return p.limb == "" and p.pos.z < -0.2)
	check_eq(back.size(), 2, "pack and bedroll behind the body")
	for p in back:
		var aabb: AABB = (p.mesh as Mesh).get_aabb()
		var near_z: float = p.pos.z + aabb.end.z # the bedroll turns about z, which keeps its depth
		check(near_z > -0.34, "%s touches the back (front face at z %.2f)" % [p.mesh.get_class(), near_z])
		check(absf(p.pos.x) + 0.22 < AvatarBuilder.LIMB_PIVOTS.ArmL.x, "clear of the swinging arms")
	var belt := AvatarBuilder.parts(42).filter(func(p): return p.limb == "" and p.color == AvatarBuilder.LEATHER.darkened(0.3))
	check_eq(belt.size(), 1, "a belt")

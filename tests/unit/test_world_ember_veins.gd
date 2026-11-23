extends TestCase
## World stream: Emberlight part 2a (docs/art_bible.md). Every gatherable carries glowing ember
## veins (live look only, more on richer tiers), resource nodes and flora draw with the shared
## Emberlight materials, and the night glow still reaches the node leaves and the sap.


func _first_of(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _veins(node: Dictionary, depleted: bool = false) -> Array:
	return NodeProps.parts(node, depleted).filter(func(p): return p.layer == NodeProps.VEIN_LAYER)


func test_every_live_gatherable_has_veins() -> void:
	var counts := {}
	for n in ResourceNodes.all():
		var live := _veins(n)
		check(live.size() >= 4, "node %d (%s) has ember veins (%d)" % [n.id, n.kind, live.size()])
		check(live.size() <= NodeProps.MAX_VEIN_PARTS, "node %d: veins fit NodeFx's glow shell" % n.id)
		check_eq(_veins(n, true).size(), 0, "node %d: an emptied node goes dark" % n.id)
		counts[n.kind] = true
		for v in live:
			check_eq((v.color as Color).a, 0.0, "node %d: vein parts are marked as vein (alpha 0)" % n.id)
	check_eq(counts.size(), 4, "all four kinds checked")


func test_richer_tiers_glow_more() -> void:
	for kind in ["ash", "pine", "stone", "ember_sap"]:
		var n := _first_of(kind).duplicate()
		var t1 := _veins(n).size()
		n["tier"] = 2
		var t2 := _veins(n).size()
		check(t2 > t1, "%s: tier 2 has more vein parts than tier 1 (%d > %d)" % [kind, t2, t1])
		check(t2 <= NodeProps.MAX_VEIN_PARTS, "%s: tier 2 still fits the shell" % kind)
		check(NodeProps.vein_cracks(kind, 2) > NodeProps.vein_cracks(kind, 1), "%s: more cracks per tier" % kind)


func test_veins_sit_on_the_surface() -> void:
	# Trunk veins hug the trunk (radius 0.24 to 0.36 at scale 1); stone and seep veins sit on
	# their stones, never floating out past the prop or sunk deep inside it.
	for n in ResourceNodes.all().slice(0, 120):
		var s: float = n.scale
		for v in _veins(n):
			var o: Vector3 = (v.xform as Transform3D).origin - (n.pos as Vector3)
			var d := Vector2(o.x, o.z).length() / s
			match n.kind:
				"ash", "pine":
					check(d > 0.22 and d < 0.38, "node %d: trunk vein on the bark (%.3f m from the axis)" % [n.id, d])
					check(o.y / s > 0.2 and o.y / s < 1.9, "node %d: trunk vein between roots and crown" % n.id)
				"stone":
					var e := Vector3(o.x / s / 1.1, (o.y / s - 0.6) / 0.9, o.z / s / 0.9).length()
					check(e > 0.9 and e < 1.04, "node %d: stone vein on the big stone (%.3f)" % [n.id, e])
				"ember_sap":
					check(d > 0.6 and d < 1.3, "node %d: seep vein on a rim stone (%.3f m out)" % [n.id, d])
					check(o.y / s > 0.15 and o.y / s < 0.43, "node %d: seep vein on top of the stone" % n.id)


func test_veins_are_deterministic() -> void:
	var n := _first_of("stone")
	var a := _veins(n)
	var b := _veins(n)
	check_eq(a.size(), b.size(), "same count")
	for i in a.size():
		check((a[i].xform as Transform3D).is_equal_approx(b[i].xform), "vein %d in the same place" % i)


func test_nodes_and_flora_use_emberlight() -> void:
	for l in NodeProps.LAYERS:
		check(Emberlight.is_emberlight(NodeProps.layer_material(l)), "node layer %s is on Emberlight" % l)
	for l in Flora.LAYERS:
		check(Emberlight.is_emberlight(Flora.layer_material(l)), "flora layer %s is on Emberlight" % l)
	check_eq(NodeProps.layer_material(NodeProps.VEIN_LAYER), Emberlight.material("glow"), "veins on the shared glow material")
	check_eq(NodeProps.layer_material("NodeTrunks"), WorldBuilder.scatter_material("Trunks"), "node bark shares the forest's solid")
	check_eq(NodeProps.layer_material("NodePineTiers"), WorldBuilder.scatter_material("PineTiers"), "node pines share the forest's foliage")
	check(NodeProps.layer_material("NodeAshCrowns") != Lamps.ember_leaf_material(), "node leaves glow on their own number")
	check(NodeProps.layer_material(NodeProps.GLOW_LAYER) != Emberlight.material("glow"), "sap glows whole; veins only where marked")
	var mats := {}
	for l in NodeProps.LAYERS:
		mats[NodeProps.layer_material(l).get_instance_id()] = true
	for l in Flora.LAYERS:
		mats[Flora.layer_material(l).get_instance_id()] = true
	check(mats.size() <= 6, "eight node layers and seven flora layers on at most six materials (%d)" % mats.size())
	check(Emberlight.count() <= 24, "within the art bible's 24-material budget (%d)" % Emberlight.count())


func test_baking_keeps_node_and_flora_shapes() -> void:
	# WorldSolids and NodeFx's shells read these meshes: baked colours must not move a vertex.
	var nm := NodeProps._meshes()
	var fm := Flora._meshes()
	for meshes in [nm, fm]:
		for l in meshes:
			var arrays := (meshes[l] as Mesh).surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_VERTEX].size() > 0, "%s has vertices" % l)
	check(nm.NodeTrunks is ArrayMesh and nm.NodeTrunks.surface_get_arrays(0)[Mesh.ARRAY_COLOR].size() > 0, "node trunks carry baked AO")
	var raw := CylinderMesh.new()
	raw.top_radius = 0.24
	raw.bottom_radius = 0.36
	raw.height = 2.8
	raw.radial_segments = 6
	raw.rings = 1
	var a: PackedVector3Array = raw.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var b: PackedVector3Array = nm.NodeTrunks.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check_eq(a, b, "node trunk vertices unchanged by the bake")


func test_night_glow_reaches_emberlight_nodes() -> void:
	var nodes := [_first_of("ash"), _first_of("ember_sap")]
	var world := Node3D.new()
	var root := NodeProps.build(nodes)
	world.add_child(root)
	Lamps.apply_glow(world, 1.0)
	var leaf := NodeProps.layer_material("NodeAshCrowns")
	var sap := NodeProps.layer_material(NodeProps.GLOW_LAYER)
	check_near(float(leaf.get_shader_parameter("emission_energy")), Lamps.NODE_ASH_GLOW, 0.001, "node ash leaves glow at night")
	check_near(float(sap.get_shader_parameter("emission_energy")), Lamps.SAP_NIGHT, 0.001, "sap brightens at night")
	Lamps.apply_glow(world, 0.0)
	check_near(float(leaf.get_shader_parameter("emission_energy")), 0.0, 0.001, "node ash leaves dark by day")
	check_near(float(sap.get_shader_parameter("emission_energy")), Lamps.SAP_DAY, 0.001, "sap at its day glow")
	var drawn := 0
	for c in root.get_node(NodeProps.VEIN_LAYER).get_children(): # one MultiMesh per chunk
		drawn += (c as MultiMeshInstance3D).multimesh.instance_count
	check_eq(drawn, _veins(nodes[0]).size() + _veins(nodes[1]).size(), "every vein drawn")
	world.free()

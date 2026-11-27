extends TestCase
## World stream: chunked instancing (art bible section 7, "Draw less"). The scatter forest and
## the flora are split into ~64 m chunks with per-layer draw distances, without moving a prop.


## The layer node holds exactly `Chunks.split(layout)`: one chunk per key, same instance counts,
## and the split itself is the layout regrouped, nothing moved, dropped or added. (The headless
## renderer doesn't keep MultiMesh data, so this checks the split the build is made from.)
func _check_same_props(layer: String, layer_node: Node, layout: Array) -> void:
	var by_chunk := Chunks.split(layout, Chunks.size_of(layer))
	check_eq(layer_node.get_child_count(), by_chunk.size(), "%s: one node per chunk" % layer)
	var total := 0
	for k in by_chunk:
		var c := layer_node.get_node_or_null("c%d_%d" % [k.x, k.y]) as MultiMeshInstance3D
		check(c != null, "%s: chunk %s built" % [layer, k])
		if c != null:
			check_eq(c.multimesh.instance_count, (by_chunk[k] as Array).size(), "%s chunk %s holds its props" % [layer, k])
			check_eq(c.position, Chunks.centre(k, Chunks.size_of(layer)), "%s chunk %s sits at its centre" % [layer, k])
		for inst in by_chunk[k]:
			check_eq(Chunks.key((inst[0] as Transform3D).origin, Chunks.size_of(layer)), k, "%s: in the right chunk" % layer)
		total += (by_chunk[k] as Array).size()
	check_eq(total, layout.size(), "%s: every prop kept" % layer)
	# Regrouped in input order: walking the layout and popping each chunk's list front gives the same instances.
	var cursor := {}
	var same := true
	for inst in layout:
		var k := Chunks.key((inst[0] as Transform3D).origin, Chunks.size_of(layer))
		var idx: int = cursor.get(k, 0)
		var got: Array = (by_chunk[k] as Array)[idx]
		same = same and got[0] == inst[0] and got[1] == inst[1]
		cursor[k] = idx + 1
	check(same, "%s: every prop in the same place with the same colour" % layer)


func test_split_keeps_every_instance_in_its_chunk() -> void:
	var inst := [
		[Transform3D(Basis(), Vector3(1, 0, 1)), Color.RED],
		[Transform3D(Basis(), Vector3(-1, 0, 1)), Color.GREEN],
		[Transform3D(Basis(), Vector3(63.9, 0, 0.5)), Color.BLUE],
		[Transform3D(Basis(), Vector3(64.0, 0, 0.5)), Color.WHITE],
	]
	var s := Chunks.split(inst, 64.0)
	check_eq(s.size(), 3, "three chunks")
	check_eq((s[Vector2i(0, 0)] as Array).size(), 2, "both near-origin props in chunk 0,0")
	check_eq((s[Vector2i(0, 0)] as Array)[0][1], Color.RED, "order kept inside a chunk")
	check_eq((s[Vector2i(-1, 0)] as Array).size(), 1, "negative x goes to chunk -1")
	check_eq((s[Vector2i(1, 0)] as Array).size(), 1, "64 m starts the next chunk")


func test_scatter_forest_is_chunked_without_moving_a_prop() -> void:
	var meshes := WorldBuilder.scatter_meshes()
	var layout := WorldBuilder.scatter_layout()
	for l in WorldBuilder.SCATTER_LAYERS:
		var n := Chunks.build(l, meshes[l], layout[l], WorldBuilder.scatter_material(l))
		check(n.get_child_count() > 8, "%s is split into many chunks (%d)" % [l, n.get_child_count()])
		_check_same_props(l, n, layout[l])
		for c in n.get_children():
			var mmi := c as MultiMeshInstance3D
			check(mmi.material_override == WorldBuilder.scatter_material(l), "%s chunks share the layer's material" % l)
			check(mmi.visibility_range_end >= Chunks.range_of(l) + Chunks.size_of(l) * 0.7071, "%s: no prop closer than the layer's range is cut" % l)
			check(mmi.visibility_range_end <= Chunks.range_of(l) + Chunks.size_of(l), "%s: the cut stays near the layer's range" % l)
		n.free()


func test_flora_is_chunked_without_moving_a_prop() -> void:
	var flora := Flora.build()
	var lay := Flora.layout(Flora.spots())
	for l in Flora.LAYERS:
		var n := flora.get_node(l)
		if (l as String).begins_with("Palm"):
			check_eq(lay[l].size(), 0, "%s: palms grow only on an island's beaches, not in Ashgrove" % l)
			continue
		check(n.get_child_count() > 1, "%s is chunked" % l)
		_check_same_props(l, n, lay[l])
		for c in n.get_children():
			var mmi := c as MultiMeshInstance3D
			var shadows := mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			check_eq(shadows, not Chunks.NO_SHADOW.has(l), "%s shadows as set" % l)
	var bloom := flora.get_node("FlowerBlooms").get_child(0) as MultiMeshInstance3D
	check(bloom.visibility_range_end >= 90.0 and bloom.visibility_range_end < 120.0, "flowers drawn out to 90 m and not much further")
	flora.free()


func test_cut_and_centre() -> void:
	check_eq(Chunks.centre(Vector2i(0, 0), 64.0), Vector3(32, 0, 32), "chunk 0,0 centre")
	check_eq(Chunks.centre(Vector2i(-1, 2), 32.0), Vector3(-16, 0, 80), "negative chunk centre")
	check_eq(Chunks.cut_of("Water"), 0.0, "unlisted layers have no limit")
	# A prop in a chunk's far corner, exactly at the layer's range, is still inside the cut.
	var s := Chunks.size_of("Rocks")
	var corner := Chunks.centre(Vector2i(0, 0), s) + Vector3(s * 0.5, 0, s * 0.5)
	var cam := corner + Vector3(1, 0, 1).normalized() * Chunks.range_of("Rocks")
	check(cam.distance_to(Chunks.centre(Vector2i(0, 0), s)) <= Chunks.cut_of("Rocks") + 0.01, "far corner at range is drawn")


func test_ranges_follow_the_art_bible() -> void:
	check_eq(Chunks.range_of("FlowerBlooms"), 90.0, "flowers 90 m")
	check_eq(Chunks.range_of("Rocks"), 160.0, "props about 160 m")
	check_eq(Chunks.range_of("Trunks"), 300.0, "trees about 300 m")
	check_eq(Chunks.range_of("BirchCrowns"), Chunks.range_of("BirchBark"), "a crown never outlives its trunk")
	check_eq(Chunks.range_of("AshCrowns"), Chunks.range_of("Trunks"), "ash crowns go with their trunks")
	check_eq(Chunks.range_of("PineTiers"), Chunks.range_of("Trunks"), "pine tiers go with their trunks")


func test_glow_still_reaches_chunked_ash_crowns() -> void:
	var world := Node3D.new()
	var meshes := WorldBuilder.scatter_meshes()
	var layout := WorldBuilder.scatter_layout()
	world.add_child(Chunks.build("AshCrowns", meshes["AshCrowns"], layout["AshCrowns"], WorldBuilder.scatter_material("AshCrowns")))
	var mat := WorldBuilder.scatter_material("AshCrowns") as ShaderMaterial
	Lamps.apply_glow(world, 1.0)
	var night: float = mat.get_shader_parameter("emission_energy")
	Lamps.apply_glow(world, 0.0)
	var day: float = mat.get_shader_parameter("emission_energy")
	check(night > day, "ash crowns glow at night through the chunked layer (%.2f > %.2f)" % [night, day])
	world.free()

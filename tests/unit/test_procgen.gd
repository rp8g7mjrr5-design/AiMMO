extends TestCase


func test_terrain_chunk() -> void:
	var m := TerrainMesh.build_chunk(0, 0, 4, 4.0)
	check_eq(m.get_surface_count(), 1)
	var arrays := m.surface_get_arrays(0)
	check_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 4 * 4 * 2 * 3, "flat-shaded triangles")
	check((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0, "vertex colours")


func test_props_are_deterministic() -> void:
	var a := Props.scatter(200)
	var b := Props.scatter(200)
	check_eq(a.size(), 200)
	check_eq(a[17].pos, b[17].pos, "same forest every time")
	for p in a:
		check(Vector2(p.pos.x, p.pos.z).length() >= 10.0, "spawn stays clear")


func test_avatar_builds() -> void:
	if DisplayServer.get_name() == "headless":
		return # primitive meshes need a real renderer; covered by the client smoke run
	var n := AvatarBuilder.build("Fern", 42, false)
	check(n.get_node_or_null("Skeleton") is Skeleton3D, "has its skeleton")
	check(n.get_node_or_null("Skeleton/Mesh") is MeshInstance3D, "and its one skinned mesh")
	n.free()


func test_sounds_are_synthesised() -> void:
	var w := Sfx.chime()
	check(w.data.size() > 1000, "chime has samples")


func test_palette_from_seed_is_stable() -> void:
	check_eq(Palette.from_seed(7), Palette.from_seed(7))

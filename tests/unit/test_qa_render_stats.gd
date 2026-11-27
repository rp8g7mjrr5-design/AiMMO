extends TestCase
## The client smoke test's render-stats capture (tests/client_smoke/render_stats.gd): it takes
## the worst frame, converts memory to MB, counts distinct world materials once each, and
## counts triangles per world part. The budget maths are in tests/client_smoke/test_render_budget.py.

const RenderStats := preload("res://tests/client_smoke/render_stats.gd")


func _frame(dc: int, prims: int, ms: float) -> Dictionary:
	return {"draw_calls": dc, "primitives": prims, "objects": 10, "texture_mem": 2 * 1048576,
		"video_mem": 4 * 1048576, "buffer_mem": 1048576, "frame_ms": ms}


func test_summarise_takes_worst_frame_and_median_time() -> void:
	var frames: Array[Dictionary] = [_frame(100, 5000, 10.0), _frame(140, 4000, 30.0), _frame(120, 9000, 20.0)]
	var s := RenderStats.summarise(frames)
	check_eq(s.frames, 3)
	check_eq(s.draw_calls, 140, "worst draw calls")
	check_eq(s.primitives, 9000, "worst primitives")
	check_near(s.texture_mem_mb, 2.0, 0.001, "bytes to MB")
	check_near(s.video_mem_mb, 4.0, 0.001)
	check_near(s.frame_ms_median, 20.0, 0.001, "median frame time")
	var empty: Array[Dictionary] = []
	check_eq(RenderStats.summarise(empty), {"frames": 0}, "no frames, nothing made up")


## Every mesh made here stays referenced until the test object goes: the headless test renderer
## logs "Parameter m is null" when a MeshInstance3D is freed after the last ref to its mesh.
var _keep: Array[Mesh] = []


## An ArrayMesh of `tris` triangles (the headless test renderer has no PrimitiveMesh data).
func _mesh(tris: int, mat: Material = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in tris:
		st.add_vertex(Vector3(i, 0, 0))
		st.add_vertex(Vector3(i, 1, 0))
		st.add_vertex(Vector3(i, 0, 1))
	if mat != null:
		st.set_material(mat)
	var m := st.commit()
	_keep.append(m)
	return m


func _box_with(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(12, mat)
	return mi


func test_count_materials_counts_each_once() -> void:
	var root := Node3D.new()
	var shared := StandardMaterial3D.new()
	root.add_child(_box_with(shared))
	root.add_child(_box_with(shared))
	var other := _box_with(StandardMaterial3D.new())
	root.add_child(other)
	check_eq(RenderStats.count_materials(root), 2, "two boxes share one material")
	other.material_override = shared
	check_eq(RenderStats.count_materials(root), 1, "an override hides the mesh's own material")
	var mm := MultiMeshInstance3D.new()
	mm.multimesh = MultiMesh.new()
	mm.multimesh.mesh = _mesh(2, StandardMaterial3D.new())
	root.get_child(0).add_child(mm)
	check_eq(RenderStats.count_materials(root), 2, "nested multimesh material counted")
	var hidden := Node3D.new()
	hidden.visible = false
	hidden.add_child(_box_with(StandardMaterial3D.new()))
	root.add_child(hidden)
	check_eq(RenderStats.count_materials(root), 2, "a hidden node draws nothing, so its material doesn't count")
	hidden.visible = true
	check_eq(RenderStats.count_materials(root), 3, "shown, it counts")
	root.free()


func test_triangles_by_part() -> void:
	var world := Node3D.new()
	var a := Node3D.new()
	a.name = "Big"
	var mm := MultiMeshInstance3D.new()
	mm.multimesh = MultiMesh.new()
	mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mm.multimesh.mesh = _mesh(12)
	mm.multimesh.instance_count = 10
	a.add_child(mm)
	world.add_child(a)
	var b := _box_with(null)
	b.name = "Small"
	world.add_child(b)
	world.add_child(Node3D.new()) # no geometry: left out
	check_eq(RenderStats.mesh_triangles(_mesh(12)), 12, "unindexed: vertices / 3")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.ONE]:
		st.add_vertex(v)
	for i in [0, 1, 2, 1, 3, 2]:
		st.add_index(i)
	check_eq(RenderStats.mesh_triangles(st.commit()), 2, "indexed: indices / 3")
	check_eq(RenderStats.triangles_by_part(world), [["Big", 120], ["Small", 12]], "biggest first, multimesh x instances")
	world.free()

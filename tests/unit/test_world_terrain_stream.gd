extends TestCase
## World stream: the terrain in chunks around the camera (TerrainStream), so a 3 km island
## opens at once. A small world is still built whole; a big one starts with the chunks near
## you and streams the rest on a thread, nearest first, without changing a single height.


func _verts(arrays: Array) -> PackedVector3Array:
	return arrays[Mesh.ARRAY_VERTEX]


func test_ashgrove_is_built_whole_as_before() -> void:
	WorldGen.reset()
	var t := TerrainStream.make()
	check(not t.streaming, "a 512 m world isn't streamed")
	check_eq(t.get_child_count(), 64, "every chunk, up front")
	check_eq(t.name, &"Terrain")
	check_eq((t.get_child(0) as Node).get_meta("chunk"), Vector2i(0, 0), "the first chunk is the north-west one, as before")
	check_eq((t.get_child(63) as Node).get_meta("chunk"), Vector2i(7, 7), "and the last the south-east one")
	expect_error("Parameter \"m\" is null") # freeing meshes on the headless dummy renderer
	t.free()


func test_an_island_starts_near_you_and_streams_the_rest() -> void:
	WorldGen.configure(4, 3000.0, WorldGen.ISLAND)
	var sp := WorldGen.spawn_point()
	var t0 := Time.get_ticks_msec()
	var t := TerrainStream.make()
	t.keep_arrays = true
	var ms := Time.get_ticks_msec() - t0
	check(t.streaming, "a 3 km island is streamed")
	var start := t.get_child_count()
	check(start > 4 and start < 40, "only the chunks near spawn up front (%d)" % start)
	check(ms < 3000, "the start is quick (%d ms)" % ms)
	var here := Vector2i(int((sp.x + 1500.0) / TerrainStream.SPAN), int((sp.z + 1500.0) / TerrainStream.SPAN))
	check(t.is_built(here), "the chunk you stand on is there before the first frame")
	# The thread builds the rest, nearest first, and the heights match a direct build.
	t.rethink(sp)
	var deadline := Time.get_ticks_msec() + 120000
	while t.busy() and Time.get_ticks_msec() < deadline:
		t.take_finished(64)
		OS.delay_msec(5)
	t.take_finished(100000)
	var want := t.cells_within(sp, TerrainStream.RANGE)
	var missing := 0
	for c in want:
		if not t.is_built(c):
			missing += 1
	check_eq(missing, 0, "every chunk within range got built")
	check(t.built().size() < 47 * 47, "but not the whole island (%d of %d)" % [t.built().size(), 47 * 47])
	var c: Vector2i = want[want.size() - 1]
	var mi := t.chunk_node(c)
	check(mi != null and mi.has_meta("arrays"), "the farthest chunk was streamed")
	if mi != null and mi.has_meta("arrays"):
		var direct := TerrainMesh.chunk_arrays(t.corner(c).x, t.corner(c).y)
		check(_verts(mi.get_meta("arrays")) == _verts(direct), "a streamed chunk is the same ground as a direct build")
	# Walk to the far side: the old chunks go, the new ones come.
	var far := Vector3(-sp.x, 0.0, -sp.z)
	t.rethink(far)
	t.take_finished(100000)
	check(not t.is_built(here), "chunks far behind you are dropped")
	deadline = Time.get_ticks_msec() + 120000
	while t.busy() and Time.get_ticks_msec() < deadline:
		t.take_finished(64)
		OS.delay_msec(5)
	t.take_finished(100000)
	var there: Vector2i = t.cells_within(far, 40.0)[0]
	check(t.is_built(there), "and the ground ahead of you is built")
	t.finish()
	expect_error("Parameter \"m\" is null") # freeing meshes on the headless dummy renderer
	t.free()
	WorldGen.reset()


func test_cells_within_is_nearest_first() -> void:
	WorldGen.configure(4, 1500.0, WorldGen.ISLAND)
	var t := TerrainStream.make(Vector3(0, 0, 0))
	var cells := t.cells_within(Vector3(100, 0, -50), 300.0)
	var last := -1.0
	var ok := true
	for c in cells:
		var d := (t.corner(c) + Vector2(32, 32)).distance_to(Vector2(100, -50))
		if d < last - 0.001:
			ok = false
		last = d
	check(ok and cells.size() > 50, "nearest first (%d cells)" % cells.size())
	expect_error("Parameter \"m\" is null") # freeing meshes on the headless dummy renderer
	t.free()
	WorldGen.reset()

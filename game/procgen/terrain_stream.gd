class_name TerrainStream
extends Node3D
## The terrain, built in 64 m chunks around the camera so a 3 km island opens at once (owner,
## 2026-11-26: the island map; world backlog "a generated map that loads fast").
##
## A small world (Ashgrove's 512 m is 64 chunks) is built whole, the same way and in the same
## order as before. A bigger one builds only the chunks within NEAR of where you start before
## the first frame, then works out the rest on one background thread, nearest first, out to
## RANGE (the camera's 600 m far plane plus half a chunk diagonal), and drops chunks past DROP
## as you walk away. The thread only does maths (`TerrainMesh.chunk_arrays`); the main thread
## wraps at most PER_FRAME finished chunks a frame in meshes, which is cheap.
##
## Nothing here changes a height: every chunk is TerrainMesh.build_chunk's, wherever it is
## built (unit test compares).

const SPAN := TerrainMesh.CELL * TerrainMesh.CHUNK_CELLS ## 64 m
const NEAR := 160.0 ## metres around the start built before the first frame
const RANGE := 680.0 ## chunks whose centre is within this are kept built
const DROP := 820.0 ## chunks whose centre is past this are freed
const WHOLE_MAX := 144 ## worlds of this many chunks or fewer are built whole, up front
const PER_FRAME := 4 ## finished chunks put in the world per frame
const RETHINK := 0.25 ## seconds between looks at where the camera is

var streaming := false
var focus_override: Variant = null ## a Vector3 to stream around instead of the camera (tests)
var keep_arrays := false ## tests: keep each streamed chunk's arrays as meta "arrays"
var material: Material
var _n := 0 ## chunks per side
var _half := 0.0
var _chunks := {} ## Vector2i -> MeshInstance3D, main thread only
var _wanted := {} ## Vector2i -> true: queued or being built, main thread only
var _think := 0.0

var _thread: Thread
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _queue: Array = [] ## Vector2i nearest first (under _mutex)
var _finished: Array = [] ## [Vector2i, arrays] (under _mutex)
var _stop := false
var _working := false ## the thread is on a chunk (under _mutex)


## The terrain node for the configured world, named "Terrain" as before. `start` is where the
## first chunks go (the spawn point unless told otherwise).
static func make(start: Variant = null) -> TerrainStream:
	var t := TerrainStream.new()
	t.name = "Terrain"
	t.material = TerrainMesh.material()
	t._half = WorldGen.half_size()
	t._n = int(ceil(WorldGen.size_m() / SPAN))
	if t._n * t._n <= WHOLE_MAX:
		var z := -t._half
		while z < t._half:
			var x := -t._half
			while x < t._half:
				t._add(Vector2i(int(round((x + t._half) / SPAN)), int(round((z + t._half) / SPAN))), TerrainMesh.build_chunk(x, z))
				x += SPAN
			z += SPAN
		return t
	t.streaming = true
	var at: Vector3 = start if start is Vector3 else WorldGen.spawn_point()
	for c in t.cells_within(at, NEAR):
		t._add(c, TerrainMesh.build_chunk(t.corner(c).x, t.corner(c).y))
	return t


## The world corner (x, z) of chunk `c`.
func corner(c: Vector2i) -> Vector2:
	return Vector2(-_half + c.x * SPAN, -_half + c.y * SPAN)


## Chunks whose centre lies within `r` metres of `p` (horizontally), nearest first.
func cells_within(p: Vector3, r: float) -> Array:
	var out: Array = []
	var lo_x := clampi(int(floor((p.x - r + _half) / SPAN)), 0, _n - 1)
	var hi_x := clampi(int(floor((p.x + r + _half) / SPAN)), 0, _n - 1)
	var lo_z := clampi(int(floor((p.z - r + _half) / SPAN)), 0, _n - 1)
	var hi_z := clampi(int(floor((p.z + r + _half) / SPAN)), 0, _n - 1)
	var dist := {}
	for j in range(lo_z, hi_z + 1):
		for i in range(lo_x, hi_x + 1):
			var c := Vector2i(i, j)
			var d := _centre(c).distance_to(Vector2(p.x, p.z))
			if d <= r:
				out.append(c)
				dist[c] = d
	out.sort_custom(func(a, b): return dist[a] < dist[b])
	return out


func built() -> Array:
	return _chunks.keys()


func is_built(c: Vector2i) -> bool:
	return _chunks.has(c)


func _centre(c: Vector2i) -> Vector2:
	return corner(c) + Vector2(SPAN, SPAN) * 0.5


func _add(c: Vector2i, mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.set_meta("chunk", c)
	add_child(mi)
	_chunks[c] = mi
	return mi


## The node holding chunk `c`, or null.
func chunk_node(c: Vector2i) -> MeshInstance3D:
	return _chunks.get(c)


func _focus() -> Vector3:
	if focus_override is Vector3:
		return focus_override
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		return cam.global_position
	return WorldGen.spawn_point()


func _process(delta: float) -> void:
	if not streaming:
		return
	_think -= delta
	if _think <= 0.0:
		_think = RETHINK
		rethink(_focus())
	take_finished(PER_FRAME)


## Works out which chunks should exist around `p`: frees the far ones and queues the missing
## ones, nearest first. Public so tests can drive it without a camera.
func rethink(p: Vector3) -> void:
	var here := Vector2(p.x, p.z)
	for c in _chunks.keys():
		if _centre(c).distance_to(here) > DROP:
			(_chunks[c] as Node).queue_free()
			_chunks.erase(c)
	var todo: Array = []
	for c in cells_within(p, RANGE):
		if not _chunks.has(c):
			todo.append(c)
	_mutex.lock()
	_queue = todo # nearest first; anything no longer wanted simply isn't built
	_mutex.unlock()
	_wanted.clear()
	for c in todo:
		_wanted[c] = true
	if not todo.is_empty():
		if _thread == null:
			_thread = Thread.new()
			_thread.start(_work, Thread.PRIORITY_LOW)
		_sem.post()


## Puts up to `limit` chunks the thread has finished into the world. Returns how many.
func take_finished(limit: int) -> int:
	_mutex.lock()
	var take: Array = _finished.slice(0, limit)
	_finished = _finished.slice(limit)
	_mutex.unlock()
	var added := 0
	for f in take:
		var c: Vector2i = f[0]
		if _chunks.has(c) or not _wanted.has(c):
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, f[1])
		var mi := _add(c, mesh)
		if keep_arrays:
			mi.set_meta("arrays", f[1])
		added += 1
	return added


## True while the thread still has chunks to build or hand over.
func busy() -> bool:
	_mutex.lock()
	var b := _working or not _queue.is_empty() or not _finished.is_empty()
	_mutex.unlock()
	return b


func _work() -> void:
	while true:
		_mutex.lock()
		if _stop:
			_mutex.unlock()
			return
		var c: Variant = _queue.pop_front() if not _queue.is_empty() else null
		_working = c != null
		_mutex.unlock()
		if c == null:
			_sem.wait()
			continue
		var k: Vector2i = c
		var arrays := TerrainMesh.chunk_arrays(-_half + k.x * SPAN, -_half + k.y * SPAN)
		_mutex.lock()
		_finished.append([k, arrays])
		_working = false
		_mutex.unlock()


func _exit_tree() -> void:
	finish()


## Stops the thread after the chunk it is on. Safe to call twice.
func finish() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	_sem.post()
	_thread.wait_to_finish()
	_thread = null
	_stop = false

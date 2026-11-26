class_name TravellerBodies
extends Node
## Puts the sculpted traveller (Traveller, art bible section 3) on every avatar the client
## draws, without ever building one in a frame.
##
## Sculpting a body takes about two seconds of GDScript, so it happens on one background
## thread, once per shape (`Traveller.shape_key`: build, face, hair, beard, head, layer; never
## colours). Until a shape is ready the avatar keeps the body it has (the old kit-of-parts
## traveller, or its previous sculpted body while a look is being changed), then the new mesh
## drops in on the same skeleton, so animation never stops. Finished shapes are kept in memory
## and on disk (`CACHE_DIR`), so a shape is sculpted once per install, not once per session.
##
## The disk cache is only a cache: deleting it, or a new `Traveller.VERSION`, just means the
## bodies are sculpted again. Nothing here is player data.

const CACHE_DIR := "user://travellers"

var _thread: Thread
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _queue: Array = [] ## styles waiting to be sculpted (thread reads, main writes; under _mutex)
var _finished: Array = [] ## geometry the thread has finished (under _mutex)
var _stop := false
var _queued := {} ## shape key -> true, main thread only
var _geo := {} ## shape key -> geometry, main thread only
var _waiting := {} ## shape key -> Array of [MeshInstance3D, style]
var use_disk := true ## tests turn it off


## Dresses the avatar skeleton `skel` (AvatarBuilder.skinned) in its sculpted body for
## `look`, now if its shape is ready, else as soon as the thread has sculpted it. True when
## it was dressed right away.
func dress(skel: Skeleton3D, look: Dictionary, appearance_seed: int, first: bool = false) -> bool:
	var mi := skel.get_node_or_null("Mesh") as MeshInstance3D
	if mi == null:
		return false
	var st := Traveller.style(look, appearance_seed)
	var key := Traveller.shape_key(st)
	var geo := geometry(key)
	if not geo.is_empty():
		mi.mesh = Traveller.paint(geo, st)
		mi.set_meta("traveller_key", key)
		return true
	if not _waiting.has(key):
		_waiting[key] = []
	(_waiting[key] as Array).append([mi, st])
	_enqueue(key, st, first)
	return false


## The sculpted shape for `key` if it is in memory or on disk, else {}.
func geometry(key: String) -> Dictionary:
	if _geo.has(key):
		return _geo[key]
	if use_disk:
		var geo := load_geometry(key)
		if not geo.is_empty():
			_geo[key] = geo
			return geo
	return {}


## Copies the current sculpted mesh from `old` onto the fresh skeleton `skel` (a restyle
## keeps the sculpted body on screen while the new shape is sculpted).
static func carry(old: Skeleton3D, skel: Skeleton3D) -> void:
	var a := old.get_node_or_null("Mesh") as MeshInstance3D
	var b := skel.get_node_or_null("Mesh") as MeshInstance3D
	if a != null and b != null and a.has_meta("traveller_key"):
		b.mesh = a.mesh
		b.set_meta("traveller_key", a.get_meta("traveller_key"))


## True while any shape is waiting to be sculpted.
func busy() -> bool:
	return not _waiting.is_empty()


func _enqueue(key: String, st: Dictionary, first: bool) -> void:
	if _queued.has(key):
		return
	_queued[key] = true
	_mutex.lock()
	if first:
		_queue.push_front(st) # your own body before anyone else's
	else:
		_queue.append(st)
	_mutex.unlock()
	if _thread == null:
		_thread = Thread.new()
		_thread.start(_work, Thread.PRIORITY_LOW)
	_sem.post()


func _work() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		if _stop:
			_mutex.unlock()
			return
		var st: Variant = _queue.pop_front() if not _queue.is_empty() else null
		_mutex.unlock()
		if st == null:
			continue
		var geo := Traveller.geometry(st)
		_mutex.lock()
		_finished.append(geo)
		_mutex.unlock()


func _process(_delta: float) -> void:
	_mutex.lock()
	var done := _finished
	_finished = []
	_mutex.unlock()
	for geo in done:
		var key: String = geo.key
		_geo[key] = geo
		_queued.erase(key)
		if use_disk:
			save_geometry(geo)
		for w in _waiting.get(key, []):
			var mi: MeshInstance3D = w[0]
			if is_instance_valid(mi):
				mi.mesh = Traveller.paint(geo, w[1])
				mi.set_meta("traveller_key", key)
		_waiting.erase(key)


func _exit_tree() -> void:
	finish()


## Stops the thread (after the body it is sculpting now). Safe to call twice.
func finish() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	_sem.post()
	_thread.wait_to_finish()
	_thread = null


static func cache_path(key: String) -> String:
	return "%s/%s.bin" % [CACHE_DIR, key]


static func save_geometry(geo: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open_compressed(cache_path(geo.key), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_var(geo)
	f.close()


## A body from the disk cache, or {} if it isn't there or doesn't read back whole.
static func load_geometry(key: String) -> Dictionary:
	var path := cache_path(key)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var v: Variant = f.get_var()
	f.close()
	if typeof(v) != TYPE_DICTIONARY or str((v as Dictionary).get("key", "")) != key:
		return {}
	var geo: Dictionary = v
	for k in ["verts", "normals", "regions", "bones", "weights"]:
		if not geo.has(k):
			return {}
	var n: int = (geo.verts as PackedVector3Array).size()
	if n == 0 or (geo.normals as PackedVector3Array).size() != n or (geo.regions as PackedByteArray).size() * 3 != n \
			or (geo.bones as PackedInt32Array).size() != n * 4 or (geo.weights as PackedFloat32Array).size() != n * 4:
		return {}
	return geo

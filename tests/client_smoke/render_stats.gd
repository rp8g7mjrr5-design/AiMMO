extends SceneTree
## Client smoke: what one frame of the real client costs to draw at the spawn shot (art bible,
## section 7 "Budgets", enforced by tests/client_smoke/render_budget.py).
##
##   AIMMO_TIME_OF_DAY=0.5 xvfb-run godot --rendering-driver opengl3 --path game \
##     -s tests/client_smoke/render_stats.gd -- --stats-out=/abs/noon.json \
##     --name=X --password=Y --address=127.0.0.1:PORT --autoconnect
##
## Boots the real game scene (main.tscn picks the client role from the same user args) and times
## it: the client builds the whole world synchronously in start(), so "world_build_s" is the time
## from the scene entering the tree until the world exists (it includes the UI, which is small).
## Logs in, lets the world settle at spawn like the world.png shot, then samples SAMPLE_FRAMES
## frames of the rendering monitors and counts the distinct materials in the world. Writes one
## JSON object; render_budget.py turns the noon and night ones into render_stats.json and gates
## them. Exits 1 if it could not log in or measure, 0 otherwise (the budget is judged in Python).

const LOGIN_TIMEOUT := 40.0
const SETTLE := 5.0 ## seconds after login before sampling (world.png is taken ~8 s after launch)
const SAMPLE_FRAMES := 30

var out_path := ""
var world_build_s := -1.0
var world_parts: Array[Node] = [] ## the world's children as built, so avatars added later don't count (nor walkers)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stats-out="):
			out_path = a.substr(12)
	if out_path == "":
		push_error("render_stats: pass --stats-out=/abs/file.json")
		quit(2)
		return
	var main: Node = load("res://main.tscn").instantiate()
	var t0 := Time.get_ticks_usec()
	# main._ready creates the client, whose start() builds the world before it returns; `ready`
	# fires right after (the add happens on the first frame, not inside _initialize).
	main.ready.connect(func() -> void:
		var c := _client()
		if c != null and c.get("world") != null:
			world_build_s = (Time.get_ticks_usec() - t0) / 1e6
			# Walkers (the "Zombai" node) rise near players on the server's clock, so whether one
			# stands in the shot when it is sampled is chance (the same build counts 16 or 17
			# materials depending on it). Their "carved" material is the survivors' own, which avatars
			# already leave out, so they are left out the same way.
			world_parts.assign(c.world.get_children().filter(func(n: Node) -> bool: return n.name != "Zombai")), CONNECT_ONE_SHOT)
	root.add_child(main)
	_run.call_deferred()


func _client() -> Node:
	for n in root.get_children():
		var c := n.get_node_or_null("Role")
		if c != null:
			return c
	return null


func _run() -> void:
	var client := await _wait_for_login()
	if client == null:
		print("[render] client did not log in within %.0fs" % LOGIN_TIMEOUT)
		quit(1)
		return
	await create_timer(SETTLE).timeout
	var frames: Array[Dictionary] = []
	for i in SAMPLE_FRAMES:
		await RenderingServer.frame_post_draw
		frames.append(sample())
	var stats := summarise(frames)
	stats["world_build_s"] = snappedf(world_build_s, 0.001)
	# The world as built: avatars (yours, others') differ by name and would make these flaky.
	var parts: Array = world_parts.filter(func(n: Node) -> bool: return is_instance_valid(n))
	stats["materials"] = count_materials_in(parts)
	stats["triangles_by_part"] = triangles_by_part_of(parts)
	var scene := 0
	for p in stats["triangles_by_part"]:
		scene += int(p[1])
	stats["scene_triangles"] = scene
	stats["time_of_day"] = OS.get_environment("AIMMO_TIME_OF_DAY")
	stats["viewport"] = [root.size.x, root.size.y]
	stats["renderer"] = RenderingServer.get_video_adapter_name()
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("[render] cannot write ", out_path)
		quit(1)
		return
	f.store_string(JSON.stringify(stats, "  "))
	f.close()
	print("[render] ", JSON.stringify(stats))
	quit(0)


func _wait_for_login() -> Node:
	var t := 0.0
	while t < LOGIN_TIMEOUT:
		var c := _client()
		if c != null and "logged_in" in c and c.logged_in and c.avatars.has(c.my_id):
			return c
		await process_frame
		t += root.get_process_delta_time()
	return null


## One frame's rendering monitors.
static func sample() -> Dictionary:
	return {
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"texture_mem": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"video_mem": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"buffer_mem": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
	}


## Worst frame for the counts (the budget is per frame, so the worst one is what counts), and
## memory in MB. Frame time is the median: it is only reported (CI renders in software).
static func summarise(frames: Array[Dictionary]) -> Dictionary:
	var out := {"frames": frames.size()}
	if frames.is_empty():
		return out
	for k in ["draw_calls", "primitives", "objects"]:
		var hi := 0.0
		for fr in frames:
			hi = maxf(hi, float(fr[k]))
		out[k] = int(hi)
	for k in ["texture_mem", "video_mem", "buffer_mem"]:
		var hi := 0.0
		for fr in frames:
			hi = maxf(hi, float(fr[k]))
		out[k + "_mb"] = snappedf(hi / 1048576.0, 0.01)
	var ms: Array[float] = []
	for fr in frames:
		ms.append(float(fr["frame_ms"]))
	ms.sort()
	out["frame_ms_median"] = snappedf(ms[ms.size() / 2], 0.01)
	out["fps"] = Performance.get_monitor(Performance.TIME_FPS)
	return out


## Distinct materials on everything drawn under `node` (or `nodes`) (material overrides, per-surface
## overrides and the meshes' own surface materials). Sky and environment don't count.
static func count_materials(node: Node) -> int:
	return count_materials_in([node])


static func count_materials_in(nodes: Array) -> int:
	var seen := {}
	for n in nodes:
		_collect(n, seen)
	return seen.size()


static func _collect(node: Node, seen: Dictionary) -> void:
	if node is GeometryInstance3D:
		var g := node as GeometryInstance3D
		if g.material_override != null:
			seen[g.material_override.get_instance_id()] = true
		var mesh: Mesh = null
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
			for i in (node as MeshInstance3D).get_surface_override_material_count():
				var m := (node as MeshInstance3D).get_surface_override_material(i)
				if m != null:
					seen[m.get_instance_id()] = true
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
		if mesh != null and g.material_override == null:
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m != null:
					seen[m.get_instance_id()] = true
	for c in node.get_children():
		_collect(c, seen)


## Triangles in the scene under each top-level world child (each MultiMesh counted once per
## instance), biggest first. Not what one frame draws (culling, shadows), but it tells world
## which part to slim when primitives go over budget. A list of [name, triangles].
static func triangles_by_part(world: Node) -> Array:
	return triangles_by_part_of(world.get_children())


static func triangles_by_part_of(nodes: Array) -> Array:
	var parts := []
	for c in nodes:
		var n := _triangles(c)
		if n > 0:
			parts.append([str(c.name), n])
	parts.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return parts


static func _triangles(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		n += mesh_triangles((node as MeshInstance3D).mesh)
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm.mesh != null:
			var count := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
			n += mesh_triangles(mm.mesh) * count
	for c in node.get_children():
		n += _triangles(c)
	return n


static func mesh_triangles(mesh: Mesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

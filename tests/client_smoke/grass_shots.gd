extends SceneTree
## Grass near the camera, photographed (not a test: it never fails, it only draws). Builds the
## real world (WorldBuilder) on an island, stands a survivor on open turf inland of a landing
## and shoots it from the action camera at its default arm and pitch:
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path game \
##     -s tests/client_smoke/grass_shots.gd -- --out=/abs/dir [--seed=1126] [--tag=after]
##
## Writes <tag>-settled-<time>.png (the grass after it has filled in), <tag>-turn.png (a
## quarter second after the camera swings round 180 degrees, where cells stream in) and
## <tag>-run-NN.png (frames of a 6 m/s run, one every 0.1 s, for a strip or a gif).

const W := 1600
const H := 900
const TIMES := {"noon": 0.5, "golden": 0.74}

var out := ""
var seed_v := 1126
var tag := "shot"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--seed="):
			seed_v = a.substr(7).to_int()
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	DisplayServer.window_set_size(Vector2i(W, H))
	root.size = Vector2i(W, H)
	_run.call_deferred()


## The first long open stretch of turf walking inland from a landing: where the grass is.
func _meadow() -> Array:
	var lands := WorldGen.landings()
	for lp in lands:
		var dir := (-(lp as Vector2)).normalized()
		var run := 0
		for k in 300:
			var p: Vector2 = lp + dir * (20.0 + k * 2.0)
			var h := Terrain.height(p.x, p.y)
			if Grass.growth(p.x, p.y, h, 0.0) > 0.7:
				run += 1
				if run >= 20:
					return [p - dir * 30.0, dir]
			else:
				run = 0
	return [Vector2.ZERO, Vector2(0, 1)]


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out)
	img.save_png(out.path_join("%s-%s.png" % [tag, name]))
	print("[grass_shots] saved ", tag, "-", name)


func _place(cam: Camera3D, fig: Node3D, p: Vector2, dir: Vector2) -> void:
	var feet := Vector3(p.x, Terrain.height(p.x, p.y), p.y)
	fig.position = feet
	fig.rotation.y = atan2(dir.x, dir.y)
	var fwd := Vector3(dir.x, 0.0, dir.y)
	var right := fwd.cross(Vector3.UP)
	var pivot := feet + Vector3.UP * ActionCamera.PIVOT_HEIGHT + right * ActionCamera.SHOULDER
	var look := (fwd * cos(ActionCamera.PITCH_DEFAULT) + Vector3.UP * sin(ActionCamera.PITCH_DEFAULT)).normalized()
	cam.look_at_from_position(pivot - look * ActionCamera.DIST_DEFAULT, pivot + look * 10.0, Vector3.UP)


func _run() -> void:
	WorldGen.configure(seed_v, 3000.0, WorldGen.ISLAND)
	ResourceNodes.reset()
	DayNight.pinned_fraction = 0.5
	var world := WorldBuilder.build()
	root.add_child(world)
	var m := _meadow()
	var p: Vector2 = m[0]
	var dir: Vector2 = m[1]
	print("[grass_shots] meadow at ", p, " facing ", dir)
	var fig := Node3D.new()
	var carved := "res://procgen/carved.gd"
	fig.add_child(load(carved).call("skinned", 11, {}) if ResourceLoader.exists(carved) else AvatarBuilder.skinned(11, {}))
	root.add_child(fig)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var dn: DayNight = world.get_node("DayNight")
	_place(cam, fig, p, dir)
	for t in TIMES:
		DayNight.pinned_fraction = TIMES[t]
		dn.apply(TIMES[t])
		for i in 60:
			await process_frame
		await _snap("settled-" + t)
	var mm: MultiMesh = (world.find_child("Tufts", true, false) as MultiMeshInstance3D).multimesh
	print("[grass_shots] tufts in the MultiMesh: ", mm.instance_count)
	DayNight.pinned_fraction = 0.5
	dn.apply(0.5)
	# Swing round: the grass behind you has to stream in.
	_place(cam, fig, p, -dir)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 250:
		await process_frame
	await _snap("turn")
	_place(cam, fig, p, dir)
	for i in 60:
		await process_frame
	# A run: 6 m/s, a frame saved every 0.1 s of game time (fixed steps, not wall time).
	var step := 6.0 / 30.0
	for f in 60:
		p += dir * step
		_place(cam, fig, p, dir)
		await process_frame
		if f % 3 == 2:
			await _snap("run-%02d" % (f / 3))
	quit(0)

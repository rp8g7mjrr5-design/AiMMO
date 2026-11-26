extends SceneTree
## The starting beach, photographed (not a test: it never fails, it only draws). Builds the
## real world (WorldBuilder) on an island, stands two survivors on a landing and shoots it from
## the action camera's height at noon, golden hour and night:
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path game \
##     -s tests/client_smoke/beach_shots.gd -- --out=/abs/dir [--seed=7] [--landing=0] [--tag=after]
##
## Writes <tag>-<view>-<time>.png for each view (wide: the beach from just inland; close:
## over a survivor's shoulder at the waterline) and time (noon 0.5, golden 0.74, night 0.0).

const W := 1600
const H := 900
const TIMES := {"noon": 0.5, "golden": 0.74, "night": 0.0}

var out := ""
var seed_v := 7
var landing := 0
var tag := "shot"
var only_view := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--seed="):
			seed_v = a.substr(7).to_int()
		elif a.begins_with("--landing="):
			landing = a.substr(10).to_int()
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--view="):
			only_view = a.substr(7)
	DisplayServer.window_set_size(Vector2i(W, H))
	root.size = Vector2i(W, H)
	_run.call_deferred()


## A survivor: the carved figure where that branch is in, else the current one.
func _figure(s: int) -> Node3D:
	var holder := Node3D.new()
	var carved := "res://procgen/carved.gd"
	if ResourceLoader.exists(carved):
		holder.add_child(load(carved).call("skinned", s, {}))
	else:
		holder.add_child(AvatarBuilder.skinned(s, {}))
	return holder


func _run() -> void:
	WorldGen.configure(seed_v, 3000.0, WorldGen.ISLAND)
	ResourceNodes.reset()
	DayNight.pinned_fraction = 0.5
	var world := WorldBuilder.build()
	root.add_child(world)
	var lands := WorldGen.landings()
	var lp: Vector2 = lands[clampi(landing, 0, lands.size() - 1)]
	var centre := Vector2.ZERO
	var sea := (lp - centre).normalized()
	if ResourceLoader.exists("res://shared/beach_gen.gd"):
		var info: Dictionary = load("res://shared/beach_gen.gd").call("beach", clampi(landing, 0, lands.size() - 1))
		if not info.is_empty():
			sea = info.sea
	var side := Vector2(-sea.y, sea.x)
	var ground := func(p: Vector2) -> Vector3:
		return Vector3(p.x, Terrain.height(p.x, p.y), p.y)
	var a: Vector3 = ground.call(lp + sea * 4.0 + side * 1.0)
	var b: Vector3 = ground.call(lp + sea * 5.5 - side * 1.2)
	for pair in [[a, 11], [b, 23]]:
		var f := _figure(int(pair[1]))
		f.position = pair[0]
		f.rotation.y = atan2(sea.x, sea.y) + (0.4 if pair[1] == 11 else -0.6)
		root.add_child(f)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var views := {
		"wide": [lp - sea * 16.0 + side * 6.0, 4.2, lp + sea * 30.0 - side * 4.0, 1.0],
		"close": [lp + sea * 1.0 + side * 2.6, 2.1, lp + sea * 16.0 - side * 1.0, 1.0],
		"along": [lp + sea * 8.0 + side * 26.0, 2.6, lp + sea * 6.0 - side * 10.0, 0.8],
	}
	# One view per landmark: from the landward side, a little above head height.
	if ResourceLoader.exists("res://shared/beach_gen.gd"):
		var info: Dictionary = load("res://shared/beach_gen.gd").call("beach", clampi(landing, 0, lands.size() - 1))
		for i in info.get("landmarks", []).size():
			var lm: Dictionary = info.landmarks[i]
			var c := Vector2(lm.pos.x, lm.pos.z)
			var dist := 15.0 if lm.kind in ["shipwreck", "whale_bones", "old_pier"] else 10.0
			var from2 := c - sea * dist * 0.75 + side * dist * 0.55 * (1.0 if i % 2 == 0 else -1.0)
			views["lm%d-%s" % [i, lm.kind]] = [from2, 3.2, c + sea * (6.0 if lm.kind == "old_pier" else 0.0), 0.6]
	var dn: DayNight = world.get_node("DayNight")
	for v in views:
		if only_view != "" and not (v as String).begins_with(only_view):
			continue
		var spec: Array = views[v]
		var from: Vector3 = ground.call(spec[0])
		from.y = maxf(from.y, 0.0) + float(spec[1])
		var to: Vector3 = ground.call(spec[2])
		to.y = maxf(to.y, 0.0) + float(spec[3])
		cam.look_at_from_position(from, to, Vector3.UP)
		for t in TIMES:
			DayNight.pinned_fraction = TIMES[t]
			dn.apply(TIMES[t])
			for i in 40:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(out)
			img.save_png(out.path_join("%s-%s-%s.png" % [tag, v, t]))
			print("[beach_shots] saved ", tag, "-", v, "-", t)
	quit(0)

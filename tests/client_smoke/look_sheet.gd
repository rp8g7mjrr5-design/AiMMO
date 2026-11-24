extends SceneTree
## A lineup of traveller looks (Appearance), for judging the character-creation choices by eye:
##
##   xvfb-run godot --rendering-driver opengl3 --path game -s tests/client_smoke/look_sheet.gd -- \
##     --out=/abs/file.png [--sheet=options|random|seed] [--view=front|three_q|back|close]
##
## Each figure is the real skinned traveller (AvatarBuilder.skinned) standing at rest, side by
## side under one sun. --sheet=options (default) steps one option at a time through every
## choice; random draws eight looks from Appearance.random; seed draws eight never-chosen
## travellers (their seed looks, as before customization). Not a test: it never fails, it only
## draws.

const W := 1600
const H := 720
const SPACING := 0.75

var out := ""
var sheet := "options"
var view := "three_q"
var only_key := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--sheet="):
			sheet = a.substr(8)
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--key="):
			only_key = a.substr(6)
	if out == "":
		push_error("look_sheet: pass --out=/abs/file.png")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(W, H))
	root.size = Vector2i(W, H)
	_run.call_deferred()


## [[seed, look], ...] for the sheet.
func lineup() -> Array:
	var out_l: Array = []
	match sheet:
		"random":
			var rng := RandomNumberGenerator.new()
			rng.seed = 2026
			for i in 8:
				out_l.append([1000 + i, Appearance.random(rng)])
		"seed":
			for i in 8:
				out_l.append([hash("traveller%d" % i) & 0x7FFFFFFF, {}])
		_:
			var key := only_key if only_key != "" else "hair"
			var base := Appearance.DEFAULT.duplicate()
			base.tunic = 2
			for i in Appearance.count(key):
				var lk := base.duplicate()
				lk[key] = i
				out_l.append([7, lk])
	return out_l


func _run() -> void:
	Emberlight.ensure_globals()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.64, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.55
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(40, 40)
	ground.mesh = gm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.43, 0.34)
	ground.material_override = mat
	root.add_child(ground)
	var figures := lineup()
	var n := figures.size()
	for i in n:
		var sk := AvatarBuilder.skinned(int(figures[i][0]), figures[i][1])
		var holder := Node3D.new()
		holder.position = Vector3((i - (n - 1) * 0.5) * SPACING, 0, 0)
		match view:
			"three_q":
				holder.rotation.y = 0.5
			"back":
				holder.rotation.y = PI
			"side":
				holder.rotation.y = PI * 0.5
		holder.add_child(sk)
		root.add_child(holder)
	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	var width := n * SPACING
	if view == "close":
		cam.fov = 18.0
		cam.look_at_from_position(Vector3(0, 1.62, width * 1.35 + 1.0), Vector3(0, 1.6, 0), Vector3.UP)
	else:
		cam.look_at_from_position(Vector3(0, 1.3, width * 1.25 + 1.5), Vector3(0, 0.92, 0), Vector3.UP)
	for i in 8:
		await process_frame
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	quit(0)

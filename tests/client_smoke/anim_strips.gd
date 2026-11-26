extends SceneTree
## Frame strips and clips of every traveller animation, for judging the motion by eye:
##
##   xvfb-run godot --rendering-driver opengl3 --path game -s tests/client_smoke/anim_strips.gd -- \
##     --out=/abs/dir [--clips=walk,run] [--view=side|three_q|back] [--fps=30] [--seed=N|--mannequin]
##
## For each clip it drives a real AvatarAnimator (the same state machine the client runs) on
## the real skinned traveller (AvatarBuilder.skinned, appearance seed --seed, default 7), or
## the plain preview mannequin with --mannequin, and writes
## <out>/<clip>/<frame>.png at --fps plus <out>/<clip>-strip.png, eight frames side by side.
## The mannequin walks over a striped floor that moves with it, so a planted foot that slides
## shows against the stripes. Not a test: it never fails, it only draws.

const W := 480
const H := 540
const STRIP_FRAMES := 8

## clip -> [seconds, label]
const CLIPS := {
	"idle": [3.0, "Idle"],
	"walk": [1.6, "Walk 1.5 m/s"],
	"run": [1.5, "Run 6 m/s"],
	"walk_to_run": [3.0, "Walk to run and stop"],
	"backpedal": [1.6, "Backpedal (S): a walk, never a run"],
	"strafe": [1.6, "Strafe (D): hips to the travel"],
	"chop": [1.6, "Chop (ash, pine)"],
	"mine": [2.0, "Mine (stone)"],
	"collect": [2.8, "Collect (ember sap)"],
	"craft": [1.9, "Craft at the bench"],
	"swing_light": [0.75, "Light swing (jab)"],
	"swing_heavy": [1.35, "Heavy swing (haymaker)"],
	"swing_run": [1.2, "Jab while running"],
	"jump": [1.45, "Jump"],
	"knockdown": [3.2, "Knocked down, getting up"],
	"sit": [3.4, "Sit, rest, stand"],
}

var out_dir := ""
var view := "side"
var fps := 30
var only: Array = []
var appearance_seed := 7
var mannequin := false

var rig: Node3D
var skel: Skeleton3D
var floor_node: Node3D
var cam: Camera3D
var anim: AvatarAnimator


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--fps="):
			fps = int(a.substr(6))
		elif a.begins_with("--seed="):
			appearance_seed = int(a.substr(7))
		elif a == "--mannequin":
			mannequin = true
		elif a.begins_with("--clips="):
			only = Array(a.substr(8).split(","))
	if out_dir == "":
		push_error("anim_strips: pass --out=/abs/dir")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(W, H))
	root.size = Vector2i(W, H)
	_scene()
	_run.call_deferred()


func _scene() -> void:
	Emberlight.ensure_globals()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.72, 0.74, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.55
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.7, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	root.add_child(sun)
	floor_node = Node3D.new()
	root.add_child(floor_node)
	# A checker, so a foot sliding either way (a strafe too) shows against it.
	var m := BoxMesh.new()
	m.size = Vector3(0.25, 0.02, 0.25)
	var mats: Array = []
	for c in [Color(0.42, 0.45, 0.36), Color(0.5, 0.53, 0.43)]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mats.append(mat)
	for i in range(-30, 31):
		for j in range(-12, 13):
			var tile := MeshInstance3D.new()
			tile.mesh = m
			tile.material_override = mats[posmod(i + j, 2)]
			tile.position = Vector3(j * 0.25, -0.01, i * 0.25)
			floor_node.add_child(tile)
	rig = Node3D.new()
	root.add_child(rig)
	skel = AvatarSkeleton.rigged(AvatarSkeleton.mannequin_groups()) if mannequin else AvatarBuilder.skinned(appearance_seed)
	rig.add_child(skel)
	cam = Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	_place_camera()


func _place_camera() -> void:
	var target := Vector3(0, 0.85, 0)
	var from: Vector3
	match view:
		"three_q":
			from = Vector3(3.4, 1.6, 3.4)
		"back":
			from = Vector3(0.9, 1.9, -4.2)
		_:
			from = Vector3(5.0, 1.0, 0.0)
	cam.look_at_from_position(from, target, Vector3.UP)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	for clip in CLIPS:
		if not only.is_empty() and not clip in only:
			continue
		await _render(clip)
	quit(0)


## Drives the clip for one frame at time t: returns the ctx for AvatarAnimator.step and fires
## events. `travel` is how far the body has moved along +z so far.
func _drive(clip: String, t: float, dt: float, state: Dictionary) -> Dictionary:
	var v := 0.0
	var dir := Vector3(0, 0, 1) # facing +z; the line of travel
	match clip:
		"walk":
			v = 1.5
		"run", "swing_run":
			v = 6.0
		"walk_to_run":
			v = 1.5 if t < 1.0 else (6.0 if t < 2.3 else 0.0)
		"backpedal": # holding S: the server's cap (Movement.BACK_SPEED)
			v = GameConfig.WALK_SPEED * Movement.BACK_SPEED
			dir = Vector3(0, 0, -1)
		"strafe": # holding D
			v = GameConfig.WALK_SPEED * Movement.SIDE_SPEED
			dir = Vector3(-1, 0, 0)
	var ctx := {}
	match clip:
		"chop":
			ctx.gather = {"kind": "ash", "pos": Vector3(0, 0, 1.2)}
		"mine":
			ctx.gather = {"kind": "stone", "pos": Vector3(0, 0, 1.2)}
		"collect":
			ctx.gather = {"kind": "scrub", "pos": Vector3(0, 0, 1.0)}
		"craft":
			if not state.has("fired"):
				anim.craft()
				state.fired = true
		"swing_light":
			if t >= 0.1 and not state.has("fired"):
				anim.swing("light", 0.12, 0.10, 0.22) # Weapons bare-hand light (PR 180)
				state.fired = true
		"swing_heavy":
			if t >= 0.1 and not state.has("fired"):
				anim.swing("heavy", 0.40, 0.12, 0.40) # Weapons bare-hand heavy
				state.fired = true
		"swing_run":
			if t >= 0.4 and not state.has("fired"):
				anim.swing("light", 0.12, 0.10, 0.22)
				state.fired = true
		"jump":
			# What a server jump would send: a ballistic arc after the take-off dip.
			if t >= 0.1 and not state.has("fired"):
				anim.jump()
				state.fired = true
				state.lift = t + AvatarClips.TAKEOFF
			if state.has("lift") and t >= state.lift:
				var ta: float = t - state.lift
				var vy0 := 5.0
				var g := 15.0
				ctx.height = maxf(vy0 * ta - 0.5 * g * ta * ta, 0.0)
				v = 2.0
		"knockdown":
			if t >= 0.15 and not state.has("fired"):
				anim.knock_down()
				state.fired = true
			if t >= 1.65 and not state.has("up"):
				anim.get_up()
				state.up = true
		"sit":
			if t >= 0.1 and not state.has("fired"):
				anim.sit()
				state.fired = true
			if t >= 2.5 and not state.has("up"):
				anim.stand()
				state.up = true
	state.travel = (state.get("travel", Vector3.ZERO) as Vector3) + dir * v * dt
	ctx.pos = state.travel
	ctx.yaw = 0.0
	return ctx


func _render(clip: String) -> void:
	anim = AvatarAnimator.new()
	var seconds: float = CLIPS[clip][0]
	var dt := 1.0 / float(fps)
	var state := {}
	# Moving clips start already up to speed: a second of the same motion, unrendered.
	if clip in ["walk", "run", "swing_run", "backpedal", "strafe"]:
		var pre := {"fired": true}
		for i in fps:
			anim.step(dt, _drive(clip, 0.0, dt, pre))
		state.travel = pre.travel
	else:
		for i in 10:
			anim.step(dt, {"pos": Vector3.ZERO})
	var dir := out_dir.path_join(clip)
	DirAccess.make_dir_recursive_absolute(dir)
	var frames := int(ceil(seconds * fps))
	var strip := Image.create(W * STRIP_FRAMES, H, false, Image.FORMAT_RGB8)
	var every := maxi(frames / STRIP_FRAMES, 1)
	var placed := 0
	for i in frames:
		var ctx := _drive(clip, i * dt, dt, state)
		anim.step(dt, ctx)
		anim.apply(skel)
		var pos: Vector3 = ctx.pos
		var h: float = ctx.get("height", 0.0)
		rig.position = Vector3(0, h, 0)
		# The camera follows the body; the floor slides back under it by the distance walked.
		floor_node.position = Vector3(-fposmod(pos.x, 0.5), 0, -fposmod(pos.z, 0.5))
		await process_frame
		await process_frame
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		if img.get_size() != Vector2i(W, H): # a window manager that ignored the size: keep the middle
			img = img.get_region(Rect2i((img.get_width() - W) / 2, (img.get_height() - H) / 2, W, H))
		img.save_png(dir.path_join("%03d.png" % i))
		if i % every == 0 and placed < STRIP_FRAMES:
			strip.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(placed * W, 0))
			placed += 1
	strip.save_png(out_dir.path_join("%s-strip.png" % clip))
	print("anim_strips: %s, %d frames" % [clip, frames])

extends SceneTree
## Client smoke: screenshots from the over-the-shoulder action camera, with checks on the real
## rendered client (design bible, "Owner directions → 2. The camera").
##
##   xvfb-run godot --rendering-driver opengl3 --path game -s tests/client_smoke/camera_shots.gd -- \
##     --name=X --password=Y --address=127.0.0.1:PORT --autoconnect --shots=/abs/dir
##
## Boots the real game scene (main.tscn picks the client role from the same user args), logs in,
## then takes two pictures:
## - camera.png: the camera as it is after login. The reticle is shown at the exact centre of
##   the screen and your character stands left of centre (the camera sits over the right
##   shoulder), in front of the camera.
## - camera-hill.png: the character walks (real WASD input, server-moved) to the foot of the
##   steepest slope within HILL_SEARCH metres of spawn, then the camera is turned to back onto
##   that rise, looking up and zoomed all the way out, which even on flat ground would put a
##   6 m arm about 2.6 m under the turf. The arm must have pulled in, and the camera (and a ring around it as wide
##   as the near plane) must still be above the ground.
## Exits 1 with every problem printed, 0 when both shots look right. The ActionCamera maths are
## unit tested and run on real positions in the bot test (client_action_camera); this checks
## the real client wires it to the rendered Camera3D and reticle.

const Stats := preload("res://tests/client_smoke/image_stats.gd")

const LOGIN_TIMEOUT := 40.0
const SETTLE := 2.5 ## seconds for the pivot and arm to ease into place before a shot
const MIN_LEFT_PX := 20.0 ## the character must be at least this far left of centre
const GROUND_MARGIN := 0.05 ## metres the camera must stay above the ground
const HILL_SEARCH := 30.0 ## metres around spawn searched for the steepest slope
const WALK_TIMEOUT := 20.0

var problems: Array[String] = []
var shots := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	if shots == "":
		push_error("camera_shots: pass --shots=/abs/dir")
		quit(2)
		return
	root.add_child(load("res://main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	var client: Node = await _wait_for_login()
	if client == null:
		_finish()
		return
	await _wait(SETTLE)
	await _shot_default(client)
	await _walk_to(client, steepest_spot(_feet(client)))
	await _shot_hill(client)
	_finish()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_for_login() -> Node:
	var t := 0.0
	while t < LOGIN_TIMEOUT:
		var c := root.get_node_or_null("Main/Role")
		if c == null:
			for n in root.get_children():
				c = n.get_node_or_null("Role")
				if c != null:
					break
		if c != null and "logged_in" in c and c.logged_in and c.avatars.has(c.my_id):
			return c
		await process_frame
		t += root.get_process_delta_time()
	problems.append("client did not log in within %.0fs" % LOGIN_TIMEOUT)
	return null


func _save(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := shots.path_join(name)
	img.save_png(path)
	print("[camera] saved ", path)
	return img


func _feet(client: Node) -> Vector3:
	return (client.avatars[client.my_id].node as Node3D).global_position


## Picture 1: the camera as players first see it.
func _shot_default(client: Node) -> void:
	var img := await _save("camera.png")
	var cam3d: Camera3D = client.camera
	var size := Vector2(img.get_width(), img.get_height())
	var reticle: Control = client.reticle
	if not reticle.is_visible_in_tree():
		problems.append("camera.png: the reticle is hidden while playing")
	var centre := reticle.get_global_rect().get_center()
	if centre.distance_to(size * 0.5) > 2.0:
		problems.append("camera.png: the reticle is at %s, not the screen centre %s" % [centre, size * 0.5])
	var chest := _feet(client) + Vector3.UP * 1.0
	if cam3d.is_position_behind(chest):
		problems.append("camera.png: your character is behind the camera")
	else:
		var p := cam3d.unproject_position(chest)
		print("[camera] character at %.0f, %.0f on a %dx%d screen" % [p.x, p.y, size.x, size.y])
		if p.x > size.x * 0.5 - MIN_LEFT_PX:
			problems.append("camera.png: your character is not left of centre (x %.0f, centre %.0f)" % [p.x, size.x * 0.5])
		if p.x < 0.0 or p.y < 0.0 or p.y > size.y:
			problems.append("camera.png: your character is off screen (%.0f, %.0f)" % [p.x, p.y])
	_check_above_ground("camera.png", cam3d)
	var lum := Stats.mean_luminance(img)
	if lum < Stats.MIN_DAY:
		problems.append("camera.png: too dark (%.3f): did the world render?" % lum)


## The foot of the steepest dry slope near `from`: the spot whose ground rises most within 6 m
## behind it (see uphill_yaw), searched on a 2 m grid.
static func steepest_spot(from: Vector3) -> Vector3:
	var best := from
	var best_rise := -INF
	var water := Terrain.water_level()
	var r := int(HILL_SEARCH / 2.0)
	for i in range(-r, r + 1):
		for j in range(-r, r + 1):
			var x := from.x + i * 2.0
			var z := from.z + j * 2.0
			var h := Terrain.height(x, z)
			if h < water + 0.3:
				continue
			var p := Vector3(x, h, z)
			var rise := _rise_behind(p, uphill_yaw(p))
			if rise > best_rise:
				best_rise = rise
				best = p
	return best


static func _rise_behind(feet: Vector3, y: float) -> float:
	var back := -ActionCamera.forward(y)
	var rise := -INF
	for d in [1.5, 3.0, 4.5, 6.0]:
		var p: Vector3 = feet + back * d
		rise = maxf(rise, Terrain.height(p.x, p.z) - feet.y)
	return rise


## Walks the character to `target` with real input: the camera faces it and W is held, so the
## client sends camera-relative moves and the server moves the character.
func _walk_to(client: Node, target: Vector3) -> void:
	var cam: ActionCamera = client.cam
	print("[camera] walking from %s to the slope at %s" % [_feet(client), target])
	var t := 0.0
	while t < WALK_TIMEOUT:
		var d := target - _feet(client)
		d.y = 0.0
		if d.length() < 1.0:
			break
		cam.yaw = atan2(-d.x, -d.z)
		cam.heading = cam.yaw
		Input.action_press("move_forward")
		await process_frame
		t += root.get_process_delta_time()
	Input.action_release("move_forward")
	await _wait(1.0)
	var left := Vector2(target.x - _feet(client).x, target.z - _feet(client).z).length()
	print("[camera] stopped %.1f m from the slope after %.1fs" % [left, t])


## The yaw whose camera arm points up the steepest rise behind the character.
static func uphill_yaw(feet: Vector3) -> float:
	var best_yaw := 0.0
	var best_rise := -INF
	for i in 24:
		var y := TAU * i / 24.0
		var rise := _rise_behind(feet, y)
		if rise > best_rise:
			best_rise = rise
			best_yaw = y
	return wrapf(best_yaw, -PI, PI)


## Picture 2: backed against the hill, looking up, zoomed out: the worst case for clipping.
func _shot_hill(client: Node) -> void:
	var cam: ActionCamera = client.cam
	var feet := _feet(client)
	cam.yaw = uphill_yaw(feet)
	cam.heading = cam.yaw
	cam.pitch = ActionCamera.PITCH_MAX
	cam.distance = ActionCamera.DIST_MAX
	await _wait(SETTLE)
	var img := await _save("camera-hill.png")
	var cam3d: Camera3D = client.camera
	print("[camera] hill shot: ground rises %.2f m within 6 m behind; yaw %.2f, pitch %.2f, arm %.2f of %.2f, camera at %s, ground %.2f" % [
		_rise_behind(feet, cam.yaw), cam.yaw, cam.pitch, cam.arm, cam.distance, cam3d.global_position,
		Terrain.height(cam3d.global_position.x, cam3d.global_position.z)])
	if cam.arm > cam.distance - 0.5:
		problems.append("camera-hill.png: the arm did not pull in (%.2f of %.2f), so this shot proves nothing" % [cam.arm, cam.distance])
	_check_above_ground("camera-hill.png", cam3d)
	if cam3d.is_position_behind(_feet(client) + Vector3.UP * 1.0):
		problems.append("camera-hill.png: your character is behind the camera")
	if Stats.mean_luminance(img) < 0.02:
		problems.append("camera-hill.png: the picture is black (camera inside the ground?)")


## The camera and a ring around it as wide as the near plane's corners must be above ground.
func _check_above_ground(label: String, cam3d: Camera3D) -> void:
	var c := cam3d.global_position
	var r := cam3d.near * 2.0
	for i in 9:
		var p := c
		if i > 0:
			var a := TAU * (i - 1) / 8.0
			p += Vector3(cos(a), 0.0, sin(a)) * r
		var h := Terrain.height(p.x, p.z)
		if c.y < h + GROUND_MARGIN:
			problems.append("%s: the camera is in the ground (camera y %.2f, ground %.2f at %.2f, %.2f)" % [label, c.y, h, p.x, p.z])
			return


func _finish() -> void:
	if problems.is_empty():
		print("[camera] camera shots passed")
		quit(0)
	else:
		for p in problems:
			print("[camera] FAIL ", p)
		quit(1)

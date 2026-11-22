extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the over-the-shoulder action camera on real server positions. Each bot runs the
## client's ActionCamera every frame behind its real position, over real terrain and real
## resource node props, while sweeping the mouse (yaw and pitch, zoom and shoulder swaps).
## Checks: the camera never ends up under the ground or inside a tree or rock, the arm stays
## within its limits, W from the camera walks the way the camera looks, and the look-to-
## interact target is always a node in reach.

const Cam := preload("res://client/action_camera.gd")
const PromptScript := preload("res://client/gather_prompt.gd")

var _cam: RefCounted
var _height := Callable(Terrain, "height")
var frames := 0
var pulled_in := 0
var min_arm := INF
var aimed := 0
var swaps := 0
var _t := 0.0


func setup(_net: Node) -> void:
	_cam = Cam.new()


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_cam.place(Vector3(character.x, character.y, character.z), float(character.yaw) + PI)


func on_play(delta: float) -> void:
	if not bot.have_pos or delta <= 0.0:
		return
	_t += delta
	# A deterministic "mouse": slow sweeps left and right, nodding up and down.
	_cam.turn(Vector2(sin(_t * 0.7) * 1.2 * delta, cos(_t * 0.45) * 0.9 * delta))
	if int(_t * 0.2) % 2 == 0:
		_cam.zoom(1.0 * delta * 3.0)
	else:
		_cam.zoom(-1.0 * delta * 3.0)
	if int(_t / 20.0) != int((_t - delta) / 20.0):
		_cam.swap_shoulder()
		swaps += 1
	var feet: Vector3 = bot.my_pos
	var props := ResourceNodes.near(feet, Cam.DIST_MAX + 3.0)
	var xf: Transform3D = _cam.step(feet, delta, _height, props)
	frames += 1
	var p := xf.origin
	var ground: float = _height.call(p.x, p.z)
	if p.y < ground + Cam.CLEARANCE * 0.5 - 0.001:
		fail("camera %.2f m under the ground at %s" % [ground - p.y, p])
	if _cam.arm < Cam.ARM_MIN - 0.001 or _cam.arm > Cam.DIST_MAX + 0.001:
		fail("arm %.2f out of limits" % _cam.arm)
	if _cam.arm < _cam.distance - 0.05:
		pulled_in += 1
	min_arm = minf(min_arm, _cam.arm)
	# The arm is checked against where the pivot is; the pivot trails the feet a little, so check
	# props against the same pivot the camera used.
	for n in props:
		if Cam.inside_prop(p, n, 0.0):
			fail("camera inside %s node %d" % [n.kind, n.id])
	var w: Vector2 = Cam.move_vector(1.0, 0.0, _cam.move_yaw())
	var f: Vector3 = Cam.forward(_cam.yaw)
	if w.distance_to(Vector2(f.x, f.z)) > 0.001:
		fail("W does not walk where the camera looks")
	var t: Dictionary = PromptScript.target(feet, WorldClock.now_seconds(), p, -xf.basis.z)
	if not t.is_empty():
		aimed += 1
		if not ResourceNodes.in_range(int(t.id), feet):
			fail("look-to-interact picked node %d out of reach" % int(t.id))


func on_finish() -> void:
	stat("frames", frames)
	stat("pulled_in_frames", pulled_in)
	stat("min_arm", snappedf(min_arm, 0.01) if min_arm < INF else -1.0)
	stat("target_frames", aimed)
	stat("shoulder_swaps", swaps)
	if bot.elapsed > 60.0 and frames == 0:
		fail("camera never ran")

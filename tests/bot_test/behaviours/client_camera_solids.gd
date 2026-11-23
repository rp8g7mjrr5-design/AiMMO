extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the action camera keeps out of decoration. Every second the bot looks round in 8
## directions from where it stands with exactly what the client's camera uses
## (`ActionCamera.camera_solids`: resource nodes plus world's decorative trees, rocks,
## birches, boulders, lanterns and workbench) and fails if the camera would end inside any of
## them. Looks pinned at ARM_MIN are skipped (the bot stands inside a footprint there).

const Cam := preload("res://client/action_camera.gd")
const YAWS := 8

var looks := 0
var pulled_in := 0
var deco_seen := 0
var _since := 0.0


func on_play(delta: float) -> void:
	_since += delta
	if _since < 1.0 or not bot.have_pos:
		return
	_since = 0.0
	var me: Vector3 = bot.my_pos
	var solids := Cam.camera_solids(me)
	for s in solids:
		if s.get("kind", "") == WorldSolids.KIND:
			deco_seen += 1
	var height := Callable(Terrain, "height")
	for i in YAWS:
		var yaw := TAU * i / YAWS
		looks += 1
		var shoulder := Cam.shoulder_point(me, yaw, 1.0)
		var arm := Cam.clear_arm(shoulder, yaw, Cam.PITCH_DEFAULT, Cam.DIST_DEFAULT, height, solids)
		if arm < Cam.DIST_DEFAULT:
			pulled_in += 1
		if arm <= Cam.ARM_MIN:
			continue
		var cam := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, arm)
		for s in solids:
			if NodeProps.inside_solid(cam, s):
				fail("camera at %s ended inside %s at %s" % [cam, s.get("source", s.kind), s.pos])
				return


func on_finish() -> void:
	stat("looks", looks)
	stat("pulled_in", pulled_in)
	stat("deco_seen", deco_seen)
	if looks < 8:
		fail("only %d camera looks" % looks)

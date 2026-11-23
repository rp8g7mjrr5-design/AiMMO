extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): camera clearance for decoration.
##
## Every second the bot looks round in 8 directions from where it stands, the way the
## over-the-shoulder camera would, using the client's own ActionCamera.clear_arm twice:
## once with only the resource nodes (what the client passes today) and once with the
## nodes plus WorldSolids.near() (decorative trees, rocks, birches, boulders, lanterns and the
## workbench). With decoration the camera must never end inside any solid; without it, the
## stat `camera_inside_decoration_nodes_only` counts how often it would, which is the bug the
## client fixes by passing WorldSolids.near() too. Looks where the arm is already at ARM_MIN
## are skipped (the bot itself stands inside a footprint and no arm could clear it).

const Cam := preload("res://client/action_camera.gd")
const YAWS := 8

var looks := 0
var inside_nodes_only := 0
var arm_shorter := 0
var sources := {}
var _since := 0.0


func on_play(delta: float) -> void:
	_since += delta
	if _since < 1.0:
		return
	_since = 0.0
	var me: Vector3 = bot.my_pos
	var nodes := ResourceNodes.near(me, Cam.DIST_MAX + 3.0)
	var deco := WorldSolids.near(me, Cam.DIST_MAX + 3.0)
	for s in deco:
		sources[s.source] = true
		if s.kind != WorldSolids.KIND or s.columns.is_empty():
			fail("decoration solid at %s has no columns" % s.pos)
			return
	var both := nodes + deco
	var height := Callable(Terrain, "height")
	for i in YAWS:
		var yaw := TAU * i / YAWS
		looks += 1
		var shoulder := Cam.shoulder_point(me, yaw, 1.0)
		var old_arm := Cam.clear_arm(shoulder, yaw, Cam.PITCH_DEFAULT, Cam.DIST_DEFAULT, height, nodes)
		if old_arm > Cam.ARM_MIN:
			var old_cam := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, old_arm)
			for s in deco:
				if WorldSolids.inside(old_cam, s):
					inside_nodes_only += 1
					break
		var arm := Cam.clear_arm(shoulder, yaw, Cam.PITCH_DEFAULT, Cam.DIST_DEFAULT, height, both)
		if arm > old_arm + 0.0001:
			fail("adding decoration made the arm longer (%.2f > %.2f)" % [arm, old_arm])
		if arm < old_arm:
			arm_shorter += 1
		if arm > Cam.ARM_MIN:
			var cam := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, arm)
			for s in both:
				if NodeProps.inside_solid(cam, s):
					fail("camera at %s is inside %s at %s" % [cam, s.get("source", s.kind), s.pos])
					return


func on_finish() -> void:
	stat("deco_looks", looks)
	stat("deco_sources_seen", sources.size())
	stat("camera_inside_decoration_nodes_only", inside_nodes_only)
	stat("deco_arm_pulled_in", arm_shorter)
	if looks == 0:
		fail("never looked round")

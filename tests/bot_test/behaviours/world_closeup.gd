extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): the close-up read behind the action camera.
##
## Every second the bot looks round in 8 directions from where it stands, the way the
## over-the-shoulder camera would, and checks the resource nodes nearby: each one's
## close-up detail (root flares, bark ridges, seam studs) is there and inside the node's
## solid columns, and a camera arm pulled in against NodeProps.inside_solid() never ends
## inside a prop. It also counts how often the client's real camera arm
## (ActionCamera.clear_arm, which now uses the same shared NodeProps.inside_solid columns)
## still leaves the camera inside a mesh; that stat should read 0. Looks where the arm is
## already pulled all the way in to ARM_MIN are skipped, because then the bot itself stands
## inside a prop's footprint and no arm length could clear it. Every joining player's
## avatar must carry its pack and bedroll on its back.

const Cam := preload("res://client/action_camera.gd")
const YAWS := 8

var looks := 0
var nodes_seen := {}
var detail_checked := 0
var inside_with_client_columns := 0
var packs := 0
var _since := 0.0


func setup(net: Node) -> void:
	net.player_joined.connect(_on_player_joined)


func _on_player_joined(_id: int, player_name: String, appearance_seed: int) -> void:
	var back := AvatarBuilder.parts(appearance_seed).filter(func(p): return p.limb == "" and p.pos.z < -0.2)
	if back.size() != 2:
		fail("%s's avatar has %d parts on its back, want pack and bedroll" % [player_name, back.size()])
	else:
		packs += 1


func on_play(delta: float) -> void:
	_since += delta
	if _since < 1.0:
		return
	_since = 0.0
	var me: Vector3 = bot.my_pos
	var near := ResourceNodes.near(me, Cam.DIST_MAX + 3.0)
	for n in near:
		if nodes_seen.has(n.id):
			continue
		nodes_seen[n.id] = true
		for p in NodeProps.parts(n):
			if p.layer != NodeProps.DETAIL_LAYER:
				continue
			detail_checked += 1
			if not NodeProps.inside_solid(p.xform.origin, n, 0.01):
				fail("node %d detail at %s is outside its solid columns" % [n.id, p.xform.origin])
		var want := {"ash": 7, "pine": 7, "stone": 6, "ember_sap": 0}
		var got := NodeProps.parts(n).filter(func(p): return p.layer == NodeProps.DETAIL_LAYER).size()
		if got != want[n.kind]:
			fail("%s node %d has %d detail parts, want %d" % [n.kind, n.id, got, want[n.kind]])
	for i in YAWS:
		var yaw := TAU * i / YAWS
		looks += 1
		var shoulder := Cam.shoulder_point(me, yaw, 1.0)
		var client_arm := Cam.clear_arm(shoulder, yaw, Cam.PITCH_DEFAULT, Cam.DIST_DEFAULT, Callable(Terrain, "height"), near)
		var cam := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, client_arm)
		if client_arm > Cam.ARM_MIN:
			for n in near:
				if NodeProps.inside_solid(cam, n):
					inside_with_client_columns += 1
					break
		var arm := _world_arm(shoulder, yaw, near)
		var safe := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, arm)
		if arm > Cam.ARM_MIN:
			for n in near:
				if NodeProps.inside_solid(safe, n):
					fail("camera at %s is inside %s node %d" % [safe, n.kind, n.id])


## The longest arm (in Cam.ARM_SAMPLE steps, up to the default) whose camera stays
## Cam.CLEARANCE away from every node's solid columns.
func _world_arm(shoulder: Vector3, yaw: float, near: Array) -> float:
	var t := Cam.ARM_SAMPLE
	while t <= Cam.DIST_DEFAULT + 0.0001:
		var p := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, t)
		for n in near:
			if NodeProps.inside_solid(p, n, Cam.CLEARANCE):
				return maxf(Cam.ARM_MIN, t - Cam.ARM_SAMPLE)
		t += Cam.ARM_SAMPLE
	return Cam.DIST_DEFAULT


func on_finish() -> void:
	stat("closeup_looks", looks)
	stat("closeup_nodes_seen", nodes_seen.size())
	stat("closeup_detail_parts_checked", detail_checked)
	stat("camera_inside_mesh_with_client_columns", inside_with_client_columns)
	stat("avatar_packs_checked", packs)
	if looks == 0:
		fail("never looked round")
	if packs == 0:
		fail("never saw a player join, so no pack was checked")

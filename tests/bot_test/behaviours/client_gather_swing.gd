extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the gather swing on a real server. Each bot keeps a GatherWatch and a GatherSwing
## per avatar it sees (itself included) exactly as client.gd does: positions and yaws from
## snapshots, gathers from the v3 s2c_gather_begin/end events, and a real avatar rig posed by
## WalkAnim then GatherSwing every frame.
##
## It sends nothing (gameplay_gather_v3.gd presses E on this bot). It checks that:
## - during a gather of a few seconds, the avatar ends up facing the node and its arms move;
## - after every gather ends, the swing has fully blended out within a second and a half;
## - no pose is ever NaN or out of range.

const WatchScript := preload("res://client/gather_watch.gd")
const SwingScript := preload("res://client/gather_swing.gd")
const WalkScript := preload("res://client/walk_anim.gd")
const ClientScript := preload("res://client/client.gd")
const FACE_TOLERANCE := 0.35 ## radians
const SETTLE_AFTER := 0.5    ## seconds into a gather before facing is checked
const BLEND_OUT_MAX := 1.5   ## seconds after an end by which the swing is gone

var _watch: RefCounted
var _av := {} ## peer id -> {pos, yaw, walk, swing, rig, since, lo, hi, ended_at}
var swing_frames := 0
var faced_frames := 0
var unfaced_frames := 0
var strokes_seen := 0
var blend_outs := 0
var others_swung := 0


func setup(net: Node) -> void:
	_watch = WatchScript.new()
	net.gather_begun.connect(_on_begun)
	net.gather_ended.connect(_on_ended)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_watch.reset()
	for id in _av:
		_av[id].rig.free()
	_av.clear() # peer ids change across reconnects


func _avatar(id: int) -> Dictionary:
	if not _av.has(id):
		_av[id] = {"pos": Vector3.ZERO, "yaw": 0.0, "walk": WalkScript.new(), "swing": SwingScript.new(),
			"rig": ClientScript.wrap_avatar(AvatarBuilder.rig()), "since": -1.0, "lo": 0.0, "hi": -PI, "ended_at": -1.0, "seen": false}
	return _av[id]


func _on_begun(peer: int, node_id: int, _seconds: float) -> void:
	_watch.begun(peer, node_id)
	var a := _avatar(peer)
	a.since = bot.elapsed
	a.lo = 0.0
	a.hi = -PI
	a.ended_at = -1.0


func _on_ended(peer: int, node_id: int, _reason: String) -> void:
	_watch.ended(peer, node_id, _reason)
	if _av.has(peer):
		var a: Dictionary = _av[peer]
		if a.since >= 0.0 and bot.elapsed - a.since > 0.6 and a.hi - a.lo > 0.8:
			strokes_seen += 1
			if peer != bot.my_id:
				others_swung += 1
		a.since = -1.0
		a.ended_at = bot.elapsed


func on_snapshot(_tick: int, entries: Array) -> void:
	var i := 0
	while i + 4 < entries.size():
		var a := _avatar(int(entries[i]))
		a.pos = Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
		a.yaw = float(entries[i + 4])
		a.seen = true
		i += 5


func on_play(delta: float) -> void:
	if delta <= 0.0:
		return
	for id in _av:
		var a: Dictionary = _av[id]
		if not a.seen:
			continue
		var body: Node3D = a.rig.get_node("Body")
		var walk: WalkAnim = a.walk
		var swing: GatherSwing = a.swing
		var node: Dictionary = ResourceNodes.get_by_id(int(_watch.running[id])) if _watch.running.has(id) else {}
		walk.step(a.pos, delta)
		walk.apply(body)
		swing.step(delta, node, a.pos, a.yaw)
		swing.apply(body)
		var arm: float = (body.get_node("ArmL") as Node3D).rotation.x
		for v in [arm, body.rotation.x, body.rotation.y, swing.weight]:
			if is_nan(v) or is_inf(v) or absf(v) > PI + 0.01:
				fail("bad swing pose %s for peer %d" % [str(v), id])
				return
		if not node.is_empty():
			swing_frames += 1
			a.lo = minf(a.lo, arm)
			a.hi = maxf(a.hi, arm)
			var flat := Vector2(node.pos.x - a.pos.x, node.pos.z - a.pos.z)
			if a.since >= 0.0 and bot.elapsed - a.since > SETTLE_AFTER and flat.length() > 0.3:
				var want := GatherSwing.face_yaw(a.pos, node.pos)
				var facing: float = a.yaw + body.rotation.y
				if absf(angle_difference(facing, want)) <= FACE_TOLERANCE:
					faced_frames += 1
				else:
					unfaced_frames += 1
		elif a.ended_at >= 0.0 and bot.elapsed - a.ended_at > BLEND_OUT_MAX:
			if swing.swinging():
				fail("peer %d still swinging %.2f s after its gather ended (weight %.3f)" % [id, bot.elapsed - a.ended_at, swing.weight])
				return
			blend_outs += 1
			a.ended_at = -1.0


func on_finish() -> void:
	stat("swing_frames", swing_frames)
	stat("faced_frames", faced_frames)
	stat("unfaced_frames", unfaced_frames)
	stat("strokes_seen", strokes_seen)
	stat("others_swung", others_swung)
	stat("blend_outs", blend_outs)
	for id in _av:
		_av[id].rig.free()
	_av.clear()
	if faced_frames + unfaced_frames < 30:
		return # too few settled gathers seen to judge; bot.gd and gameplay_gather_v3 report why
	if unfaced_frames > (faced_frames + unfaced_frames) * 0.1:
		fail("avatars faced away from their node on %d of %d settled gather frames" % [unfaced_frames, faced_frames + unfaced_frames])
	if strokes_seen == 0:
		fail("no gather ever showed a real swing of the arms")

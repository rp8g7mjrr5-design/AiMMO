extends TestCase
## Client gather swing: the body turns to the node, the arms loop a per-kind stroke, and it
## blends in and out without snapping.

const ClientScript := preload("res://client/client.gd")
const DT := 1.0 / 60.0


func _run(swing: GatherSwing, node: Dictionary, root_pos: Vector3, root_yaw: float, seconds: float) -> void:
	for i in int(seconds / DT):
		swing.step(DT, node, root_pos, root_yaw)


func test_face_yaw() -> void:
	check_near(GatherSwing.face_yaw(Vector3.ZERO, Vector3(0, 0, 2)), 0.0, 0.0001, "+Z is yaw 0")
	check_near(GatherSwing.face_yaw(Vector3.ZERO, Vector3(2, 0, 0)), PI * 0.5, 0.0001, "+X is +90 deg")
	check_near(absf(GatherSwing.face_yaw(Vector3.ZERO, Vector3(0, 5, -2))), PI, 0.0001, "-Z is 180 deg, height ignored")


func test_styles_per_kind() -> void:
	check_eq(GatherSwing.style_for("ash"), "chop")
	check_eq(GatherSwing.style_for("pine"), "chop")
	check_eq(GatherSwing.style_for("stone"), "mine")
	check_eq(GatherSwing.style_for("ember_sap"), "collect")
	check_eq(GatherSwing.style_for("mystery"), "chop", "unknown kinds still swing")
	for k in ResourceNodes.KIND_ORDER:
		check(GatherSwing.KIND_STYLE.has(k), "every node kind has a style: %s" % k)


func test_stroke_winds_up_slowly_and_bites_fast() -> void:
	for st in GatherSwing.STYLES:
		var s: Dictionary = GatherSwing.STYLES[st]
		check_near(GatherSwing.stroke(st, 0.0).arm, s.bottom, 0.0001, "%s starts at the bottom" % st)
		check_near(GatherSwing.stroke(st, s.wind).arm, s.top, 0.0001, "%s tops out after the wind-up" % st)
		check_near(GatherSwing.stroke(st, 0.9999).arm, s.bottom, 0.01, "%s ends back at the bottom" % st)
		check(float(s.wind) >= 0.5, "%s: the wind-up is never the shorter part" % st)
		# The lean is deepest at the bottom of the stroke (into the blow), none at the top.
		check_near(GatherSwing.stroke(st, s.wind).lean, 0.0, 0.0001, "%s no lean at the top" % st)
		check_near(GatherSwing.stroke(st, 0.0).lean, s.lean, 0.0001, "%s leans at the bottom" % st)
		for i in 50:
			var p := GatherSwing.stroke(st, i / 50.0)
			check(p.arm <= 0.0 and p.arm >= -PI, "%s arm stays forward and below straight up" % st)


func test_blends_in_turns_and_loops() -> void:
	var swing := GatherSwing.new()
	check(not swing.swinging(), "idle at start")
	var node := {"kind": "ash", "pos": Vector3(3, 0, 0)} # to the avatar's right of +Z
	_run(swing, node, Vector3.ZERO, 0.0, 0.6)
	check(swing.weight > 0.98, "full swing after 0.6 s (%f)" % swing.weight)
	check_near(swing.turn, PI * 0.5, 0.02, "body faces the node")
	var lo := 0.0
	var hi := -PI
	for i in 60:
		swing.step(DT, node, Vector3.ZERO, 0.0)
		lo = minf(lo, swing.pose().arm)
		hi = maxf(hi, swing.pose().arm)
	check(hi - lo > 1.5, "the arms really chop (range %f)" % (hi - lo))


func test_turn_is_relative_to_root_yaw() -> void:
	var swing := GatherSwing.new()
	# Root already faces the node: the body needs no extra turn.
	_run(swing, {"kind": "stone", "pos": Vector3(0, 0, -4)}, Vector3.ZERO, PI, 1.0)
	check_near(swing.turn, 0.0, 0.02, "no turn when the root faces the node")
	check_eq(swing.style, "mine")


func test_blends_out_and_unturns() -> void:
	var swing := GatherSwing.new()
	_run(swing, {"kind": "pine", "pos": Vector3(-2, 0, 0)}, Vector3.ZERO, 0.0, 0.8)
	_run(swing, {}, Vector3.ZERO, 0.0, 1.5)
	check_eq(swing.weight, 0.0, "swing fully gone")
	check_near(swing.turn, 0.0, 0.01, "body back to the root's heading")
	# Easing, not snapping: one frame after a cancel the weight has dropped only a little.
	var s2 := GatherSwing.new()
	_run(s2, {"kind": "pine", "pos": Vector3(-2, 0, 0)}, Vector3.ZERO, 0.0, 0.8)
	var before := s2.weight
	s2.step(DT, {}, Vector3.ZERO, 0.0)
	check(s2.weight > before * 0.8, "no snap on cancel")


func test_on_top_of_the_node_does_not_spin() -> void:
	var swing := GatherSwing.new()
	_run(swing, {"kind": "ember_sap", "pos": Vector3(0.05, 0, 0.05)}, Vector3.ZERO, 0.0, 0.5)
	check_near(swing.turn, 0.0, 0.0001, "no direction to face, no turn")
	check(swing.weight > 0.9, "still swings")


func test_apply_moves_arms_and_body() -> void:
	var rig := ClientScript.wrap_avatar(AvatarBuilder.rig())
	var body: Node3D = rig.get_node("Body")
	var walk := WalkAnim.new()
	var swing := GatherSwing.new()
	var node := {"kind": "ash", "pos": Vector3(0, 0, -3)}
	for i in 40:
		walk.step(Vector3.ZERO, DT)
		walk.apply(body)
		swing.step(DT, node, Vector3.ZERO, 0.0)
		swing.apply(body)
	check(absf(body.rotation.y) > 2.5, "body turned around towards the node (%f)" % body.rotation.y)
	var arm_l: Node3D = body.get_node("ArmL")
	var arm_r: Node3D = body.get_node("ArmR")
	check(arm_l.rotation.x < -0.5, "left arm raised forward (%f)" % arm_l.rotation.x)
	check_near(arm_l.rotation.x, arm_r.rotation.x, 0.0001, "two-handed: both arms together")
	# Done: back to the plain walk pose.
	for i in 120:
		walk.step(Vector3.ZERO, DT)
		walk.apply(body)
		swing.step(DT, {}, Vector3.ZERO, 0.0)
		swing.apply(body)
	check(absf(body.rotation.y) < 0.01, "body unturned")
	check(absf(arm_l.rotation.x) < 0.01, "arms back at the sides")
	rig.free()


## Where a hand ends up for an arm angle and body lean (rotation.x, pivots from AvatarBuilder).
## Returns Vector2(forward, height) in metres from the feet.
func _hand(arm: float, lean: float) -> Vector2:
	var shoulder: Vector3 = AvatarBuilder.LIMB_PIVOTS.ArmL
	var y := shoulder.y - AvatarBuilder.ARM_LENGTH * cos(arm)
	var z := -AvatarBuilder.ARM_LENGTH * sin(arm)
	return Vector2(y * sin(lean) + z * cos(lean), y * cos(lean) - z * sin(lean))


func test_strokes_land_with_adult_arms() -> void:
	# Character overhaul (art bible section 3): longer arms from higher shoulders. Every stroke
	# must still bite at working height in front of the body, and chop/mine wind up overhead.
	for style_name in GatherSwing.STYLES:
		var s: Dictionary = GatherSwing.STYLES[style_name]
		var bottom := _hand(float(s.bottom), float(s.lean))
		check(bottom.y >= 0.6 and bottom.y <= 1.1, "%s bites at working height, got %f m" % [style_name, bottom.y])
		check(bottom.x >= 0.4 and bottom.x <= 0.8, "%s bites in front of the body, got %f m" % [style_name, bottom.x])
		if style_name != "collect":
			var top := _hand(float(s.top), 0.0)
			check(top.y > AvatarBuilder.HEIGHT, "%s winds up over the head, got %f m" % [style_name, top.y])

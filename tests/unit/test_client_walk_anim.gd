extends TestCase
## Client walk animation: the gait follows rendered speed, ignores teleports, and settles.

const ClientScript := preload("res://client/client.gd")


func _walk(anim: WalkAnim, speed: float, seconds: float, start := Vector3.ZERO) -> Vector3:
	var dt := 1.0 / 60.0
	var pos := start
	for i in int(seconds / dt):
		pos += Vector3(0, 0, speed * dt)
		anim.step(pos, dt)
	return pos


func test_standing_still_is_idle() -> void:
	var anim := WalkAnim.new()
	for i in 120:
		anim.step(Vector3(5, 1, 5), 1.0 / 60.0)
	check_near(anim.amount(), 0.0, 0.0001, "amount")
	var p := anim.pose()
	check(absf(p.bob) <= WalkAnim.BREATH_HEIGHT + 0.0001, "only breathing when idle, got bob %f" % p.bob)
	check_near(p.roll, 0.0, 0.0001, "roll")
	check_near(p.lean, 0.0, 0.0001, "lean")


func test_walking_reaches_full_gait() -> void:
	var anim := WalkAnim.new()
	_walk(anim, GameConfig.WALK_SPEED, 2.0)
	check_near(anim.amount(), 1.0, 0.02, "amount at walk speed")
	check_near(anim.pose().lean, WalkAnim.LEAN, 0.005, "lean")
	# Over a second of walking the body must actually bob and sway both ways.
	var max_bob := 0.0
	var min_roll := 0.0
	var max_roll := 0.0
	var dt := 1.0 / 60.0
	var pos := Vector3(0, 0, GameConfig.WALK_SPEED * 2.0)
	for i in 60:
		pos.z += GameConfig.WALK_SPEED * dt
		anim.step(pos, dt)
		var p := anim.pose()
		max_bob = maxf(max_bob, p.bob)
		min_roll = minf(min_roll, p.roll)
		max_roll = maxf(max_roll, p.roll)
		check(p.bob >= -0.0001 and p.bob <= WalkAnim.BOB_HEIGHT + 0.0001, "bob in range")
	check(max_bob > WalkAnim.BOB_HEIGHT * 0.8, "body bobs (max %f)" % max_bob)
	check(min_roll < -WalkAnim.SWAY_ROLL * 0.8 and max_roll > WalkAnim.SWAY_ROLL * 0.8, "sways both ways")


func test_slow_walk_is_partial() -> void:
	var anim := WalkAnim.new()
	_walk(anim, GameConfig.WALK_SPEED * 0.5, 2.0)
	check_near(anim.amount(), 0.5, 0.03, "half speed, half gait")


func test_teleport_does_not_start_walking() -> void:
	var anim := WalkAnim.new()
	anim.step(Vector3(0, -100, 0), 1.0 / 60.0)
	anim.step(Vector3(40, 3, 40), 1.0 / 60.0) # first sighting snap
	for i in 30:
		anim.step(Vector3(40, 3, 40), 1.0 / 60.0)
	check_near(anim.amount(), 0.0, 0.0001, "no gait after a snap")


func test_stopping_settles_feet() -> void:
	var anim := WalkAnim.new()
	var pos := _walk(anim, GameConfig.WALK_SPEED, 1.3)
	for i in 180:
		anim.step(pos, 1.0 / 60.0)
	check_near(anim.amount(), 0.0, 0.0001, "stopped")
	check(absf(sin(anim.phase)) < 0.05, "feet back at rest, phase %f" % anim.phase)


func test_zero_delta_is_safe() -> void:
	var anim := WalkAnim.new()
	anim.step(Vector3.ZERO, 0.0)
	anim.step(Vector3(1, 0, 0), 0.0)
	check(not is_nan(anim.speed), "speed is a number")


func test_apply_and_wrap() -> void:
	# A stand-in avatar: primitive meshes need a real renderer, and the smoke run covers the
	# real one. Same shape as AvatarBuilder's output: parts plus a Label3D name tag (a Label3D
	# also needs a renderer, so headless runs check only the body).
	var with_tag := DisplayServer.get_name() != "headless"
	var body := Node3D.new()
	body.add_child(Node3D.new())
	if with_tag:
		var tag := Label3D.new()
		tag.text = "Tester"
		body.add_child(tag)
	var root := ClientScript.wrap_avatar(body)
	check_eq(root.get_node("Body"), body, "body child")
	check_eq(body.find_children("*", "Label3D", false, false).size(), 0, "no tag left on the body")
	if with_tag:
		check_eq(root.find_children("*", "Label3D", false, false).size(), 1, "tag on the steady root")
	var arm := Node3D.new()
	arm.name = "ArmL"
	body.add_child(arm)
	var anim := WalkAnim.new()
	_walk(anim, GameConfig.WALK_SPEED, 1.1)
	anim.apply(body)
	var p := anim.pose()
	check_near(body.position.y, p.bob, 0.0001, "bob applied")
	check_near(body.rotation.z, p.roll, 0.0001, "roll applied")
	check_near(arm.rotation.x, p.arm, 0.0001, "arm swings when present")
	root.free()


func test_adult_stride_on_lean_limbs() -> void:
	# Art bible section 3: lean 1.78 m adults with 0.92 m legs and 0.63 m arms. The old angles
	# were a goose-step (feet 0.44 m out each way) and a waddle (head 0.11 m side to side).
	var foot_reach := AvatarBuilder.LEG_LENGTH * sin(WalkAnim.LEG_SWING)
	check(foot_reach <= 0.33, "each foot reaches at most 0.33 m fore and aft, got %f" % foot_reach)
	check(foot_reach >= 0.22, "but the legs still stride, got %f" % foot_reach)
	var head_sway := AvatarBuilder.HEIGHT * sin(WalkAnim.SWAY_ROLL)
	check(head_sway <= 0.04, "the head sways at most 4 cm, got %f" % head_sway)
	var hand_reach := AvatarBuilder.ARM_LENGTH * sin(WalkAnim.ARM_SWING)
	check(hand_reach <= 0.26, "hands swing close to the body, got %f" % hand_reach)
	check(WalkAnim.ARM_SWING > WalkAnim.LEG_SWING, "arms swing a little wider than legs, as people do")
	check(WalkAnim.BOB_HEIGHT >= 0.075 and WalkAnim.BOB_HEIGHT <= 0.1, "a little more bob carries the weight")


func test_walk_pose_never_exceeds_adult_limits() -> void:
	var anim := WalkAnim.new()
	var dt := 1.0 / 60.0
	var pos := Vector3.ZERO
	var max_leg := 0.0
	var max_roll := 0.0
	for i in 240:
		pos.z += GameConfig.WALK_SPEED * 1.4 * dt # faster than walk speed: amount clamps at 1
		anim.step(pos, dt)
		var p := anim.pose()
		max_leg = maxf(max_leg, absf(p.leg))
		max_roll = maxf(max_roll, absf(p.roll))
	check(max_leg <= WalkAnim.LEG_SWING + 0.0001, "leg swing capped, got %f" % max_leg)
	check(max_roll <= WalkAnim.SWAY_ROLL + 0.0001, "roll capped, got %f" % max_roll)

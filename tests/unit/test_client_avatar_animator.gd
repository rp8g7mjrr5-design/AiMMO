extends TestCase
## The traveller's animation: leg IK that plants feet, a gait with no foot sliding, every clip
## well-formed, and the state machine's moves (jump, knock-down, get up, sit, swings, gathering).

const DT := 1.0 / 60.0


## Where each foot's ankle is in the avatar's space for `pose`.
func _ankles(pose: Dictionary) -> Dictionary:
	var sk := AvatarSkeleton.build()
	AvatarAnimator.apply_pose(sk, pose)
	var out := {}
	for s in ["Left", "Right"]:
		out[s] = sk.get_bone_global_pose(sk.find_bone(s + "Foot")).origin
	sk.free()
	return out


func _run(anim: AvatarAnimator, seconds: float, ctx_for: Callable) -> void:
	var t := 0.0
	while t < seconds:
		anim.step(DT, ctx_for.call(t))
		t += DT


func test_leg_ik_reaches_its_target() -> void:
	var hip := Vector2(0.0, AvatarSkeleton.HIP_HEIGHT - 0.08)
	for target in [Vector2(0.0, 0.06), Vector2(0.3, 0.1), Vector2(-0.35, 0.06), Vector2(0.2, 0.5), Vector2(0.4, 0.3)]:
		var a := AvatarClips.leg_ik(hip, target)
		var got := AvatarClips.leg_fk(hip, a.x, a.y)
		check(got.distance_to(target) < 0.002, "ankle reaches %s, got %s" % [target, got])
		check(a.y >= 0.0, "the knee never bends backwards")
	# Out of reach: the leg straightens towards it.
	var far := AvatarClips.leg_ik(hip, Vector2(0.0, -1.0))
	check(far.y < 0.25, "nearly straight when out of reach (%.2f)" % far.y)


func test_standing_feet_are_on_the_ground_under_the_hips() -> void:
	for p in [AvatarClips.gait(0.3, 0.0), AvatarClips.idle(0.0), AvatarClips.idle(7.3)]:
		var ankles := _ankles(p)
		for s in ankles:
			check_near(ankles[s].y, AvatarSkeleton.ANKLE_HEIGHT, 0.01, "%s ankle on the ground" % s)
			check(absf(ankles[s].z) < 0.06, "%s foot under the body" % s)


func test_planted_foot_does_not_slide() -> void:
	# During stance a planted foot must move back exactly as fast as the body moves forward,
	# so it stays put on the ground.
	for speed in [1.5, 3.5, 6.0]:
		var f := AvatarClips.cadence(speed)
		var dphase := 0.01
		var a := _ankles(AvatarClips.gait(0.02, speed))
		var b := _ankles(AvatarClips.gait(0.02 + dphase, speed))
		var dz: float = b.Left.z - a.Left.z
		var expected: float = -speed * dphase / f
		check_near(dz, expected, absf(expected) * 0.2 + 0.002, "left foot planted at %.1f m/s" % speed)
		check_near(a.Left.y, AvatarSkeleton.ANKLE_HEIGHT, 0.03, "left foot down at %.1f m/s" % speed)


func test_swinging_foot_clears_the_ground() -> void:
	for speed in [1.5, 6.0]:
		var high := 0.0
		for i in 40:
			var p := AvatarClips.gait(float(i) / 40.0, speed)
			high = maxf(high, _ankles(p).Right.y)
		check(high > AvatarSkeleton.ANKLE_HEIGHT + 0.06, "the swinging foot lifts at %.1f m/s (%.2f)" % [speed, high])


func test_every_clip_is_finite() -> void:
	var poses := []
	for i in 12:
		var t := i * 0.15
		poses.append_array([
			AvatarClips.idle(t), AvatarClips.gait(t, 1.5), AvatarClips.gait(t, 6.0),
			AvatarClips.gather("chop", fposmod(t, 1.0)), AvatarClips.gather("mine", fposmod(t, 1.0)),
			AvatarClips.gather("collect", fposmod(t, 1.0)), AvatarClips.craft(t),
			AvatarClips.swing("light", t * 0.4, 0.12, 0.10, 0.22), AvatarClips.swing("heavy", t * 0.6, 0.4, 0.12, 0.4),
			AvatarClips.jump_takeoff(t * 0.1), AvatarClips.jump_air(t * 0.3, 4.0 - t * 5.0), AvatarClips.jump_land(t * 0.2),
			AvatarClips.knockdown(t * 0.6), AvatarClips.lying(t), AvatarClips.getup(t),
			AvatarClips.sit_down(t * 0.6), AvatarClips.sitting(t), AvatarClips.stand_up(t * 0.5),
		])
	var bones := AvatarSkeleton.names()
	for p in poses:
		for k in p:
			var v = p[k]
			if v is Vector3:
				check(k == "root_pos" or k in bones, "known key %s" % k)
				check(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "%s finite" % k)
				if k != "root_pos":
					check(absf(v.x) < 3.2 and absf(v.y) < 3.2 and absf(v.z) < 3.2, "%s within a half turn" % k)


## Where `bone` is in the avatar's space for `pose` (a fresh skeleton each time: a reused
## one can hand back a cached global pose).
func _at(pose: Dictionary, bone: String) -> Vector3:
	var sk := AvatarSkeleton.build()
	AvatarAnimator.apply_pose(sk, pose)
	var o := sk.get_bone_global_pose(sk.find_bone(bone)).origin
	sk.free()
	return o


func test_lying_is_on_the_ground_and_sitting_is_low() -> void:
	var lying := AvatarClips.lying(0.0)
	check(_at(lying, "Head").y < 0.35, "the head is down when lying (%.2f)" % _at(lying, "Head").y)
	var sitting := AvatarClips.sitting(0.0)
	check(_at(sitting, "Hips").y < 0.25, "the hips are on the ground when sitting (%.2f)" % _at(sitting, "Hips").y)
	check(_at(sitting, "Head").y > 0.6, "sitting upright (head at %.2f)" % _at(sitting, "Head").y)
	for s in ["Left", "Right"]:
		check(_at(sitting, s + "Foot").y > 0.0, "%s foot above the turf when sitting" % s)


func test_blend_and_timeline() -> void:
	var a := {"root_pos": Vector3.ZERO, "Hips": Vector3(1, 0, 0), "crouch": 0.0}
	var b := {"root_pos": Vector3(0, -1, 0), "Chest": Vector3(0, 1, 0), "crouch": 0.2}
	var m := AvatarClips.blend(a, b, 0.5)
	check(m.Hips.is_equal_approx(Vector3(0.5, 0, 0)), "a bone only in a fades to rest")
	check(m.Chest.is_equal_approx(Vector3(0, 0.5, 0)), "a bone only in b fades in")
	check_near(m.crouch, 0.1, 0.0001, "scalars blend")
	var masked := AvatarClips.blend(a, b, 1.0, ["Chest"])
	check(masked.root_pos == Vector3.ZERO and masked.Hips == Vector3(1, 0, 0), "a mask leaves the rest")
	var keys := [[0.0, a], [1.0, b, "linear"]]
	check_near(AvatarClips.timeline(keys, 0.25).crouch, 0.05, 0.0001, "timeline interpolates")
	check_near(AvatarClips.timeline(keys, 5.0).crouch, 0.2, 0.0001, "and holds the last key")


func test_running_steps_alternate_feet() -> void:
	var anim := AvatarAnimator.new()
	var feet := []
	var t := 0.0
	while t < 3.0:
		anim.step(DT, {"pos": Vector3(0, 0, t * 6.0)})
		if anim.stepped:
			feet.append(anim.foot)
		t += DT
	check(feet.size() >= 6, "steps while running (%d)" % feet.size())
	for i in range(1, feet.size()):
		check(feet[i] != feet[i - 1], "feet alternate")
		if feet[i] == feet[i - 1]:
			break
	check_near(anim.amount(), 1.0, 0.01, "full gait")


func test_teleport_is_not_running() -> void:
	var anim := AvatarAnimator.new()
	anim.step(DT, {"pos": Vector3.ZERO})
	anim.step(DT, {"pos": Vector3(50, 0, 0)})
	anim.step(DT, {"pos": Vector3(50, 0, 0)})
	check_near(anim.speed, 0.0, 0.0001, "a snap is not speed")


func test_jump_goes_up_and_lands() -> void:
	var anim := AvatarAnimator.new()
	anim.step(DT, {"pos": Vector3.ZERO})
	anim.jump()
	check_eq(anim.body, "takeoff", "the dip")
	_run(anim, 0.15, func(_t): return {"pos": Vector3.ZERO})
	var lift := func(t): return {"pos": Vector3.ZERO, "height": maxf(5.0 * t - 7.5 * t * t, 0.0)}
	_run(anim, 0.3, lift)
	check_eq(anim.body, "air", "in the air")
	_run(anim, 0.5, func(t): return lift.call(t + 0.3))
	check_eq(anim.body, "land", "landing")
	_run(anim, AvatarClips.LAND + 0.05, func(_t): return {"pos": Vector3.ZERO})
	check_eq(anim.body, "move", "back on its feet")


func test_a_jump_the_server_never_lifts_settles() -> void:
	var anim := AvatarAnimator.new()
	anim.jump()
	_run(anim, 1.0, func(_t): return {"pos": Vector3.ZERO})
	check_eq(anim.body, "move", "the dip settles back")


func test_knocked_down_then_up() -> void:
	var anim := AvatarAnimator.new()
	var still := func(_t): return {"pos": Vector3.ZERO, "gather": {"kind": "ash", "pos": Vector3(0, 0, 1)}}
	_run(anim, 0.5, still)
	check(anim.action == "gather" and anim.action_weight > 0.9, "gathering")
	anim.knock_down()
	_run(anim, 2.0, still)
	check_eq(anim.body, "down", "lying there")
	check_near(anim.action_weight, 0.0, 0.01, "no swinging while down")
	anim.get_up()
	check_eq(anim.body, "getup", "getting up")
	_run(anim, AvatarClips.GETUP + 0.05, func(_t): return {"pos": Vector3.ZERO})
	check_eq(anim.body, "move", "standing again")


func test_sit_and_stand() -> void:
	var anim := AvatarAnimator.new()
	anim.sit()
	_run(anim, 2.0, func(_t): return {"pos": Vector3.ZERO})
	check_eq(anim.body, "sit", "sitting")
	anim.stand()
	check_eq(anim.body, "stand", "standing up")
	_run(anim, AvatarClips.STAND + 0.05, func(_t): return {"pos": Vector3.ZERO})
	check_eq(anim.body, "move", "up")
	# Walking off stands you up on its own.
	anim.sit()
	_run(anim, 0.5, func(t): return {"pos": Vector3(0, 0, t * 4.0)})
	check(anim.body != "sit", "moving gets you up")


func test_swing_plays_once_and_fades() -> void:
	var anim := AvatarAnimator.new()
	anim.swing("heavy", 0.4, 0.12, 0.4)
	_run(anim, 0.3, func(_t): return {"pos": Vector3.ZERO})
	check(anim.action == "swing" and anim.action_weight > 0.9, "swinging")
	_run(anim, 1.5, func(_t): return {"pos": Vector3.ZERO})
	check_eq(anim.action, "", "done")
	check_near(anim.action_weight, 0.0, 0.01, "faded out")


func test_gathering_faces_the_node() -> void:
	var anim := AvatarAnimator.new()
	_run(anim, 1.0, func(_t): return {"pos": Vector3.ZERO, "yaw": 0.0, "gather": {"kind": "stone", "pos": Vector3(2, 0, 0)}})
	check_near(anim.turn, PI * 0.5, 0.05, "turned to face +X")
	check_eq(anim.gather_style, "mine", "stone is mined")
	_run(anim, 1.5, func(_t): return {"pos": Vector3.ZERO, "yaw": 0.0})
	check_near(anim.turn, 0.0, 0.05, "turned back")


func test_apply_moves_the_skeleton() -> void:
	var anim := AvatarAnimator.new()
	anim.knock_down()
	_run(anim, 1.5, func(_t): return {"pos": Vector3.ZERO})
	var sk := AvatarSkeleton.build()
	anim.apply(sk)
	check(sk.get_bone_global_pose(sk.find_bone("Head")).origin.y < 0.4, "the head is on the ground")
	sk.free()

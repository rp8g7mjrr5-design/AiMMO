extends TestCase
## A clean fight (owner, 2026-11-25: "no silly text", "cleaner animations", "I shouldn't be able
## to run backwards"): the backpedal cap on both ends of the wire, the backwards stride and
## strafe hips, getting up after a knock-down, the Zombai's steady shamble and held stagger,
## and no words on screen from a walker's grab, a blow, a knock-down or a winded swing.

const ServerScript := preload("res://server/server.gd")
const DT := 1.0 / 60.0


func _wire(list: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in list:
		out.append_array(PackedFloat32Array([float(e[0]), float(e[1]), float(e[2]), float(e[3]),
			float(Gloam.STATES.find(str(e[4]))), float(e[5]) if e.size() > 5 else 0.0]))
	return out


# --- no running backwards ---

func test_full_speed_only_ahead() -> void:
	var yaw := 0.7
	var ahead := Vector2(sin(yaw), cos(yaw))
	check_near(Movement.limit_for_facing(ahead, yaw).length(), 1.0, 0.0001, "ahead is a run")
	check_near(Movement.limit_for_facing(-ahead, yaw).length(), Movement.BACK_SPEED, 0.0001, "straight back is a walk")
	var side := Vector2(cos(yaw), -sin(yaw))
	check_near(Movement.limit_for_facing(side, yaw).length(), Movement.SIDE_SPEED, 0.0001, "sideways is a jog")
	var back_diag := (-ahead + side).normalized()
	var cap := Movement.limit_for_facing(back_diag, yaw).length()
	check(cap > Movement.BACK_SPEED and cap < Movement.SIDE_SPEED, "back-diagonal between the two (%.2f)" % cap)
	check(Movement.BACK_SPEED * GameConfig.WALK_SPEED <= AvatarClips.RUN_FROM, "a backpedal is in the gait's walk band")
	check_eq(Movement.limit_for_facing(Vector2(NAN, 0), yaw), Vector2.ZERO, "junk is no move")
	check_eq(Movement.limit_for_facing(-ahead * 0.2, yaw), -ahead * 0.2, "a slow back step under the cap is untouched")


func test_cap_is_idempotent_so_client_and_server_agree() -> void:
	for i in 24:
		var yaw := -PI + TAU * float(i) / 24.0
		for j in 16:
			var a := TAU * float(j) / 16.0
			var once := Movement.limit_for_facing(Vector2(sin(a), cos(a)), yaw)
			check(once.is_equal_approx(Movement.limit_for_facing(once, yaw)), "applied twice is the same")


func test_server_caps_a_backpedal_from_any_client() -> void:
	var srv: Node = ServerScript.new()
	srv.sessions[2] = {"logged_in": true, "character": CharacterData.normalize({"name": "P2"}),
		"move": Vector2.ZERO, "yaw": 0.0, "seq": -1, "last_chat": -1000.0, "last_gather": -1000.0,
		"channel": {}, "login_attempts": 0, "inv_dirty": false}
	srv._on_input(2, 1, Vector2(0, -1), 0.0) # facing +z, running at -z: a hacked or old client
	check_near((srv.sessions[2].move as Vector2).length(), Movement.BACK_SPEED, 0.0001, "the server walks it")
	srv._on_input(2, 2, Vector2(0, 1), 0.0)
	check_near((srv.sessions[2].move as Vector2).length(), 1.0, 0.0001, "ahead still runs")
	srv.free()


# --- the traveller's legs ---

func test_backpedal_runs_the_stride_backwards() -> void:
	var anim := AvatarAnimator.new()
	var feet := []
	var phases := []
	var t := 0.0
	var v := Movement.BACK_SPEED * GameConfig.WALK_SPEED
	while t < 3.0:
		anim.step(DT, {"pos": Vector3(0, 0, -t * v), "yaw": 0.0}) # facing +z, moving -z
		if anim.stepped:
			feet.append(anim.foot)
		phases.append(anim.phase)
		t += DT
	check(anim.backward, "moving back is a backpedal")
	check(anim.speed < AvatarClips.RUN_FROM, "at a walk (%.2f m/s)" % anim.speed)
	check(feet.size() >= 3, "steps while backing off (%d)" % feet.size())
	for i in range(1, feet.size()):
		if feet[i] == feet[i - 1]:
			check(false, "feet alternate backing off")
			break
	var down := 0
	for i in range(1, phases.size()):
		if float(phases[i]) < float(phases[i - 1]):
			down += 1
	check(down > phases.size() / 2, "the stride phase runs backwards")
	check_near(anim.stride_turn, 0.0, 0.05, "straight back: the legs stay square")


func test_strafe_turns_the_hips_not_the_shoulders() -> void:
	var anim := AvatarAnimator.new()
	var t := 0.0
	while t < 1.5:
		anim.step(DT, {"pos": Vector3(t * 4.5, 0, 0), "yaw": 0.0}) # facing +z, stepping to +x
		t += DT
	check(not anim.backward, "a strafe is not a backpedal")
	check(anim.stride_turn > 0.9, "the legs turn to the line of travel (%.2f)" % anim.stride_turn)
	var p := anim.pose()
	var hips := (p.Hips as Vector3).y
	var chest := hips + (p.Spine as Vector3).y + (p.Chest as Vector3).y
	check(absf(chest) < absf(hips) * 0.5, "the chest turns back towards the facing (hips %.2f, chest %.2f)" % [hips, chest])


func test_coming_to_lies_then_gets_up_and_walking_cuts_it_short() -> void:
	var anim := AvatarAnimator.new()
	anim.step(DT, {"pos": Vector3.ZERO, "yaw": 0.0})
	anim.lie_down()
	anim.step(DT, {"pos": Vector3.ZERO, "yaw": 0.0})
	check_eq(anim.body, "down", "lying there")
	check(anim.body_t >= AvatarClips.KNOCKDOWN, "past the fall: already on the ground")
	anim.get_up()
	check_eq(anim.body, "getup")
	var t := 0.0
	while t < AvatarAnimator.GETUP_MIN + 0.3:
		anim.step(DT, {"pos": Vector3(0, 0, t * 6.0), "yaw": 0.0})
		t += DT
	check_eq(anim.body, "move", "walking off cuts getting up short")
	var shade_dark: float = ClientScript().came_to_alpha(0.1)
	check_near(shade_dark, 1.0, 0.0001, "the screen is dark as you go down")
	check_near(ClientScript().came_to_alpha(10.0), 0.0, 0.0001, "and clear again after")


func ClientScript() -> GDScript:
	return load("res://client/client.gd")


# --- the Zombai ---

func test_walker_keeps_a_steady_pace_between_updates() -> void:
	var v := ZombaiView.new()
	v.feed(_wire([[1, 0.0, 0.0, 0.0, "hunt"]]), 0.0)
	v.feed(_wire([[1, 1.0, 0.0, 0.0, "hunt"]]), 1.0)
	var a := v.position(1, 1.0 + ZombaiView.BLEND * 0.25).x
	var b := v.position(1, 1.0 + ZombaiView.BLEND * 0.5).x
	var c := v.position(1, 1.0 + ZombaiView.BLEND * 0.75).x
	check_near(b - a, c - b, 0.001, "even pace, no ease in and out")


func test_late_update_does_not_cancel_a_stagger() -> void:
	var v := ZombaiView.new()
	v.feed(_wire([[3, 0.0, 0.0, 0.0, "hunt"]]), 0.0)
	v.struck("heavy", [3], [], 1.0)
	check_eq(v.state(3), "stagger")
	var ev := v.feed(_wire([[3, 0.0, 0.0, 0.0, "hunt"]]), 1.05) # sent before the blow, arrived after
	check_eq(v.state(3), "stagger", "still reeling")
	check(not ev.any(func(e): return str(e.event) == "hunt"), "no fresh groan for it")
	v.feed(_wire([[3, 0.0, 0.0, 0.0, "stagger"]]), 1.2)
	check_near(v.since_stagger(3, 1.2), 0.2, 0.0001, "the server's stagger doesn't restart it")
	v.feed(_wire([[3, 0.0, 0.0, 0.0, "hunt"]]), 1.0 + ZombaiView.STAGGER_HOLD + 0.5)
	check_eq(v.state(3), "hunt", "after it, the server's word goes")


func test_shamble_feet_hold_the_ground() -> void:
	# The planted foot's travel per metre walked matches the ground at a day and night pace.
	for speed in [Gloam.WANDER_SPEED, Gloam.DAY_SPEED, Gloam.NIGHT_SPEED]:
		var per_m := ZombaiBody.strides_per_metre(speed)
		var s := ZombaiBody.leg_speed(speed)
		var f := AvatarClips.cadence(s)
		# The gait's body moves s / f metres a cycle; a cycle here is 1 / per_m metres.
		check_near(1.0 / per_m, s / f, 0.0001, "no skating at %.1f m/s" % speed)


# --- no words in a fight ---

func test_no_fight_text_on_screen() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	check(not src.contains("show_notice(\"Zombai down"), "no 'Zombai down.' notice")
	check(not src.contains("ZOMBAI_GRAB_HINT"), "no grab hint")
	check(not src.contains("show_notice(Weapons.refusal_text"), "a winded swing flashes the bar, no words")
	check(src.contains("if text == Vitals.KNOCKED_DOWN_TEXT:"), "a knock-down is a fade, not a notice")

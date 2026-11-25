extends TestCase
## The Zombai on screen (protocol v10): ZombaiView's smoothing, windup timing, blows and
## bodies; ZombaiBody's drained look and poses; ZombaiFigures' pose choice; their sounds.


func _wire(list: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for e in list:
		out.append_array(PackedFloat32Array([float(e[0]), float(e[1]), float(e[2]), float(e[3]),
			float(Gloam.STATES.find(str(e[4]))), float(e[5]) if e.size() > 5 else 0.0]))
	return out


func test_first_sighting_is_placed_on_the_ground() -> void:
	var v := ZombaiView.new()
	var ev := v.feed(_wire([[4, 60.0, 12.0, 0.3, "wander"]]), 1.0)
	check_eq(ev.size(), 1)
	check_eq(str(ev[0].event), "appear")
	var p := v.position(4, 1.0)
	check_near(p.x, 60.0, 0.001, "placed at once")
	check_near(p.y, Terrain.height(60.0, 12.0), 0.001, "on the ground")
	check_near(v.facing(4, 1.0), 0.3, 0.001)
	check_eq(v.state(4), "wander")


func test_updates_blend_without_jumping() -> void:
	var v := ZombaiView.new()
	v.feed(_wire([[1, 0.0, 0.0, 0.0, "hunt"]]), 0.0)
	v.feed(_wire([[1, 1.0, 0.0, 0.0, "hunt"]]), 1.0)
	check_near(v.position(1, 1.0).x, 0.0, 0.001, "starts where it was drawn")
	check_near(v.position(1, 1.0 + ZombaiView.BLEND).x, 1.0, 0.001, "lands on the server's spot")
	v.feed(_wire([[1, 30.0, 0.0, 0.0, "hunt"]]), 2.0)
	check_near(v.position(1, 2.0).x, 30.0, 0.001, "a jump past SNAP_DIST is placed, not slid")


func test_raised_arms_are_an_event_and_timed_to_the_server() -> void:
	var v := ZombaiView.new()
	v.feed(_wire([[2, 0.0, 0.0, 0.0, "hunt"]]), 0.0)
	var ev := v.feed(_wire([[2, 0.0, 0.0, 0.0, "grab", Gloam.GRAB_WINDUP * 0.75]]), 0.2)
	check(ev.any(func(e): return str(e.event) == "windup"), "arms up is a moment: %s" % [ev])
	check_eq(v.windups, 1)
	check_near(v.windup(2, 0.2), 0.25, 0.001, "a quarter through the windup, from windup_left")
	check_near(v.windup(2, 0.2 + Gloam.GRAB_WINDUP * 0.75), 1.0, 0.001, "closes when the server's grab does")
	check_near(v.windup(2, 5.0), 1.0, 0.001, "never past 1")
	ev = v.feed(_wire([[2, 0.0, 0.0, 0.0, "grab", Gloam.GRAB_WINDUP * 0.5]]), 0.4)
	check(not ev.any(func(e): return str(e.event) == "windup"), "the same windup isn't a second moment")
	v.feed(_wire([[2, 0.0, 0.0, 0.0, "recover"]]), 0.6)
	check_near(v.windup(2, 0.6), 0.0, 0.001, "no windup once it's recovering")


func test_turning_on_you_is_a_groan_moment() -> void:
	var v := ZombaiView.new()
	v.feed(_wire([[3, 0.0, 0.0, 0.0, "wander"]]), 0.0)
	var ev := v.feed(_wire([[3, 0.0, 0.0, 0.0, "hunt"]]), 0.2)
	check(ev.any(func(e): return str(e.event) == "hunt"), "it saw you")
	v.feed(_wire([[3, 0.0, 0.0, 0.0, "stagger"]]), 0.4)
	ev = v.feed(_wire([[3, 0.0, 0.0, 0.0, "hunt"]]), 0.6)
	check(not ev.any(func(e): return str(e.event) == "hunt"), "back on its feet after a stagger isn't a new sighting")


func test_blows_flinch_stagger_and_put_down() -> void:
	var v := ZombaiView.new()
	v.feed(_wire([[5, 10.0, 0.0, 1.0, "hunt"], [6, 12.0, 0.0, 0.0, "hunt"]]), 0.0)
	var ev := v.struck("light", [5], [], 1.0)
	check_eq(str(ev[0].event), "struck")
	check_near(v.since_flinch(5, 1.1), 0.1, 0.001, "it jerks")
	check_eq(v.state(5), "hunt", "a light blow doesn't stagger")
	v.struck("heavy", [6], [], 1.0)
	check_eq(v.state(6), "stagger", "a heavy blow staggers at once, before the next update")
	ev = v.struck("heavy", [5], [5], 2.0)
	check_eq(str(ev[0].event), "down")
	check(not v.has(5) and v.bodies() == [5], "it's a body now")
	check_eq(v.state(5), "down")
	check_near(v.facing(5, 3.0), 1.0, 0.001, "lies facing the way it fell")
	# It's gone from the server; the next update must not make the body "leave".
	ev = v.feed(_wire([[6, 12.0, 0.0, 0.0, "hunt"]]), 2.2)
	check(v.bodies() == [5], "the body stays")
	check(not ev.any(func(e): return int(e.id) == 5), "no leave for a body")
	# A late packet that still has it doesn't stand it back up.
	v.feed(_wire([[5, 10.0, 0.0, 1.0, "hunt"], [6, 12.0, 0.0, 0.0, "hunt"]]), 2.3)
	check(not v.has(5), "a late packet doesn't raise the dead")
	check_near(v.sink(5, 2.0 + ZombaiView.LIE_SECONDS), 0.0, 0.001, "lies still first")
	check(v.sink(5, 2.0 + ZombaiView.LIE_SECONDS + ZombaiView.SINK_SECONDS * 0.9) > 0.3, "then sinks")
	check_eq(v.expire(2.0 + ZombaiView.LIE_SECONDS), [])
	check_eq(v.expire(2.0 + ZombaiView.LIE_SECONDS + ZombaiView.SINK_SECONDS), [5])
	check(v.bodies().is_empty(), "and is gone")
	check_eq(v.downs, 1)


func test_empty_update_means_they_left_view() -> void:
	var v := ZombaiView.new()
	v.feed(_wire([[1, 0.0, 0.0, 0.0, "wander"], [2, 5.0, 0.0, 0.0, "wander"]]), 0.0)
	var ev := v.feed(PackedFloat32Array(), 0.2)
	check_eq(ev.size(), 2)
	check(v.ids().is_empty(), "both gone")
	v.feed(_wire([[1, 0.0, 0.0, 0.0, "wander"]]), 0.4)
	v.clear()
	check(v.ids().is_empty() and v.bodies().is_empty(), "clear forgets everything")


func test_body_is_a_drained_traveller_without_a_pack() -> void:
	for variant in ZombaiBody.VARIANTS:
		var parts := ZombaiBody.parts(variant)
		var src := AvatarBuilder.parts(90210 + variant * 7919)
		check_eq(parts.size(), src.size() - 2, "pack and bedroll gone (variant %d)" % variant)
		for p in parts:
			check(not (p.limb == "" and (p.pos as Vector3).z < AvatarSkeleton.BACK_FROM), "nothing on its back")
			var c: Color = p.color
			check(c.s < 0.4, "drained, never vivid: %s" % [c])
		var head: Color = parts[1].color
		check(head.b >= head.r, "ash-cold flesh, not warm skin: %s" % [head])
		check(head.g <= head.b + 0.02, "grey, never zombie green: %s" % [head])


func test_poses_read_at_a_glance() -> void:
	var walk := ZombaiBody.shamble(0.25, 1.8, 3.0)
	check((walk.Spine as Vector3).x + (walk.Chest as Vector3).x > 0.2, "hunched over")
	check(absf((walk.Head as Vector3).z) > 0.15, "head lolled to one side")
	var arms_up := ZombaiBody.grab(1.0)
	for s in ["Left", "Right"]:
		check((arms_up[s + "UpperArm"] as Vector3).x < -1.3, "both arms reach straight out at the end of the windup")
	var start := ZombaiBody.grab(0.0)
	check((start.LeftUpperArm as Vector3).x > -0.6, "arms still low as the windup starts")
	check((arms_up.root_pos as Vector3).z > 0.15, "the lunge")
	var rocked := ZombaiBody.stagger(0.12)
	check((rocked.Spine as Vector3).x < 0.0, "a heavy blow rocks it back")
	var down := ZombaiBody.fall(ZombaiBody.FALL + 3.0)
	check((down.root_pos as Vector3).y < -0.6, "put down, it lies on the ground")
	check_eq(down, ZombaiBody.fall(ZombaiBody.FALL + 6.0), "and lies still: no breathing")


func test_figures_pick_the_pose_for_the_state() -> void:
	var grab := ZombaiFigures.pose_for("grab", 0.0, 0.0, 1.0, 1.0, INF, INF, 0.0, 1.0)
	check((grab.LeftUpperArm as Vector3).x < -1.3, "grab: arms up")
	var hit := ZombaiFigures.pose_for("hunt", 0.0, 1.8, 1.0, 0.0, INF, 0.0, 0.0, 1.0)
	var calm := ZombaiFigures.pose_for("hunt", 0.0, 1.8, 1.0, 0.0, INF, INF, 0.0, 1.0)
	check((hit.Spine as Vector3).x < (calm.Spine as Vector3).x - 0.2, "a struck walker jerks back")
	var down := ZombaiFigures.pose_for("down", 0.0, 0.0, 1.0, 0.0, INF, INF, 5.0, 1.0)
	check((down.root_pos as Vector3).y < -0.6, "down: lying")
	check_eq(ZombaiBody.variant_of(7), ZombaiBody.variant_of(7), "a walker keeps its body")
	check(ZombaiBody.size_of(3) > 0.9 and ZombaiBody.size_of(3) < 1.05, "real proportions, a little variety")


func test_their_sounds_are_generated_and_audible() -> void:
	for i in Sfx.GROAN_VARIANTS:
		var g := Sfx.groan(i)
		check(g.data.size() > Sfx.RATE, "a groan lasts about a second")
		check(_peak(g) > 0.1, "and can be heard")
	var r := Sfx.rasp()
	check_near(float(r.data.size()) / 2.0 / Sfx.RATE, Sfx.RASP_LENGTH, 0.01)
	check(_peak(r) > 0.1, "the rasp can be heard")
	check(Sfx.RASP_LENGTH < Gloam.GRAB_WINDUP, "the rasp is over before the grab closes")


func _peak(w: AudioStreamWAV) -> float:
	var top := 0
	for i in range(0, w.data.size(), 2):
		var s := w.data[i] | (w.data[i + 1] << 8)
		if s >= 32768:
			s -= 65536
		top = maxi(top, absi(s))
	return float(top) / 32767.0

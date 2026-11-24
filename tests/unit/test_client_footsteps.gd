extends TestCase
## Client footsteps: a foot comes down twice per stride cycle while walking, never while
## standing, settling or teleporting; the sound is real, varied and short; far steps are
## silent.


func _walk(anim: WalkAnim, speed: float, seconds: float, start := Vector3.ZERO) -> Dictionary:
	var dt := 1.0 / 60.0
	var pos := start
	var steps := 0
	var feet := []
	for i in int(seconds / dt):
		pos += Vector3(0, 0, speed * dt)
		anim.step(pos, dt)
		if anim.stepped:
			steps += 1
			feet.append(anim.foot)
	return {"pos": pos, "steps": steps, "feet": feet}


func test_walking_steps_twice_per_cycle() -> void:
	var anim := WalkAnim.new()
	_walk(anim, GameConfig.WALK_SPEED, 1.0) # get up to speed
	var start := anim.footsteps
	var r := _walk(anim, GameConfig.WALK_SPEED, 4.0, Vector3(0, 0, GameConfig.WALK_SPEED))
	var want := 4.0 * WalkAnim.STRIDE_CYCLES_PER_SEC * 2.0
	check(absf(float(r.steps) - want) <= 1.5, "about %.1f steps in 4 s, got %d" % [want, r.steps])
	check_eq(anim.footsteps - start, r.steps, "footsteps counts every stepped frame")
	var feet: Array = r.feet
	for i in range(1, feet.size()):
		check(feet[i] != feet[i - 1], "feet alternate (step %d)" % i)


func test_standing_and_settling_never_step() -> void:
	var anim := WalkAnim.new()
	var r := _walk(anim, 0.0, 2.0, Vector3(3, 0, 3))
	check_eq(r.steps, 0, "no steps standing still")
	# Walk, then stop: the settle eases the phase to rest, which must not sound like steps.
	var w := _walk(anim, GameConfig.WALK_SPEED, 1.37)
	var stopped := 0
	for i in 180:
		anim.step(w.pos, 1.0 / 60.0)
		if anim.stepped and anim.amount() < WalkAnim.FOOTSTEP_MIN_GAIT:
			stopped += 1
	check_eq(stopped, 0, "no steps while coming to rest")
	check(not anim.stepped, "stepped clears once still")


func test_creeping_is_silent() -> void:
	var anim := WalkAnim.new()
	var r := _walk(anim, GameConfig.WALK_SPEED * 0.2, 4.0)
	check_eq(r.steps, 0, "a creep below FOOTSTEP_MIN_GAIT makes no footsteps")


func test_teleport_is_not_a_step() -> void:
	var anim := WalkAnim.new()
	anim.step(Vector3.ZERO, 1.0 / 60.0)
	var steps := 0
	for i in 60:
		anim.step(Vector3(40.0 * (i % 2), 0, 0), 1.0 / 60.0) # snapping back and forth
		steps += int(anim.stepped)
	check_eq(steps, 0, "teleports don't step")


func test_zero_delta_clears_stepped() -> void:
	var anim := WalkAnim.new()
	var r := _walk(anim, GameConfig.WALK_SPEED, 3.0)
	check(r.steps > 0, "walked")
	anim.stepped = true
	anim.step(r.pos, 0.0)
	check(not anim.stepped, "a zero-length frame is not a step")


func test_sound_is_short_varied_and_not_silent() -> void:
	var seen := {}
	for v in Sfx.FOOTSTEP_VARIANTS:
		var w := Sfx.footstep(v)
		var samples := w.data.size() / 2
		check_near(float(samples) / Sfx.RATE, Sfx.FOOTSTEP_LENGTH, 0.01, "length")
		var peak := 0
		for i in range(0, w.data.size(), 2):
			var s := w.data.decode_s16(i)
			peak = maxi(peak, absi(s))
		check(peak > 2000, "variant %d is audible (peak %d)" % [v, peak])
		check(peak < 20000, "variant %d stays soft (peak %d)" % [v, peak])
		var last := absi(w.data.decode_s16(w.data.size() - 2))
		check(last < 200, "variant %d ends without a click (%d)" % [v, last])
		seen[w.data.slice(0, 2000).hex_encode().md5_text()] = true
	check_eq(seen.size(), Sfx.FOOTSTEP_VARIANTS, "every variant sounds different")
	check(Sfx.footstep(-1).data == Sfx.footstep(Sfx.FOOTSTEP_VARIANTS - 1).data, "variants wrap")


func test_variants_rotate_and_differ_between_players() -> void:
	check(Footsteps.variant_for(5, 0) != Footsteps.variant_for(5, 1), "consecutive steps differ")
	check(Footsteps.variant_for(5, 0) != Footsteps.variant_for(6, 0), "side-by-side players differ")
	for c in 10:
		var v := Footsteps.variant_for(-3, c)
		check(v >= 0 and v < Sfx.FOOTSTEP_VARIANTS, "variant in range")


func test_gait_volume_and_hearing_range() -> void:
	check_near(Footsteps.gait_db(1.0), 0.0, 0.001, "full volume at a walk")
	check_near(Footsteps.gait_db(WalkAnim.FOOTSTEP_MIN_GAIT), Footsteps.SLOW_DROP_DB, 0.001, "softer easing in")
	check(Footsteps.hears(7, 7, 999.0), "your own steps are always heard")
	check(Footsteps.hears(3, 7, Footsteps.HEAR_RANGE - 0.1), "near player heard")
	check(not Footsteps.hears(3, 7, Footsteps.HEAR_RANGE + 0.1), "far player silent")


func test_pick_chooses_voice_volume_and_range() -> void:
	var fs := Footsteps.new()
	var me := Node3D.new()
	var other := Node3D.new()
	var far := Node3D.new()
	other.position = Vector3(4, 0, 0)
	far.position = Vector3(60, 0, 0)
	var anim := WalkAnim.new()
	_walk(anim, GameConfig.WALK_SPEED, 1.0)
	anim.stepped = true
	var mine := fs.pick(1, me, anim, 1, Vector3.ZERO)
	check(not mine.is_empty() and mine.own, "own step plays on the flat voice")
	check_near(mine.db, Footsteps.OWN_DB + Footsteps.gait_db(anim.amount()), 0.001, "own volume")
	check(absf(mine.pitch - 1.0) <= Footsteps.PITCH_SPREAD + 0.0001, "pitch varies a little")
	var theirs := fs.pick(2, other, anim, 1, Vector3.ZERO)
	check(not theirs.is_empty() and not theirs.own, "near player's step is positional")
	check(fs.pick(3, far, anim, 1, Vector3.ZERO).is_empty(), "far step is silent")
	check(fs.pick(1, null, anim, 1, Vector3.ZERO).is_empty(), "no node, no sound")
	anim.stepped = false
	check(fs.pick(1, me, anim, 1, Vector3.ZERO).is_empty(), "no foot down, no sound")
	# Outside the scene tree (as here) step() never plays, and says so.
	anim.stepped = true
	check(not fs.step(1, me, anim, 1, Vector3.ZERO), "nothing plays outside the tree")
	check_eq(fs.played, 0, "played count")
	for n in [me, other, far]:
		n.free()


func test_voice_rides_the_avatar() -> void:
	var fs := Footsteps.new()
	var avatar := Node3D.new()
	var v := fs.voice(9, avatar)
	check(v.get_parent() == avatar, "3D voice is a child of the avatar")
	check(fs.voice(9, avatar) == v, "made once")
	check_near(v.max_distance, Footsteps.HEAR_RANGE, 0.001, "fades out by the hearing range")
	fs.forget(9)
	check(not fs.voices.has(9), "forget drops the voice")
	avatar.free()

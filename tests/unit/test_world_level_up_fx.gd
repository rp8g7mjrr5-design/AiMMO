extends TestCase
## World stream: the level-up burst (LevelUpFx). The column, ring, light and sparks are pure
## maths, so this runs headless; the node is driven with advance() off the scene tree.


func test_column_shoots_up_holds_and_fades() -> void:
	check_eq(LevelUpFx.column_at(0.0).strength, 0.0, "nothing before the burst")
	check_eq(LevelUpFx.column_at(LevelUpFx.DURATION).strength, 0.0, "gone at the end")
	var early := LevelUpFx.column_at(0.25)
	check(early.height > 0.9 * LevelUpFx.COLUMN_HEIGHT, "full height within a quarter second (%.2f m)" % early.height)
	check(early.strength >= 1.0, "bright while it holds")
	check(LevelUpFx.column_at(0.05).strength > LevelUpFx.column_at(0.4).strength, "a pop at the start")
	check(LevelUpFx.column_at(1.8).strength < 0.2, "faded by the end")
	var t := 0.01
	while t < LevelUpFx.DURATION:
		var c := LevelUpFx.column_at(t)
		check(c.radius > 0.25 and c.radius <= LevelUpFx.COLUMN_RADIUS, "column hugs the avatar at %.2f (%.2f m)" % [t, c.radius])
		check(c.height >= 0.0 and c.height < 7.0, "column height sane at %.2f" % t)
		t += 0.05


func test_ring_and_light_go_out() -> void:
	check_eq(LevelUpFx.ring_at(0.0).strength, 0.0, "no ring before")
	check(LevelUpFx.ring_at(0.1).radius < LevelUpFx.ring_at(0.6).radius, "ring rolls outward")
	check_eq(LevelUpFx.ring_at(1.0).strength, 0.0, "ring gone in under a second")
	check(LevelUpFx.light_at(0.1) > 0.8 * LevelUpFx.LIGHT_ENERGY, "light flashes up at once")
	check_eq(LevelUpFx.light_at(LevelUpFx.DURATION), 0.0, "light out at the end")
	check(LevelUpFx.light_at(0.3) > LevelUpFx.light_at(1.5), "light falls off")


func test_sparks_rise_round_the_avatar_and_burn_out() -> void:
	var sp := LevelUpFx.sparks(3)
	check_eq(sp.size(), LevelUpFx.SPARKS, "spark count")
	var highest := 0.0
	for s in sp:
		check(s.delay + s.life <= LevelUpFx.DURATION, "spark ends inside the burst")
		check(s.color.r > s.color.g and s.color.g > s.color.b, "spark is warm")
		var prev_y := -1.0
		var t := 0.0
		while t <= LevelUpFx.DURATION:
			var xf := LevelUpFx.spark_at(s, t)
			if not xf.basis.get_scale().is_zero_approx():
				var p := xf.origin
				check(p.y > 0.0, "spark above the ground")
				check(Vector2(p.x, p.z).length() < 1.8, "spark stays round the avatar")
				check(p.y >= prev_y - 0.001, "spark only climbs")
				prev_y = p.y
				highest = maxf(highest, p.y)
			t += 0.05
		check(LevelUpFx.spark_at(s, s.delay + s.life).basis.get_scale().is_zero_approx(), "spark burnt out")
	check(highest > 2.2, "sparks rise past the head (%.2f m)" % highest)


func test_sparks_deterministic_and_varied() -> void:
	var a := LevelUpFx.sparks(1)
	var b := LevelUpFx.sparks(1)
	var c := LevelUpFx.sparks(2)
	check_eq(a[5].r0, b[5].r0, "same seed, same sparks")
	check(a[5].r0 != c[5].r0, "another seed, other sparks")


func test_play_restarts_one_burst_and_finishes() -> void:
	var avatar := AvatarBuilder.rig()
	var fx := LevelUpFx.play(avatar)
	check(fx.get_parent() == avatar, "burst sits on the avatar")
	for n in ["Column", "Ring", "Sparks", "Light"]:
		check(fx.get_node_or_null(n) != null, "burst has its %s" % n)
	fx.advance(0.2)
	check((fx.get_node("Column") as MultiMeshInstance3D).visible, "column shows")
	check((fx.get_node("Light") as OmniLight3D).light_energy > 1.0, "light on")
	var again := LevelUpFx.play(avatar, 1)
	check(again == fx, "a second level-up restarts the same burst")
	check_eq(fx.age, 0.0, "restarted from the top")
	var count := 0
	for ch in avatar.get_children():
		if ch is LevelUpFx:
			count += 1
	check_eq(count, 1, "never two bursts stacked on one avatar")
	var done := false
	for i in 200:
		done = fx.advance(1.0 / 60.0)
		if done:
			break
	check(done, "burst ends")
	check(not fx.visible and not (fx.get_node("Light") as OmniLight3D).visible, "nothing left showing")
	check(fx.advance(0.1), "stays finished")
	avatar.free()


func test_daylight_widens_lifts_and_bounds_the_column() -> void:
	var t := 0.05
	while t < LevelUpFx.DURATION:
		var night := LevelUpFx.column_at(t, 0.0)
		var day := LevelUpFx.column_at(t, 1.0)
		check(day.radius >= night.radius * 1.45, "day column wider at %.2f (%.2f vs %.2f m)" % [t, day.radius, night.radius])
		check(day.height >= night.height * 1.15, "day column taller at %.2f" % t)
		check(day.radius <= LevelUpFx.COLUMN_RADIUS * (1.0 + LevelUpFx.DAY_WIDEN), "day column still hugs the avatar at %.2f" % t)
		check_eq(day.strength, night.strength, "same timing by day and night at %.2f" % t)
		t += 0.05
	check_eq(LevelUpFx.column_at(0.3).radius, LevelUpFx.column_at(0.3, 0.0).radius, "no day argument means tonight's look")


func test_sky_beam_shoots_high_by_day_and_stays_faint_at_night() -> void:
	check_eq(LevelUpFx.beam_at(0.0, 1.0).strength, 0.0, "no beam before the burst")
	check_eq(LevelUpFx.beam_at(LevelUpFx.BEAM_TIME, 1.0).strength, 0.0, "beam gone at BEAM_TIME")
	check(LevelUpFx.BEAM_TIME < LevelUpFx.DURATION, "beam ends inside the burst")
	var up := LevelUpFx.beam_at(0.4, 1.0)
	check(up.height > 20.0, "beam clears the trees within 0.4 s (%.1f m)" % up.height)
	check(up.strength > 0.9, "beam full by day (%.2f)" % up.strength)
	check(up.radius < LevelUpFx.COLUMN_RADIUS * 0.5, "beam slimmer than the column")
	var night := LevelUpFx.beam_at(0.4, 0.0)
	check(night.strength < 0.5 and night.strength > 0.0, "beam faint at night (%.2f)" % night.strength)
	check(LevelUpFx.beam_at(1.3, 1.0).strength < LevelUpFx.beam_at(0.6, 1.0).strength, "beam fades")
	# 24 m at 45 m away is ~28 degrees of sky: well above the tree line from the meadow edge.
	check(rad_to_deg(atan(LevelUpFx.BEAM_HEIGHT / 45.0)) > 20.0, "beam tall enough to see from 45 m")


func test_play_reads_the_sky_and_draws_the_beam_in_the_column_multimesh() -> void:
	var saved := DayNight.pinned_fraction
	var avatar := AvatarBuilder.rig()
	DayNight.pinned_fraction = 0.5
	var fx := LevelUpFx.play(avatar)
	check_near(fx.daylight, 1.0, 0.01, "noon reads as full day")
	DayNight.pinned_fraction = 0.0
	LevelUpFx.play(avatar)
	check_near(fx.daylight, 0.0, 0.01, "midnight reads as night")
	DayNight.pinned_fraction = saved
	LevelUpFx.play(avatar, 2, 1.0)
	check_eq(fx.daylight, 1.0, "an explicit day wins over the sky")
	var mm := (fx.get_node("Column") as MultiMeshInstance3D).multimesh
	check_eq(mm.instance_count, 2, "column and beam share one MultiMesh (one draw call)")
	check(mm.use_custom_data, "each instance carries its own strength")
	fx.advance(0.45)
	check(fx.beam_now.height > 20.0, "beam drawn tall (%.1f m)" % fx.beam_now.height)
	check(fx.beam_now.strength > 0.9, "beam at full strength by day")
	check(fx.column_now.radius > LevelUpFx.COLUMN_RADIUS, "day column drawn wider than the night one")
	check_eq(float((fx.get_node("Column") as MultiMeshInstance3D).material_override.get_shader_parameter("day")), 1.0, "shader told it is day")
	fx.advance(LevelUpFx.BEAM_TIME - 0.4)
	check_eq(fx.beam_now.strength, 0.0, "beam over")
	check(fx.column_now.strength > 0.0, "column still finishing")
	check((fx.get_node("Column") as MultiMeshInstance3D).visible, "column still showing")
	avatar.free()


## One burst run frame by frame on a real avatar, the way the client plays it, checking what
## the node actually drew each frame (sparks_now, column_now, beam_now). Returns
## {lit, beam_top, frames, sparks_seen, done} or fails checks as it goes.
## `restart_at` > 0 plays a second level-up that far in (two skills on one gather).
func _run_burst(avatar: Node3D, seed_value: int, day: float, fps: float, restart_at: float = -1.0) -> Dictionary:
	var fx := LevelUpFx.play(avatar, seed_value, day)
	var frame := 1.0 / fps
	var out := {"lit": false, "beam_top": 0.0, "frames": 0, "sparks_seen": 0, "done": false, "restarted": false}
	var stray := 0
	var beam_late := 0
	for i in int((LevelUpFx.DURATION + 1.0) * fps) + 30:
		out.done = fx.advance(frame)
		out.frames += 1
		var light := fx.get_node("Light") as OmniLight3D
		if light.visible and light.light_energy > 1.0:
			out.lit = true
		out.beam_top = maxf(out.beam_top, float(fx.beam_now.height))
		if fx.age >= LevelUpFx.BEAM_TIME and float(fx.beam_now.strength) > 0.0:
			beam_late += 1
		for p in fx.sparks_now:
			out.sparks_seen += 1
			if p.y < 0.0 or Vector2(p.x, p.z).length() > 2.0:
				stray += 1
		if restart_at > 0.0 and not out.restarted and fx.age > restart_at:
			out.restarted = true
			var again := LevelUpFx.play(avatar, seed_value + 1000, day)
			check(again == fx and fx.age == 0.0, "seed %d: a second level-up restarts the burst" % seed_value)
		if out.done:
			break
	check_eq(stray, 0, "seed %d: every drawn spark stays round the avatar and above its feet" % seed_value)
	check_eq(beam_late, 0, "seed %d: sky beam gone by BEAM_TIME" % seed_value)
	check(not fx.visible and not (fx.get_node("Light") as OmniLight3D).visible and fx.sparks_now.is_empty(), "seed %d: burst ends with nothing showing" % seed_value)
	check(fx.position == Vector3.ZERO, "seed %d: burst sits at the avatar's feet, so it follows the avatar" % seed_value)
	var count := 0
	for ch in avatar.get_children():
		if ch is LevelUpFx:
			count += 1
	check_eq(count, 1, "seed %d: one burst on the avatar" % seed_value)
	return out


## The checks the world_level_up_fx bot behaviour used to run inside every bot (11 bursts
## each), now once here over 64 seeds, day and night, with and without a restart, at the
## spots players actually level: the meadow, a few ash and stone nodes, the tier-2 landmarks.
func test_bursts_play_cleanly_on_a_real_avatar_everywhere() -> void:
	var avatar := AvatarBuilder.rig()
	var spots: Array = [Vector3.ZERO]
	var nodes := ResourceNodes.all()
	for i in range(0, nodes.size(), 37):
		spots.append(nodes[i].pos)
	for n in ResourceNodes.tier2():
		spots.append(n.pos)
	var total_sparks := 0
	var day_beams := 0
	for seed_value in 64:
		var spot: Vector3 = spots[seed_value % spots.size()]
		avatar.position = Vector3(spot.x, Terrain.height(spot.x, spot.z), spot.z)
		var day := 1.0 if seed_value % 2 == 0 else 0.0
		var restart := 0.6 if seed_value % 4 == 1 else -1.0
		var r := _run_burst(avatar, seed_value * 31 + 2, day, 30.0, restart)
		check(r.lit, "seed %d: the light came on" % seed_value)
		check(r.done, "seed %d: the burst finished" % seed_value)
		total_sparks += int(r.sparks_seen)
		if day > 0.5:
			check(float(r.beam_top) >= 20.0, "seed %d: day beam reached %.1f m" % [seed_value, r.beam_top])
			day_beams += 1
	check(total_sparks > 64 * LevelUpFx.SPARKS, "sparks were really drawn (%d spark-frames)" % total_sparks)
	check_eq(day_beams, 32, "every day burst checked its beam")
	avatar.free()


## A slow laptop and a 144 Hz screen see the same burst: it lasts DURATION whatever the
## frame rate, and the beam clears the trees on both.
func test_burst_lasts_the_same_at_any_frame_rate() -> void:
	var avatar := AvatarBuilder.rig()
	for fps in [15.0, 30.0, 60.0, 144.0]:
		var r := _run_burst(avatar, 7, 1.0, fps)
		var seconds: float = float(r.frames) / fps
		check(seconds >= LevelUpFx.DURATION - 0.001 and seconds <= LevelUpFx.DURATION + 1.0 / fps + 0.001, "%d fps: burst lasts %.3f s" % [int(fps), seconds])
		check(float(r.beam_top) >= 20.0, "%d fps: beam clears the trees" % int(fps))
		check(int(r.sparks_seen) > 0, "%d fps: sparks drawn" % int(fps))
	avatar.free()


func test_sparks_now_follows_what_is_drawn() -> void:
	var avatar := AvatarBuilder.rig()
	var fx := LevelUpFx.play(avatar, 5, 0.0)
	check(fx.sparks_now.is_empty(), "no sparks at the very start")
	fx.advance(0.7)
	var want := 0
	for s in LevelUpFx.sparks(5):
		if not LevelUpFx.spark_at(s, fx.age).basis.get_scale().is_zero_approx():
			want += 1
	check(want > 0, "some sparks are up at 0.7 s")
	check_eq(fx.sparks_now.size(), want, "sparks_now lists exactly the sparks drawn")
	LevelUpFx.play(avatar, 5, 0.0)
	check(fx.sparks_now.is_empty(), "a restart clears them")
	avatar.free()

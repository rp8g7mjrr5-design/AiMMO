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

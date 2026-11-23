extends TestCase
## XP you can see (Milestone 1, part 1): the "+12 Felling" floater and the skill bar's texts,
## slide, fades and running totals.


func test_texts() -> void:
	check_eq(XpMeter.gain_text("felling", 12), "+12 Felling")
	check_eq(XpMeter.gain_text("toolcraft", 40), "+40 Toolcraft")
	check_eq(XpMeter.level_text("quarrying", 0), "Quarrying 1 · %d XP to 2" % Skills.xp_for_level(2))
	var xp := Skills.xp_for_level(3) + 40
	check_eq(XpMeter.level_text("felling", xp), "Felling 3 · %d XP to 4" % (Skills.xp_for_level(4) - xp))
	check_eq(XpMeter.level_text("tapping", Skills.xp_for_level(Skills.CAP) + 5), "Tapping 100 · max")


func test_gain_motion_within_a_level() -> void:
	var m := XpMeter.gain_motion(20, 10, 30)
	check_eq(int(m.levels), 0)
	check_near(float(m.from), Skills.progress(20), 0.0001)
	check_near(float(m.to), Skills.progress(30), 0.0001)
	check(float(m.to) > float(m.from), "the bar grows")


func test_gain_motion_without_a_known_total_assumes_total_minus_gain() -> void:
	var m := XpMeter.gain_motion(-1, 10, 30)
	check_near(float(m.from), Skills.progress(20), 0.0001)
	var odd := XpMeter.gain_motion(500, 10, 30) # a stale higher total never runs the bar backwards past 0 levels
	check_eq(int(odd.levels), 0)


func test_gain_motion_across_a_level() -> void:
	var two := Skills.xp_for_level(2)
	var m := XpMeter.gain_motion(two - 5, 10, two + 5)
	check_eq(int(m.levels), 1, "crossed into level 2")
	check(float(m.to) < float(m.from), "the new level's bar starts low again")


func test_bar_value_slides_and_lands() -> void:
	check_near(XpMeter.bar_value(0.2, 0.5, 0, 0.0), 0.2, 0.0001, "starts where it was")
	check_near(XpMeter.bar_value(0.2, 0.5, 0, XpMeter.FILL_SECONDS), 0.5, 0.0001, "lands where it is")
	check_near(XpMeter.bar_value(0.2, 0.5, 0, 99.0), 0.5, 0.0001)
	var mid := XpMeter.bar_value(0.2, 0.5, 0, XpMeter.FILL_SECONDS * 0.5)
	check(mid > 0.35 and mid < 0.5, "eases out: past halfway at half time (%f)" % mid)
	var prev := 0.0
	for i in 11:
		var v := XpMeter.bar_value(0.2, 0.5, 0, XpMeter.FILL_SECONDS * i / 10.0)
		check(v >= prev - 0.0001, "never goes backwards")
		prev = v


func test_bar_value_runs_through_full_on_a_level_up() -> void:
	var saw_high := false
	var saw_wrap := false
	var prev := 0.8
	var end := XpMeter.settle_seconds(1)
	for i in 81:
		var v := XpMeter.bar_value(0.8, 0.1, 1, end * i / 80.0)
		check(v >= 0.0 and v <= 1.0, "stays a legal bar value")
		if v > 0.95:
			saw_high = true
		if v < prev - 0.5:
			saw_wrap = true
		prev = v
	check(saw_high, "fills to the top")
	check(saw_wrap, "wraps to the new level")
	check_near(XpMeter.bar_value(0.8, 0.1, 1, end), 0.1, 0.0001, "lands in the new level")
	check_near(XpMeter.bar_value(0.8, 0.1, 1, 99.0), 0.1, 0.0001)


func test_a_level_up_holds_the_bar_full_while_the_banner_pops() -> void:
	check_near(XpMeter.bar_value(0.8, 0.1, 1, 0.0), 0.8, 0.0001, "starts where it was")
	check_near(XpMeter.bar_value(0.8, 0.1, 1, XpMeter.FILL_SECONDS), 1.0, 0.0001, "full when the fill ends")
	for i in 11:
		var age := XpMeter.FILL_SECONDS + XpMeter.LEVEL_HOLD * i / 10.0 - 0.0001
		check_near(XpMeter.bar_value(0.8, 0.1, 1, age), 1.0, 0.0001, "holds full at %.2f s" % age)
	check(XpMeter.holding_full(1, XpMeter.FILL_SECONDS + 0.1), "brightens while it holds")
	check(not XpMeter.holding_full(1, 0.1), "not while it fills")
	check(not XpMeter.holding_full(0, XpMeter.FILL_SECONDS + 0.1), "a gain inside a level never holds")
	check(not XpMeter.holding_full(1, XpMeter.settle_seconds(1)), "done by the time it settles")
	check_near(XpMeter.settle_seconds(0), XpMeter.FILL_SECONDS, 0.0001, "within a level: as before")
	# The hold overlaps the banner's full-alpha stretch, so the full bar and "Felling 5" read together.
	var banner_full_until := LevelUpBanner.DURATION - LevelUpBanner.FADE_SECONDS
	check(XpMeter.FILL_SECONDS + XpMeter.LEVEL_HOLD <= banner_full_until, "the bar holds while the banner is fully up")
	check(XpMeter.settle_seconds(1) < XpMeter.HOLD_SECONDS, "the bar settles before it starts to fade")
	# Never runs backwards while filling or after the wrap.
	var prev := 0.0
	for i in 21:
		var v := XpMeter.bar_value(0.8, 0.6, 1, XpMeter.FILL_SECONDS + XpMeter.LEVEL_HOLD + XpMeter.WRAP_SECONDS * i / 20.0 + 0.0001)
		check(v >= prev - 0.0001, "the new level's slide only rises")
		prev = v


func test_fades() -> void:
	check_near(XpMeter.float_alpha(0.0), 1.0, 0.0001)
	check_near(XpMeter.float_alpha(XpMeter.FLOAT_SECONDS), 0.0, 0.0001)
	check(XpMeter.float_alpha(XpMeter.FLOAT_SECONDS * 0.75) < 1.0, "fades in its second half")
	check_near(XpMeter.bar_alpha(XpMeter.HOLD_SECONDS), 1.0, 0.0001, "bar holds")
	check_near(XpMeter.bar_alpha(XpMeter.HOLD_SECONDS + XpMeter.FADE_SECONDS), 0.0, 0.0001, "then goes")
	check(XpMeter.FLOAT_SECONDS < XpMeter.HOLD_SECONDS, "the number goes before the bar")
	check(XpMeter.HOLD_SECONDS + XpMeter.FADE_SECONDS < 5.0, "out of the way within a few seconds")


func test_node_shows_and_hides() -> void:
	var m := XpMeter.new()
	m.setup(Theme.new())
	check(not m.showing(), "nothing at login")
	m.on_skills({"felling": 140, "quarrying": "12", "junk": -3})
	check_eq(int(m.skills.felling), 140)
	check_eq(int(m.skills.quarrying), 12, "normalized")
	var r := m.on_gain("felling", 10, 150)
	check_eq(int(r.levels), 1, "140 + 10 reaches level 2")
	check_eq(m.gain_label.text, "+10 Felling")
	check(m.level_label.text.begins_with("Felling 2"), m.level_label.text)
	check(m.showing(), "the gain shows")
	check_near(m.gain_label.modulate.a, 1.0, 0.0001)
	m.step(XpMeter.FILL_SECONDS + 0.1)
	check_near(m.bar.value, 1.0, 0.0001, "a level-up holds the bar full first")
	check(m.bar.self_modulate.r > 1.0, "and brightens it")
	check(not m.settled(), "not at rest while it holds")
	m.step(XpMeter.LEVEL_HOLD + XpMeter.WRAP_SECONDS)
	check(m.settled(), "at rest after the hold and the slide")
	check_near(m.bar.value, Skills.progress(150), 0.0001, "bar landed")
	check_eq(m.bar.self_modulate, Color.WHITE, "glow gone")
	m.step(XpMeter.HOLD_SECONDS + XpMeter.FADE_SECONDS)
	check(not m.showing(), "faded")
	check_near(m.gain_label.modulate.a, 0.0, 0.0001)
	m.on_gain("toolcraft", 40, 40)
	check_eq(m.current_skill(), "toolcraft")
	m.hide_all()
	check(not m.showing(), "hidden")
	check(m.skills.is_empty(), "totals cleared")
	m.free()

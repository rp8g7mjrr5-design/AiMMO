extends TestCase
## The level-up moment (Milestone 1, part 2): the banner's texts, pop and fade, the chat line
## it swallows, and the rising chord.


func test_texts() -> void:
	check_eq(LevelUpBanner.title_text("felling", 5), "Felling 5")
	var u5: Dictionary = Skills.unlock_at("felling", 5)
	check_eq(LevelUpBanner.unlock_text("felling", [u5]), "Old ember ash: work the old ember ashes past the meadow", "live since tier-2 nodes landed (#104)")
	var soon := u5.duplicate()
	soon["soon"] = true
	check_eq(LevelUpBanner.unlock_text("felling", [soon]), "Old ember ash: work the old ember ashes past the meadow (coming soon)", "an unlock not yet in the world says so")
	var u10: Dictionary = Skills.unlock_at("felling", 10)
	check_eq(LevelUpBanner.unlock_text("felling", [u10]), "Clean cuts: +1 wood from every gather")
	check_eq(LevelUpBanner.unlock_text("quarrying", []), "Your %s are a little quicker" % str(Skills.SKILLS.quarrying.verb))
	check_eq(LevelUpBanner.unlock_text("toolcraft", []), "", "a plain Toolcraft level gives nothing to say")
	check_eq(LevelUpBanner.unlock_text("junk", []), "")
	check(LevelUpBanner.unlock_text("felling", [u5, u10]).contains("  ·  "), "two unlocks side by side")
	check_eq(LevelUpBanner.unlock_text("felling", ["not a dict"]), "", "bad entries skipped")
	check_eq(LevelUpBanner.next_text("felling", 2), "Next: Felling 5, Old ember ash")
	check_eq(LevelUpBanner.next_text("felling", 5), "Next: Felling 10, Clean cuts")
	check_eq(LevelUpBanner.next_text("felling", 25), "", "nothing named left")


func test_pop_and_fade() -> void:
	check_near(LevelUpBanner.pop_scale(0.0), 0.6, 0.0001)
	var peak := 0.0
	for i in 40:
		peak = maxf(peak, LevelUpBanner.pop_scale(LevelUpBanner.POP_SECONDS * i / 40.0))
	check(peak > 1.03 and peak < 1.15, "overshoots a little (%.3f)" % peak)
	check_near(LevelUpBanner.pop_scale(LevelUpBanner.POP_SECONDS), 1.0, 0.0001, "settles")
	check_near(LevelUpBanner.alpha(0.0), 0.0, 0.0001)
	check_near(LevelUpBanner.alpha(0.5), 1.0, 0.0001, "holds")
	check(LevelUpBanner.alpha(LevelUpBanner.DURATION - 0.1) < 1.0, "fading at the end")
	check_near(LevelUpBanner.alpha(LevelUpBanner.DURATION), 0.0, 0.0001, "gone")
	check(LevelUpBanner.DURATION < 2.0, "the moment is short (design: under 2 s)")


func test_node_shows_swallows_and_hides() -> void:
	var b := LevelUpBanner.new()
	b.setup(Theme.new())
	check(not b.showing(), "nothing at first")
	check_eq(b.mouse_filter, Control.MOUSE_FILTER_IGNORE, "never takes the mouse")
	for c in b.get_children():
		check_eq((c as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % c.name)
	var u: Dictionary = Skills.unlock_at("felling", 5)
	b.on_level_up("felling", 5, [u])
	b.step(0.3)
	check(b.showing(), "shows")
	check_eq(b.current(), "Felling 5")
	check_eq(b.title_label.text, "Felling 5")
	check(b.unlock_label.text.begins_with("Old ember ash"), b.unlock_label.text)
	check(b.icon.texture != null, "the skill badge")
	var line := Skills.level_up_text({"skill": "felling", "level": 5, "unlocks": [u]})
	check_eq(LevelUpBanner.announcement("felling", 5, [u]), line)
	check(not b.consume_system("Someone said hi"), "other lines go to chat")
	check(b.consume_system(line), "its own announcement stays out of chat")
	check(not b.consume_system(line), "but only once")
	b.step(LevelUpBanner.DURATION)
	check(not b.showing(), "gone within DURATION")
	check_near(b.modulate.a, 0.0, 0.0001)
	b.on_level_up("toolcraft", 2, [])
	check_eq(b.unlock_label.text, "")
	b.hide_all()
	check(not b.showing(), "hidden")
	check(not b.consume_system(LevelUpBanner.announcement("toolcraft", 2, [])), "hide clears the pending line")
	b.free()


func test_level_up_sound() -> void:
	var w := Sfx.level_up()
	var samples := w.data.size() / 2
	check_near(float(samples) / Sfx.RATE, Sfx.LEVEL_UP_SECONDS, 0.01, "about 1.5 s")
	check(Sfx.LEVEL_UP_SECONDS < 2.0, "short")
	var peak := 0
	var last := 0
	for i in samples:
		var v := w.data.decode_s16(i * 2)
		peak = maxi(peak, absi(v))
		if i == samples - 1:
			last = absi(v)
	check(peak > 6000, "audible (%d)" % peak)
	check(peak < 32767, "doesn't clip")
	check(last < 200, "ends without a click")
	# It rises: the notes come in low to high.
	for i in range(1, Sfx.LEVEL_UP_NOTES.size()):
		check(float(Sfx.LEVEL_UP_NOTES[i][1]) > float(Sfx.LEVEL_UP_NOTES[i - 1][1]), "rising")

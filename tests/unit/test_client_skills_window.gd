extends TestCase
## The skills window and the next-goal line (Milestone 1, part 3): totals, per-skill texts,
## the closest-unlock goal, the K key, and the window's rows following the server's numbers.


func test_totals() -> void:
	check_eq(SkillsWindow.total_level({}), 4, "a new character is level 1 in four skills")
	check_eq(SkillsWindow.total_text({}), "Total level 4  ·  0 XP")
	var all := {"felling": Skills.xp_for_level(5), "quarrying": Skills.xp_for_level(2) + 10}
	check_eq(SkillsWindow.total_level(all), 5 + 2 + 1 + 1)
	check_eq(SkillsWindow.total_xp(all), Skills.xp_for_level(5) + Skills.xp_for_level(2) + 10)
	check_eq(SkillsWindow.total_text({"felling": 12345}), "Total level %d  ·  12,345 XP" % (Skills.level_for(12345) + 3))


func test_grouping() -> void:
	check_eq(SkillsWindow._grouped(0), "0")
	check_eq(SkillsWindow._grouped(999), "999")
	check_eq(SkillsWindow._grouped(1000), "1,000")
	check_eq(SkillsWindow._grouped(4800000), "4,800,000")


func test_row_texts() -> void:
	var xp := Skills.xp_for_level(3) + 40
	var all := {"felling": xp}
	check_eq(SkillsWindow.level_text(all, "felling"), "Felling 3")
	check_eq(SkillsWindow.xp_text(all, "felling"), "%s XP to level 4" % SkillsWindow._grouped(Skills.xp_for_level(4) - xp))
	check_eq(SkillsWindow.xp_text({"tapping": Skills.xp_for_level(Skills.CAP)}, "tapping"), "Max level")
	check_eq(SkillsWindow.next_text(all, "felling"), "Level 5: Old ember ash, work the old ember ashes past the meadow")
	# Bench sense is "coming soon" until gameplay's ember lantern recipe lands; either way the
	# line names it, and says "(coming soon)" exactly while the data says so.
	var bench = Skills.next_unlock("toolcraft", 1)
	var bench_line := SkillsWindow.next_text({}, "toolcraft")
	check(bench_line.begins_with("Level %d: %s" % [int(bench.level), str(bench.name)]), bench_line)
	check_eq(bench_line.ends_with(" (coming soon)"), bool(bench.get("soon", false)), bench_line)
	check_eq(SkillsWindow.next_text({"felling": Skills.xp_for_level(25)}, "felling"), "", "nothing named past Heartwood")


func test_goal_picks_the_closest_unlock() -> void:
	# Brand new: quarrying 5 and felling 5 cost the same; felling is listed first.
	var g := SkillsWindow.next_goal({})
	check_eq(str(g.skill), "felling")
	check_eq(int(g.level), 5)
	check_eq(int(g.need), Skills.xp_for_level(5))
	check_eq(SkillsWindow.goal_text({}), "Next: Felling 5 unlocks Old ember ash (%s XP)" % SkillsWindow._grouped(Skills.xp_for_level(5)))
	# Some quarrying done: the rich seam is now closer.
	var all := {"quarrying": Skills.xp_for_level(4) + 30}
	g = SkillsWindow.next_goal(all)
	check_eq(str(g.skill), "quarrying")
	check_eq(int(g.need), Skills.xp_for_level(5) - Skills.xp_for_level(4) - 30)
	check_eq(SkillsWindow.goal_key(all), "quarrying:5")


func test_goal_follows_the_skills_you_train() -> void:
	# A fresh character is pointed where the game starts (the first skill), never at a
	# Toolcraft unlock it has no materials for, however cheap that unlock is.
	check_eq(str(SkillsWindow.next_goal({}).skill), str(Skills.ORDER[0]))
	check_eq(str(SkillsWindow.next_goal({"toolcraft": 0, "tapping": 0}).skill), str(Skills.ORDER[0]), "0 XP is untrained")
	# Only trained skills compete: a little Toolcraft makes Toolcraft the goal, a little
	# Quarrying on top makes whichever is closer win.
	var g := SkillsWindow.next_goal({"toolcraft": 10})
	check(g.is_empty() or str(g.skill) == "toolcraft", "only toolcraft is trained (got %s)" % g)
	var both := {"tapping": 10, "quarrying": Skills.xp_for_level(5) - 5}
	check_eq(SkillsWindow.goal_key(both), "quarrying:5", "the closer of the trained skills")
	# Past the last unlock of everything you've trained: the untrained skills step in.
	var done := {str(Skills.ORDER[0]): Skills.xp_for_level(Skills.CAP)}
	var after := SkillsWindow.next_goal(done)
	check(not after.is_empty(), "a goal is still offered")
	check(str(after.get("skill", "")) != str(Skills.ORDER[0]), "from another skill (got %s)" % after)


func test_goal_skips_unlocks_not_in_the_world_yet() -> void:
	# Put a skill just short of a "coming soon" unlock, so it would be the cheapest goal; it
	# never becomes the goal. Found from the data, so it keeps working as soon unlocks get built
	# (Toolcraft 5 was soon until #110).
	for s in Skills.ORDER:
		var u = Skills.next_unlock(s, 0)
		while u != null and not u.get("soon", false):
			u = Skills.next_unlock(s, int(u.level))
		if u == null:
			continue
		var g := SkillsWindow.next_goal({s: Skills.xp_for_level(int(u.level)) - 5})
		check(g.is_empty() or str(g.name) != str(u.name), "a soon unlock is no goal (got %s)" % g)
	for s in Skills.ORDER:
		var u = Skills.next_unlock(s, 0)
		while u != null:
			if u.get("soon", false):
				check(not SkillsWindow.goal_text({}).contains(str(u.name)), "%s isn't a goal" % u.name)
			u = Skills.next_unlock(s, int(u.level))


func test_goal_moves_on_and_runs_out() -> void:
	var all := {"felling": Skills.xp_for_level(5)}
	check(SkillsWindow.goal_key(all) != "felling:5", "reached goals move on")
	var maxed := {}
	for s in Skills.ORDER:
		maxed[s] = Skills.xp_for_level(Skills.CAP)
	check_eq(SkillsWindow.goal_text(maxed), "", "no goal left at the cap")
	check_eq(SkillsWindow.goal_key(maxed), "")


func test_goal_colour_flashes_gold_and_settles() -> void:
	check(SkillsWindow.goal_colour(1.0).is_equal_approx(SkillsWindow.GOLD), "gold at the start of a flash")
	check(SkillsWindow.goal_colour(0.0).is_equal_approx(SkillsWindow.GOAL_COLOUR), "quiet at rest")
	check(SkillsWindow.GOAL_FLASH_SECONDS < 2.0, "the flash is short")


func test_goal_line_steps_aside_for_the_level_up_banner() -> void:
	check_near(SkillsWindow.goal_alpha(0.0), 1.0, 0.0001, "no banner: the goal line shows")
	check_near(SkillsWindow.goal_alpha(1.0), 0.0, 0.0001, "banner fully up: hidden")
	check_near(SkillsWindow.goal_alpha(LevelUpBanner.alpha(LevelUpBanner.DURATION - LevelUpBanner.FADE_SECONDS * 0.5)), 0.5, 0.0001, "cross-fades as the banner goes")
	check_near(SkillsWindow.goal_alpha(LevelUpBanner.alpha(LevelUpBanner.DURATION)), 1.0, 0.0001, "back when it's gone")
	check_near(SkillsWindow.goal_alpha(7.0), 0.0, 0.0001, "clamped")
	# The new goal's gold flash waits behind the banner and plays as it hands over.
	var flash := SkillsWindow.GOAL_FLASH_SECONDS
	for i in 30:
		flash = SkillsWindow.goal_flash_after(flash, 0.1, true)
	check_near(flash, SkillsWindow.GOAL_FLASH_SECONDS, 0.0001, "held while the banner is up")
	flash = SkillsWindow.goal_flash_after(flash, 0.5, false)
	check_near(flash, SkillsWindow.GOAL_FLASH_SECONDS - 0.5, 0.0001, "runs once it's gone")
	check_near(SkillsWindow.goal_flash_after(0.2, 1.0, false), 0.0, 0.0001, "never below zero")


func test_k_opens_it() -> void:
	ControlsOverlay.install_input()
	check_eq(ControlsOverlay.key_text("toggle_skills"), "K")
	check(ControlsOverlay.listed_actions().has("toggle_skills"), "K is in the F1 list")


func test_window_rows_follow_the_server() -> void:
	var w := SkillsWindow.new()
	w.setup(Theme.new())
	check(not w.visible, "starts hidden")
	check_eq(w.total_shown(), "Total level 4  ·  0 XP")
	w.on_skills({"felling": 200, "quarrying": 0, "tapping": 0, "toolcraft": 0})
	check_eq(str(w.row_texts("felling").level), "Felling %d" % Skills.level_for(200))
	check_near(float(w.row_texts("felling").bar), Skills.progress(200), 0.0001)
	w.on_gain("felling", 260)
	check_eq(str(w.row_texts("felling").xp), SkillsWindow.xp_text({"felling": 260}, "felling"), "a gain updates the row")
	w.on_gain("junk", 99)
	check(not w.skills.has("junk"), "unknown skills ignored")
	var closes := [0]
	w.closed.connect(func(): closes[0] += 1)
	w.toggle()
	check(w.visible, "toggle opens")
	w.toggle()
	check(not w.visible, "toggle closes")
	check_eq(closes[0], 1)
	w.reset()
	check_eq(w.total_shown(), "Total level 4  ·  0 XP", "reset forgets the old character")
	w.free()

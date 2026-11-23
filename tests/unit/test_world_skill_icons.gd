extends TestCase
## World stream: procedural skill badges (SkillIcons). Every skill in Skills.ORDER has its
## own round badge, drawn in code, inside the square, telling apart from the others by
## colour alone at small sizes, and the same every time. Unknown skill ids get a plain badge.


func _stats(img: Image) -> Dictionary:
	var n := img.get_width()
	var solid := 0
	var border := 0.0
	var corner := 0.0
	var sum := Color(0, 0, 0, 0)
	for y in n:
		for x in n:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				solid += 1
				sum += Color(c.r, c.g, c.b, 1.0)
			if x == 0 or y == 0 or x == n - 1 or y == n - 1:
				border = maxf(border, c.a)
			if (x < n / 8 or x >= n - n / 8) and (y < n / 8 or y >= n - n / 8):
				corner = maxf(corner, c.a)
	var mean := Color(sum.r / maxf(sum.a, 1.0), sum.g / maxf(sum.a, 1.0), sum.b / maxf(sum.a, 1.0))
	return {"solid": float(solid) / (n * n), "border": border, "corner": corner, "mean": mean}


func test_every_skill_has_its_own_badge() -> void:
	for skill in Skills.ORDER:
		check(SkillIcons.has_icon(skill), "%s has a badge" % skill)
		check(SkillIcons.shapes(skill) != SkillIcons.shapes(SkillIcons.FALLBACK), "%s is not the plain badge" % skill)
	for skill in Skills.SKILLS:
		check(SkillIcons.has_icon(skill), "%s (Skills.SKILLS) has a badge" % skill)


func test_badges_are_round_and_inside_the_square() -> void:
	for skill in Skills.ORDER:
		var img := SkillIcons.image(skill, 48)
		check_eq(img.get_width(), 48, "%s width" % skill)
		var s := _stats(img)
		# A disc of radius 0.42 covers about 55% of its square.
		check(s.solid > 0.45 and s.solid < 0.7, "%s is a full disc (%.2f)" % [skill, s.solid])
		check(s.border < 0.15, "%s is not clipped (border alpha %.2f)" % [skill, s.border])
		check(s.corner < 0.15, "%s leaves the corners clear, so it reads round (%.2f)" % [skill, s.corner])
		for sh in SkillIcons.shapes(skill):
			var c: Vector2 = sh.get("c", sh.get("a", Vector2(0.5, 0.5)))
			check(c.distance_to(SkillIcons.CENTRE) <= SkillIcons.RADIUS + 0.001, "%s emblem part %s sits on the disc" % [skill, sh.t])
			if sh.t == "poly":
				for q in sh.pts:
					check(q.distance_to(SkillIcons.CENTRE) <= SkillIcons.RADIUS, "%s emblem point %s sits on the disc" % [skill, q])


func test_badges_tell_apart_by_colour_at_small_size() -> void:
	var means := {}
	for skill in Skills.ORDER:
		means[skill] = _stats(SkillIcons.image(skill, 24)).mean
	var skills: Array = Skills.ORDER
	for i in skills.size():
		for j in range(i + 1, skills.size()):
			var a: Color = means[skills[i]]
			var b: Color = means[skills[j]]
			var d := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			check(d > 0.08, "%s and %s read apart by colour at 24 px (%.3f)" % [skills[i], skills[j], d])
	for skill in skills:
		check(SkillIcons.tint(skill) != SkillIcons.tint(SkillIcons.FALLBACK), "%s has its own tint" % skill)


func test_only_tapping_glows() -> void:
	for skill in Skills.ORDER:
		var glows := SkillIcons.shapes(skill).any(func(s): return s.get("glow", 0.0) > 0.0)
		check_eq(glows, skill == "tapping", "%s glow" % skill)


func test_deterministic_and_cached() -> void:
	check(SkillIcons.image("felling", 32).get_data() == SkillIcons.image("felling", 32).get_data(), "draws the same every time")
	var t := SkillIcons.texture("quarrying", 32)
	check(t != null, "texture exists")
	check(t == SkillIcons.texture("quarrying", 32), "texture is cached")
	check_eq(t.get_width(), 32, "texture size")


func test_unknown_skills_get_a_plain_badge() -> void:
	check(not SkillIcons.has_icon("sailing"), "unknown id has no own badge")
	check(SkillIcons.shapes("sailing") == SkillIcons.shapes(SkillIcons.FALLBACK), "unknown id gets the plain badge")
	check(_stats(SkillIcons.image("sailing", 32)).solid > 0.4, "the plain badge is drawn")
	check(SkillIcons.texture("sailing", 32) == SkillIcons.texture("fishing", 32), "every unknown id shares one texture")

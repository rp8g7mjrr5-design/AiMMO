extends TestCase
## A chosen look (Appearance) dresses the traveller, and a character who never chose keeps
## exactly the look their seed has always drawn.


func _all_looks(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var out: Array = []
	for i in n:
		out.append(Appearance.random(rng))
	return out


func test_no_look_is_the_seed_look() -> void:
	for s in [1, 42, 77777]:
		var a := AvatarBuilder.parts(s)
		var b := AvatarBuilder.parts(s, {})
		check_eq(a.size(), b.size(), "same parts")
		for i in a.size():
			check_eq(a[i].color, b[i].color, "part %d colour" % i)
			check_eq(a[i].pos, b[i].pos, "part %d place" % i)
		check_eq(AvatarBuilder.height_scale({}), 1.0, "seed looks stand 1.78 m")


func test_each_option_changes_the_figure() -> void:
	var base := Appearance.DEFAULT.duplicate()
	var p0 := AvatarBuilder.parts(5, base)
	for key in Appearance.ORDER:
		if key == "height":
			continue # the skeleton's scale, not the parts
		var lk := base.duplicate()
		lk[key] = (int(base[key]) + 1) % Appearance.count(key)
		var p1 := AvatarBuilder.parts(5, lk)
		var differs := p1.size() != p0.size()
		for i in mini(p0.size(), p1.size()):
			if differs:
				break
			differs = p0[i].color != p1[i].color or p0[i].pos != p1[i].pos or p0[i].scl != p1[i].scl or p0[i].mesh != p1[i].mesh
		check(differs, "changing %s changes the traveller" % key)
	var tall := base.duplicate()
	tall.height = Appearance.count("height") - 1
	check(AvatarBuilder.height_scale(tall) > 1.0, "tall stands taller")


func test_dyes_and_skin_come_from_the_palette() -> void:
	var lk := Appearance.DEFAULT.duplicate()
	lk.skin = 7
	lk.tunic = 2
	var p := AvatarBuilder.parts(5, lk)
	check_eq(p[1].color, Palette.skin_tone(7), "the head wears the chosen skin")
	var dye: Color = Palette.CLOTH[2]
	check(absf(p[0].color.h - dye.h) < 0.03 or dye.s < 0.1, "the tunic is the chosen dye, give or take its wear")


func test_every_look_fits_the_triangle_budget() -> void:
	for lk in _all_looks(40):
		var mesh := AvatarSkeleton.skin_parts(AvatarBuilder.parts(3, lk), AvatarBuilder.LIMB_PIVOTS)
		var tris := mesh.surface_get_array_index_len(0) / 3
		check(tris <= 3000, "inside the 3,000-triangle budget (%d) for %s" % [tris, lk])


func test_builds_widen_the_body_not_lengthen_it() -> void:
	var lean := Appearance.DEFAULT.duplicate()
	lean.body = 0
	var broad := Appearance.DEFAULT.duplicate()
	broad.body = 3
	var a := AvatarSkeleton.skin_parts(AvatarBuilder.parts(3, lean), AvatarBuilder.LIMB_PIVOTS).get_aabb()
	var b := AvatarSkeleton.skin_parts(AvatarBuilder.parts(3, broad), AvatarBuilder.LIMB_PIVOTS).get_aabb()
	check(b.size.x > a.size.x + 0.03, "broad is wider (%.2f vs %.2f)" % [b.size.x, a.size.x])
	check_near(b.size.y, a.size.y, 0.02, "and the same height")
	check_near(a.position.y, b.position.y, 0.01, "feet stay on the ground")


func test_head_gear_rides_the_head() -> void:
	# Hair, beards and the face's extra parts sit above AvatarSkeleton.HEAD_FROM (or down the
	# back for long hair), so they turn with the head, never float off it.
	for lk in _all_looks(20):
		for p in AvatarBuilder.head_gear(lk, Color.BLACK, Color.GRAY, Color.BROWN, Color.TAN):
			check((p.pos as Vector3).y > 1.35, "head gear %s too low" % [p.pos])

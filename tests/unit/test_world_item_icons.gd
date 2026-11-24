extends TestCase
## World stream: procedural inventory icons (ItemIcons). Every item has its own picture,
## drawn in code, inside the square, distinct from the others, and the same every time.
## Unknown item ids still get a picture (save compatibility: retired items stay visible).


## Fraction of pixels that are mostly opaque, and the most opaque pixel on the border.
func _stats(img: Image) -> Dictionary:
	var n := img.get_width()
	var solid := 0
	var border := 0.0
	var warm := 0
	for y in n:
		for x in n:
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				solid += 1
				if c.r > 0.9 and c.g > 0.45 and c.b < 0.5:
					warm += 1
			if x == 0 or y == 0 or x == n - 1 or y == n - 1:
				border = maxf(border, c.a)
	return {"solid": float(solid) / (n * n), "border": border, "warm": warm}


## Every item a player can hold: ITEM_ORDER plus the ones gameplay keeps in NEW_ITEMS until
## they move over, plus any UNDRAWN item world has drawn since (the ember tools), without
## repeats once they move over, plus items world drew ahead of gameplay (DRAWN_AHEAD).
func _all_items() -> Array:
	var out: Array = Inventory.ITEM_ORDER.duplicate()
	for item in Inventory.NEW_ITEMS:
		if not out.has(item):
			out.append(item)
	for item in Inventory.UNDRAWN:
		if not out.has(item) and ItemIcons.has_icon(item):
			out.append(item)
	for item in DRAWN_AHEAD:
		if not out.has(item):
			out.append(item)
	return out


## Icons world drew before gameplay added the item (gameplay's request in world's backlog):
## they get every check the real items get, so they are ready the moment the item exists.
const DRAWN_AHEAD := ["ember_lantern", "cooked_meat"]


func test_every_item_has_its_own_icon() -> void:
	for item in _all_items():
		check(ItemIcons.has_icon(item), "%s has an icon" % item)
		check(ItemIcons.shapes(item) != ItemIcons.shapes(ItemIcons.FALLBACK), "%s is not the fallback bundle" % item)
	for item in Inventory.ITEMS:
		check(ItemIcons.has_icon(item), "%s (Inventory.ITEMS) has an icon" % item)


func test_icons_fill_the_square_without_clipping() -> void:
	for item in _all_items():
		var img := ItemIcons.image(item, 48)
		check_eq(img.get_width(), 48, "%s width" % item)
		check_eq(img.get_height(), 48, "%s height" % item)
		var s := _stats(img)
		check(s.solid > 0.12 and s.solid < 0.75, "%s covers a sensible share of its square (%.2f)" % [item, s.solid])
		check(s.border < 0.15, "%s is not clipped at the edge (border alpha %.2f)" % [item, s.border])
		for sh in ItemIcons.shapes(item):
			var pts := []
			match sh.t:
				"circle":
					pts = [sh.c + Vector2(sh.r, sh.r), sh.c - Vector2(sh.r, sh.r)]
				"capsule":
					pts = [sh.a + Vector2(sh.r, sh.r), sh.a - Vector2(sh.r, sh.r), sh.b + Vector2(sh.r, sh.r), sh.b - Vector2(sh.r, sh.r)]
				"poly":
					pts = Array(sh.pts)
				"box":
					pts = [sh.c]
			for q in pts:
				check(q.x >= ItemIcons.MARGIN - 0.001 and q.x <= 1.0 - ItemIcons.MARGIN + 0.001 and q.y >= ItemIcons.MARGIN - 0.001 and q.y <= 1.0 - ItemIcons.MARGIN + 0.001,
					"%s shape %s stays inside the margin (%s)" % [item, sh.t, q])


func test_icons_are_distinct() -> void:
	var imgs := {}
	var items := _all_items()
	for item in items:
		imgs[item] = ItemIcons.image(item, 24)
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Image = imgs[items[i]]
			var b: Image = imgs[items[j]]
			var diff := 0.0
			for y in 24:
				for x in 24:
					var ca := a.get_pixel(x, y)
					var cb := b.get_pixel(x, y)
					diff += absf(ca.a - cb.a) + absf(ca.r * ca.a - cb.r * cb.a) + absf(ca.g * ca.a - cb.g * cb.a)
			check(diff / (24 * 24) > 0.08, "%s and %s look different (%.3f)" % [items[i], items[j], diff / (24 * 24)])


func test_glowing_things_glow_and_cold_things_do_not() -> void:
	for item in ["ember_sap", "torch", "campfire", "ember_heartwood", "veinstone"]:
		check(_stats(ItemIcons.image(item, 48)).warm >= 20, "%s has a bright warm core" % item)
		check(ItemIcons.shapes(item).any(func(s): return s.get("glow", 0.0) > 0.0), "%s has a halo" % item)
	for item in ["stone", "stone_axe", "stone_pickaxe", "pine_wood"]:
		check(not ItemIcons.shapes(item).any(func(s): return s.get("glow", 0.0) > 0.0), "%s does not glow" % item)


func test_deterministic_and_cached() -> void:
	for item in ["stone", "torch"]:
		check(ItemIcons.image(item, 32).get_data() == ItemIcons.image(item, 32).get_data(), "%s draws the same every time" % item)
	var t := ItemIcons.texture("stone", 32)
	check(t != null, "texture exists")
	check(t == ItemIcons.texture("stone", 32), "texture is cached")
	check_eq(t.get_width(), 32, "texture size")


func test_unknown_items_get_a_bundle() -> void:
	check(not ItemIcons.has_icon("retired_gizmo"), "unknown id has no own icon")
	check(ItemIcons.shapes("retired_gizmo") == ItemIcons.shapes(ItemIcons.FALLBACK), "unknown id gets the bundle")
	check(_stats(ItemIcons.image("retired_gizmo", 32)).solid > 0.1, "the bundle is drawn")
	check(ItemIcons.texture("retired_gizmo", 32) == ItemIcons.texture("other_gizmo", 32), "every unknown id shares one bundle texture")
	check(ItemIcons.tint("retired_gizmo") is Color, "unknown id still has a tint")


func test_tier2_materials_look_richer_than_their_tier1() -> void:
	# Ember heartwood comes from the old ember ash, veinstone from the rich seam: each has its
	# own icon, glows where its plain cousin doesn't, and tints the toast its own colour.
	for pair in [["ember_heartwood", "ash_wood"], ["veinstone", "stone"]]:
		check(ItemIcons.has_icon(pair[0]), "%s has its own icon" % pair[0])
		var rich := _stats(ItemIcons.image(pair[0], 48))
		var plain := _stats(ItemIcons.image(pair[1], 48))
		check(rich.warm > plain.warm + 15, "%s glows more than %s (%d vs %d)" % [pair[0], pair[1], rich.warm, plain.warm])
		check(ItemIcons.tint(pair[0]) != ItemIcons.tint(pair[1]), "%s tints differently from %s" % pair)
		check(ItemIcons.tint(pair[0]) != ItemIcons.tint(ItemIcons.FALLBACK), "%s does not tint like the bundle" % pair[0])


func test_ember_tools_are_drawn_and_burn_hotter_than_stone() -> void:
	# Gameplay's Toolcraft 5 tools: the stone tools' shapes with coal-dark heads and an
	# ember edge, so upgrading reads at a glance in the pack and on the craft toast.
	for pair in [["ember_axe", "stone_axe"], ["ember_pickaxe", "stone_pickaxe"]]:
		check(ItemIcons.has_icon(pair[0]), "%s has its own icon" % pair[0])
		check(ItemIcons.shapes(pair[0]).any(func(s): return s.get("glow", 0.0) > 0.0), "%s has a halo" % pair[0])
		var hot := _stats(ItemIcons.image(pair[0], 48))
		var cold := _stats(ItemIcons.image(pair[1], 48))
		check(hot.warm >= 20 and hot.warm > cold.warm + 15, "%s edge glows (%d vs %d)" % [pair[0], hot.warm, cold.warm])
		check(ItemIcons.tint(pair[0]) != ItemIcons.tint(pair[1]), "%s tints differently from %s" % pair)
	# Only the ember tools: anything else in Inventory.UNDRAWN is allowed to wait for its
	# icon (that is what UNDRAWN is for; gameplay's request, 2026-11-23).


func test_ember_lantern_glows_and_reads_apart_from_torch_and_campfire() -> void:
	# Gameplay's "Bench sense" lantern: a lantern with an ember inside. It glows like the
	# other fire items but must not be mistaken for the torch or campfire in a pack slot.
	check(ItemIcons.has_icon("ember_lantern"), "ember_lantern has its own icon")
	var s := _stats(ItemIcons.image("ember_lantern", 48))
	check(s.warm >= 20, "ember_lantern has a bright warm core (%d)" % s.warm)
	check(ItemIcons.shapes("ember_lantern").any(func(sh): return sh.get("glow", 0.0) > 0.0), "ember_lantern has a halo")
	check(ItemIcons.tint("ember_lantern") != ItemIcons.tint(ItemIcons.FALLBACK), "ember_lantern does not tint like the bundle")
	var a := ItemIcons.image("ember_lantern", 24)
	for other in ["torch", "campfire"]:
		var b := ItemIcons.image(other, 24)
		var diff := 0.0
		for y in 24:
			for x in 24:
				diff += absf(a.get_pixel(x, y).a - b.get_pixel(x, y).a)
		check(diff / (24 * 24) > 0.12, "ember_lantern's silhouette differs from %s (%.3f)" % [other, diff / (24 * 24)])


func test_hunt_drops_are_drawn_earthy_and_never_glow() -> void:
	# Gameplay's first hunt (2026-11-24): a downed grazer gives hide and raw meat. Each gets
	# its own picture so the kill toast and the pack show what you took, and neither may
	# look like ember: no halo, no bright warm core (ember means "usable fire" in Ashgrove).
	for item in ["hide", "raw_meat"]:
		check(ItemIcons.has_icon(item), "%s has its own icon" % item)
		check(not ItemIcons.shapes(item).any(func(s): return s.get("glow", 0.0) > 0.0), "%s has no halo" % item)
		check(_stats(ItemIcons.image(item, 48)).warm < 5, "%s has no ember-bright pixels" % item)
		check(ItemIcons.tint(item) != ItemIcons.tint(ItemIcons.FALLBACK), "%s does not tint like the bundle" % item)
	# Meat is a deep red, well away from ember orange; the hide is a muted brown.
	var meat := Palette.RAW_MEAT
	check(meat.r > meat.g * 2.0 and meat.v < 0.6, "raw meat is a dark red (%s)" % meat)
	check(absf(meat.h - Palette.EMBER.h) > 0.05, "raw meat's hue is not ember's (%.3f vs %.3f)" % [meat.h, Palette.EMBER.h])
	check(Palette.HIDE_FUR.s < 0.5 and Palette.HIDE_FUR.v < 0.6, "hide fur is a muted brown (%s)" % Palette.HIDE_FUR)
	# The two drops come off one animal at once, so the toast must tell them apart.
	check(ItemIcons.tint("hide") != ItemIcons.tint("raw_meat"), "hide and meat tint differently")


func test_cooked_meat_is_drawn_ahead_browned_and_never_glows() -> void:
	# Drawn ahead of gameplay's cooking (campfires): food, not fire, so no halo and no ember.
	check(ItemIcons.has_icon("cooked_meat"), "cooked_meat has its own icon")
	check(not ItemIcons.shapes("cooked_meat").any(func(s): return s.get("glow", 0.0) > 0.0), "cooked_meat has no halo")
	check(_stats(ItemIcons.image("cooked_meat", 48)).warm < 5, "cooked_meat has no ember-bright pixels")
	var c := Palette.COOKED_MEAT
	check(c.s < 0.7 and c.v < 0.55, "cooked meat is a dull brown (%s)" % c)
	check(absf(c.h - Palette.RAW_MEAT.h) > 0.02, "cooked meat is browner than raw (%.3f vs %.3f)" % [c.h, Palette.RAW_MEAT.h])
	check(ItemIcons.tint("cooked_meat") != ItemIcons.tint("raw_meat"), "cooked and raw tint differently")
	# Cooking should be visible in the pack: the two icons differ by more than a tint.
	var a := ItemIcons.image("cooked_meat", 24)
	var b := ItemIcons.image("raw_meat", 24)
	var diff := 0.0
	for y in 24:
		for x in 24:
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			diff += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) + absf(p.a - q.a)
	check(diff / (24 * 24) > 0.08, "cooked_meat looks different from raw_meat (%.3f)" % (diff / (24 * 24)))

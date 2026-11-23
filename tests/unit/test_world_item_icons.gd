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


func test_every_item_has_its_own_icon() -> void:
	for item in Inventory.ITEM_ORDER:
		check(ItemIcons.has_icon(item), "%s has an icon" % item)
		check(ItemIcons.shapes(item) != ItemIcons.shapes(ItemIcons.FALLBACK), "%s is not the fallback bundle" % item)
	for item in Inventory.ITEMS:
		check(ItemIcons.has_icon(item), "%s (Inventory.ITEMS) has an icon" % item)


func test_icons_fill_the_square_without_clipping() -> void:
	for item in Inventory.ITEM_ORDER:
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
	for item in Inventory.ITEM_ORDER:
		imgs[item] = ItemIcons.image(item, 24)
	var items: Array = Inventory.ITEM_ORDER
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
	for item in ["ember_sap", "torch", "campfire"]:
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

extends TestCase
## Client item icons: the shelf draws every icon the client shows ahead of time (on a thread),
## never hands back null, and the gather/craft toasts and the workbench window put the right
## item's icon next to the right words.


func test_shelf_wants_every_item_at_every_size() -> void:
	var w := IconShelf.wanted()
	check_eq(w.size(), Inventory.ITEM_ORDER.size() * IconShelf.SIZES.size(), "one per item per size")
	var seen := {}
	for pair in w:
		seen[IconShelf.key(pair[0], pair[1])] = true
	check_eq(seen.size(), w.size(), "no icon drawn twice")
	for size in [IconShelf.TOAST_SIZE, IconShelf.ROW_SIZE, IconShelf.PART_SIZE]:
		check(IconShelf.SIZES.has(size), "size %d is drawn ahead" % size)
	check_eq(int(w[0][1]), IconShelf.TOAST_SIZE, "toast icons come first")
	for item in Inventory.ITEM_ORDER:
		check(ItemIcons.has_icon(item), "%s has its own icon, not the bundle" % item)


func test_draw_all_now_fills_the_shelf() -> void:
	var shelf := IconShelf.new()
	check_eq(shelf.ready_count(), 0)
	shelf.draw_all_now()
	check_eq(shelf.ready_count(), IconShelf.wanted().size())
	for pair in IconShelf.wanted():
		check(shelf.is_ready(pair[0], pair[1]), "%s@%d ready" % pair)
	var tex := shelf.texture("ash_wood", IconShelf.TOAST_SIZE)
	check(tex != null, "a texture")
	check_eq(tex.get_width(), IconShelf.TOAST_SIZE)
	check(shelf.texture("ash_wood", IconShelf.TOAST_SIZE) == tex, "the same texture every call")
	# The shelf's drawing is the very picture world draws.
	var want := ItemIcons.image("stone", IconShelf.PART_SIZE)
	var got := shelf.texture("stone", IconShelf.PART_SIZE).get_image()
	check_eq(got.get_data(), want.get_data(), "same pixels as ItemIcons.image")


func test_shelf_draws_on_a_thread() -> void:
	var shelf := IconShelf.new()
	shelf.start()
	shelf.start() # twice is harmless
	var waited := 0
	while shelf.ready_count() < IconShelf.wanted().size() and waited < 20000:
		OS.delay_msec(20)
		waited += 20
	check_eq(shelf.ready_count(), IconShelf.wanted().size(), "thread drew them all in %d ms" % waited)
	shelf.finish()
	shelf.finish() # twice is harmless
	check_eq(shelf.texture("torch", IconShelf.TOAST_SIZE).get_width(), IconShelf.TOAST_SIZE)


func test_shelf_never_returns_null() -> void:
	var shelf := IconShelf.new() # nothing drawn yet
	var t := shelf.texture("pine_wood", IconShelf.TOAST_SIZE)
	check(t != null and t.get_width() == IconShelf.TOAST_SIZE, "falls back to drawing now")
	var odd := shelf.texture("retired_item", IconShelf.PART_SIZE)
	check(odd != null and odd.get_width() == IconShelf.PART_SIZE, "unknown items get the bundle")
	# Stopping before the thread finishes leaves the shelf usable.
	var s2 := IconShelf.new()
	s2.start()
	s2.finish()
	check(s2.texture("stone_axe", IconShelf.TOAST_SIZE) != null, "still works after an early stop")


func test_every_gather_toast_gets_its_items_icon() -> void:
	var shelf := IconShelf.new()
	shelf.draw_all_now()
	var g := GatherPrompt.new()
	g.setup(Theme.new())
	g.icons = shelf
	for kind in ResourceNodes.KINDS:
		var item := str(ResourceNodes.kind_info(kind).item)
		g.pack = {item: 6}
		g.on_result(item, 2) # s2c_gather_result
		check(g.toast_label.text.ends_with("(6)"), g.toast_label.text)
		check_eq(g.toast_item(), item, "%s toast shows the %s icon" % [kind, item])
		check(g.toast_icon.visible, "icon shown")
		check(g.toast_icon.texture == shelf.texture(item, IconShelf.TOAST_SIZE), "icon from the shelf")
	g.show_toast("Crafted: Stone axe!", "stone_axe")
	check_eq(g.toast_item(), "stone_axe", "craft toast shows the axe")
	g.show_toast("Welcome")
	check_eq(g.toast_item(), "", "plain toasts have no icon")
	check(not g.toast_icon.visible, "icon hidden")
	g.show_toast("Crafted: 3 Torches!", "torch")
	g.hide_all()
	check(not g.toast_icon.visible, "hide_all hides the icon")
	g.free()


func test_toast_icon_and_text_are_centred_together() -> void:
	for w in [40.0, 120.0, 200.0]:
		var x: float = GatherPrompt.icon_x(w)
		var right: float = x + IconShelf.TOAST_SIZE + GatherPrompt.ICON_GAP + w
		check_near(x, GatherPrompt.WIDTH - right, 0.001, "equal margins for %d px text" % w)
		check(x >= 0.0, "icon stays inside the prompt")
	var g := GatherPrompt.new()
	g.setup(Theme.new())
	g.show_toast("+2 Ash wood  (6)", "ash_wood")
	var text_w := g.toast_label.get_minimum_size().x
	var text_left := g.toast_label.position.x + (GatherPrompt.WIDTH - text_w) * 0.5
	check_near(g.toast_icon.position.x + IconShelf.TOAST_SIZE + GatherPrompt.ICON_GAP, text_left, 0.5, "icon sits just left of the text")
	g.show_toast("Welcome")
	check_eq(g.toast_label.position.x, 0.0, "plain toasts stay centred")
	g.free()


func test_workbench_rows_show_icons() -> void:
	var shelf := IconShelf.new()
	shelf.draw_all_now()
	var w := CraftWindow.new()
	w.icons = shelf
	w.setup(Theme.new())
	w.seed_pack({"ash_wood": 2, "stone": 2})
	for id in Crafting.RECIPE_ORDER:
		var row: Dictionary = w._rows[id]
		var icon: TextureRect = row.icon
		check(icon.texture == shelf.texture(id, IconShelf.ROW_SIZE), "%s row shows its product" % id)
	var needs: RichTextLabel = w._rows["stone_axe"].needs
	var text := needs.get_parsed_text()
	check(text.contains("Stone 2/3"), "axe needs text: %s" % text)
	check(text.contains("Wooden axe 0/1"), "axe needs text: %s" % text)
	w.reset()
	w.refresh()
	check(w._rows["stone_axe"].needs.get_parsed_text().contains("..."), "unknown pack shows dots")
	w.free()

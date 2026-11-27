extends TestCase
## The pack window (I key): slot order and counts from the server's pack, texts, the gold glow
## and "+N" on a slot that grew, and the I key in the F1 list.


func test_slots_follow_the_pack_in_a_fixed_order() -> void:
	var inv := {"stone": 3, "ash_wood": 12, "torch": 0, "mystery_thing": 2}
	var s := PackWindow.slots(inv)
	check_eq(s.size(), 3, "empty stacks are not slots")
	check_eq(str(s[0].item), "ash_wood")
	check_eq(int(s[0].count), 12)
	check_eq(str(s[0].label), "Ash Wood")
	check_eq(str(s[1].item), "stone")
	check_eq(str(s[2].item), "mystery_thing", "an unknown id is kept, last (save compatibility)")
	check(not bool(s[0].full), "12 is not full")
	check(bool(PackWindow.slots({"stone": Inventory.MAX_STACK})[0].full), "a stack at the cap is full")


func test_texts() -> void:
	ControlsOverlay.install_input()
	check_eq(PackWindow.total_text({}), "Empty")
	check_eq(PackWindow.total_text({"stone": 1}), "1 item")
	check_eq(PackWindow.total_text({"stone": 3, "ash_wood": 4}), "7 items")
	check(PackWindow.empty_text().ends_with("press E."), PackWindow.empty_text())
	check(not PackWindow.empty_text().contains("/"), "no chat command in the empty text")
	# Built from the recipe table and the stack cap, so new recipes (the ember lantern) and a
	# bigger stack (999) land without touching this test.
	check_eq(PackWindow.used_in("stone"), _recipes_using("stone"))
	check(PackWindow.used_in("stone").has("stone axe"), "stone makes the stone axe")
	var ash_uses := ", ".join(PackedStringArray(_recipes_using("ash_wood")))
	check_eq(PackWindow.tooltip_text("ash_wood", 12), "Ash Wood\n12 of %d\nUsed in: %s" % [Inventory.MAX_STACK, ash_uses])
	check(PackWindow.tooltip_text("stone", Inventory.MAX_STACK).contains("(full)"), "full stack says so")
	check(not PackWindow.tooltip_text("stone", Inventory.MAX_STACK - 1).contains("(full)"), "one short is not full")
	check(PackWindow.tooltip_text("torch", 3).count("\n") == 1, "a torch is used in nothing yet: two lines")
	check(PackWindow.tooltip_text("wooden_axe", 1).contains("Used in: stone axe"), "the wooden axe upgrades")
	check(PackWindow.tooltip_text("stone_maul", 1).contains("A weapon"), "weapons say so")
	check(PackWindow.tooltip_text("bandage", 1).contains("Press H"), "the bandage says how")
	for item in Inventory.ITEM_ORDER:
		check(PackWindow.tooltip_text(item, 1) != "", item)


func test_gained() -> void:
	check_eq(PackWindow.gained({"stone": 2}, {"stone": 4, "ash_wood": 1}), {"stone": 2, "ash_wood": 1})
	check_eq(PackWindow.gained({"stone": 4, "pine_wood": 3}, {"stone": 2}), {}, "crafting uses things up: no glow")


func test_window_follows_the_server() -> void:
	ControlsOverlay.install_input()
	var w := PackWindow.new()
	w.setup(Theme.new())
	check_eq(w.shown(), [], "an empty grid")
	w.seed_pack({"ash_wood": 2, "stone": 1})
	check_eq(w.shown(), ["ash_wood", "stone"])
	check_eq(w.count_shown("ash_wood"), "2")
	check_eq(w.flash_of("ash_wood"), 0.0, "the first pack (login) never glows")
	w.seed_pack({"ash_wood": 4, "stone": 1})
	check_eq(w.count_shown("ash_wood"), "4")
	check_eq(w.flash_of("ash_wood"), 1.0, "a stack that grew glows")
	check_eq(w.flash_of("stone"), 0.0)
	w.seed_pack({"ash_wood": 5, "stone": 1})
	check_eq(int(w._gain["ash_wood"]), 3, "a second haul while glowing adds to the +N")
	w.step(PackWindow.FLASH_SECONDS * 0.5)
	check(w.flash_of("ash_wood") > 0.4 and w.flash_of("ash_wood") < 0.6, "glow fades")
	w.step(PackWindow.FLASH_SECONDS)
	check_eq(w.flash_of("ash_wood"), 0.0, "and is gone")
	check(not w._gain.has("ash_wood"), "+N gone")
	w.seed_pack("not a pack")
	check_eq(w.count_shown("ash_wood"), "5", "junk is ignored")
	w.seed_pack({"ash_wood": 45})
	check_eq(w.shown(), ["ash_wood", "ash_wood", "ash_wood"], "45 logs are three stacks")
	w.seed_places([["ash_wood", 2, 9, 4, false]])
	check_eq(PackGrid.stack_at(w.laid(), 9, 4), {"item": "ash_wood", "index": 2}, "the server's layout is drawn")
	w.open()
	check(w.visible, "opens")
	var closes := [0]
	w.closed.connect(func(): closes[0] += 1)
	w.toggle()
	check(not w.visible, "shuts")
	check_eq(closes[0], 1)
	w.reset()
	check(not w.pack_known, "reset forgets the pack")
	check_eq(w.shown(), [])
	w.free()


func test_drag_turn_and_drop() -> void:
	var w := PackWindow.new()
	w.setup(Theme.new())
	w.seed_pack({"ash_wood": 5, "stone": 3})
	var moves: Array = []
	var drops: Array = []
	w.move_requested.connect(func(i, n, x, y, t): moves.append([i, n, x, y, t]))
	w.drop_requested.connect(func(i, n): drops.append([i, n]))
	var c := PackWindow.CELL
	# the log sits at (0, 0) standing (1x2): grab its top half
	check(w.pick_up_at(Vector2(0.5, 0.5) * c), "picked up")
	check_eq(w.put_down_at(Vector2(7.5, 2.5) * c), "moved")
	check_eq(moves, [["ash_wood", 0, 7, 2, false]], "the server is asked")
	check_eq(PackGrid.stack_at(w.laid(), 7, 3), {"item": "ash_wood", "index": 0}, "and it shows at once")
	check(w.pick_up_at(Vector2(7.5, 2.5) * c), "again")
	w.turn_held()
	check_eq(w.put_down_at(Vector2(2.5, 5.5) * c), "moved", "turned, it lies in the bottom row")
	check_eq(moves[1], ["ash_wood", 0, 2, 5, true])
	check(w.pick_up_at(Vector2(2.5, 5.5) * c), "the turned log")
	var stone_at: Dictionary = {}
	for p in w.laid().placed:
		if str(p.item) == "stone":
			stone_at = p
	check_eq(w.put_down_at((Vector2(int(stone_at.x), int(stone_at.y)) + Vector2(0.5, 0.5)) * c), "back", "not onto the stone")
	check_eq(moves.size(), 2, "a refused move asks nothing")
	check(not w.holding(), "the hand is empty again")
	check(w.pick_up_at((Vector2(int(stone_at.x), int(stone_at.y)) + Vector2(0.5, 0.5)) * c), "the stone")
	check_eq(w.put_down_at(Vector2(PackWindow.GRID_W + 80.0, 20.0)), "dropped", "out of the grid is a drop")
	check_eq(drops, [["stone", 0]])
	check(not w.pick_up_at(Vector2(9.5, 0.5) * c), "nothing in an empty pocket")
	w.free()


func test_what_does_not_fit_waits_below() -> void:
	var laid := PackGrid.layout({"ash_wood": 999}, [])
	var t := PackWindow.over_text(laid)
	check(t.begins_with("No room for"), t)
	check(t.contains("ash wood"), t)
	check_eq(PackWindow.over_text(PackGrid.layout({"stone": 2}, [])), "", "nothing over, no line")
	check(PackWindow.stack_tooltip("ash_wood", 20, 45).contains("This stack: 20 of 20"), "a stack says its own count")
	check(PackWindow.stack_tooltip("stone_axe", 1, 1).contains("Takes 1x3"), "a tool says its size")


func test_i_key_is_listed() -> void:
	check_eq(ControlsOverlay.DEFAULT_BINDS.get("toggle_pack"), [KEY_I])
	check(ControlsOverlay.listed_actions().has("toggle_pack"), "I is in the F1 list")
	check(IconShelf.SIZES.has(PackWindow.ICON), "slot icons are drawn ahead")


## The recipe labels that need `item`, in the workbench's order, read straight from the table.
func _recipes_using(item: String) -> Array:
	var out: Array = []
	for id in Crafting.RECIPE_ORDER:
		if (Crafting.RECIPES[id].needs as Dictionary).has(item):
			out.append(str(Crafting.RECIPES[id].label))
	return out


func test_a_stack_count_fits_its_cell() -> void:
	var font := ThemeDB.fallback_font
	var most := 0
	for item in PackGrid.SHAPES:
		most = maxi(most, PackGrid.stack_size(item))
	var w := font.get_string_size(str(most), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	check(w + 10.0 < PackWindow.CELL * 0.6, "\"%d\" is %.0f px in a %.0f px cell" % [most, w, PackWindow.CELL])
	check(PackWindow.WIDTH < 640.0, "the window fits beside the world at 1280 px")

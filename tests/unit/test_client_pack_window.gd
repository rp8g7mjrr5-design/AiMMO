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


func test_slot_count() -> void:
	check_eq(PackWindow.slot_count(0), 10, "two rows even when empty")
	check_eq(PackWindow.slot_count(10), 10)
	check_eq(PackWindow.slot_count(11), 15, "rounded up to a full row")


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
	check(PackWindow.tooltip_text("stone_axe", 1).contains("Used in: ember axe"), "axe upgrades")
	for item in Inventory.ITEM_ORDER:
		check(PackWindow.tooltip_text(item, 1) != "", item)


func test_gained() -> void:
	check_eq(PackWindow.gained({"stone": 2}, {"stone": 4, "ash_wood": 1}), {"stone": 2, "ash_wood": 1})
	check_eq(PackWindow.gained({"stone": 4, "pine_wood": 3}, {"stone": 2}), {}, "crafting uses things up: no glow")


func test_window_follows_the_server() -> void:
	ControlsOverlay.install_input()
	var w := PackWindow.new()
	w.setup(Theme.new())
	check_eq(w.shown().size(), 10)
	check_eq(w.shown()[0], "")
	w.seed_pack({"ash_wood": 2, "stone": 1})
	check_eq(w.shown().slice(0, 3), ["ash_wood", "stone", ""])
	check_eq(w.count_shown("ash_wood"), "2")
	check_eq(w.flash_of("ash_wood"), 0.0, "the first pack (login) never glows")
	w.seed_pack({"ash_wood": 4, "stone": 1})
	check_eq(w.count_shown("ash_wood"), "4")
	check_eq(w.flash_of("ash_wood"), 1.0, "a slot that grew glows")
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
	var many := {}
	for item in Inventory.ITEM_ORDER:
		many[item] = 1
	many["zz_new"] = 1
	w.seed_pack(many)
	check_eq(w.shown().size(), PackWindow.slot_count(Inventory.ITEM_ORDER.size() + 1), "every stack plus the unknown one, in full rows")
	w.open()
	check(w.visible, "opens")
	var closes := [0]
	w.closed.connect(func(): closes[0] += 1)
	w.toggle()
	check(not w.visible, "shuts")
	check_eq(closes[0], 1)
	w.reset()
	check(not w.pack_known, "reset forgets the pack")
	check_eq(w.shown()[0], "")
	w.free()


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


func test_a_three_digit_stack_fits_its_slot() -> void:
	# Gameplay is raising Inventory.MAX_STACK to 999: the count in a slot's corner must still
	# fit inside the slot, with room to spare for the icon.
	var font := ThemeDB.fallback_font
	var w := font.get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	check(w + 10.0 < PackWindow.SLOT * 0.6, "\"999\" is %.0f px in a %.0f px slot" % [w, PackWindow.SLOT])
	var big := font.get_string_size(str(maxi(Inventory.MAX_STACK, 999)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	check(big < PackWindow.SLOT - 8.0, "the full stack's count fits too")

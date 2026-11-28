extends TestCase
## Crafting from the pack (I) and your traveller in it (owner, 2026-11-28): the craft column
## lists the hand recipes first and makes them anywhere, the bench ones wait for a bench, Craft
## goes out as one request at a time, and the figure holds your best kit.

const FAR := Vector3(400, 0, 400) ## nowhere near the workbench


func test_hand_recipes_come_first() -> void:
	var ids := CraftPanel.order()
	check_eq(ids.size(), Crafting.RECIPE_ORDER.size(), "every recipe is listed")
	var seen_bench := false
	for id in ids:
		var bench := bool(Crafting.RECIPES[id].bench)
		check(bench or not seen_bench, "%s: no hand recipe after a bench one" % id)
		seen_bench = seen_bench or bench
	for id in ["wooden_axe", "wooden_pickaxe", "bandage", "torch"]:
		check(not bool(Crafting.RECIPES[id].bench), "%s is made in the pack, anywhere" % id)


func test_ready_count_and_hints() -> void:
	var inv := {"ash_wood": 3, "plant_fibre": 3}
	# wooden axe, wooden club (3 ash each) and a bandage; nothing at the bench this far out.
	check_eq(CraftPanel.ready_count(inv, FAR), 3)
	check_eq(CraftPanel.head_text(inv, FAR, true), "3 ready")
	check_eq(CraftPanel.head_text({}, FAR, true), "")
	check_eq(CraftPanel.head_text(inv, FAR, false), "", "nothing said before the pack arrives")
	check_eq(CraftPanel.short_hint("bench"), "At a workbench")
	check_eq(CraftPanel.short_hint("owned"), "Carried")
	check_eq(CraftPanel.short_hint("missing"), "", "the red counts already say what's short")


func test_panel_crafts_one_at_a_time() -> void:
	var p := CraftPanel.new()
	p.setup()
	var sent: Array = []
	p.craft_requested.connect(func(id: String): sent.append(id))
	p.tick(0.0, FAR)
	check(not p.craft("bandage"), "nothing goes out before the pack is known")
	p.seed_pack({"plant_fibre": 6, "stone": 9, "wooden_axe": 1}, true)
	check(not p.craft("stone_axe"), "a bench recipe away from the bench is not sent")
	check(not p.craft("wooden_axe"), "a tool you carry is not made twice")
	check(p.craft("bandage"), "a bandage is made anywhere")
	check(not p.craft("bandage"), "one request at a time")
	check_eq(sent, ["bandage"])
	p.on_craft_result("bandage", true, "You made a bandage.")
	check(not p.is_waiting(), "the answer frees the buttons")
	check_eq(p.status_label.text, "", "a success is told by the chime and the glowing stack")
	check(p.craft("bandage"), "again after the answer")
	p.on_craft_result("bandage", false, "Your pack is full.")
	check_eq(p.status_label.text, "Your pack is full.", "a refusal says why")
	check(p.craft("bandage"), "and again")
	p.tick(CraftPanel.REPLY_TIMEOUT + 0.1, FAR)
	check(not p.is_waiting(), "no answer: the buttons light again")
	check_eq(p.status_label.text, CraftWindow.NO_ANSWER)
	p.free()


func test_figure_holds_your_best_kit() -> void:
	check_eq(PackPreview.held_for({}), "", "empty hands")
	check_eq(PackPreview.held_for({"torch": 2}), "torch")
	check_eq(PackPreview.held_for({"torch": 2, "wooden_axe": 1}), "wooden_axe")
	check_eq(PackPreview.held_for({"wooden_axe": 1, "stone_axe": 1, "wooden_spear": 1}), "wooden_spear", "a weapon beats a tool")
	check_eq(PackPreview.held_for({"wooden_spear": 1, "stone_maul": 1}), "stone_maul", "the weapon you swing (Weapons.ORDER)")
	for id in PackPreview.TOOL_ORDER:
		check(HeldItems.has(id), "%s can be held" % id)
	check_near(PackPreview.turn_for(0.0, 100.0), 100.0 * PackPreview.DRAG_TURN, 0.0001)
	check(absf(PackPreview.turn_for(3.0, 1000.0)) <= PI, "the turn wraps")


func test_pack_window_crafts_and_dresses_the_figure() -> void:
	# The headless dummy renderer logs this for any MeshInstance3D it is handed (the figure).
	expect_error("Parameter \"m\" is null")
	ControlsOverlay.install_input()
	var w := PackWindow.new()
	w.setup(Theme.new())
	var sent: Array = []
	w.craft_requested.connect(func(id: String): sent.append(id))
	w.set_traveller("Ash", 7, {})
	check_eq(w.preview.holding(), "", "nothing in hand before the pack arrives")
	w.seed_pack({"pine_wood": 3, "wooden_club": 1})
	check_eq(w.preview.holding(), "wooden_club", "the club you carry is in your hand")
	w.open()
	w.step(0.016, FAR)
	check(w.crafting.craft("wooden_spear"), "craft from the pack")
	check_eq(sent, ["wooden_spear"])
	w.crafting.on_craft_result("wooden_spear", true, "")
	w.seed_pack({"wooden_spear": 1, "wooden_club": 1})
	check_eq(w.preview.holding(), "wooden_club", "spear and club are equals; the club is swung (Weapons.ORDER)")
	w.seed_pack({"stone_maul": 1, "wooden_spear": 1})
	check_eq(w.preview.holding(), "stone_maul", "a new weapon shows in your hand at once")
	check(PackWindow.WIDTH <= 1240.0, "fits a 1280 px wide screen")
	w.reset()
	check_eq(w.preview.holding(), "")
	w.free()

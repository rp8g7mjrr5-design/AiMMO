extends TestCase
## The grid pack (owner direction 2026-11-27, mechanics like Tarkov or ARC Raiders): items
## take room by shape, stacks fill the grid, a full pack refuses more, a saved layout holds,
## and nothing a player owns is ever lost when it doesn't fit.


func test_stacks_split_by_size() -> void:
	var st := PackGrid.stacks({"ash_wood": 45, "wooden_axe": 1})
	check_eq(st.size(), 4, "45 wood is three stacks of 20, 20 and 5, plus the axe")
	check_eq(int(st[0].n), 20)
	check_eq(int(st[2].n), 5, "the part stack comes last")
	check_eq(int(st[2].index), 2)
	check_eq(PackGrid.shape("wooden_spear"), Vector2i(1, 4), "a spear is long")
	check_eq(PackGrid.shape("cooked_mystery"), Vector2i(1, 1), "an unknown item is one cell")
	check_eq(PackGrid.stack_size("stone_axe"), 1, "tools never stack")


func test_first_fit_is_deterministic_and_never_overlaps() -> void:
	var inv := {"ash_wood": 30, "stone": 20, "stone_maul": 1, "wooden_spear": 1, "bandage": 3}
	var a := PackGrid.layout(inv, [])
	var b := PackGrid.layout(inv, [])
	check_eq(PackGrid.places_of(a), PackGrid.places_of(b), "same counts, same layout")
	check_eq(PackGrid.over_count(a), 0)
	var cells := {}
	for p in a.placed:
		for y in range(int(p.y), int(p.y) + int(p.h)):
			for x in range(int(p.x), int(p.x) + int(p.w)):
				check(not cells.has(Vector2i(x, y)), "no two stacks share a cell")
				cells[Vector2i(x, y)] = true
				check(x >= 0 and x < PackGrid.COLS and y >= 0 and y < PackGrid.ROWS, "inside the grid")


func test_a_saved_place_holds_and_a_move_is_checked() -> void:
	var inv := {"ash_wood": 10, "stone": 5}
	var places := PackGrid.move(inv, [], "stone", 0, 9, 5, false)
	check(not places.is_empty(), "a stone can go in the bottom-right corner")
	var laid := PackGrid.layout(inv, places)
	check_eq(PackGrid.stack_at(laid, 9, 5), {"item": "stone", "index": 0}, "and stays there")
	check(PackGrid.move(inv, places, "ash_wood", 0, 9, 5, false).is_empty(), "not onto another stack")
	check(PackGrid.move(inv, places, "ash_wood", 0, 9, 5, true).is_empty(), "not off the grid either")
	check(not PackGrid.move(inv, places, "ash_wood", 0, 3, 5, true).is_empty(), "a log turned on its side fits a 2x1 gap")
	check(PackGrid.move(inv, places, "pine_wood", 0, 0, 0, false).is_empty(), "no such stack")
	# After a gather adds a stack, the stone still sits where it was put.
	var more := PackGrid.layout({"ash_wood": 30, "stone": 5}, places)
	check_eq(PackGrid.stack_at(more, 9, 5), {"item": "stone", "index": 0})


func test_a_full_pack_refuses_more_and_loses_nothing() -> void:
	var cells := PackGrid.COLS * PackGrid.ROWS
	var inv := {"stone": 15 * cells} # one stone stack in every cell
	check_eq(PackGrid.room_for(inv, [], "stone"), 0, "every cell holds a full stack of stone")
	check_eq(PackGrid.room_for(inv, [], "bandage"), 0, "and nothing else fits")
	var some := {"stone": 7}
	check_eq(PackGrid.room_for(some, [], "stone"), 15 * cells - 7, "an empty pack takes stone until every cell is full")
	var old := {"ash_wood": 999}
	var laid := PackGrid.layout(old, [])
	check(PackGrid.over_count(laid) > 0, "an old save's 999 wood doesn't fit")
	var kept := 0
	for p in laid.placed:
		kept += int(p.n)
	for o in laid.over:
		kept += int(o.n)
	check_eq(kept, 999, "but every log is still owned, in the grid or waiting below it")
	check_eq(PackGrid.room_for(old, [], "ash_wood"), 0, "no more wood until there is room")


func test_one_only_tools() -> void:
	check_eq(PackGrid.room_for({}, [], "stone_axe"), 1)
	check_eq(PackGrid.room_for({"stone_axe": 1}, [], "stone_axe"), 0)


func test_layout_survives_junk() -> void:
	var junk := [["stone", 0, 99, 99, false], ["stone", 0, 1, 1, false], "nope", [1], ["", 0, 0, 0, false]]
	var clean := PackGrid.normalize(junk)
	check_eq(clean.size(), 1, "one place per stack, the junk dropped")
	var laid := PackGrid.layout({"stone": 3}, junk)
	check_eq(PackGrid.over_count(laid), 0, "an off-grid place just gets packed again")
	check_eq(PackGrid.from_json(PackGrid.to_json([["stone", 0, 2, 3, true]])), [["stone", 0, 2, 3, true]])
	check_eq(PackGrid.from_json(""), [], "an old save has no layout")
	check_eq(PackGrid.layout({}, null).placed, [])


func test_room_is_quick() -> void:
	var inv := {"ash_wood": 120, "pine_wood": 80, "stone": 60, "plant_fibre": 40, "bandage": 9, "wooden_axe": 1, "stone_pickaxe": 1}
	var t := Time.get_ticks_usec()
	for i in 20:
		PackGrid.room_for(inv, [], "stone")
	var ms := float(Time.get_ticks_usec() - t) / 1000.0 / 20.0
	check(ms < 15.0, "room_for runs on every gather: %.2f ms" % ms)

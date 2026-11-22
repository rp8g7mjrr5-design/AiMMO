extends TestCase
## Crafting (game/shared/crafting.gd), tools in Gathering, and /craft's command routing.

const AT_BENCH := Vector3(3.0, 0.0, -2.0)
const FAR := Vector3(60.0, 0.0, 60.0)


func test_recipes_are_well_formed() -> void:
	check_eq(Crafting.RECIPE_ORDER.size(), Crafting.RECIPES.size(), "every recipe listed once")
	for id in Crafting.RECIPE_ORDER:
		var r: Dictionary = Crafting.RECIPES[id]
		check(Inventory.is_item(id), "%s is an item a pack can hold" % id)
		check(Inventory.ITEM_ORDER.has(id), "%s has a place in pack order" % id)
		check(int(r.makes) >= 1, "%s makes something" % id)
		check(not r.needs.is_empty(), "%s costs something" % id)
		for item in r.needs:
			check(Inventory.is_item(item) and not Crafting.is_recipe(item), "%s needs raw %s" % [id, item])
			check(int(r.needs[item]) > 0, "%s needs a positive %s" % [id, item])
	for kind in Gathering.TOOLS:
		check(Crafting.makes_tool(Gathering.TOOLS[kind]), "the %s tool is a craftable tool" % kind)


func test_workbench_sits_in_open_meadow() -> void:
	var p := Crafting.workbench_pos()
	check(Vector2(p.x, p.z).length() < ResourceNodes.SPAWN_CLEAR_RADIUS - 2.0, "inside the empty meadow centre")
	check(p.y > Terrain.water_level(), "on dry land")
	check(Crafting.near_bench(GameConfig.SPAWN_POINT), "a new player arrives within reach of it")
	check(ResourceNodes.near(p, 4.0).is_empty(), "no tree or rock on top of it")


func test_parse_recipe() -> void:
	check_eq(Crafting.parse_recipe(""), "")
	check_eq(Crafting.parse_recipe("axe"), "stone_axe")
	check_eq(Crafting.parse_recipe("Stone Axe"), "stone_axe")
	check_eq(Crafting.parse_recipe("a pickaxe"), "stone_pickaxe")
	check_eq(Crafting.parse_recipe("stone-pick"), "stone_pickaxe")
	check_eq(Crafting.parse_recipe("torches"), "torch")
	check_eq(Crafting.parse_recipe("fire"), "campfire")
	check_eq(Crafting.parse_recipe("dragon"), null)


func test_check_reasons_in_order() -> void:
	var inv := {"ash_wood": 3, "stone": 2}
	check_eq(Crafting.check(inv, "sword", AT_BENCH), "unknown")
	check_eq(Crafting.check(inv, "stone_axe", FAR), "bench")
	check_eq(Crafting.check(inv, "stone_axe", AT_BENCH), "")
	check_eq(Crafting.check({"ash_wood": 2, "stone": 2}, "stone_axe", AT_BENCH), "missing")
	check_eq(Crafting.check({"ash_wood": 3, "stone": 2, "stone_axe": 1}, "stone_axe", AT_BENCH), "owned", "one axe is enough")
	check_eq(Crafting.check({"pine_wood": 1, "ember_sap": 1}, "torch", FAR), "", "torches need no bench")
	check_eq(Crafting.check({"pine_wood": 1, "ember_sap": 1, "torch": Inventory.MAX_STACK - 1}, "torch", FAR), "full")
	check_eq(Crafting.missing({"ash_wood": 1}, "campfire"), {"ash_wood": 1, "pine_wood": 2, "stone": 4})


func test_replies() -> void:
	var r := Crafting.refusal("missing", {"ash_wood": 1}, "stone_axe", AT_BENCH)
	check_eq(r, "You need 2 ash wood and 2 stone more to make a stone axe.")
	r = Crafting.refusal("bench", {}, "campfire", Vector3(3.0, 0.0, 30.0))
	check(r.begins_with("A campfire needs the workbench. The workbench is 32 m to the north"), r)
	check(Crafting.refusal("owned", {}, "stone_pickaxe", AT_BENCH).begins_with("You already carry a stone pickaxe"), "line 59")
	check_eq(Crafting.needs_text({"stone": 4, "ash_wood": 2, "pine_wood": 2}), "2 ash wood, 2 pine wood and 4 stone", "pack order, joined nicely")
	var list := Crafting.recipes_text({"pine_wood": 1, "ember_sap": 1, "stone_axe": 1})
	check(list.begins_with("Recipes"), list)
	check(list.contains("stone axe: 3 ash wood and 2 stone, at the workbench (have it)"), list)
	check(list.contains("3 torches: 1 pine wood and 1 ember sap, anywhere (ready)"), list)
	check(not list.contains("campfire: 2 ash wood, 2 pine wood and 4 stone, at the workbench (ready)"), list)
	check(Crafting.success("torch", 3, {"torch": 5}).contains("You craft 3 torches (5 in your pack)"), "line 66")
	check(Crafting.success("stone_axe", 1, {"stone_axe": 1}).begins_with("You craft a stone axe."), "line 67")


## The same steps the server runs (check, then take each ingredient, then give), on a plain
## Dictionary, so the bookkeeping is proven without a network.
func test_craft_uses_up_exactly_the_recipe() -> void:
	var inv := {"ash_wood": 5, "stone": 3, "pine_wood": 1}
	check_eq(Crafting.check(inv, "stone_axe", AT_BENCH), "")
	var r: Dictionary = Crafting.RECIPES.stone_axe
	for item in r.needs:
		check(Inventory.remove(inv, item, int(r.needs[item])), "took %s" % item)
	check_eq(Inventory.add(inv, "stone_axe", int(r.makes)), 1)
	check_eq(inv, {"ash_wood": 2, "stone": 1, "pine_wood": 1, "stone_axe": 1})
	check_eq(Crafting.check(inv, "stone_axe", AT_BENCH), "owned")


func test_tools_help_gathering() -> void:
	var bare := {}
	var axe := {"stone_axe": 1}
	var pick := {"stone_pickaxe": 1}
	check_eq(Gathering.tool_for("pine", bare), "")
	check_eq(Gathering.tool_for("pine", axe), "stone_axe")
	check_eq(Gathering.tool_for("ash", axe), "stone_axe")
	check_eq(Gathering.tool_for("stone", axe), "", "an axe doesn't mine")
	check_eq(Gathering.tool_for("stone", pick), "stone_pickaxe")
	check_eq(Gathering.tool_for("ember_sap", {"stone_axe": 1, "stone_pickaxe": 1}), "", "sap is by hand")
	check_eq(Gathering.tool_for("pine", {"stone_axe": 0}), "", "a 0 row is not carrying it")
	var base := int(ResourceNodes.kind_info("pine").amount)
	check_eq(Gathering.amount_for("pine", bare), base)
	check_eq(Gathering.amount_for("pine", axe), base + Gathering.TOOL_EXTRA)
	check_eq(Gathering.cooldown_for("stone", bare), Gathering.COOLDOWN)
	check(Gathering.cooldown_for("stone", pick) < Gathering.COOLDOWN, "faster with a pickaxe")
	# check() honours the shorter cooldown.
	var st := Gathering.new_state()
	var n: Dictionary = ResourceNodes.near(Vector3.ZERO, 200.0, "stone")[0]
	var t := 50.0
	var since := Gathering.COOLDOWN * 0.75
	check_eq(Gathering.check(st, n.id, n.pos, t, 0.0, t - since), "cooldown", "bare hands still busy")
	check_eq(Gathering.check(st, n.id, n.pos, t, 0.0, t - since, Gathering.cooldown_for("stone", pick)), "", "pickaxe ready")
	check(Gathering.success(n.id, 3, 3, false, "stone_pickaxe").contains("with your stone pickaxe (3 in your pack)"), "line 106")


func test_craft_command_routing() -> void:
	for line in ["/craft", "/craft axe", "/CRAFT torch", "/make campfire", "/recipes"]:
		check(ChatCommands.is_craft(line), "%s is /craft" % line)
		check(not ChatCommands.is_gather(line), "%s is not /gather" % line)
	check(not ChatCommands.is_craft("craft me an axe"), "plain chat")
	check(not ChatCommands.is_craft("/gather"), "line 114")
	check(ChatCommands.HELP.contains("/craft"), "listed in /help")
	check_eq(ChatCommands.argument("/craft stone axe"), "stone axe")

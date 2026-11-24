extends TestCase
## The bot test's craft-haul check (tests/bot_test/craft_haul.gd, seed_crafter.gd and
## client_craft_window.gd --craft-haul): where the crafter stands, what it carries, that the
## real client window says both recipes are Ready there, and the verdict on its stats.

const CraftHaul := preload("res://tests/bot_test/craft_haul.gd")
const WindowScript := preload("res://client/craft_window.gd")
const Behaviour := preload("res://tests/bot_test/behaviours/client_craft_window.gd")


func test_crafter_stands_at_the_bench_on_the_ground() -> void:
	var p := CraftHaul.spot()
	var d := Vector2(p.x, p.z).distance_to(Crafting.WORKBENCH_XZ)
	check(absf(d - CraftHaul.BENCH_OFFSET) < 0.01, "%.2f m from the bench" % d)
	check(d < Crafting.BENCH_RANGE - Behaviour.EDGE, "inside the range the behaviour trusts for a campfire")
	check(WindowScript.near_bench(p), "the client shows the workbench prompt there")
	check(absf(p.y - Terrain.height(p.x, p.z)) < 0.001, "on the ground")


func test_pack_is_exactly_both_recipes() -> void:
	var inv := CraftHaul.pack()
	check_eq(Inventory.count(inv, "ember_sap"), 1, "one sap for the torch")
	check_eq(Inventory.count(inv, "pine_wood"), 3, "pine for the campfire and the torch")
	check_eq(Inventory.count(inv, "ash_wood"), 2)
	check_eq(Inventory.count(inv, "stone"), 4)
	check_eq(Crafting.check(inv, "campfire", CraftHaul.spot()), "", "campfire ready at the bench")
	check_eq(Crafting.check(inv, "torch", CraftHaul.spot()), "", "torch ready")
	check_eq(WindowScript.row(inv, "campfire", CraftHaul.spot()).reason, "", "the window row says Ready")


func test_both_crafts_leave_exactly_the_goods() -> void:
	# Run the real recipe on the pack in the order the bot presses, as the server would.
	var inv := Inventory.normalize(CraftHaul.pack())
	var p := CraftHaul.spot()
	for id in CraftHaul.RECIPES:
		check_eq(Crafting.check(inv, id, p), "", "%s still ready after the one before" % id)
		for item in Crafting.RECIPES[id].needs:
			inv[item] = Inventory.count(inv, item) - int(Crafting.RECIPES[id].needs[item])
		inv[id] = Inventory.count(inv, id) + int(Crafting.RECIPES[id].makes)
	check_eq(Inventory.to_wire(Inventory.normalize(inv)), Inventory.to_wire(Inventory.normalize(CraftHaul.pack_after())))
	check_eq(Inventory.count(CraftHaul.pack_after(), "torch"), 3, "a torch press makes three")
	check_eq(Crafting.check(Inventory.normalize(inv), "torch", p), "missing", "a later torch press is refused")


func test_verdict() -> void:
	var good := {"made": ["campfire", "torch"], "presses": 4, "toolcraft_xp": 2, "haul_pack": CraftHaul.pack_after()}
	check_eq(CraftHaul.verdict(good), [], "a full haul passes")
	var none := good.duplicate()
	none.made = []
	none.toolcraft_xp = 0
	check_eq(CraftHaul.verdict(none).size(), 3, "nothing made: both recipes and the XP are reported")
	var short := good.duplicate()
	short.haul_pack = CraftHaul.pack()
	check(CraftHaul.verdict(short).size() == 1 and str(CraftHaul.verdict(short)[0]).begins_with("pack after"), "inputs still in the pack")
	var lost := good.duplicate()
	lost.erase("haul_pack")
	check_eq(CraftHaul.verdict(lost), ["no pack reported after the crafts"])


func test_haul_mode_holds_still_and_presses_soon() -> void:
	var bot: Node = preload("res://tests/bot_test/bot.gd").new()
	bot.args = {"craft-haul": true}
	var b = Behaviour.new()
	b.bot = bot
	check(Behaviour.haul_mode(bot.args), "--craft-haul turns haul mode on")
	check(not Behaviour.haul_mode({}), "off without it")
	b._haul = true
	b._w = WindowScript.new()
	b._w.setup(Theme.new())
	bot.elapsed = 10.0
	b.on_login(false, {"inventory": CraftHaul.pack()})
	check(b._next_press - bot.elapsed <= Behaviour.HAUL_FIRST_PRESS + 0.001, "first press within %.1f s" % Behaviour.HAUL_FIRST_PRESS)
	check(b._w.pack_known, "the window knows the seeded pack")
	bot.phase = "playing_1"
	bot.have_pos = true
	bot.my_pos = CraftHaul.spot()
	bot.move = Vector2(1, 0)
	b._next_press = INF
	b.on_play(0.016)
	check_eq(bot.move, Vector2.ZERO, "holds still at the bench until the haul is made")
	b.made = ["campfire", "torch"]
	bot.move = Vector2(1, 0)
	b.on_play(0.016)
	check_eq(bot.move, Vector2(1, 0), "wanders once both are made")
	b._w.free()
	bot.free()

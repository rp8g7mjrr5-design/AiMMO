extends TestCase
## The grounded survival kit (owner direction, 2026-11-26: "basic zombie survival tools ...
## Bandages and other things like that. We dont need magic"): plant fibre from scrub, the
## bandage and the slower natural healing that makes it worth carrying, the wooden and stone
## weapons you swing, and old saves whose ember items turn into plain ones.

const ServerScript := preload("res://server/server.gd")
const FAR := Vector3(60.0, 0.0, 60.0)


func _server(inv: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "Medic", "inventory": inv})
	ch.x = FAR.x
	ch.y = Terrain.height(FAR.x, FAR.z)
	ch.z = FAR.z
	srv.sessions[2] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func test_no_magic_left_in_the_items() -> void:
	for id in Inventory.ITEMS:
		check(not str(id).contains("ember"), "%s is not an ember item" % id)
		check(not str(Inventory.label(id)).contains("ember"), Inventory.label(id))
	for id in Crafting.RECIPES:
		check(not str(id).contains("ember"), "%s is not an ember recipe" % id)
		for item in Crafting.RECIPES[id].needs:
			check(Inventory.ITEMS.has(item), "%s needs %s, a real item" % [id, item])
	for kind in ResourceNodes.KINDS:
		check(Inventory.ITEMS.has(str(ResourceNodes.KINDS[kind].item)), "%s gives a real item" % kind)
		check(not bool(ResourceNodes.KINDS[kind].night_only), "%s: nothing only at night any more" % kind)
	for kind in ResourceNodes.TIER2:
		check(Inventory.ITEMS.has(str(ResourceNodes.TIER2[kind].item)), "tier-2 %s gives a real item" % kind)


func test_scrub_gives_plant_fibre_by_hand() -> void:
	check_eq(str(ResourceNodes.KINDS.scrub.item), "plant_fibre")
	check(Gathering.charges("scrub") >= 2, "a patch is worth the walk")
	check_eq(Gathering.parse_kind("fibre"), "scrub")
	var n := 0
	for node in ResourceNodes.all():
		if node.kind == "scrub":
			n += 1
	check(n > 10, "scrub all over the valley (%d)" % n)


func test_bandage_recipe_and_heal() -> void:
	check_eq(Crafting.check({"plant_fibre": 3}, "bandage", FAR), "", "made anywhere from fibre")
	check(not Crafting.makes_tool("bandage"), "carry as many as you like")
	var v := Vitals.full()
	check_eq(Vitals.bandage_check(v), "full", "not hurt")
	v.hp = 40.0
	v.hit_at = 100.0 # in a fight: no natural trickle, so only the bandage heals
	check_eq(Vitals.apply_bandage(v), "")
	check_eq(Vitals.apply_bandage(v), "busy", "one at a time")
	var steps := int(Vitals.BANDAGE_SECONDS / 0.05) + 2
	for i in steps:
		Vitals.tick(v, 100.0 + (i + 1) * 0.05, 0.05)
	check_near(float(v.hp), 40.0 + Vitals.BANDAGE_HEAL, 0.01, "healed BANDAGE_HEAL, even mid-fight")
	check_eq(Vitals.bandage_check(v), "", "done: ready for the next")
	v.hp = 95.0
	Vitals.apply_bandage(v)
	for i in steps:
		Vitals.tick(v, 200.0 + i * 0.05, 0.05)
	check_eq(float(v.hp), 100.0, "never past full")
	check_eq(float(v.heal_left), 0.0)


func test_health_trickles_back_only_to_half() -> void:
	var v := Vitals.full()
	v.hp = 10.0
	for i in 600: # 60 s out of combat
		Vitals.tick(v, 1000.0 + i * 0.1, 0.1)
	check(float(v.hp) > 10.0, "some health comes back by itself")
	check(float(v.hp) < 50.0, "slowly: %.1f after a minute" % float(v.hp))
	for i in 3000:
		Vitals.tick(v, 2000.0 + i * 0.1, 0.1)
	check_near(float(v.hp), Vitals.MAX_HP * Vitals.HP_REGEN_CAP, 0.01, "and stops at half")


func test_server_bandage_through_place() -> void:
	var srv := _server({"bandage": 2})
	var r: Dictionary = srv.place_request(2, "bandage")
	check_eq(r.reason, "full", "not hurt: refused, kept")
	check_eq(Inventory.count(srv.sessions[2].character.inventory, "bandage"), 2)
	srv.vitals_of(2).hp = 30.0
	r = srv.place_request(2, "bandage")
	check(r.ok, r.text)
	check_eq(Inventory.count(srv.sessions[2].character.inventory, "bandage"), 1, "one used")
	check_eq(srv.place_request(2, "bandage").reason, "busy")
	srv.free()
	srv = _server({})
	srv.vitals_of(2).hp = 30.0
	r = srv.place_request(2, "bandage")
	check_eq(r.reason, "no_item")
	check(str(r.text).contains("plant fibre"), r.text)
	srv.free()


func test_you_swing_the_best_weapon_you_carry() -> void:
	var srv := _server({})
	check_eq(srv.weapon_of(2), Weapons.FISTS)
	srv.sessions[2].character.inventory = {"wooden_club": 1}
	check_eq(srv.weapon_of(2), "wooden_club")
	srv.sessions[2].character.inventory = {"wooden_club": 1, "stone_spear": 1}
	check_eq(srv.weapon_of(2), "stone_spear", "stone beats wood")
	srv.free()
	for id in Weapons.ORDER:
		check(Crafting.is_recipe(id) and Inventory.is_item(id), "%s can be made and carried" % id)
		check(Crafting.makes_tool(id), "%s: you only need one" % id)
	check_eq(Crafting.check({"ash_wood": 3}, "wooden_club", FAR), "", "a club from wood, anywhere")
	check_eq(Crafting.RECIPES.stone_maul.upgrades, "wooden_club")
	check_eq(Crafting.RECIPES.stone_spear.upgrades, "wooden_spear")


func test_old_saves_turn_ember_items_into_plain_ones() -> void:
	var ch := CharacterData.normalize({"name": "Veteran", "inventory": {
		"ember_axe": 1, "ember_pickaxe": 1, "stone_pickaxe": 1, "ember_lantern": 2,
		"ember_heartwood": 3, "veinstone": 4, "ember_sap": 5, "ash_wood": 10}})
	var inv: Dictionary = ch.inventory
	check_eq(Inventory.count(inv, "stone_axe"), 1, "the ember axe is a stone axe now")
	check_eq(Inventory.count(inv, "stone_pickaxe"), 1, "never a second pickaxe")
	check_eq(Inventory.count(inv, "torch"), 6, "each lantern is three torches")
	check_eq(Inventory.count(inv, "ash_wood"), 16, "heartwood is ash wood")
	check_eq(Inventory.count(inv, "stone"), 8, "veinstone is stone")
	check_eq(Inventory.count(inv, "plant_fibre"), 5, "sap is fibre")
	for old in Inventory.RETIRED:
		check_eq(Inventory.count(inv, old), 0, "%s is gone from the pack" % old)
		check(inv.has(old), "%s stays at 0 so the next save writes it" % old)
		check(not Inventory.is_item(old), "%s can't be gained again" % old)
	check(not Inventory.held(inv).has("ember_axe"), "and never shown")
	# Idempotent: a second load changes nothing.
	var again := inv.duplicate()
	check(Inventory.convert_retired(again).is_empty(), "nothing left to convert")
	check_eq(again, inv)


func test_every_island_landing_has_the_first_kit_close_by() -> void:
	# The island (generator v2): wherever you wash up, the wood for a wooden axe and pickaxe and
	# a scrub patch for fibre (bandages, torches, stone-tool bindings) are in your starter ring.
	for seed in [1, 2]:
		WorldGen.configure(seed, 3000.0, WorldGen.ISLAND)
		var landings := WorldGen.landings()
		var total := {}
		for n in ResourceNodes.all():
			total[n.kind] = total.get(n.kind, 0) + 1
		check(total.get("scrub", 0) >= 20, "seed %d: scrub across the island (%d)" % [seed, total.get("scrub", 0)])
		for i in landings.size():
			var kinds := {}
			for n in WorldGen.node_spots():
				if n.starter and Vector2(n.pos.x, n.pos.z).distance_to(landings[i]) < 80.0:
					kinds[n.kind] = true
			for k in ["ash", "pine", "scrub"]:
				check(kinds.has(k), "seed %d landing %d has %s close by" % [seed, i, k])
		check_eq(Crafting.check({"ash_wood": 2, "pine_wood": 2}, "wooden_pickaxe", Vector3(landings[0].x, 0, landings[0].y)), "",
			"seed %d: a wooden pickaxe is made right on the beach" % seed)
	WorldGen.reset()

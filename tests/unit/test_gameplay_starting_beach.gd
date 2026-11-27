extends TestCase
## The starting beaches (BeachGen, owner 2026-11-26: "lets talk our starting beach"): every
## island landing rolls a landmark or two and gets pickings you gather by hand, so a fresh
## character has a wooden pickaxe's worth of wood within a few steps. The beach nodes are
## appended after every older node, so no older id moves. Every test puts the world back to
## Ashgrove, because the config is global.

const ServerScript := preload("res://server/server.gd")
const SEEDS := [3, 1126]


func _island(seed: int) -> void:
	WorldGen.configure(seed, 3000.0, WorldGen.ISLAND)
	ResourceNodes.reset()
	BeachGen.reset()


func _done() -> void:
	WorldGen.reset()
	ResourceNodes.reset()
	BeachGen.reset()


func test_every_landing_gets_a_dressed_beach() -> void:
	for seed in SEEDS:
		_island(seed)
		var beaches := BeachGen.all()
		check_eq(beaches.size(), WorldGen.landings().size(), "seed %d: one beach per landing" % seed)
		for b in beaches:
			var tag := "seed %d beach %d" % [seed, b.index]
			check(b.landmarks.size() >= 1 and b.landmarks.size() <= 2, tag + ": one or two landmarks (%d)" % b.landmarks.size())
			var kinds := {}
			for lm in b.landmarks:
				check(BeachGen.LANDMARKS.has(lm.kind), tag + ": a known landmark " + str(lm.kind))
				check(not kinds.has(lm.kind), tag + ": never the same landmark twice on one beach")
				kinds[lm.kind] = true
				var d := Vector2(lm.pos.x, lm.pos.z).distance_to(b.landing)
				check(d >= BeachGen.CLEAR, tag + ": %s stands clear of the landing (%.1f m)" % [lm.kind, d])
				check(d < 90.0, tag + ": %s is on this beach (%.1f m)" % [lm.kind, d])
			check(b.pools.size() >= 2, tag + ": tide pools")
			check(b.deco.size() > 20, tag + ": shells and wrack on the sand (%d)" % b.deco.size())
			check(absf((b.sea as Vector2).length() - 1.0) < 0.001, tag + ": the sea is a direction")
			var out: Vector2 = (b.landing as Vector2) + (b.sea as Vector2) * (b.shore + 3.0)
			check(Terrain.height(out.x, out.y) < Terrain.water_level(), tag + ": the sea is that way")
			check(b.shore > 3.0 and b.shore < 60.0, tag + ": the landing is a short walk from the water (%.1f m)" % b.shore)
	_done()


func test_landmarks_vary_from_beach_to_beach() -> void:
	var seen := {}
	for seed in [1, 2, 3, 7, 1126]:
		_island(seed)
		for lm in BeachGen.landmarks():
			seen[lm.kind] = seen.get(lm.kind, 0) + 1
	for k in BeachGen.LANDMARK_ORDER:
		check(seen.get(k, 0) >= 1, "%s turns up on some beach (%s)" % [k, seen])
	_done()


func test_same_seed_same_beaches() -> void:
	_island(11)
	var a := var_to_str(BeachGen.all())
	BeachGen.reset()
	check_eq(var_to_str(BeachGen.all()), a, "the same island dresses its beaches the same way (a restart)")
	_island(12)
	check(var_to_str(BeachGen.all()) != a, "a new island (a wipe), new beaches")
	_done()


func test_no_beaches_off_the_island() -> void:
	WorldGen.reset()
	check(BeachGen.all().is_empty(), "Ashgrove has no beaches")
	WorldGen.configure(5, 1200.0, WorldGen.KINGDOM)
	check(BeachGen.all().is_empty(), "nor a version 1 kingdom")
	ResourceNodes.reset()
	for n in ResourceNodes.all():
		check(not ResourceNodes.BEACH_KINDS.has(n.kind), "no beach nodes on a kingdom")
	_done()


func test_beach_nodes_are_appended_so_older_ids_never_move() -> void:
	for seed in SEEDS:
		_island(seed)
		var all := ResourceNodes.all()
		var beach := BeachGen.nodes()
		check(beach.size() >= 6 * WorldGen.landings().size(), "seed %d: pickings on every beach (%d)" % [seed, beach.size()])
		var first := all.size() - beach.size()
		for i in first:
			check(not ResourceNodes.BEACH_KINDS.has(all[i].kind), "seed %d: node %d before the beach pass is an older kind" % [seed, i])
		for i in beach.size():
			var n: Dictionary = all[first + i]
			check_eq(n.id, first + i, "ids are indices")
			check_eq(n.kind, beach[i].kind, "seed %d: beach node %d in BeachGen's order" % [seed, i])
		# The older passes alone give exactly the list they gave before the beaches existed.
		var older := WorldGen.node_spots().size() + ResourceNodes.tier2().size()
		check_eq(first, older, "seed %d: only the world's spots and the tier-2 ring come first" % seed)
	_done()


func test_beach_pickings_by_hand() -> void:
	for kind in ResourceNodes.BEACH_ORDER:
		var info := ResourceNodes.kind_info(kind)
		check(Inventory.ITEMS.has(str(info.item)), "%s gives a real item" % kind)
		check(not bool(info.get("needs_tool", false)), "%s needs no tool: you have nothing yet" % kind)
		check(Gathering.charges(kind) >= 2, "%s is worth stopping for" % kind)
		check(float(GatherChannel.SECONDS.get(kind, 0.0)) <= 2.0, "%s is quick" % kind)
	check_eq(Gathering.parse_kind("driftwood"), "driftwood")
	check_eq(Gathering.parse_kind("seaweed"), "kelp")
	check_eq(Gathering.parse_kind("crate"), "wreck_crate")


func test_a_wooden_pickaxe_off_every_beach() -> void:
	# Within 50 m of where you wake: driftwood and a crate give the ash and pine wood for a
	# wooden pickaxe (2 ash, 2 pine) by hand, and the kelp the fibre for a bandage.
	for seed in SEEDS:
		_island(seed)
		for b in BeachGen.all():
			var got := {}
			for n in b.nodes:
				if Vector2(n.pos.x, n.pos.z).distance_to(b.landing) > 50.0:
					continue
				var info := ResourceNodes.kind_info(n.kind)
				got[info.item] = got.get(info.item, 0) + int(info.amount) * Gathering.charges(n.kind)
			var tag := "seed %d beach %d" % [seed, b.index]
			check(got.get("ash_wood", 0) >= 2 and got.get("pine_wood", 0) >= 2, tag + ": a wooden pickaxe's wood (%s)" % got)
			check(got.get("plant_fibre", 0) >= 3, tag + ": a bandage's fibre (%s)" % got)
			check(got.get("stone", 0) >= 1, tag + ": a few loose stones (%s)" % got)
	_done()


func test_beach_nodes_sit_on_the_sand() -> void:
	for seed in SEEDS:
		_island(seed)
		var wl := Terrain.water_level()
		for n in BeachGen.nodes():
			check(n.pos.y > wl, "seed %d: %s above the water (%.2f)" % [seed, n.kind, n.pos.y])
			check(n.pos.y < 4.6, "seed %d: %s down on the beach (%.2f)" % [seed, n.kind, n.pos.y])
			for s in WorldGen.ruin_sites():
				check(Vector2(n.pos.x, n.pos.z).distance_to(Vector2(s.pos.x, s.pos.z)) > float(s.radius), "seed %d: %s not inside a location" % [seed, n.kind])
		# Never two nodes on top of each other.
		var list := ResourceNodes.all()
		var first := list.size() - BeachGen.nodes().size()
		for i in range(first, list.size()):
			for near in ResourceNodes.near(list[i].pos, 3.0):
				if near.id != list[i].id:
					check(false, "seed %d: node %d (%s) crowds node %d (%s)" % [seed, i, list[i].kind, near.id, near.kind])
	_done()


func test_server_gathers_driftwood_and_a_crate_by_hand() -> void:
	_island(3)
	var srv: Node = ServerScript.new()
	srv.use_world(WorldGen.config())
	srv.test_now = 100.0
	var b: Dictionary = BeachGen.beach(0)
	for kind in ["driftwood", "wreck_crate", "kelp", "beach_stones"]:
		var node := {}
		var list := ResourceNodes.all()
		for i in range(list.size() - BeachGen.nodes().size(), list.size()):
			if list[i].kind == kind:
				node = list[i]
				break
		check(not node.is_empty(), "a %s on the island" % kind)
		var ch := CharacterData.normalize({"name": "Castaway", "inventory": {}})
		ch.x = node.pos.x + 0.5
		ch.y = node.pos.y
		ch.z = node.pos.z
		srv.sessions[2] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
		srv.test_now += 10.0
		srv.gather(2, kind)
		var item := str(ResourceNodes.kind_info(kind).item)
		check_eq(Inventory.count(srv.sessions[2].character.inventory, item), int(ResourceNodes.kind_info(kind).amount), "bare hands take %s from %s" % [item, kind])
	check(b.landmarks.size() >= 1, "beach 0 has a landmark")
	srv.free()
	_done()

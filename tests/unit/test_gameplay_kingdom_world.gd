extends TestCase
## Phase 1 part 3: nodes, ruins and spawn on a generated kingdom. With WorldGen on gen_version 1
## the server puts every resource node, the tier-2 ring, the herds, the workbench and the spawn
## where the seed says, and a fresh character can gather and craft end to end there. Ashgrove
## (gen_version 0, the live world) stays exactly as it was.
##
## Every test that configures a kingdom puts Ashgrove back before it returns, because WorldGen,
## ResourceNodes and Wildlife are static and the other tests expect today's world.

const ServerScript := preload("res://server/server.gd")
const SEEDS := [11, 2024]


func _kingdom(seed: int) -> void:
	WorldGen.configure(seed, 1200.0, WorldGen.KINGDOM)
	ResourceNodes.reset()


func _ashgrove() -> void:
	WorldGen.reset()
	ResourceNodes.reset()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_ashgrove_is_untouched_by_a_trip_to_a_kingdom() -> void:
	_ashgrove()
	var before := ResourceNodes.fingerprint()
	var herds_before := str(Wildlife.spawns().map(func(c): return c.pos))
	var bench_before := Crafting.workbench_pos()
	check_eq(Crafting.workbench_xz(), Crafting.WORKBENCH_XZ, "Ashgrove's bench is where it always was")
	_kingdom(SEEDS[0])
	check(ResourceNodes.fingerprint() != before, "a kingdom has its own nodes")
	_ashgrove()
	check_eq(ResourceNodes.fingerprint(), before, "back on Ashgrove, every node id and place is as before")
	check_eq(str(Wildlife.spawns().map(func(c): return c.pos)), herds_before, "and the herds too")
	check_eq(Crafting.workbench_pos(), bench_before)
	check_eq(Ruins.count(), 0, "Ashgrove has no ruins")
	check_eq(ServerScript.describe_world(), "Ashgrove (gen 0, 512 m)")


func test_the_cache_follows_the_config_on_its_own() -> void:
	_ashgrove()
	var ash := ResourceNodes.count()
	WorldGen.configure(SEEDS[0], 1200.0, WorldGen.KINGDOM) # no ResourceNodes.reset()
	check(ResourceNodes.count() != ash, "all() rebuilt for the new world without being told")
	WorldGen.reset()
	check_eq(ResourceNodes.count(), ash, "and again on the way back")
	_ashgrove()


func test_nodes_come_from_the_seed_in_stable_order() -> void:
	for seed in SEEDS:
		_kingdom(seed)
		var spots := WorldGen.node_spots()
		var nodes := ResourceNodes.all()
		check(spots.size() > 200, "seed %d: a kingdom is full of nodes (%d spots)" % [seed, spots.size()])
		for i in spots.size():
			if nodes[i].id != i or nodes[i].kind != spots[i].kind or nodes[i].pos != spots[i].pos:
				check(false, "seed %d: node %d is WorldGen's spot %d" % [seed, i, i])
				break
		var fp := ResourceNodes.fingerprint()
		check_eq(ResourceNodes.fingerprint(), ResourceNodes.fingerprint(), "seed %d: stable" % seed)
		ResourceNodes.reset()
		check_eq(ResourceNodes.fingerprint(), fp, "seed %d: the same ids after a rebuild (a restart)" % seed)
		var kinds := {}
		for n in nodes:
			kinds[n.kind] = true
			check(ResourceNodes.KINDS.has(n.kind), "a known kind: %s" % n.kind)
		for k in ResourceNodes.KIND_ORDER:
			check(kinds.has(k), "seed %d has %s" % [seed, k])
	_kingdom(SEEDS[0])
	var a := ResourceNodes.fingerprint()
	_kingdom(SEEDS[1])
	check(ResourceNodes.fingerprint() != a, "two seeds, two worlds")
	_ashgrove()


func test_first_gather_is_a_short_walk_from_spawn() -> void:
	for seed in SEEDS:
		_kingdom(seed)
		var sp := WorldGen.spawn_point()
		# 60 s of walking is GameConfig.WALK_SPEED * 60 m; the starter ring is far closer.
		var walk := GameConfig.WALK_SPEED * 60.0
		for k in ResourceNodes.KIND_ORDER:
			var n := ResourceNodes.nearest(sp, k, walk)
			check(not n.is_empty(), "seed %d: a %s within a minute's walk of spawn" % [seed, k])
		var starters := ResourceNodes.near(sp, WorldGen.STARTER_MAX + 0.5)
		check(starters.size() >= 5, "seed %d: the starter ring stands round the spawn plot (%d)" % [seed, starters.size()])
		var near_spawn := ResourceNodes.near(sp, WorldGen.SPAWN_CLEAR - 0.01)
		check_eq(near_spawn.size(), 0, "seed %d: the very centre of spawn stays clear" % seed)
	_ashgrove()


func test_tier2_ring_waits_round_the_kingdom_spawn() -> void:
	for seed in SEEDS:
		_kingdom(seed)
		var sp := WorldGen.spawn_point()
		var t2 := ResourceNodes.tier2()
		check(t2.size() >= 6, "seed %d: most of the tier-2 ring found ground (%d of 8)" % [seed, t2.size()])
		var kinds := {}
		for n in t2:
			kinds[n.kind] = true
			check_eq(n.min_level, 5, "a level gate")
			check(n.id >= WorldGen.node_spots().size(), "tier 2 is appended after every spot")
			var d := _flat(n.pos, sp)
			check(d >= ResourceNodes.TIER2_MIN_RADIUS - 0.01 and d < 140.0, "seed %d: tier 2 a short walk out (%.0f m)" % [seed, d])
			check(n.pos.y >= Terrain.water_level() + 1.0, "on dry ground")
			check(Ruins.at(n.pos).is_empty(), "not inside a ruin")
			for m in ResourceNodes.near(n.pos, ResourceNodes.TIER2_SPACING - 0.01):
				check(m.id == n.id, "seed %d: room round tier-2 node %d" % [seed, n.id])
		check(kinds.has("ash") and kinds.has("stone"), "seed %d: old ashes and rich seams" % seed)
	_ashgrove()


func test_bench_and_herds_follow_the_spawn() -> void:
	for seed in SEEDS:
		_kingdom(seed)
		var sp := WorldGen.spawn_point()
		var bench := Crafting.workbench_pos()
		check_near(_flat(bench, sp), Crafting.WORKBENCH_XZ.length(), 0.001, "seed %d: the bench stands by spawn" % seed)
		check(Crafting.near_bench(sp), "spawn is in the bench's reach")
		check(bench.y > Terrain.water_level(), "the bench is on dry land")
		check_eq(ResourceNodes.near(bench, 3.0).size(), 0, "no node grows through the bench")
		var herds := Wildlife.spawns()
		check(herds.size() >= 9, "seed %d: grazers in the hills round spawn (%d)" % [seed, herds.size()])
		for c in herds:
			if not Wildlife.good_ground(c.home.x, c.home.z):
				check(false, "seed %d: herd home %s on good ground" % [seed, c.home])
				break
			var d := _flat(c.home, sp)
			if d < Wildlife.HERD_MIN_RADIUS - 0.01 or d > Wildlife.HERD_MAX_RADIUS + 0.01:
				check(false, "seed %d: herd home %.0f m from spawn" % [seed, d])
				break
		var st := Wildlife.new_state()
		check_eq(st.creatures.size(), herds.size(), "a fresh state has every grazer")
	_ashgrove()


func test_ruins_with_their_grades() -> void:
	for seed in SEEDS:
		_kingdom(seed)
		var ruins := Ruins.all()
		check_eq(ruins.size(), WorldGen.ruin_sites().size())
		var grades := {}
		var kinds := {}
		for r in ruins:
			grades[r.grade] = true
			kinds[r.kind] = true
			check(Ruins.GRADE_NAMES.has(r.grade), "a known grade")
			check(Ruins.LABELS.has(r.kind), "a label for %s" % r.kind)
			check_eq(int(Ruins.at(r.pos).get("id", -1)), r.id, "standing in the middle of %s finds it" % r.label)
			check(int(Ruins.at(r.pos + Vector3(r.radius + 80.0, 0, 0)).get("id", -1)) != r.id, "far outside is not in it")
		for g in [1, 2, 3, 4]:
			check(grades.has(g), "seed %d has a grade %d ruin" % [seed, g])
		for k in WorldGen.RUIN_MUST_HAVE:
			check(kinds.has(k), "seed %d has a %s" % [seed, k])
		var castle := Ruins.nearest(WorldGen.spawn_point(), 4)
		check_eq(castle.kind, "fallen_castle")
		check_eq(Ruins.title(castle), "The Fallen Castle (Deadly)")
		check(Ruins.describe().begins_with("%d ruins" % ruins.size()), Ruins.describe())
	check_eq(Ruins.grade_name(1), "Quiet")
	check_eq(Ruins.label("mystery_tower"), "Mystery Tower", "a new kind reads fine before it has a label")
	_ashgrove()


## The whole first loop on a generated world, through the real server functions: log in, land
## at the kingdom's spawn, gather ash and stone from the starter ring, walk to the bench, craft.
func test_a_fresh_character_gathers_and_crafts_on_a_kingdom() -> void:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var st := JsonStore.new()
	st.path = "user://test_kingdom_%d/players.json" % Time.get_ticks_usec()
	st.open()
	srv.store = st
	srv.use_world(WorldGen.parse("%d:1" % SEEDS[1]))
	check(WorldGen.is_kingdom(), "--world=seed:1 runs a kingdom")
	check(ServerScript.describe_world().begins_with("kingdom seed %d, 1200 m (gen 1)" % SEEDS[1]), ServerScript.describe_world())
	check_eq(srv.wildlife.creatures.size(), Wildlife.spawns().size(), "the herds are this world's")
	srv._on_peer_connected(7)
	srv._on_login(7, GameConfig.PROTOCOL_VERSION, "Wanderer", "hunter22pass")
	var ch: Dictionary = srv.sessions[7].character
	var sp := WorldGen.spawn_point()
	check(_flat(CharacterData.position(ch), sp) < 0.01, "a new character arrives at the kingdom's spawn")
	var need := {"ash": 3, "stone": 2}
	var item := {"ash": "ash_wood", "stone": "stone"}
	for kind in need:
		var tries := 0
		while Inventory.count(ch.inventory, item[kind]) < need[kind] and tries < 8:
			tries += 1
			var n := ResourceNodes.nearest(CharacterData.position(ch), kind, 60.0)
			if n.is_empty():
				break
			ch.x = n.pos.x + 1.0
			ch.y = n.pos.y
			ch.z = n.pos.z
			var r: Dictionary = srv.gather_start(7, n.id)
			if not bool(r.get("ok", false)):
				check(false, "gather %s refused: %s" % [kind, r])
				break
			var t := 0.0
			while t < 6.0 and GatherChannel.is_active(srv.sessions[7].channel):
				srv.test_now += GameConfig.TICK_DT
				t += GameConfig.TICK_DT
				srv._tick_channels(srv.test_now)
			srv.test_now += 2.0 # past the gather cooldown
		check(Inventory.count(ch.inventory, item[kind]) >= need[kind], "gathered %s on a kingdom" % item[kind])
	var bench := Crafting.workbench_pos()
	ch.x = bench.x - 1.5
	ch.z = bench.z
	ch.y = Terrain.height(ch.x, ch.z)
	var made: Dictionary = srv.craft_request(7, "stone_axe")
	check(bool(made.ok), "crafted a stone axe at the kingdom's bench: %s" % made)
	check_eq(Inventory.count(ch.inventory, "stone_axe"), 1)
	srv.free()
	_ashgrove()


func test_a_character_from_elsewhere_never_logs_in_under_water() -> void:
	_ashgrove()
	var ch := {"x": 9999.0, "y": 0.0, "z": 0.0}
	check(not ServerScript.place_on_this_world(ch), "Ashgrove never moves anyone")
	check_eq(ch.x, 9999.0)
	_kingdom(SEEDS[0])
	var sp := WorldGen.spawn_point()
	check(ServerScript.place_on_this_world(ch), "past the border: moved")
	check(_flat(Vector3(ch.x, 0, ch.z), sp) < 0.01, "to the kingdom's spawn")
	# Find some water on this kingdom (a lake or the river).
	var wet := Vector3.INF
	for x in range(-500, 500, 10):
		for z in range(-500, 500, 10):
			if Terrain.height(x, z) < Terrain.water_level() - 1.0:
				wet = Vector3(x, 0, z)
				break
		if wet != Vector3.INF:
			break
	check(wet != Vector3.INF, "this kingdom has water")
	var swimmer := {"x": wet.x, "y": 0.0, "z": wet.z, "inventory": {"stone": 4}}
	check(ServerScript.place_on_this_world(swimmer), "in the water: moved")
	check_eq(swimmer.inventory, {"stone": 4}, "only the position changes")
	var dry := {"x": sp.x + 5.0, "y": sp.y, "z": sp.z + 5.0}
	check(not ServerScript.place_on_this_world(dry), "on dry land: left where they were")
	_ashgrove()

extends TestCase
## World stream: generator v2, the island (owner, 2026-11-26: "Lets do an island", 3 km,
## wash up on a random beach with nothing, the old Spawn Meadow as one more random place,
## and every place rolls random so it never looks the same). See IslandGen.
## Every test puts the world back to Ashgrove, because the config is global.

const SEEDS := [1, 2, 3]


func test_config_parses_island_sizes() -> void:
	check_eq(WorldGen.parse("42:2"), {"seed": 42, "size_m": IslandGen.SIZE_DEFAULT, "gen_version": WorldGen.ISLAND}, "3 km by default")
	check_eq(WorldGen.parse("42:2:small").size_m, 1500.0, "small")
	check_eq(WorldGen.parse("42:2:large").size_m, 4000.0, "large")
	check_eq(WorldGen.parse("42:2:99999").size_m, IslandGen.SIZE_MAX, "clamped up top")
	check_eq(WorldGen.parse("42:2:10").size_m, IslandGen.SIZE_MIN, "clamped below")
	check_eq(WorldGen.parse("42:1").size_m, WorldGen.KINGDOM_SIZE_DEFAULT, "version 1 keeps its own sizes")
	WorldGen.configure(5, 3000.0, WorldGen.ISLAND)
	check(WorldGen.is_kingdom() and WorldGen.is_island(), "an island is a generated world")
	check_eq(WorldGen.rim(), "island")
	WorldGen.reset()
	check(not WorldGen.is_island(), "Ashgrove is not an island")


func _fingerprint() -> String:
	var bits := PackedStringArray()
	for s in Ruins.all():
		bits.append("%s@%.1f,%.1f#%d" % [s.kind, s.pos.x, s.pos.z, s.layout_seed])
	for q in WorldGen.landings():
		bits.append("L%.1f,%.1f" % [q.x, q.y])
	return ",".join(bits)


func test_same_seed_same_island_new_seed_new_island() -> void:
	WorldGen.configure(11, 3000.0, WorldGen.ISLAND)
	var a := _fingerprint()
	WorldGen.configure(12, 3000.0, WorldGen.ISLAND)
	var b := _fingerprint()
	WorldGen.configure(11, 3000.0, WorldGen.ISLAND)
	check_eq(_fingerprint(), a, "seed 11 twice gives the same island")
	check(a != b, "a new seed (a wipe) gives a new island")
	WorldGen.reset()


func test_the_layout_is_quick() -> void:
	WorldGen.configure(77, 4000.0, WorldGen.ISLAND)
	var t := Time.get_ticks_msec()
	WorldGen.ruin_sites()
	var ms := Time.get_ticks_msec() - t
	check(ms < 2000, "a 4 km island's layout takes %d ms" % ms)
	check(WorldGen.ruin_sites().size() > 30, "a large island has plenty of places (%d)" % WorldGen.ruin_sites().size())
	WorldGen.reset()


func test_islands_are_playable() -> void:
	for seed in SEEDS:
		WorldGen.configure(seed, 3000.0, WorldGen.ISLAND)
		var tag := "seed %d" % seed
		var wl := Terrain.water_level()
		var half := WorldGen.half_size()
		# Sea all round: the whole border is water.
		for k in 40:
			var t := -half + (k + 0.5) * WorldGen.size_m() / 40.0
			for q in [Vector2(t, -half + 2), Vector2(t, half - 2), Vector2(-half + 2, t), Vector2(half - 2, t)]:
				check(Terrain.height(q.x, q.y) < wl - 1.0, tag + ": sea at the border")
		# Landings: several, on dry beach near the sea, spread out, spawn is the first.
		var landings := WorldGen.landings()
		check(landings.size() >= 5, tag + ": at least 5 landings on a 3 km island (%d)" % landings.size())
		var sp := WorldGen.spawn_point()
		check(Vector2(sp.x, sp.z).distance_to(landings[0]) < 0.01, tag + ": spawn is the first landing")
		for q in landings:
			var h := Terrain.height(q.x, q.y)
			check(h > wl + 1.0 and h < 6.0, tag + ": a landing is dry, low ground (%.1f)" % h)
			var sea := false
			for k in 16:
				var p: Vector2 = q + Vector2.from_angle(TAU * k / 16.0) * 90.0
				if Terrain.height(p.x, p.y) < wl:
					sea = true
			check(sea, tag + ": a landing is by the water")
			for r in landings:
				if r != q:
					check(q.distance_to(r) >= 200.0, tag + ": landings are spread out")
		# A key spreads new characters over the beaches.
		var used := {}
		for key in 40:
			var p := WorldGen.landing_for(key)
			used["%.0f,%.0f" % [p.x, p.z]] = true
		check_eq(used.size(), landings.size(), tag + ": every landing gets used")
		_check_locations(tag)
		_check_nodes(tag, landings)
		check_eq(WorldGen.roads().size(), WorldGen.road_kinds().size(), tag + ": a kind per road")
		check(WorldGen.road_kinds().has("king") and WorldGen.road_kinds().has("track"), tag + ": king's roads and tracks")
		check(WorldGen.rivers().size() >= 2, tag + ": two or more rivers on a 3 km island")
	WorldGen.reset()


func _check_locations(tag: String) -> void:
	var all := Ruins.all()
	var kinds := {}
	var inland_by_grade := {1: [], 2: [], 3: [], 4: []}
	var L := WorldGen._L
	for s in all:
		kinds[s.kind] = kinds.get(s.kind, 0) + 1
		inland_by_grade[s.grade].append(IslandGen.inland(L, s.pos.x, s.pos.z))
		check(s.pos.y > Terrain.water_level() + 1.0, tag + ": %s is on dry land" % s.kind)
		check(Ruins.label(s.kind) != s.kind.capitalize() or Ruins.LABELS.has(s.kind), tag + ": %s has a label" % s.kind)
		var e: Dictionary = IslandGen.LOCATIONS.get(s.kind, {})
		if str(e.get("near", "")) == "river":
			check(WorldGen.river_distance(s.pos.x, s.pos.z) < s.radius + 46.0, tag + ": %s is by a river" % s.kind)
		# The pad is flat for the set piece.
		for k in 6:
			var q: Vector2 = Vector2(s.pos.x, s.pos.z) + Vector2.from_angle(TAU * k / 6.0) * float(s.radius) * 0.9
			check(absf(Terrain.height(q.x, q.y) - s.pos.y) < 0.6, tag + ": %s stands on a flat pad" % s.kind)
	for kind in IslandGen.LOCATIONS:
		var must := int(IslandGen.LOCATIONS[kind].must)
		check(kinds.get(kind, 0) >= must, tag + ": at least %d %s (%d)" % [must, kind, kinds.get(kind, 0)])
	check(kinds.get("wrecked_cart", 0) >= 1, tag + ": a wrecked cart on the road")
	# Danger rises inland.
	var mean := func(a: Array) -> float:
		var t := 0.0
		for v in a:
			t += v
		return t / maxf(1.0, a.size())
	check(mean.call(inland_by_grade[1]) < mean.call(inland_by_grade[2]), tag + ": grade 2 lies further inland than grade 1")
	check(mean.call(inland_by_grade[2]) < mean.call(inland_by_grade[3]), tag + ": grade 3 lies further inland than grade 2")
	# Every site rolls its own layout.
	var seeds := {}
	for s in all:
		seeds[s.layout_seed] = true
		check(s.rot >= 0.0 and s.rot < TAU, tag + ": a rotation")
	check_eq(seeds.size(), all.size(), tag + ": every site has its own layout seed")
	# Spaced out: no two pads overlap.
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a: Dictionary = all[i]
			var b: Dictionary = all[j]
			check(Vector2(a.pos.x, a.pos.z).distance_to(Vector2(b.pos.x, b.pos.z)) > a.radius + b.radius, tag + ": %s and %s don't overlap" % [a.kind, b.kind])


func _check_nodes(tag: String, landings: Array) -> void:
	var kinds := {}
	var near := {}
	for n in WorldGen.node_spots():
		kinds[n.kind] = kinds.get(n.kind, 0) + 1
		check(n.pos.y > Terrain.water_level() + 0.9, tag + ": nodes on dry land")
		if n.starter:
			for i in landings.size():
				if Vector2(n.pos.x, n.pos.z).distance_to(landings[i]) < 80.0:
					near[i] = near.get(i, 0) + 1
	for k in WorldGen.NODE_KINDS:
		check(kinds.get(k, 0) >= 20, tag + ": plenty of %s (%d)" % [k, kinds.get(k, 0)])
	for i in landings.size():
		check(near.get(i, 0) >= 4, tag + ": something to gather by landing %d (%d)" % [i, near.get(i, 0)])


## Every location can be walked to from the first landing (fords allowed, no deep sea).
func test_every_place_can_be_reached_on_foot() -> void:
	WorldGen.configure(4, 3000.0, WorldGen.ISLAND)
	var half := WorldGen.half_size()
	var step := 12.0
	var n := int(WorldGen.size_m() / step)
	var wl := Terrain.water_level()
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = Terrain.height(-half + (i + 0.5) * step, -half + (j + 0.5) * step)
	var cell := func(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x + half) / step), int((p.y + half) / step))
	var seen := {}
	var start: Vector2i = cell.call(WorldGen.landings()[0])
	var todo: Array = [start]
	seen[start] = true
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		var h := hs[c.y * n + c.x]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n or seen.has(q):
				continue
			var hq := hs[q.y * n + q.x]
			if hq < wl - 1.6 or absf(hq - h) > step * 0.9:
				continue
			seen[q] = true
			todo.append(q)
	for s in Ruins.all():
		check(seen.has(cell.call(Vector2(s.pos.x, s.pos.z))), "%s at (%.0f, %.0f) can be reached" % [s.kind, s.pos.x, s.pos.z])
	for q in WorldGen.landings():
		check(seen.has(cell.call(q)), "landing (%.0f, %.0f) can be reached" % [q.x, q.y])
	WorldGen.reset()


func test_ruins_list_carries_the_layout_roll() -> void:
	WorldGen.configure(9, 1500.0, WorldGen.ISLAND)
	var r: Dictionary = Ruins.all()[0]
	check(r.has("layout_seed") and r.has("rot"), "Ruins.all() hands set pieces their layout roll")
	check_eq(Ruins.label("old_meadow"), "The Old Meadow")
	check_eq(Ruins.label("barber_surgeon"), "Barber-Surgeon's House")
	WorldGen.configure(9, 1200.0, WorldGen.KINGDOM)
	check_eq(int(Ruins.all()[0].layout_seed), 0, "a version 1 kingdom's sites have no layout roll")
	WorldGen.reset()


func test_new_characters_wash_up_on_the_beaches() -> void:
	WorldGen.configure(21, 3000.0, WorldGen.ISLAND)
	var beaches := {}
	for name in ["fern", "moss", "ash", "rook", "wren", "tam", "hob", "kit", "bram", "sloe"]:
		var ch := CharacterData.new_for({"id": 1, "username": name, "username_lc": name})
		var on := -1
		for i in WorldGen.landings().size():
			if Vector2(ch.x, ch.z).distance_to(WorldGen.landings()[i]) < 1.0:
				on = i
		check(on >= 0, name + " washes up on a landing")
		beaches[on] = true
	check(beaches.size() >= 3, "ten newcomers spread over several beaches (%d)" % beaches.size())
	WorldGen.reset()
	var ch := CharacterData.new_for({"id": 1, "username": "fern", "username_lc": "fern"})
	check_eq(Vector3(ch.x, ch.y, ch.z), Terrain.clamp_to_world(GameConfig.SPAWN_POINT), "Ashgrove still starts at the meadow")

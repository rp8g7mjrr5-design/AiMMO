extends TestCase
## World stream: the island with biomes and hills (generator v3, owner 2026-11-28: "The map
## feels really flat ... We need to have different types of biomes ... forests and
## flatlands"). Pine hills, marsh, flat meadows and taller crags, on the same island plan as
## version 2; version 2 itself never changes; a wiping island moves to version 3 at its next
## wipe, never before. Every test puts the world back to Ashgrove (the config is global).

const SEEDS := [1126, 7, 42]


## Heights and biomes on a 40 x 40 grid over a 3 km island, folded into one line.
func _fingerprint() -> String:
	var sum := 0.0
	var bio := ""
	for j in 40:
		for i in 40:
			var x := -1500.0 + 37.0 * i + 11.0
			var z := -1500.0 + 37.0 * j + 7.0
			var h := Terrain.height(x, z)
			sum += h * (1 + (i * 40 + j) % 7)
			bio += WorldGen.biome_for(x, z, h).substr(0, 2)
	return "%.4f %d %d %d" % [sum, WorldGen.node_spots().size(), bio.hash(), WorldGen.ruin_sites().size()]


func test_version_two_islands_are_untouched() -> void:
	# The live world's island (AIMMO_WORLD=1126:2:3000), as it was before version 3 existed:
	# campfires and bedrolls on it must never float or sink.
	WorldGen.configure(1126, 3000.0, WorldGen.ISLAND)
	check_eq(_fingerprint(), "-6211.8614 4193 2636094575 34", "version 2 is bit-for-bit what it was")
	WorldGen.reset()


func test_version_three_parses_and_is_an_island() -> void:
	check_eq(WorldGen.parse("1126:3:3000"), {"seed": 1126, "size_m": 3000.0, "gen_version": WorldGen.ISLAND_HILLS})
	check_eq(WorldGen.LATEST, WorldGen.ISLAND_HILLS, "the newest generator")
	WorldGen.configure(5, 3000.0, WorldGen.ISLAND_HILLS)
	check(WorldGen.is_island() and WorldGen.is_kingdom(), "version 3 is an island")
	check_eq(WorldGen.rim(), "island")
	WorldGen.reset()


## Biome shares (percent of dry land) and height percentiles on a 120 x 120 grid.
func _survey() -> Dictionary:
	var counts := {}
	var hs: Array = []
	var half := WorldGen.half_size()
	var n := 120
	for j in n:
		for i in n:
			var x := -half + (i + 0.5) * WorldGen.size_m() / n
			var z := -half + (j + 0.5) * WorldGen.size_m() / n
			var h := Terrain.height(x, z)
			if h < 0.0:
				continue
			hs.append(h)
			var b := WorldGen.biome_for(x, z, h)
			counts[b] = int(counts.get(b, 0)) + 1
	hs.sort()
	var shares := {}
	for b in counts:
		shares[b] = 100.0 * counts[b] / hs.size()
	return {"shares": shares, "p50": hs[int(hs.size() * 0.5)], "p90": hs[int(hs.size() * 0.9)]}


func test_every_biome_shows_up_and_the_land_has_real_hills() -> void:
	for s in SEEDS:
		WorldGen.configure(s, 3000.0, WorldGen.ISLAND)
		var flat := _survey()
		WorldGen.configure(s, 3000.0, WorldGen.ISLAND_HILLS)
		var hilly := _survey()
		var sh: Dictionary = hilly.shares
		for b in ["farmland", "forest", "moor", "pine_hills", "marsh", "stone_hills", "shore"]:
			check(float(sh.get(b, 0.0)) > 2.0, "seed %d: %s is a real part of the island (%.1f%%)" % [s, b, float(sh.get(b, 0.0))])
		check(float(sh.get("pine_hills", 0.0)) > 8.0, "seed %d: pine hills cover a good share (%.1f%%)" % [s, float(sh.get("pine_hills", 0.0))])
		check(float(sh.get("farmland", 0.0)) > 15.0, "seed %d: the flatlands are still wide (%.1f%%)" % [s, float(sh.get("farmland", 0.0))])
		check(float(hilly.p90) > float(flat.p90) + 5.0, "seed %d: the high ground is higher (p90 %.1f m, was %.1f m)" % [s, hilly.p90, flat.p90])
	WorldGen.reset()


func test_pine_hills_rise_and_marshes_lie_low_with_pools() -> void:
	WorldGen.configure(1126, 3000.0, WorldGen.ISLAND_HILLS)
	var hill_h: Array = []
	var marsh_h: Array = []
	var pools := 0
	var half := WorldGen.half_size()
	for j in 150:
		for i in 150:
			var x := -half + (i + 0.5) * 20.0
			var z := -half + (j + 0.5) * 20.0
			var h := Terrain.height(x, z)
			var b := WorldGen.biome_for(x, z, h)
			if b == "pine_hills":
				hill_h.append(h)
			elif b == "marsh":
				marsh_h.append(h)
			elif b == "water" and WorldGen.inland(x, z) > 0.1 and WorldGen.river_distance(x, z) > 40.0:
				var lake := false
				for l in WorldGen.lakes():
					if Vector2(x, z).distance_to(l.center) < float(l.radius) * 1.3 + 10.0:
						lake = true
				if not lake:
					pools += 1
	hill_h.sort()
	marsh_h.sort()
	check(hill_h[int(hill_h.size() * 0.9)] > 25.0, "pine hills top out well above the lowland (p90 %.1f m)" % hill_h[int(hill_h.size() * 0.9)])
	check(marsh_h[int(marsh_h.size() * 0.9)] < 3.0, "a marsh lies low and flat (p90 %.1f m)" % marsh_h[int(marsh_h.size() * 0.9)])
	check(pools > 20, "marshes hold pools of open water (%d samples)" % pools)
	WorldGen.reset()


func test_snow_only_on_the_heart() -> void:
	WorldGen.configure(7, 3000.0, WorldGen.ISLAND_HILLS)
	WorldGen.ruin_sites() # builds the layout
	var heart: Vector2 = WorldGen._L.heart
	var reach: float = WorldGen._L.radius * IslandGen.HEART_REACH
	var half := WorldGen.half_size()
	for j in 100:
		for i in 100:
			var x := -half + (i + 0.5) * 30.0
			var z := -half + (j + 0.5) * 30.0
			if WorldGen.biome_at(x, z) == "snow" and Vector2(x, z).distance_to(heart) > reach:
				check(false, "snow at (%.0f, %.0f), away from the heart's peaks" % [x, z])
				WorldGen.reset()
				return
	check(true, "no snow on the pine hills")
	WorldGen.reset()


func test_every_island_still_has_its_must_haves_landings_and_nodes() -> void:
	for s in [1126, 7, 42, 3, 99]:
		WorldGen.configure(s, 3000.0, WorldGen.ISLAND_HILLS)
		var kinds := {}
		for site in WorldGen.ruin_sites():
			kinds[site.kind] = true
		for kind in IslandGen.LOCATIONS:
			if int(IslandGen.LOCATIONS[kind].must) > 0:
				check(kinds.has(kind), "seed %d: has a %s" % [s, kind])
		check(WorldGen.landings().size() >= 4, "seed %d: at least 4 beach landings (%d)" % [s, WorldGen.landings().size()])
		var by := {}
		for n in WorldGen.node_spots():
			by[n.kind] = int(by.get(n.kind, 0)) + 1
		for k in WorldGen.NODE_KINDS:
			check(int(by.get(k, 0)) > 40, "seed %d: plenty of %s to gather (%d)" % [s, k, int(by.get(k, 0))])
	WorldGen.reset()


func test_the_new_biomes_have_trees_grass_and_colour() -> void:
	WorldGen.configure(1126, 3000.0, WorldGen.ISLAND_HILLS)
	var snags := 0
	var hill_pines := 0
	for it in Props.scatter():
		var b := WorldGen.biome_at(it.pos.x, it.pos.z)
		if it.kind == "snag":
			snags += 1
			check_eq(b, "marsh", "a dead tree stands in the marsh")
		elif it.kind == "pine" and b == "pine_hills":
			hill_pines += 1
	check(snags > 20, "the marsh has its drowned trees (%d)" % snags)
	check(hill_pines > 200, "the pine hills are wooded (%d)" % hill_pines)
	var parts: Array = WorldBuilder.scatter_parts([{"kind": "snag", "pos": Vector3.ZERO, "rot": 0.3, "scale": 1.0}])
	check_eq(parts[0].size(), 2, "a snag is a bare trunk and one broken limb")
	for b in ["pine_hills", "marsh"]:
		check(float(Grass.BIOME_DENSITY.get(b, 0.0)) > 0.0, "%s grows grass" % b)
		check(Props.KINGDOM_KEEP.has(b), "%s grows scatter trees" % b)
		check(WorldGen.BIOME_NODES.has(b) and WorldGen.BIOME_DENSITY.has(b), "%s grows resource nodes" % b)
	WorldGen.reset()


func _store() -> JsonStore:
	var st := JsonStore.new()
	st.path = "user://test_hills_%d/players.json" % Time.get_ticks_usec()
	st.open()
	return st


func test_a_live_island_moves_to_the_hills_at_its_wipe_not_before() -> void:
	var st := _store()
	var cfg := {"seed": 1126, "size_m": 3000.0, "gen_version": WorldGen.ISLAND}
	var first := WorldWipe.choose(st, cfg, 1000, 5)
	check_eq(int(first.gen_version), WorldGen.ISLAND, "the first world is what the server was told")
	# A server now configured for version 3 keeps running the version 2 world until its wipe.
	var cfg3 := {"seed": 1126, "size_m": 3000.0, "gen_version": WorldGen.ISLAND_HILLS}
	check_eq(int(WorldWipe.choose(st, cfg3, 2000, 5).id), int(first.id), "no wipe mid-month for a new generator")
	check_eq(int(WorldWipe.choose(st, cfg, 2000, 5).id), int(first.id), "and none on a plain restart")
	# The scheduled wipe rolls the next island on the newest generator.
	var next := WorldWipe.roll(st, cfg, int(first.wipes_at), false, 9)
	check_eq(int(next.gen_version), WorldGen.LATEST, "the wipe brings the hills")
	check(int(next.seed) != 1126, "on a new seed")
	check_eq(int(WorldWipe.choose(st, cfg, int(first.wipes_at) + 10, 5).id), int(next.id), "a restart after the wipe keeps the new island")
	check(WorldWipe.same_kind(2, 3) and not WorldWipe.same_kind(0, 2) and not WorldWipe.same_kind(1, 2), "only islands move between versions")

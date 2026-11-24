extends TestCase
## World stream: the world config and the kingdom generator v1 (Phase 1, "A kingdom from a
## seed"; docs/vision.md, "The map"). gen_version 0 is today's Ashgrove, bit for bit;
## gen_version 1 is a generated stretch of the fallen kingdom with water, every node kind,
## the king's roads and ruins of every grade, the higher grades further from spawn.
## Every test puts the world back to Ashgrove, because the config is global.

const SEEDS := [1, 2, 3, 4, 5]


## Today's Ashgrove height, copied from terrain.gd before WorldGen existed. Never edit.
static var _n: FastNoiseLite
static var _r: FastNoiseLite


func _legacy_height(x: float, z: float) -> float:
	if _n == null:
		_n = FastNoiseLite.new()
		_n.seed = GameConfig.WORLD_SEED
		_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_n.frequency = 0.006
		_n.fractal_type = FastNoiseLite.FRACTAL_FBM
		_n.fractal_octaves = 4
		_r = FastNoiseLite.new()
		_r.seed = GameConfig.WORLD_SEED + 1
		_r.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_r.frequency = 0.0025
	var base := _n.get_noise_2d(x, z) * 9.0
	var r := 1.0 - absf(_r.get_noise_2d(x, z))
	var ridge := r * r * r * 18.0
	var d := Vector2(x, z).length()
	var calm := clampf((d - 20.0) / 60.0, 0.0, 1.0)
	return (base + ridge - 4.0) * calm + 0.5 * (1.0 - calm)


func _ashgrove_matches(label: String) -> void:
	var bad := 0
	for gz in range(-20, 21):
		for gx in range(-20, 21):
			var x := gx * 13.7
			var z := gz * 13.1
			if Terrain.height(x, z) != _legacy_height(x, z):
				bad += 1
	check_eq(bad, 0, "%s: Ashgrove heights differ from the legacy field at %d points" % [label, bad])
	check_eq(Terrain.water_level(), -2.5, label + ": water level")
	check_eq(WorldGen.half_size(), GameConfig.WORLD_HALF_SIZE, label + ": half size")
	check_eq(Terrain.clamp_to_world(Vector3(900, 0, -900)), Vector3(256, Terrain.height(256, -256), -256), label + ": clamp")
	check_eq(WorldGen.spawn_point(), GameConfig.SPAWN_POINT, label + ": spawn")
	check(WorldGen.ruin_sites().is_empty() and WorldGen.node_spots().is_empty(), label + ": no generated placement")


func test_ashgrove_is_the_default_and_bit_identical() -> void:
	WorldGen.reset()
	check_eq(WorldGen.config(), {"seed": GameConfig.WORLD_SEED, "size_m": 512.0, "gen_version": 0}, "default config")
	_ashgrove_matches("default")
	# Visiting a kingdom and coming back leaves Ashgrove untouched.
	WorldGen.configure(3, 1200, 1)
	check(Terrain.height(100, 100) != _legacy_height(100, 100), "a kingdom is a different land")
	WorldGen.configure(999, 1500, 0) # gen 0 ignores seed and size
	_ashgrove_matches("after a kingdom")
	WorldGen.reset()


func test_config_parse_and_apply() -> void:
	check_eq(WorldGen.parse(""), {"seed": GameConfig.WORLD_SEED, "size_m": 512.0, "gen_version": 0}, "empty is Ashgrove")
	check_eq(WorldGen.parse("junk"), WorldGen.parse(""), "junk is Ashgrove")
	check_eq(WorldGen.parse("42:1"), {"seed": 42, "size_m": 1200.0, "gen_version": 1}, "default size")
	check_eq(WorldGen.parse("42:1:1500"), {"seed": 42, "size_m": 1500.0, "gen_version": 1}, "explicit size")
	check_eq(WorldGen.parse("42:1:small"), {"seed": 42, "size_m": 1000.0, "gen_version": 1}, "named size")
	check_eq(WorldGen.parse("42:1:99999").size_m, WorldGen.KINGDOM_SIZE_MAX, "size clamped")
	check_eq(WorldGen.parse("42:7").gen_version, WorldGen.LATEST, "future version clamps to the latest")
	check_eq(WorldGen.parse("42:0:900").size_m, 512.0, "version 0 is always 512 m")
	WorldGen.apply({"seed": 9, "size_m": 1000.0, "gen_version": 1})
	check_eq(WorldGen.config(), {"seed": 9, "size_m": 1000.0, "gen_version": 1}, "apply")
	check_eq(WorldGen.half_size(), 500.0, "half size follows the config")
	WorldGen.apply({})
	check_eq(WorldGen.gen_version(), 0, "an empty config is Ashgrove")
	WorldGen.reset()


func _fingerprint() -> String:
	var hs := PackedFloat32Array()
	for gz in range(-12, 13):
		for gx in range(-12, 13):
			hs.append(Terrain.height(gx * 47.0, gz * 47.0))
	var p := WorldGen.placement()
	return var_to_str(hs) + var_to_str(p.ruins) + var_to_str(p.roads) + var_to_str(p.nodes) + var_to_str(p.spawn)


func test_same_seed_same_world() -> void:
	WorldGen.configure(7, 1200, 1)
	var a := _fingerprint()
	WorldGen.configure(8, 1200, 1)
	var b := _fingerprint()
	WorldGen.configure(7, 1200, 1)
	check(a == _fingerprint(), "seed 7 twice gives the same world")
	check(a != b, "seeds 7 and 8 give different worlds")
	WorldGen.reset()


## Flood fill on an 8 m grid from spawn over ground a player can walk or wade.
func _reachable(sp: Vector3) -> Dictionary:
	var half := WorldGen.half_size()
	var step := 8.0
	var n := int(WorldGen.size_m() / step)
	var wl := Terrain.water_level()
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			hs[j * n + i] = Terrain.height(-half + (i + 0.5) * step, -half + (j + 0.5) * step)
	var seen := {}
	var start := Vector2i(int((sp.x + half) / step), int((sp.z + half) / step))
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
			if hq < wl - 1.2 or absf(hq - h) > step * 0.75:
				continue # deep water or a cliff
			seen[q] = true
			todo.append(q)
	return {"seen": seen, "step": step, "half": half}


func _is_reached(r: Dictionary, p: Vector3) -> bool:
	return r.seen.has(Vector2i(int((p.x + r.half) / r.step), int((p.z + r.half) / r.step)))


func test_five_seeds_are_playable_kingdoms() -> void:
	for seed in SEEDS:
		WorldGen.configure(seed, 1200, 1)
		var tag := "seed %d" % seed
		var wl := Terrain.water_level()
		var sp := WorldGen.spawn_point()
		# A calm, dry, flat spawn plot.
		check(sp.y > wl + 1.0, tag + ": spawn is dry (%.1f)" % sp.y)
		for k in 8:
			var q := Vector2(sp.x, sp.z) + Vector2.from_angle(TAU * k / 8.0) * 18.0
			check(absf(Terrain.height(q.x, q.y) - sp.y) < 0.3, tag + ": spawn plot is flat")
		# Water: a coast or lakes, and a river.
		var wet := 0
		for gz in 40:
			for gx in 40:
				if Terrain.height(-570 + gx * 29.0, -570 + gz * 29.0) < wl:
					wet += 1
		check(wet >= 8, tag + ": has water (%d of 1600 samples)" % wet)
		check(WorldGen.rivers().size() == 1 and WorldGen.rivers()[0].size() > 4, tag + ": a river")
		check(Terrain.height(WorldGen.rivers()[0][3].x, WorldGen.rivers()[0][3].y) < wl, tag + ": the river holds water")
		# Every node kind, a starter ring near spawn.
		var kinds := {}
		var starters := 0
		for n in WorldGen.node_spots():
			kinds[n.kind] = kinds.get(n.kind, 0) + 1
			if n.starter:
				starters += 1
				check(Vector2(n.pos.x, n.pos.z).distance_to(Vector2(sp.x, sp.z)) <= WorldGen.STARTER_MAX + 0.5, tag + ": starter ring near spawn")
		for k in WorldGen.NODE_KINDS:
			check(kinds.get(k, 0) >= 10, tag + ": plenty of %s (%d)" % [k, kinds.get(k, 0)])
		check_eq(starters, WorldGen.STARTER_KINDS.size(), tag + ": the whole starter ring")
		# Ruins: every grade, the first two set pieces, higher grades further out.
		var by_grade := {1: [], 2: [], 3: [], 4: []}
		var kinds_seen := {}
		for s in WorldGen.ruin_sites():
			by_grade[int(s.grade)].append(Vector2(s.pos.x, s.pos.z).distance_to(Vector2(sp.x, sp.z)))
			kinds_seen[s.kind] = true
		for g in [1, 2, 3, 4]:
			check(not by_grade[g].is_empty(), tag + ": a grade %d ruin" % g)
		for k in WorldGen.RUIN_MUST_HAVE:
			check(kinds_seen.has(k), tag + ": has a " + k)
		var mean := func(a: Array) -> float:
			var t := 0.0
			for v in a:
				t += v
			return t / maxf(a.size(), 1)
		check(mean.call(by_grade[1]) < mean.call(by_grade[2]), tag + ": grade 2 further out than grade 1")
		check(mean.call(by_grade[2]) < mean.call(by_grade[3]), tag + ": grade 3 further out than grade 2")
		check(mean.call(by_grade[4]) > mean.call(by_grade[2]), tag + ": the castle lies far from spawn")
		# Roads reach every ruin, and you can walk to every ruin and every node kind.
		check(WorldGen.roads().size() >= WorldGen.ruin_sites().size(), tag + ": a road per ruin")
		var ends := []
		for line in WorldGen.roads():
			ends.append(line[0])
			ends.append(line[line.size() - 1])
		for s in WorldGen.ruin_sites():
			var linked := false
			for e in ends:
				if (e as Vector2).distance_to(Vector2(s.pos.x, s.pos.z)) < 1.0:
					linked = true
			check(linked, tag + ": a road reaches the " + s.kind)
		var reach := _reachable(sp)
		for s in WorldGen.ruin_sites():
			check(_is_reached(reach, s.pos), tag + ": can walk from spawn to the " + s.kind)
		var walk_kinds := {}
		for n in WorldGen.node_spots():
			if _is_reached(reach, n.pos):
				walk_kinds[n.kind] = true
		check_eq(walk_kinds.size(), WorldGen.NODE_KINDS.size(), tag + ": every node kind reachable on foot")
	WorldGen.reset()


func test_spots_and_pads_keep_clear() -> void:
	WorldGen.configure(4, 1200, 1)
	var wl := Terrain.water_level()
	var spots := WorldGen.node_spots()
	var grid := {}
	for n in spots:
		var p := Vector2(n.pos.x, n.pos.z)
		check(n.pos.y > wl + 0.9, "spot on dry land")
		check_near(n.pos.y, Terrain.height(p.x, p.y), 0.001, "spot sits on the ground")
		if not n.starter:
			check(WorldGen.road_distance(p.x, p.y) >= WorldGen.ROAD_HALF_WIDTH + 2.0, "spot off the road")
		for s in WorldGen.ruin_sites():
			check(p.distance_to(Vector2(s.pos.x, s.pos.z)) >= s.radius, "spot off the %s pad" % s.kind)
		var c := Vector2i(int(floor(p.x / 6.0)), int(floor(p.y / 6.0)))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for q in grid.get(c + Vector2i(dx, dz), []):
					check(p.distance_to(q) >= WorldGen.NODE_SPACING - 0.001, "spots at least 6 m apart")
		if not grid.has(c):
			grid[c] = []
		grid[c].append(p)
	# Ruin pads are flat, so a set piece stands on level ground.
	for s in WorldGen.ruin_sites():
		for k in 6:
			var q: Vector2 = Vector2(s.pos.x, s.pos.z) + Vector2.from_angle(TAU * k / 6.0) * s.radius * 0.9
			check(absf(Terrain.height(q.x, q.y) - s.pos.y) < 0.5, "the %s pad is flat" % s.kind)
	WorldGen.reset()


func test_sizes_scale_the_kingdom() -> void:
	WorldGen.configure(2, 1000, 1)
	var small := WorldGen.ruin_sites().size()
	var small_nodes := WorldGen.node_spots().size()
	WorldGen.configure(2, 1500, 1)
	check(WorldGen.ruin_sites().size() > small, "a large world has more ruins")
	check(WorldGen.node_spots().size() > small_nodes, "and more nodes")
	var sp := WorldGen.spawn_point()
	check(absf(sp.x) < 750.0 and absf(sp.z) < 750.0, "spawn inside the world")
	WorldGen.reset()


func test_layout_is_quick() -> void:
	var t := Time.get_ticks_msec()
	WorldGen.configure(5, 1500, 1)
	WorldGen.spawn_point()
	WorldGen.node_spots()
	var ms := Time.get_ticks_msec() - t
	check(ms < 2500, "layout and node spots in under 2.5 s (%d ms)" % ms)
	WorldGen.reset()


func test_map_paints_the_kingdom() -> void:
	WorldGen.configure(1, 1200, 1)
	var img := WorldMap.paint(96)
	check_eq(img.get_width(), 96, "map size")
	var water := 0
	var grades := {}
	for j in 96:
		for i in 96:
			var c := img.get_pixel(i, j)
			if c.b > c.r:
				water += 1
			for g in 4:
				var want: Color = Palette.MAP_GRADE[g]
				if absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b) < 0.02: # RGB8 rounding
					grades[g] = true
	check(water > 0, "water on the map")
	check_eq(grades.size(), 4, "a mark for every ruin grade")
	WorldGen.reset()
	check_eq(WorldMap.paint(32).get_width(), 32, "Ashgrove paints too")

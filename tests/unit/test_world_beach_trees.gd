extends TestCase
## The island's beaches look like beaches (owner, 2026-11-27: "Trees shouldn't be on the beach.
## Palm trees maybe"). No forest tree, birch, boulder, flower patch or choppable tree stands on
## the sand; palms grow there instead, in clumps, on dry sand, clear of the landings and their
## landmarks; the grass meets the sand in a soft fringe. Ashgrove is untouched.
## Every test puts the world back to Ashgrove, because the config is global.

const SEED := 1126 ## the live world's seed (AIMMO_WORLD=1126:2:3000)


func _island() -> void:
	WorldGen.configure(SEED, 3000.0, WorldGen.ISLAND)
	ResourceNodes.reset()


func _done() -> void:
	WorldGen.reset()
	ResourceNodes.reset()


## Sand within 2 m of a point (tighter than WorldGen.SAND_CLEAR, so it only catches real misses).
func _on_sand(p: Vector3) -> bool:
	return WorldGen.near_sand(p.x, p.z, 2.0)


func test_no_trees_on_the_sand() -> void:
	_island()
	var bad := {}
	for it in Props.scatter():
		if _on_sand(it.pos):
			bad["scatter " + str(it.kind)] = bad.get("scatter " + str(it.kind), 0) + 1
	for s in Flora.spots():
		if s.kind != "palm" and _on_sand(s.pos):
			bad[str(s.kind)] = bad.get(str(s.kind), 0) + 1
	for n in ResourceNodes.all():
		if (n.kind == "ash" or n.kind == "pine") and _on_sand(n.pos):
			bad["node " + str(n.kind)] = bad.get("node " + str(n.kind), 0) + 1
	check(bad.is_empty(), "nothing but palms grows on the beach (%s)" % str(bad))
	_done()


func test_moved_tree_nodes_keep_their_ids_and_stay_near_their_landing() -> void:
	_island()
	var spots := WorldGen.node_spots()
	var nodes := ResourceNodes.all()
	for i in spots.size():
		check_eq(str(nodes[i].kind), str(spots[i].kind), "node %d keeps its kind" % i)
		check_eq(int(nodes[i].id), i, "node %d keeps its id" % i)
	var lands := WorldGen.landings()
	var far := 0
	for s in spots:
		if not s.starter:
			continue
		var p := Vector2(s.pos.x, s.pos.z)
		var near := INF
		for l in lands:
			near = minf(near, p.distance_to(l))
		if near > WorldGen.STARTER_MAX + 40.0 + WorldGen.OFF_SAND_STEP * WorldGen.OFF_SAND_REACH:
			far += 1
		check_near(s.pos.y, WorldGen.height(p.x, p.y), 0.01, "a moved node stands on the ground")
	check_eq(far, 0, "every starter tree is still a short walk from its landing")
	_done()


func test_palms_grow_on_the_beaches() -> void:
	_island()
	var palms := Flora.spots().filter(func(s): return s.kind == "palm")
	check(palms.size() >= 40, "palm groves along the coast (%d)" % palms.size())
	var wl := Terrain.water_level()
	var lands := WorldGen.landings()
	for p in palms:
		var pos: Vector3 = p.pos
		check_eq(WorldGen.biome_at(pos.x, pos.z), "shore", "a palm stands on the beach")
		check(pos.y > wl + 0.7, "a palm stands above the wet band (%.2f)" % pos.y)
		for l in lands:
			check(Vector2(pos.x, pos.z).distance_to(l) >= BeachGen.CLEAR, "a palm keeps off a landing's lantern ring")
	# Clumps, not a hedge: plenty of the coast has none.
	var bare := 0
	for i in 72:
		var c := WorldGen.coast_at(TAU * i / 72.0)
		if c.is_empty():
			continue
		var any := false
		for p in palms:
			any = any or Vector2(p.pos.x, p.pos.z).distance_to(c.pos) < 40.0
		bare += 0 if any else 1
	check(bare >= 18, "long stretches of open sand between the groves (%d of 72)" % bare)
	_done()


func test_palm_parts_look_right() -> void:
	_island()
	var palm: Dictionary = Flora.spots().filter(func(s): return s.kind == "palm")[0]
	var parts := Flora.parts(palm)
	var layers := parts.map(func(p): return p.layer)
	check_eq(layers.count("PalmTrunks"), Flora.PALM_SEGMENTS, "a trunk in pieces")
	check_eq(layers.count("PalmRings"), Flora.PALM_SEGMENTS, "a leaf-scar ring at every joint")
	check_eq(layers.count("PalmFronds"), Flora.PALM_FRONDS, "a full crown")
	check_eq(layers.count("PalmNuts"), 3, "a nut cluster")
	var top := -INF
	for p in parts:
		check(p.xform.origin.y > palm.pos.y - 0.3, "no part sinks into the sand")
		top = maxf(top, p.xform.origin.y)
	check(top > palm.pos.y + 4.5 and top < palm.pos.y + 9.0, "a palm is a tall tree (%.1f m)" % (top - palm.pos.y))
	var lay := Flora.layout(Flora.spots())
	check_eq(lay.PalmFronds.size(), Flora.count("palm") * Flora.PALM_FRONDS, "layout has every frond")
	_done()


func test_grass_meets_the_sand_in_a_fringe() -> void:
	_island()
	var c: Dictionary = WorldGen.coast_at(0.7)
	var sea: Vector2 = c.sea
	var p: Vector2 = c.pos
	var last := -1.0
	var rose := false
	for step in 80:
		var q := p - sea * float(step) * 2.0
		var h := WorldGen.height(q.x, q.y)
		var m := WorldGen.sand_margin(q.x, q.y, h)
		if WorldGen.biome_for(q.x, q.y, h) == "shore":
			check_eq(m, 0.0, "on the sand the margin is nothing")
		if m > 0.0 and m < 1.0:
			rose = true
		last = m
	check(rose, "there is a soft band between the sand and the grass")
	check_eq(last, 1.0, "well inland the fringe is gone")
	_done()


func test_ashgrove_is_untouched() -> void:
	WorldGen.reset()
	ResourceNodes.reset()
	check(not WorldGen.near_sand(GameConfig.SPAWN_POINT.x, GameConfig.SPAWN_POINT.z, 500.0), "Ashgrove's hand-tuned shores keep their trees")
	check_eq(Flora.count("palm"), 0, "no palms in Ashgrove")
	check_eq(WorldGen.sand_margin(0.0, 0.0, 0.0), 1.0, "no dune fringe off an island")
	check(WorldGen.coast_at(0.0).is_empty(), "no sea coast in Ashgrove")

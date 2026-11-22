extends TestCase
## World stream: biome variety. Birches on lake shores, mossy boulders in the pine forests,
## wildflower patches in the grasslands; all deterministic and clear of nodes, spawn and trees.
## Uses the pure halves of Flora (no renderer).


func test_every_kind_grows() -> void:
	check(Flora.count("birch") >= Flora.BIRCHES * 0.6, "birch groves on the shores (%d)" % Flora.count("birch"))
	check(Flora.count("boulder") >= Flora.BOULDERS * 0.6, "mossy boulders in the forest (%d)" % Flora.count("boulder"))
	check(Flora.count("flowers") >= Flora.FLOWER_PATCHES * 0.6, "wildflower patches (%d)" % Flora.count("flowers"))


func test_each_kind_in_its_biome() -> void:
	var wl := Terrain.water_level()
	for s in Flora.spots():
		var p: Vector3 = s.pos
		check_near(p.y, Terrain.height(p.x, p.z), 0.01, "%s stands on the ground" % s.kind)
		match s.kind:
			"birch":
				check(p.y > wl + 0.5 and p.y < wl + 5.1, "birch is just above the water line (%.1f)" % p.y)
				var wet := false
				for i in 8:
					var a := TAU * i / 8.0
					wet = wet or Terrain.height(p.x + cos(a) * Flora.SHORE_PROBE, p.z + sin(a) * Flora.SHORE_PROBE) < wl
				check(wet, "birch has a lake within %.0f m" % Flora.SHORE_PROBE)
			"boulder":
				check(p.y > Flora.FOREST_MIN and p.y < Flora.FOREST_MAX, "mossy boulder is in the pine band (%.1f)" % p.y)
			"flowers":
				check(p.y > wl + 1.5 and p.y < Flora.FOREST_MIN, "flowers grow in the grassland (%.1f)" % p.y)


func test_flora_keeps_clear() -> void:
	var trees: Array = Props.scatter()
	var spawn := Vector2(GameConfig.SPAWN_POINT.x, GameConfig.SPAWN_POINT.z)
	var bad_tree := 0
	for s in Flora.spots():
		var p: Vector3 = s.pos
		check(Vector2(p.x, p.z).distance_to(spawn) >= Flora.SPAWN_CLEAR, "spawn meadow stays open")
		check(ResourceNodes.near(p, Flora.NODE_CLEARANCE).is_empty(), "flora is not on a resource node")
		for l in Lamps.positions():
			check(Vector2(p.x, p.z).distance_to(Vector2(l.pos.x, l.pos.z)) > 1.5, "flora is not on a lantern")
	# Spot-check the tree clearance on a sample (a full n*m check is slow headless).
	for s in Flora.spots().slice(0, 60):
		for t in trees:
			if Vector2(s.pos.x, s.pos.z).distance_to(Vector2(t.pos.x, t.pos.z)) < Flora.TREE_CLEARANCE - 0.01:
				bad_tree += 1
	check_eq(bad_tree, 0, "flora doesn't grow into decorative trees")


func test_flora_is_deterministic() -> void:
	var a := Flora.generate()
	var b := Flora.spots()
	check_eq(a.size(), b.size(), "same number of spots")
	for i in range(0, a.size(), 17):
		check(a[i].kind == b[i].kind and a[i].pos.is_equal_approx(b[i].pos), "spot %d same every time" % i)


func test_forest_is_unchanged() -> void:
	# Flora must not shift the existing decoration: Props.scatter still gives its 1800 trees and rocks.
	check_eq(Props.scatter().size(), 1800, "decorative scatter keeps its size")


func test_parts_look_right() -> void:
	var by_kind := {}
	for s in Flora.spots():
		if not by_kind.has(s.kind):
			by_kind[s.kind] = s
	var birch := Flora.parts(by_kind.birch)
	var layers := birch.map(func(p): return p.layer)
	check_eq(layers.count("BirchBark"), 1, "one white trunk")
	check_eq(layers.count("BirchMarks"), 3, "three dark bark marks")
	check(layers.count("BirchCrowns") >= 1, "a crown")
	for p in birch:
		check(p.xform.origin.y > by_kind.birch.pos.y - 0.2 and p.xform.origin.y < by_kind.birch.pos.y + 8.0, "birch part between ground and crown top")
	var boulder := Flora.parts(by_kind.boulder).map(func(p): return p.layer)
	check(boulder.count("MossRocks") >= 1 and boulder.count("Moss") == boulder.count("MossRocks"), "every boulder wears moss")
	var flowers := Flora.parts(by_kind.flowers)
	check_eq(flowers.filter(func(p): return p.layer == "FlowerBlooms").size(), Flora.FLOWERS_PER_PATCH, "a full patch of blooms")
	for p in flowers:
		var o: Vector3 = p.xform.origin
		check(Vector2(o.x - by_kind.flowers.pos.x, o.z - by_kind.flowers.pos.z).length() < 1.8, "flower stays in its patch")
		var gy := Terrain.height(o.x, o.z)
		check(o.y > gy - 0.05 and o.y < gy + 0.6, "flower stands on the ground, not floating")
	var lay := Flora.layout(Flora.spots())
	check_eq(lay.size(), Flora.LAYERS.size(), "a layer for every mesh")
	check_eq(lay.FlowerBlooms.size(), Flora.count("flowers") * Flora.FLOWERS_PER_PATCH, "layout has every bloom")

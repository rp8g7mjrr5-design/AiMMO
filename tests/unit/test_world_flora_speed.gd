extends TestCase
## World stream, basics 3 (fast to load): Flora's scatter runs its cheap looks first (the
## ground's height and biome before the roads, the ruins and the beach ring), so an island's
## flora grows in under half the time. The order must never change what grows: this test
## holds Flora.generate() to a copy of the old scatter, spot for spot, on Ashgrove, a kingdom
## and an island, and Props.on_pad to Props._on_ruin.


func test_same_flora_as_the_old_order_on_ashgrove() -> void:
	WorldGen.reset()
	_check_same("Ashgrove")


func test_same_flora_as_the_old_order_on_a_kingdom() -> void:
	WorldGen.configure(77, 800.0, WorldGen.KINGDOM)
	_check_same("kingdom 77")
	WorldGen.reset()


func test_same_flora_as_the_old_order_on_an_island() -> void:
	WorldGen.configure(5, 1500.0, WorldGen.ISLAND)
	_check_same("island 5")
	WorldGen.reset()


func test_on_pad_answers_like_on_ruin() -> void:
	WorldGen.configure(5, 1500.0, WorldGen.ISLAND)
	var ruins := WorldGen.ruin_sites()
	check(not ruins.is_empty(), "the island has ruins to test against")
	var pads := Props.ruin_pads(ruins)
	check_eq(pads.size(), ruins.size() * 3, "three numbers per ruin")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var h := WorldGen.half_size()
	var hits := 0
	var bad := 0
	for i in 4000:
		# half the probes near a ruin, so both answers get asked
		var x := rng.randf_range(-h, h)
		var z := rng.randf_range(-h, h)
		if i % 2 == 0:
			var r: Dictionary = ruins[rng.randi_range(0, ruins.size() - 1)]
			x = r.pos.x + rng.randf_range(-40.0, 40.0)
			z = r.pos.z + rng.randf_range(-40.0, 40.0)
		var old := Props._on_ruin(x, z, ruins)
		if old:
			hits += 1
		if Props.on_pad(x, z, pads) != old:
			bad += 1
	check_eq(bad, 0, "on_pad and _on_ruin agree everywhere")
	check(hits > 100, "plenty of probes land on a pad (%d)" % hits)
	check(not Props.on_pad(0.0, 0.0, PackedFloat64Array()), "no ruins, no pad")
	WorldGen.reset()


func _check_same(what: String) -> void:
	var now := Flora.generate()
	var old := _old_generate()
	check_eq(now.size(), old.size(), "%s: as many flora spots as the old order" % what)
	var differ := 0
	for i in mini(now.size(), old.size()):
		if str(now[i]) != str(old[i]):
			differ += 1
	check_eq(differ, 0, "%s: every spot where the old order put it" % what)
	check(now.size() > 50, "%s: flora grows (%d)" % [what, now.size()])


# ---------------------------------------------------------------------------------------
# The old scatter, frozen (Flora before the reorder). Only the order of its tests moved.

func _old_generate() -> Array:
	var blockers := Flora._Grid.new(Flora.TREE_CLEARANCE)
	for it in Props.scatter():
		blockers.add(it.pos)
	var out: Array = []
	var k := WorldGen.is_kingdom()
	var n := Flora.scale_for_world()
	_old_scatter(out, "birch", int(Flora.BIRCHES * sqrt(n)), Flora.SEED_OFFSET, blockers, Flora._is_shore)
	_old_scatter(out, "boulder", int(Flora.BOULDERS * n), Flora.SEED_OFFSET + 1, blockers, _old_forest_floor if k else Flora._is_forest_floor)
	var mask := FastNoiseLite.new()
	mask.seed = Flora._world_seed() + Flora.SEED_OFFSET + 3
	mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mask.frequency = 0.018
	var grass := _old_grassland if k else Flora._is_grassland
	_old_scatter(out, "flowers", int(Flora.FLOWER_PATCHES * n), Flora.SEED_OFFSET + 2, blockers,
		func(x: float, z: float, y: float, slope: float) -> bool: return grass.call(x, z, y, slope) and mask.get_noise_2d(x, z) > 0.15)
	if WorldGen.is_island():
		Flora._place_palms(out, blockers)
	return out


func _old_scatter(out: Array, kind: String, count: int, seed_offset: int, blockers, fits: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Flora._world_seed() + seed_offset
	var h := WorldGen.half_size() - 4.0
	var sp := WorldGen.spawn_point()
	var k := WorldGen.is_kingdom()
	var ruins := WorldGen.ruin_sites()
	var placed := 0
	var tries := 0
	var max_tries := count * (Flora.KINGDOM_TRIES if k else 60)
	while placed < count and tries < max_tries:
		tries += 1
		var x := rng.randf_range(-h, h)
		var z := rng.randf_range(-h, h)
		var rot := rng.randf() * TAU
		var s := rng.randf_range(0.75, 1.3)
		var tone := rng.randf()
		var bloom := rng.randi_range(0, Flora.BLOOMS.size() - 1)
		if Vector2(x - sp.x, z - sp.z).length() < Flora.SPAWN_CLEAR:
			continue
		if k and (WorldGen.road_distance(x, z) < WorldGen.ROAD_HALF_WIDTH + 1.0 or Props._on_ruin(x, z, ruins)):
			continue
		var y := Terrain.height(x, z)
		var slope := absf(Terrain.height(x + 1.0, z) - y) + absf(Terrain.height(x, z + 1.0) - y)
		if not fits.call(x, z, y, slope):
			continue
		if k and WorldGen.near_sand(x, z):
			continue
		var p := Vector3(x, y, z)
		if not ResourceNodes.near(p, Flora.NODE_CLEARANCE).is_empty() or blockers.hit(p):
			continue
		blockers.add(p)
		out.append({"kind": kind, "pos": p, "rot": rot, "scale": s, "tone": tone, "bloom": bloom})
		placed += 1


func _old_forest_floor(x: float, z: float, y: float, slope: float) -> bool:
	var b := WorldGen.biome_for(x, z, y)
	return (b == "forest" or b == "stone_hills") and slope < 1.4


func _old_grassland(x: float, z: float, y: float, slope: float) -> bool:
	var b := WorldGen.biome_for(x, z, y)
	return (b == "farmland" or b == "moor") and slope < 0.5

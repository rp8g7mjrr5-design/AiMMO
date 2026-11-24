extends TestCase
## World stream: a generated kingdom (WorldGen gen_version 1) gets its own dressing. The
## lantern ring, the workbench's facing, the decorative forest, flora and the ground colours
## follow the kingdom's spawn plot, size, seed and biomes (gameplay's request,
## world.d/from-gameplay-kingdom-placement.md). Ashgrove, the live world, is unchanged tree for
## tree. Every test puts Ashgrove back before it returns.

const SEED := 11
## Hashes of Ashgrove's dressing as main drew it before this change (var_to_str(...).hash()).
## If a later PR changes Ashgrove's forest, flora, lanterns or bench on purpose, update these.
const ASHGROVE_PROPS := 231910450
const ASHGROVE_FLORA := 3387123732
const ASHGROVE_LAMPS := 4294600772
const ASHGROVE_BENCH := 4182800592


func _kingdom() -> void:
	WorldGen.configure(SEED, 1200.0, WorldGen.KINGDOM)
	ResourceNodes.reset()


func _ashgrove() -> void:
	WorldGen.reset()
	ResourceNodes.reset()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_ashgrove_dressing_is_bit_identical() -> void:
	_kingdom()
	Flora.spots() # visit a kingdom first: the caches must not leak back
	_ashgrove()
	check_eq(var_to_str(Props.scatter()).hash(), ASHGROVE_PROPS, "Ashgrove's forest, tree for tree")
	check_eq(var_to_str(Flora.spots()).hash(), ASHGROVE_FLORA, "Ashgrove's birches, boulders and flowers")
	check_eq(var_to_str(Lamps.positions()).hash(), ASHGROVE_LAMPS, "Ashgrove's lantern ring")
	check_eq(var_to_str(Workbench.spot()).hash(), ASHGROVE_BENCH, "Ashgrove's workbench")
	check_eq(Props.count_for_world(), 1800)
	check_eq(Flora.scale_for_world(), 1.0)


func test_lanterns_and_bench_follow_the_spawn_plot() -> void:
	_kingdom()
	var sp := WorldGen.spawn_point()
	check(_flat(sp, GameConfig.SPAWN_POINT) > 30.0, "seed %d's spawn is away from the origin, so the test means something" % SEED)
	for l in Lamps.positions():
		var r := _flat(l.pos, sp)
		check(r > 7.0 and r < 16.0, "lantern %.1f m from the kingdom's spawn" % r)
		check_near(l.pos.y, Terrain.height(l.pos.x, l.pos.z), 0.01, "lantern on the kingdom's ground")
	var bench := Workbench.spot()
	var to_spawn: Vector3 = sp - bench.pos
	var facing := Vector3(sin(bench.rot), 0.0, cos(bench.rot))
	check(facing.dot(Vector3(to_spawn.x, 0.0, to_spawn.z).normalized()) > 0.99, "the bench's front faces the kingdom's spawn")
	_ashgrove()


func test_the_forest_follows_the_biomes() -> void:
	_kingdom()
	var items := Props.scatter()
	check(items.size() > 3000 and items.size() <= Props.KINGDOM_MAX, "a 1.2 km kingdom gets a real forest (%d)" % items.size())
	check_eq(items.size(), Props.count_for_world(), "and reaches its target")
	var sp := WorldGen.spawn_point()
	var ruins := WorldGen.ruin_sites()
	var by_biome := {}
	var h := WorldGen.half_size()
	for it in items:
		var p: Vector3 = it.pos
		check(absf(p.x) < h and absf(p.z) < h, "inside the kingdom")
		check(_flat(p, sp) >= Props.KINGDOM_SPAWN_CLEAR, "spawn plot stays open")
		check(WorldGen.road_distance(p.x, p.z) >= WorldGen.ROAD_HALF_WIDTH, "no tree on a king's road")
		check(not Props._on_ruin(p.x, p.z, ruins), "no tree on a ruin's pad")
		var b := WorldGen.biome_at(p.x, p.z)
		check(b != "water" and b != "shore" and b != "snow", "no tree in water, on the shore or in the snow (%s)" % b)
		by_biome[b] = by_biome.get(b, 0) + 1
	check(by_biome.get("forest", 0) > items.size() / 2, "most trees stand in the forests: %s" % str(by_biome))
	check_eq(var_to_str(items).hash(), var_to_str(Props.scatter()).hash(), "same seed, same forest")
	_ashgrove()


func test_flora_follows_the_kingdom() -> void:
	_ashgrove()
	var ash_count := Flora.spots().size()
	WorldGen.configure(SEED, 1200.0, WorldGen.KINGDOM) # no reset: the cache follows on its own
	var spots := Flora.spots()
	check(spots.size() > ash_count, "a bigger world grows more flora (%d vs %d)" % [spots.size(), ash_count])
	var sp := WorldGen.spawn_point()
	var kinds := {}
	for s in spots:
		check(_flat(s.pos, sp) >= Flora.SPAWN_CLEAR, "the meadow round the kingdom's spawn stays open")
		check(WorldGen.road_distance(s.pos.x, s.pos.z) >= WorldGen.ROAD_HALF_WIDTH, "nothing grows on a road")
		var b := WorldGen.biome_at(s.pos.x, s.pos.z)
		if s.kind == "flowers":
			check(b == "farmland" or b == "moor", "flowers on fields and moor, not %s" % b)
		elif s.kind == "boulder":
			check(b == "forest" or b == "stone_hills", "boulders under forest or on stone hills, not %s" % b)
		kinds[s.kind] = true
	check(kinds.has("flowers") and kinds.has("boulder") and kinds.has("birch"), "every kind grows: %s" % str(kinds.keys()))
	_ashgrove()
	check_eq(Flora.spots().size(), ash_count, "back on Ashgrove, Ashgrove's flora")


func test_kingdom_ground_reads_by_biome_not_height() -> void:
	_kingdom()
	# Ashgrove's bands would paint anything over 17 m as snow; the kingdom's rim hills go to 30 m.
	var h := WorldGen.half_size()
	var checked := 0
	var x := -h + 8.0
	while x < h:
		var z := -h + 8.0
		while z < h:
			var y := Terrain.height(x, z)
			if y > 17.0 and y < WorldGen.SNOW_LINE - 1.0:
				var c := Palette.ground_at(x, z, y, 0.1, 0.0)
				check(not c.is_equal_approx(Palette.SNOW), "no snow at %.0f m, below the snow line" % y)
				checked += 1
			z += 40.0
		x += 40.0
	check(checked > 10, "the kingdom has hills over 17 m to check (%d)" % checked)
	var c2 := Palette.ground_at(sp_x(), sp_z(), WorldGen.spawn_point().y, 0.0, 0.0)
	check(c2.g > c2.b and c2.g > 0.25, "the spawn plot is grassy")
	_ashgrove()


func sp_x() -> float:
	return WorldGen.spawn_point().x


func sp_z() -> float:
	return WorldGen.spawn_point().z

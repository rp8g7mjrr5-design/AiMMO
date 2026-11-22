extends TestCase


func test_deterministic() -> void:
	var a := Terrain.height(123.4, -56.7)
	var b := Terrain.height(123.4, -56.7)
	check_eq(a, b, "same input, same height")


func test_spawn_is_calm() -> void:
	var c := Terrain.height(0, 0)
	for p in [Vector2(5, 0), Vector2(-8, 3), Vector2(0, 10), Vector2(12, -12)]:
		check(absf(Terrain.height(p.x, p.y) - c) < 0.5, "spawn meadow is flat near %s" % p)
	check(c > Terrain.water_level(), "spawn is above water")


func test_range_is_sane() -> void:
	var lo := INF
	var hi := -INF
	var x := -GameConfig.WORLD_HALF_SIZE
	while x <= GameConfig.WORLD_HALF_SIZE:
		var z := -GameConfig.WORLD_HALF_SIZE
		while z <= GameConfig.WORLD_HALF_SIZE:
			var h := Terrain.height(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			z += 16.0
		x += 16.0
	check(lo > -25.0 and hi < 40.0, "heights within -25..40 (got %.1f..%.1f)" % [lo, hi])
	check(lo < Terrain.water_level(), "there is some water")
	check(hi > 10.0, "there are some hills")

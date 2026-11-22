extends TestCase


func test_walk_speed() -> void:
	var p := Movement.step(Vector3.ZERO, Vector2(0, 1), 1.0)
	check_near(p.z, GameConfig.WALK_SPEED, 0.001, "1s forward")
	check_near(p.y, Terrain.height(p.x, p.z), 0.0001, "on the ground")


func test_input_is_clamped() -> void:
	var p := Movement.step(Vector3.ZERO, Vector2(100, 0), 1.0)
	check_near(p.x, GameConfig.WALK_SPEED, 0.001, "speed hack clamped")


func test_nan_input_ignored() -> void:
	var p := Movement.step(Vector3(1, 0, 1), Vector2(NAN, INF), 1.0)
	check_near(p.x, 1.0, 0.0001, "x unchanged")
	check_near(p.z, 1.0, 0.0001, "z unchanged")


func test_world_edge() -> void:
	var h := GameConfig.WORLD_HALF_SIZE
	var p := Movement.step(Vector3(h - 1, 0, 0), Vector2(1, 0), 10.0)
	check_near(p.x, h, 0.0001, "stops at the edge")

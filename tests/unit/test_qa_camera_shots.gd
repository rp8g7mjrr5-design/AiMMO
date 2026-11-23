extends TestCase
## The client smoke test's action-camera shots (tests/client_smoke/camera_shots.gd) pick a real
## slope near spawn to back the camera onto. If world flattens the meadow or moves spawn, these
## fail here first with a clear reason instead of the smoke test quietly shooting flat ground.

const Shots := preload("res://tests/client_smoke/camera_shots.gd")
const SPAWN := Vector3(0, 0, 0)


func test_finds_a_dry_slope_near_spawn() -> void:
	var feet := Vector3(SPAWN.x, Terrain.height(SPAWN.x, SPAWN.z), SPAWN.z)
	var spot := Shots.steepest_spot(feet)
	check(spot.distance_to(feet) <= Shots.HILL_SEARCH * 1.5, "slope is within reach of spawn (%s)" % spot)
	check(spot.y >= Terrain.water_level() + 0.3, "slope is not under water (%s)" % spot)
	check_near(spot.y, Terrain.height(spot.x, spot.z), 0.001, "slope point is on the ground")
	var rise := Shots._rise_behind(spot, Shots.uphill_yaw(spot))
	check(rise >= 1.0, "ground rises at least 1 m behind the camera spot (got %.2f)" % rise)


func test_uphill_yaw_backs_the_arm_onto_the_rise() -> void:
	var feet := Vector3(SPAWN.x, Terrain.height(SPAWN.x, SPAWN.z), SPAWN.z)
	var spot := Shots.steepest_spot(feet)
	var best := Shots.uphill_yaw(spot)
	check(best >= -PI and best <= PI, "yaw is wrapped")
	# No other of the 24 directions has more ground behind it.
	for i in 24:
		var y := wrapf(TAU * i / 24.0, -PI, PI)
		check(Shots._rise_behind(spot, y) <= Shots._rise_behind(spot, best) + 0.0001, "yaw %.2f is not steeper" % y)

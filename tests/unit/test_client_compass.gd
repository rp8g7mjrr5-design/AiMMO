extends TestCase
## Client compass strip: headings follow the camera, other players land on the right side
## of the strip (or pinned to the edge you should turn to), dots fade with distance, and the
## Spawn Meadow marker points home.

const ClientScript := preload("res://client/client.gd")


## A camera yaw that looks along compass heading `h` (the inverse of CompassStrip.heading).
func _yaw_for(h: float) -> float:
	return -h


func test_heading_matches_the_camera_forward() -> void:
	# The client's camera looks along (-sin(yaw), 0, -cos(yaw)). That direction's bearing
	# must be the heading, for every yaw.
	for i in 36:
		var yaw := i * TAU / 36.0 - PI
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var h := CompassStrip.heading(yaw)
		check(absf(CompassStrip.relative(h, CompassStrip.bearing(Vector3.ZERO, fwd))) < 0.0001, "yaw %.2f: heading %.3f" % [yaw, h])
	check_near(CompassStrip.heading(0.0), 0.0, 0.0001, "yaw 0 looks north (-Z)")
	check_near(CompassStrip.bearing(Vector3.ZERO, Vector3(10, 0, 0)), PI / 2.0, 0.0001, "+X is east")
	check_near(CompassStrip.bearing(Vector3.ZERO, Vector3(0, 0, 10)), PI, 0.0001, "+Z is south")
	check_near(CompassStrip.bearing(Vector3.ZERO, Vector3(-10, 5, 0)), PI * 1.5, 0.0001, "-X is west, height ignored")


func test_cardinals_on_the_strip() -> void:
	var w := CompassStrip.WIDTH
	var marks := CompassStrip.cardinal_marks(_yaw_for(0.0), w)
	var by := {}
	for m in marks:
		by[m.letter] = m.x
	check_near(by.get("N", -1.0), w * 0.5, 0.01, "looking north: N in the middle")
	check_near(by.get("E", -1.0), w, 0.01, "E at the right edge")
	check_near(by.get("W", -1.0), 0.0, 0.01, "W at the left edge")
	check(not by.has("S"), "S is behind you")
	var east := CompassStrip.cardinal_marks(_yaw_for(PI / 2.0), w)
	var e := {}
	for m in east:
		e[m.letter] = m.x
	check_near(e.get("E", -1.0), w * 0.5, 0.01, "looking east: E in the middle")
	check_near(e.get("S", -1.0), w, 0.01, "S on the right when facing east")


func test_players_left_right_and_behind() -> void:
	var w := CompassStrip.WIDTH
	var me := Vector3(50, 3, 50)
	var yaw := _yaw_for(0.0) # facing north (-Z)
	var others := [
		me + Vector3(0, 0, -20), # straight ahead
		me + Vector3(-20, 0, -20), # ahead-left (45 degrees)
		me + Vector3(20, 0, 0), # due right (90 degrees, still on the strip's edge)
		me + Vector3(-5, 0, 30), # behind, slightly left
		me + Vector3(0.1, 0, 0.1), # standing on you: no direction, skipped
	]
	var marks := CompassStrip.player_marks(yaw, me, others, w)
	check_eq(marks.size(), 4, "one mark per other player, minus the one on top of you")
	check_near(marks[0].x, w * 0.5, 0.01, "ahead is centred")
	check_eq(marks[0].edge, false, "ahead is on the strip")
	check_near(marks[1].x, w * 0.25, 0.01, "45 degrees left is a quarter in")
	check_eq(marks[2].edge, false, "exactly 90 degrees is still on the strip")
	check_near(marks[2].x, w, 0.01, "90 degrees right is at the right edge")
	check_eq(marks[3].edge, true, "behind is pinned to an edge")
	check_eq(marks[3].side, -1, "behind-left points you left")
	check_near(marks[3].x, 0.0, 0.01, "pinned to the left edge")
	for m in marks:
		check(m.x >= 0.0 and m.x <= w, "every mark lies on the strip")


func test_dots_fade_with_distance() -> void:
	check_near(CompassStrip.distance_alpha(5.0), 1.0, 0.0001, "close is opaque")
	check_near(CompassStrip.distance_alpha(CompassStrip.NEAR_DISTANCE), 1.0, 0.0001, "near edge opaque")
	check_near(CompassStrip.distance_alpha(1000.0), CompassStrip.FAR_ALPHA, 0.0001, "far is faint, never gone")
	check_near(CompassStrip.edge_fade(0.0), 0.0, 0.0001, "letters vanish at the left end")
	check_near(CompassStrip.edge_fade(CompassStrip.WIDTH), 0.0, 0.0001, "and at the right end")
	check_near(CompassStrip.edge_fade(CompassStrip.WIDTH * 0.5), 1.0, 0.0001, "solid in the middle")
	var mid := CompassStrip.distance_alpha((CompassStrip.NEAR_DISTANCE + CompassStrip.FAR_DISTANCE) * 0.5)
	check(mid < 1.0 and mid > CompassStrip.FAR_ALPHA, "fades in between, got %.3f" % mid)


func test_home_marker_points_to_the_meadow() -> void:
	var w := CompassStrip.WIDTH
	check(CompassStrip.home_mark(0.0, Vector3(3, 0, -4), w).is_empty(), "no home marker inside the meadow")
	# Standing 100 m east of spawn and looking west: home is dead ahead.
	var h := CompassStrip.home_mark(_yaw_for(PI * 1.5), Vector3(100, 2, 0), w)
	check_near(h.x, w * 0.5, 0.01, "home ahead")
	check_eq(h.edge, false, "home on the strip")
	check_near(h.distance, 100.0, 0.01, "home distance")
	# Looking east instead: home is behind, pinned to an edge.
	var back := CompassStrip.home_mark(_yaw_for(PI / 2.0), Vector3(100, 2, 0), w)
	check_eq(back.edge, true, "home behind you is pinned")


func test_client_feeds_other_players_only() -> void:
	var c = ClientScript.new()
	c.my_id = 7
	var mine := Node3D.new()
	mine.position = Vector3(1, 2, 3)
	var placed := Node3D.new()
	placed.position = Vector3(10, 2, -5)
	var unplaced := Node3D.new()
	unplaced.position = Vector3(0, -100, 0) # joined, no snapshot yet
	c.avatars = {7: {"node": mine}, 8: {"node": placed}, 9: {"node": unplaced}}
	var got: Array = c.other_positions()
	check_eq(got.size(), 1, "only placed other players")
	check_eq(got[0], Vector3(10, 2, -5), "the other player's position")
	var strip := CompassStrip.new()
	strip.setup(Theme.new())
	strip.feed(0.0, mine.position, got)
	check_eq(strip._marks.size(), 1, "strip got one mark")
	check(strip.due(0.0), "first frame is due")
	check(not strip.due(0.01), "throttled after")
	strip.free()
	mine.free()
	placed.free()
	unplaced.free()
	c.free()

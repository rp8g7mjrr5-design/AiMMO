extends TestCase
## Client action camera: shoulder offset, arm length and zoom, terrain and prop pull-in,
## smooth follow at any frame rate, camera-relative movement and facing, free-look, and
## look-to-interact target picking.


static func _flat(_x: float, _z: float) -> float:
	return 0.0


static func _wall(x: float, _z: float) -> float:
	return 50.0 if x > 2.0 else 0.0 # a cliff 2 m east of the origin


func _settle(c: ActionCamera, feet: Vector3, height: Callable, props: Array = [], fps := 60.0, seconds := 3.0) -> Transform3D:
	var xf := Transform3D()
	for i in int(seconds * fps):
		xf = c.step(feet, 1.0 / fps, height, props)
	return xf


func test_shoulder_offset_and_arm_length() -> void:
	var c := ActionCamera.new()
	c.place(Vector3.ZERO, 0.0)
	c.pitch = 0.0
	var xf := _settle(c, Vector3.ZERO, _flat)
	var shoulder := ActionCamera.shoulder_point(Vector3.ZERO, 0.0, 1.0)
	check_near(shoulder.y, ActionCamera.PIVOT_HEIGHT, 0.0001, "pivot at head height")
	check_near(shoulder.x, ActionCamera.SHOULDER, 0.0001, "yaw 0 looks north, so right is +X")
	check_near(xf.origin.distance_to(shoulder), ActionCamera.DIST_DEFAULT, 0.01, "default arm 3.5 m")
	check(xf.origin.z > 3.0, "camera sits behind (south of) the character: %s" % xf.origin)
	check_near(xf.origin.x, ActionCamera.SHOULDER, 0.01, "over the right shoulder")
	# Left shoulder mirrors it.
	c.swap_shoulder()
	xf = _settle(c, Vector3.ZERO, _flat)
	check_near(xf.origin.x, -ActionCamera.SHOULDER, 0.01, "swapped to the left shoulder")
	# The camera looks along look_dir (-Z of its basis).
	check((-xf.basis.z).distance_to(ActionCamera.look_dir(c.yaw, c.pitch)) < 0.001, "basis matches look_dir")


func test_look_dir_conventions() -> void:
	for i in 36:
		var yaw := -PI + i * TAU / 36.0
		var f := ActionCamera.forward(yaw)
		var d := ActionCamera.look_dir(yaw, 0.0)
		check(f.distance_to(d) < 0.0001, "flat look is forward at yaw %f" % yaw)
		check((-ActionCamera.basis_for(yaw, 0.0).z).distance_to(f) < 0.0001, "basis forward")
		check_near(ActionCamera.right(yaw).dot(f), 0.0, 0.0001, "right is perpendicular")
		check(f.cross(ActionCamera.right(yaw)).y < 0.0, "right is to the right (clockwise from forward)")
	check(ActionCamera.look_dir(0.0, 0.5).y > 0.0, "positive pitch looks up")


func test_zoom_and_pitch_clamp() -> void:
	var c := ActionCamera.new()
	for i in 40:
		c.zoom(1.0)
	check_near(c.distance, ActionCamera.DIST_MAX, 0.0001, "zoom out stops at 6 m")
	for i in 40:
		c.zoom(-1.0)
	check_near(c.distance, ActionCamera.DIST_MIN, 0.0001, "zoom in stops at 1.5 m")
	c.turn(Vector2(0, 10))
	check_near(c.pitch, ActionCamera.PITCH_MAX, 0.0001)
	c.turn(Vector2(0, -20))
	check_near(c.pitch, ActionCamera.PITCH_MIN, 0.0001)
	c.turn(Vector2(TAU * 3 + 0.5, 0))
	check(c.yaw >= -PI and c.yaw <= PI, "yaw stays wrapped")


func test_terrain_pulls_the_arm_in() -> void:
	var shoulder := ActionCamera.shoulder_point(Vector3.ZERO, 0.0, 1.0)
	# Looking up hard swings the camera down behind you into flat ground.
	var up_arm := ActionCamera.clear_arm(shoulder, 0.0, ActionCamera.PITCH_MAX, 6.0, _flat)
	check(up_arm < 6.0, "looking up pulls in: %f" % up_arm)
	var p := ActionCamera.camera_point(shoulder, 0.0, ActionCamera.PITCH_MAX, up_arm)
	check(p.y >= ActionCamera.CLEARANCE - 0.0001, "camera stays above ground: %f" % p.y)
	# Facing west with a cliff behind you (east): the arm stops short of it.
	var west := PI * 0.5 # forward(PI/2) = (-1, 0, 0)
	var s2 := ActionCamera.shoulder_point(Vector3.ZERO, west, 1.0)
	var arm := ActionCamera.clear_arm(s2, west, 0.0, 6.0, _wall)
	var cam := ActionCamera.camera_point(s2, west, 0.0, arm)
	check(cam.x <= 2.0 - ActionCamera.CLEARANCE + ActionCamera.ARM_SAMPLE + 0.001, "stops before the cliff: arm %f at x %f" % [arm, cam.x])
	check(arm >= ActionCamera.ARM_MIN, "never shorter than ARM_MIN")
	# Open ground behind: the full arm.
	check_near(ActionCamera.clear_arm(shoulder, 0.0, 0.0, 3.5, _flat), 3.5, 0.0001, "nothing in the way")


func test_props_pull_the_arm_in() -> void:
	var tree := {"id": 0, "kind": "ash", "pos": Vector3(0.6, 0, 2.0)} # trunk right behind your right shoulder
	var shoulder := ActionCamera.shoulder_point(Vector3.ZERO, 0.0, 1.0)
	var arm := ActionCamera.clear_arm(shoulder, 0.0, 0.0, 3.5, _flat, [tree])
	check(arm < 1.5, "trunk behind you pulls the camera in: %f" % arm)
	check(not ActionCamera.inside_prop(ActionCamera.camera_point(shoulder, 0.0, 0.0, arm), tree, 0.0), "camera not inside the trunk")
	var seep := {"id": 1, "kind": "scrub", "pos": Vector3(0.6, -1.0, 2.0), "scale": 1.0} # in a dip below you
	check_near(ActionCamera.clear_arm(shoulder, 0.0, 0.0, 3.5, _flat, [seep]), 3.5, 0.0001, "a seep below the arm doesn't block")


func test_prop_shapes_come_from_world() -> void:
	# The camera's idea of each prop is world's NodeProps.solid_columns, scaled per node, so a
	# point the old hand-measured columns missed (ash crown at 1.8 m out, the old column was
	# 1.6 m) now counts, and a bigger node reaches further.
	var ash := {"id": 0, "kind": "ash", "pos": Vector3.ZERO, "scale": 1.0}
	var crown := Vector3(1.8, 3.5, 0.0)
	check(ActionCamera.inside_prop(crown, ash, 0.0), "wide ash crown counts as solid")
	check(not ActionCamera.inside_prop(Vector3(2.5, 3.5, 0.0), ash, 0.0), "outside the crown is clear")
	var big := {"id": 1, "kind": "ash", "pos": Vector3.ZERO, "scale": 1.2}
	check(ActionCamera.inside_prop(Vector3(2.2, 4.0, 0.0), big, 0.0), "node scale grows the solid")
	var seep := {"id": 2, "kind": "scrub", "pos": Vector3.ZERO, "scale": 1.0}
	check(ActionCamera.inside_prop(Vector3(0.0, 1.0, 0.0), seep, 0.0), "sap seeps are solid now too")
	for kind in ["ash", "pine", "stone", "scrub"]:
		var n := {"id": 3, "kind": kind, "pos": Vector3(4, 2, -3), "scale": 1.1}
		for p in [Vector3(4, 2.5, -3), Vector3(5.2, 3.0, -3.4), Vector3(4, 6.0, -1.5)]:
			check(ActionCamera.inside_prop(p, n, 0.2) == NodeProps.inside_solid(p, n, 0.2), "%s agrees with NodeProps at %s" % [kind, p])


func test_arm_eases_out_and_snaps_in() -> void:
	var c := ActionCamera.new()
	c.place(Vector3.ZERO, PI * 0.5)
	c.pitch = 0.0
	c.distance = 6.0
	var xf := c.step(Vector3.ZERO, 1.0 / 60.0, _wall)
	check(xf.origin.x < 2.0 - ActionCamera.CLEARANCE + 0.11, "first frame already short of the cliff: %f" % xf.origin.x)
	# Walk away from the cliff: the arm grows back out over time, not in one frame.
	var feet := Vector3(-20, 0, 0)
	c.place(feet, PI * 0.5)
	c.pitch = 0.0
	c.arm = 1.0
	c.step(feet, 1.0 / 60.0, _flat)
	check(c.arm < 1.5, "eases out, no jump: %f" % c.arm)
	_settle(c, feet, _flat)
	check_near(c.arm, 6.0, 0.02, "back to full zoom")
	check(4.0 - ActionCamera.ease_arm(4.0, 1.0, 0.016) > ActionCamera.ease_arm(1.0, 4.0, 0.016) - 1.0, "pulls in faster than it eases out")


func test_follow_is_frame_rate_independent() -> void:
	# The same 0.5 s of follow at 30, 60 and 144 fps lands in the same place.
	var ends: Array = []
	for fps in [30.0, 60.0, 144.0]:
		var p := Vector3.ZERO
		for i in int(fps * 0.5):
			p = ActionCamera.follow(p, Vector3(10, 0, 0), ActionCamera.FOLLOW_RATE, 1.0 / fps)
		ends.append(p.x)
	check(absf(ends[0] - ends[2]) < 0.01, "30 vs 144 fps: %s" % str(ends))
	check(ends[1] > 9.9, "caught up within half a second: %f" % ends[1])
	# A steadily walking character keeps a steady camera distance (no jitter).
	var c := ActionCamera.new()
	c.place(Vector3.ZERO, 0.0)
	var dists: Array = []
	for i in 240:
		var feet := Vector3(0, 0, -i * 5.0 / 60.0)
		var xf := c.step(feet, 1.0 / 60.0, _flat)
		if i > 120:
			dists.append(xf.origin.distance_to(feet))
	check(dists.max() - dists.min() < 0.01, "steady follow distance: %f..%f" % [dists.min(), dists.max()])


func test_camera_relative_movement_and_facing() -> void:
	for i in 24:
		var yaw := -PI + i * TAU / 24.0
		var w := ActionCamera.move_vector(1.0, 0.0, yaw)
		var f := ActionCamera.forward(yaw)
		check(Vector2(f.x, f.z).distance_to(w) < 0.0001, "W walks where the camera looks")
		var d := ActionCamera.move_vector(0.0, 1.0, yaw)
		var r := ActionCamera.right(yaw)
		check(Vector2(r.x, r.z).distance_to(d) < 0.0001, "D strafes right")
		check(ActionCamera.move_vector(1.0, 1.0, yaw).length() <= 1.0001, "diagonals aren't faster")
		# Facing the camera heading: an avatar with facing_yaw faces along forward(yaw).
		var face := ActionCamera.facing_yaw(yaw)
		check_near(angle_difference(face, atan2(f.x, f.z)), 0.0, 0.0001, "faces the camera heading")
	check_eq(ActionCamera.move_vector(0.0, 0.0, 1.0), Vector2.ZERO)


func test_free_look_keeps_heading_and_returns() -> void:
	var c := ActionCamera.new()
	c.place(Vector3.ZERO, 0.3)
	c.step(Vector3.ZERO, 1.0 / 60.0, _flat)
	c.set_free_look(true)
	c.turn(Vector2(1.5, 0))
	c.step(Vector3.ZERO, 1.0 / 60.0, _flat)
	check_near(c.move_yaw(), 0.3, 0.0001, "free-look: movement keeps your heading")
	check(absf(angle_difference(c.yaw, 0.3)) > 1.0, "but the camera turned")
	c.set_free_look(false)
	_settle(c, Vector3.ZERO, _flat, [], 60.0, 1.0)
	check_near(c.yaw, 0.3, 0.0001, "camera swings back behind you")
	c.turn(Vector2(0.4, 0))
	c.step(Vector3.ZERO, 1.0 / 60.0, _flat)
	check_near(c.move_yaw(), c.yaw, 0.0001, "normal look turns your heading again")


func test_cursor_capture_rules() -> void:
	check(ActionCamera.wants_capture(true, false, false, true), "playing: captured")
	check(not ActionCamera.wants_capture(false, false, false, true), "login screen: free")
	check(not ActionCamera.wants_capture(true, true, false, true), "typing in chat: free")
	check(not ActionCamera.wants_capture(true, false, true, true), "settings open: free")
	check(not ActionCamera.wants_capture(true, false, false, false), "window in the background: free")


func test_look_to_interact_target() -> void:
	var stone := {"id": 1, "kind": "stone", "pos": Vector3(2.0, 0, 0)}
	var pine := {"id": 2, "kind": "pine", "pos": Vector3(0, 0, -2.5)}
	var eye := Vector3(0.6, 2.5, 3.5)
	# Looking at the pine picks it even though the stone is nearer.
	var at_pine: Vector3 = (pine.pos + Vector3.UP - eye).normalized()
	check_eq(ActionCamera.aimed_node(eye, at_pine, [stone, pine]).get("id", -1), 2, "aimed at the pine")
	check_eq(GatherPrompt.pick([stone, pine], eye, at_pine).id, 2, "the prompt takes the aimed pine")
	# Looking at the sky: nothing aimed, fall back to the nearest.
	var sky := Vector3(0, 1, 0)
	check(ActionCamera.aimed_node(eye, sky, [stone, pine]).is_empty(), "nothing under the reticle")
	check_eq(GatherPrompt.pick([stone, pine], eye, sky).id, 1, "falls back to the nearest")
	check_eq(GatherPrompt.pick([stone, pine], eye, Vector3.ZERO).id, 1, "no camera: nearest")
	# Two of the same kind: v3 gathers by node id, so the aimed one wins over a nearer twin.
	var near_pine := {"id": 3, "kind": "pine", "pos": Vector3(1.0, 0, 0)}
	check_eq(GatherPrompt.pick([near_pine, pine], eye, at_pine).id, 2, "the aimed pine, not the nearest")


func test_look_to_interact_on_real_nodes() -> void:
	# Standing beside real nodes and looking straight at one, the prompt names it.
	var checked := 0
	for n in ResourceNodes.all().slice(0, 80):
		var feet: Vector3 = n.pos + Vector3(0, 0, 2.0)
		feet.y = Terrain.height(feet.x, feet.z)
		var eye := ActionCamera.camera_point(ActionCamera.shoulder_point(feet, 0.0, 1.0), 0.0, 0.0, 3.5)
		var look: Vector3 = (n.pos + Vector3.UP - eye).normalized()
		var t := GatherPrompt.target(feet, 0.0, eye, look)
		check(not t.is_empty(), "node %d in reach" % n.id)
		if not t.is_empty() and t.id == n.id:
			checked += 1
	check(checked >= 78, "looked-at node won %d of 80" % checked)


static func _deep(_x: float, _z: float) -> float:
	return -1000.0 # no ground in the way: only the solids matter


## The camera keeps out of decoration (world's WorldSolids) as well as resource nodes, while
## gathering still only sees resource nodes.
func test_camera_solids_include_decoration() -> void:
	var bench := {}
	var biggest := {}
	var big_r := 0.0
	for s in WorldSolids.all():
		if s.source == "workbench":
			bench = s
		for c in s.columns:
			if float(c[0]) > big_r and float(c[2]) - float(c[1]) > 1.0:
				big_r = float(c[0])
				biggest = s
	check(not bench.is_empty(), "world has a workbench solid")
	var around := ActionCamera.camera_solids(bench.pos)
	check(around.has(bench), "the workbench is one of the camera's solids at the bench")
	var node: Dictionary = ResourceNodes.all()[0]
	check(ActionCamera.camera_solids(node.pos).has(node), "resource nodes are still in")
	for n in ResourceNodes.near(bench.pos, ActionCamera.DIST_MAX + 3.0):
		check(around.has(n), "every nearby node is in too")
	# An arm swinging straight through the widest decorative column pulls in before it.
	check(not biggest.is_empty(), "found a decorative column to back into")
	var col: Array = []
	for c in biggest.columns:
		if float(c[0]) == big_r:
			col = c
	var centre := Vector3(biggest.pos.x + float(col[3]), biggest.pos.y + (float(col[1]) + float(col[2])) * 0.5, biggest.pos.z + float(col[4]))
	var shoulder := centre - Vector3(0, 0, big_r + 1.0) # yaw 0 looks -Z, so the arm runs +Z through it
	var open := ActionCamera.clear_arm(shoulder, 0.0, 0.0, ActionCamera.DIST_DEFAULT, _deep, [])
	var arm := ActionCamera.clear_arm(shoulder, 0.0, 0.0, ActionCamera.DIST_DEFAULT, _deep, [biggest])
	check_near(open, ActionCamera.DIST_DEFAULT, 0.0001, "nothing in the way without it")
	check(arm < 1.0, "pulled in before the %s (arm %.2f)" % [biggest.source, arm])
	check(not WorldSolids.inside(ActionCamera.camera_point(shoulder, 0.0, 0.0, arm), biggest), "camera ends outside it")
	# Settled from a real step, too.
	var c := ActionCamera.new()
	c.place(shoulder - Vector3(ActionCamera.SHOULDER, ActionCamera.PIVOT_HEIGHT, 0), 0.0)
	c.pitch = 0.0
	var xf := _settle(c, shoulder - Vector3(ActionCamera.SHOULDER, ActionCamera.PIVOT_HEIGHT, 0), _deep, [biggest])
	check(not WorldSolids.inside(xf.origin, biggest), "stepped camera ends outside the %s" % biggest.source)

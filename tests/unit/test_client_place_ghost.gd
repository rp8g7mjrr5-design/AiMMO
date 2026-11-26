extends TestCase
## Client: campfires on screen and set down with B (PlaceGhost, client.gd). The ghost stands
## where the server will put the fire, goes red where the server would refuse, and the place
## key is bound and listed. Plus the kindle sound.


## A good spot near Spawn Meadow (searches outward until Campfires.check_spot agrees).
func _open_spot() -> Vector3:
	for r in range(4, 200, 2):
		for a in 12:
			var ang := TAU * a / 12.0
			var at := Campfires.spot_in_front(Vector3(cos(ang) * r, 0, sin(ang) * r), 0.0)
			if Campfires.check_spot(Campfires.new_state(), "", at) == "":
				return at
	return Vector3.INF


func test_reason_matches_the_server_rules() -> void:
	var at := _open_spot()
	check(at != Vector3.INF, "found an open spot")
	check_eq(PlaceGhost.reason_at([], at), "", "an open spot is good")
	var fire := {"id": 7, "pos": at + Vector3(1.0, 0, 0), "left": 100.0}
	check_eq(PlaceGhost.reason_at([fire], at), "crowded", "on top of a burning fire is refused")
	var far := {"id": 8, "pos": at + Vector3(Campfires.MIN_SPACING + 1.0, 0, 0), "left": 100.0}
	check_eq(PlaceGhost.reason_at([far], at), "", "a fire a few steps off is fine")
	check_eq(PlaceGhost.reason_at([], Crafting.workbench_pos()), "bench", "not on the workbench")
	var node: Dictionary = ResourceNodes.nearest(Vector3.ZERO)
	check_eq(PlaceGhost.reason_at([], node.pos), "node", "not on a node")
	# The client can't see whose fires they are, so your own count never refuses here
	# (the server's too_many comes back as a refusal instead).
	var mine: Array = []
	for i in Campfires.MAX_PER_PLAYER:
		mine.append({"id": i + 1, "pos": at + Vector3(10.0 + 4.0 * i, 0, 0), "left": 100.0})
	check_eq(PlaceGhost.reason_at(mine, at), "", "own fire count is the server's call")


func test_reason_from_the_wire() -> void:
	var at := _open_spot()
	var st := Campfires.new_state()
	Campfires.place(st, "someone", at - Vector3(sin(0.0), 0, cos(0.0)) * Campfires.PLACE_DISTANCE, 0.0, 0.0)
	var fires := CampfireProps.from_wire(Campfires.to_wire(st, 0.0))
	check_eq(fires.size(), 1, "one fire on the wire")
	check_eq(PlaceGhost.reason_at(fires, at), "crowded", "the ghost knows the fire the server sent")


func test_tints_are_quiet_and_red_when_refused() -> void:
	var good := PlaceGhost.tint("")
	var bad := PlaceGhost.tint("crowded")
	check(good.a < 0.6 and bad.a < 0.6, "see-through either way (art bible section 10)")
	check(good.s < 0.45, "the good ghost is a muted natural, not a glow")
	check(bad.r > bad.g * 1.5, "a refused spot reads red")
	check(not good.is_equal_approx(Color(Palette.EMBER, good.a)), "no ember on a ghost")


func test_ghost_builds_and_follows() -> void:
	var g := PlaceGhost.new()
	g.setup()
	check_eq(str(g.name), PlaceGhost.NODE_NAME)
	check(not g.visible, "hidden until B")
	var at := _open_spot()
	g.show_at(at, "")
	check(g.visible, "shown while placing")
	check(not g.is_red(), "a good spot is pale")
	var stones := g.get_node("FireStones") as MultiMeshInstance3D
	var logs := g.get_node("FireLogs") as MultiMeshInstance3D
	check_eq(stones.multimesh.visible_instance_count, CampfireProps.RING_STONES, "the ring of stones")
	check_eq(logs.multimesh.visible_instance_count, CampfireProps.LOG_COUNT, "the leaned logs")
	for p in PlaceGhost.ghost_parts(at):
		var o: Vector3 = p.xform.origin
		check(Vector2(o.x - at.x, o.z - at.z).length() < 1.0, "the %s stands at the spot" % p.kind)
	g.show_at(at, "node")
	check(g.is_red(), "a refused spot is red")
	g.show_at(at, "")
	g.refuse()
	g.show_at(at, "", 0.1)
	check(g.is_red(), "a server refusal keeps it red for a moment")
	g.show_at(at, "", PlaceGhost.REFUSED_SECONDS)
	check(not g.is_red(), "then it's pale again")
	g.drop()
	check(not g.visible, "put away")
	g.free()


func test_place_key_is_bound_and_listed() -> void:
	ControlsOverlay.install_input()
	check_eq(ControlsOverlay.key_text("place"), "B")
	check(ControlsOverlay.listed_actions().has("place"), "the F1 list shows it")


func test_kindle_sound() -> void:
	var w := Sfx.kindle()
	var n := w.data.size() / 2
	check_near(float(n) / Sfx.RATE, Sfx.KINDLE_LENGTH, 0.01, "about 0.6 s")
	var peak := 0
	for i in n:
		var v := w.data.decode_s16(i * 2)
		peak = maxi(peak, absi(v))
	check(peak > 3000, "audible")
	check(peak < 16000, "quieter than a blow, never clipped")
	check(absi(w.data.decode_s16((n - 1) * 2)) < 200, "no click at the end")

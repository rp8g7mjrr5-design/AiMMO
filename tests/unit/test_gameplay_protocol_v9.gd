extends TestCase
## Protocol v9: the world config on the wire (s2c_world, Phase 1 part 2) and placed campfires
## over the wire (c2s_place / s2c_place_result / s2c_campfires), on Net/Play.

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

const V9_RPCS := ["c2s_place", "s2c_campfires", "s2c_place_result", "s2c_world"]


func _sent(srv: Node, id: int, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == method:
			out.append(m[2])
	return out


func _methods(srv: Node, id: int) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id:
			out.append(m[1])
	return out


func _logged_in_server(world_spec: String, names: Array) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var st := JsonStore.new()
	st.path = "user://test_v9_%d/players.json" % Time.get_ticks_usec()
	st.open()
	srv.store = st
	srv.use_world(WorldGen.parse(world_spec))
	for i in names.size():
		srv._on_peer_connected(i + 1)
		srv._on_login(i + 1, GameConfig.PROTOCOL_VERSION, names[i], "hunter22pass")
	return srv


func _done(srv: Node) -> void:
	srv.use_world(WorldGen.parse("")) # back to Ashgrove for every later test
	srv.free()


func test_v9_adds_its_rpcs_on_play_and_v8_is_frozen() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 9, "v9 or later")
	var expected := Array(ProtocolCompat.rpc_names("res://tests/protocol/net_play_v8.gd")) + V9_RPCS
	expected.sort()
	if GameConfig.PROTOCOL_VERSION == 9:
		check_eq(Array(ProtocolCompat.rpc_names("res://shared/net_play.gd")), expected, "v9 Play = v8 Play + world and campfires")
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v8.gd"),
		"Net's own RPCs unchanged since v8")


func test_v9_rpcs_reemit_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.world_config.connect(func(c): got.append(["world", c]))
	net.place_requested.connect(func(p, i): got.append(["place", p, i]))
	net.place_result.connect(func(i, ok, r, t): got.append(["result", i, ok, r, t]))
	net.campfires_changed.connect(func(e): got.append(["fires", e]))
	net.play.s2c_world({"seed": 5, "size_m": 1200.0, "gen_version": 1})
	net.play.c2s_place("campfire")
	net.play.s2c_place_result("campfire", false, "no_item", "nope")
	net.play.s2c_campfires(PackedFloat32Array([1, 2, 3, 4, 5]))
	check_eq(got, [["world", {"seed": 5, "size_m": 1200.0, "gen_version": 1}], ["place", 0, "campfire"],
		["result", "campfire", false, "no_item", "nope"], ["fires", PackedFloat32Array([1, 2, 3, 4, 5])]])
	net.free()


func test_login_names_the_world_before_anything_in_it() -> void:
	for spec in ["", "4242:1"]:
		var srv := _logged_in_server(spec, ["Wren"])
		var worlds := _sent(srv, 1, "s2c_world")
		check_eq(worlds.size(), 1, "one s2c_world per login (%s)" % spec)
		check_eq(worlds[0][0], WorldGen.config(), "it is the world the server runs (%s)" % spec)
		var order := _methods(srv, 1)
		check_eq(order.find("s2c_login_result"), 0, "the login answer first")
		check_eq(order.find("s2c_world"), 1, "then the world, before time, vitals, pack and nodes (%s)" % [order])
		_done(srv)


func test_ashgrove_config_is_gen_0_and_a_client_applying_it_changes_nothing() -> void:
	var srv := _logged_in_server("", ["Wren"])
	var cfg: Dictionary = _sent(srv, 1, "s2c_world")[0][0]
	check_eq(int(cfg.gen_version), 0, "today's valley")
	var before := WorldGen.config()
	WorldGen.apply(cfg)
	check_eq(WorldGen.config(), before, "applying what the server sent is a no-op on Ashgrove")
	_done(srv)


func test_a_kingdom_config_round_trips() -> void:
	var srv := _logged_in_server("4242:1:1000", ["Wren"])
	var cfg: Dictionary = _sent(srv, 1, "s2c_world")[0][0]
	check_eq([int(cfg.seed), int(cfg.gen_version), float(cfg.size_m)], [4242, 1, 1000.0])
	var sp := WorldGen.spawn_point()
	WorldGen.apply(WorldGen.parse(""))
	WorldGen.apply(cfg)
	check(WorldGen.spawn_point().is_equal_approx(sp), "a client applying it finds the same spawn")
	_done(srv)


func test_c2s_place_answers_the_placer_and_tells_everyone() -> void:
	var srv := _logged_in_server("", ["Wren", "Ash"])
	srv.test_outbox.clear()
	srv._on_place(1, "campfire")
	var res := _sent(srv, 1, "s2c_place_result")
	check_eq(res.size(), 1, "one answer")
	check_eq(res[0], ["campfire", false, "no_item", Campfires.refusal_text("no_item")])
	check(_sent(srv, 2, "s2c_place_result").is_empty(), "only the placer hears a refusal")
	# Find a good spot for player 1, give them a campfire, and place it over the wire.
	var spot := Vector3.ZERO
	for r in range(4, 200, 2):
		var p := WorldGen.spawn_point() + Vector3(r, 0, -r * 0.5)
		if Campfires.check_spot(srv.campfires, "wren", Campfires.spot_in_front(p, 0.0)) == "":
			spot = p
			break
	var ch: Dictionary = srv.sessions[1].character
	ch.x = spot.x
	ch.z = spot.z
	srv.sessions[1].yaw = 0.0
	srv.give_item(1, "campfire", 1)
	srv.test_outbox.clear()
	srv.test_now += 1.0
	srv._on_place(1, " Campfire ")
	res = _sent(srv, 1, "s2c_place_result")
	check(res.size() == 1 and res[0][1] == true and res[0][2] == "", "placed: %s" % [res])
	check_eq(str(res[0][3]), srv.PLACED_TEXT)
	for pid in [1, 2]:
		var fires := _sent(srv, pid, "s2c_campfires")
		check(fires.size() == 1 and (fires[0][0] as PackedFloat32Array).size() == 5, "player %d sees the fire" % pid)
	# A second request straight after is dropped (the per-player play gap), not answered.
	srv.test_outbox.clear()
	srv._on_place(1, "campfire")
	check(_sent(srv, 1, "s2c_place_result").is_empty(), "flooding is dropped quietly")
	_done(srv)


func test_c2s_place_from_someone_not_logged_in_is_ignored() -> void:
	var srv := _logged_in_server("", [])
	srv._on_peer_connected(9)
	srv._on_place(9, "campfire")
	check(_sent(srv, 9, "s2c_place_result").is_empty(), "no answer before login")
	_done(srv)

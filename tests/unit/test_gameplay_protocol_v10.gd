extends TestCase
## Protocol v10: the Gloam walkers on the wire (Basics 2, zombie survival). s2c_gloam carries
## the walkers in view about 5 times a second, with the grab's windup so the client can draw
## the telegraph; s2c_gloam_hits tells everyone in view that a blow landed on walkers (and
## which it put down). Both on Net/Play; Net's own RPCs unchanged.

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

const V10_RPCS := ["s2c_gloam", "s2c_gloam_hits"]
const DT := 0.05


func _sent(srv: Node, id: int, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == method:
			out.append(m[2])
	return out


## A spot on dry ground well outside the meadow (like test_gameplay_gloam's).
func _field() -> Vector3:
	for r in range(60, 200, 5):
		for a in 16:
			var ang := TAU * a / 16.0
			var x := cos(ang) * r
			var z := sin(ang) * r
			if Gloam.good_ground(x, z) and Gloam.good_ground(x + 12, z) and Gloam.good_ground(x - 12, z):
				return Vector3(x, Terrain.height(x, z), z)
	return Vector3(80, 0, 0)


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true
	for id in players:
		var ch := CharacterData.normalize({"name": "p%d" % id})
		var pos: Vector3 = players[id]
		ch.x = pos.x
		ch.y = pos.y
		ch.z = pos.z
		srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func test_v10_adds_its_rpcs_on_play_and_v9_is_frozen() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 10, "v10 or later")
	var expected := Array(ProtocolCompat.rpc_names("res://tests/protocol/net_play_v9.gd")) + V10_RPCS
	expected.sort()
	if GameConfig.PROTOCOL_VERSION == 10:
		check_eq(Array(ProtocolCompat.rpc_names("res://shared/net_play.gd")), expected, "v10 Play = v9 Play + the Gloam")
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v9.gd"),
		"Net's own RPCs unchanged since v9")


func test_v10_rpcs_reemit_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.gloam_changed.connect(func(e): got.append(["gloam", e]))
	net.gloam_struck.connect(func(p, k, ids, down): got.append(["hits", p, k, ids, down]))
	net.play.s2c_gloam(PackedFloat32Array([3, 50.0, 60.0, 1.5, 3, 0.4]))
	net.play.s2c_gloam_hits(2, "heavy", [3], [])
	check_eq(got, [["gloam", PackedFloat32Array([3, 50.0, 60.0, 1.5, 3, 0.4])], ["hits", 2, "heavy", [3], []]])
	net.free()


func test_wire_round_trips_and_carries_the_windup() -> void:
	var g := Gloam.new_state()
	var at := _field()
	var w := Gloam.rise(g, at + Vector3(5, 0, 0), 10.0)
	var far := Gloam.rise(g, at + Vector3(GameConfig.VIEW_RANGE + 20.0, 0, 0), 10.0)
	var wire := Gloam.to_wire_near(g, at, GameConfig.VIEW_RANGE, 10.0)
	check_eq(wire.size(), Gloam.WIRE_STRIDE, "only the walker in view")
	var back := Gloam.from_wire(wire)
	check_eq(int(back[0].id), int(w.id))
	check_near(float(back[0].x), w.pos.x, 0.01)
	check_near(float(back[0].z), w.pos.z, 0.01)
	check_eq(str(back[0].state), str(w.state))
	check_eq(float(back[0].windup_left), 0.0, "no windup while it wanders")
	check(int(far.id) != int(w.id), "two walkers")
	# Arms up: the wire says so, with the seconds until the grab closes.
	w.state = "grab"
	w.grab_at = 10.0 + Gloam.GRAB_WINDUP
	back = Gloam.from_wire(Gloam.to_wire_near(g, at, GameConfig.VIEW_RANGE, 10.3))
	check_eq(str(back[0].state), "grab")
	check_near(float(back[0].windup_left), Gloam.GRAB_WINDUP - 0.3, 0.001, "the telegraph's time left")
	check_eq(Gloam.windup_left(w, 99.0), 0.0, "never negative")
	check(Gloam.from_wire(PackedFloat32Array([1, 2, 3])).is_empty(), "a short array is ignored")


func test_server_sends_walkers_in_view_and_says_goodbye() -> void:
	var at := _field()
	var srv := _server({1: at, 2: at + Vector3(GameConfig.VIEW_RANGE * 3.0, 0, 0)})
	srv._send_gloam()
	check(_sent(srv, 1, "s2c_gloam").is_empty(), "no walkers, nothing sent (the live world sends none)")
	srv._on_chat(1, "/gloam")
	check_eq(Gloam.count(srv.gloam), 1)
	srv.test_outbox.clear()
	srv._send_gloam()
	var mine := _sent(srv, 1, "s2c_gloam")
	check_eq(mine.size(), 1, "the summoner sees it")
	var back := Gloam.from_wire(mine[0][0])
	check_eq(int(back[0].id), int(srv.gloam.walkers[0].id))
	check(_sent(srv, 2, "s2c_gloam").is_empty(), "a player far off doesn't")
	# It goes: a few empty sends so a lost packet can't leave it frozen on screen, then quiet.
	srv.gloam.walkers.clear()
	srv.test_outbox.clear()
	for i in srv.WILDLIFE_GOODBYES + 2:
		srv._send_gloam()
	var byes := _sent(srv, 1, "s2c_gloam")
	check_eq(byes.size(), srv.WILDLIFE_GOODBYES, "goodbyes")
	for b in byes:
		check((b[0] as PackedFloat32Array).is_empty(), "an empty goodbye")
	srv.free()


func test_the_grab_windup_goes_out_before_it_lands() -> void:
	var at := _field()
	var srv := _server({1: at})
	srv._on_chat(1, "/gloam")
	var hp0 := float(srv.vitals_of(1).hp)
	var saw_windup := false
	var t := 0.0
	var tick := 0
	while t < 10.0 and float(srv.vitals_of(1).hp) >= hp0:
		t += DT
		tick += 1
		srv.test_now += DT
		srv._tick_gloam(srv.test_now)
		if tick % srv.WILDLIFE_SEND_TICKS == 0:
			srv.test_outbox.clear()
			srv._send_gloam()
			for m in _sent(srv, 1, "s2c_gloam"):
				for w in Gloam.from_wire(m[0]):
					if str(w.state) == "grab" and float(w.windup_left) > 0.0:
						saw_windup = true
	check(float(srv.vitals_of(1).hp) < hp0, "it grabbed")
	check(saw_windup, "the arms-up windup was on the wire before the grab landed")
	srv.free()


func test_blows_on_a_walker_go_out_and_name_the_one_put_down() -> void:
	var at := _field()
	var srv := _server({1: at, 2: at + Vector3(3, 0, 0)})
	srv._on_chat(1, "/gloam")
	var w: Dictionary = srv.gloam.walkers[0]
	var wid := int(w.id)
	# Bring it right up to us, so every haymaker connects.
	w.pos = at + Vector3(0, 0, 1.2)
	var swings := 0
	while Gloam.count(srv.gloam) > 0 and swings < 12:
		srv.sessions[1].swing = {}
		srv.vitals_of(1).stamina = 100.0
		srv.attack_request(1, "heavy", atan2(w.pos.x - at.x, w.pos.z - at.z))
		srv.test_now += Weapons.swing_seconds(Weapons.FISTS, "heavy") + 0.01
		srv._tick_swings(srv.test_now)
		swings += 1
	check_eq(Gloam.count(srv.gloam), 0, "put down (%d swings)" % swings)
	for pid in [1, 2]:
		var hits := _sent(srv, pid, "s2c_gloam_hits")
		check_eq(hits.size(), swings, "player %d saw every blow" % pid)
		for h in hits:
			check_eq(h[2], [wid], "the walker by its wire id")
			check_eq(str(h[1]), "heavy")
		check_eq(hits[hits.size() - 1][3], [wid], "the last blow put it down")
		check_eq(hits[0][3], [], "the first didn't")
	for h in _sent(srv, 1, "s2c_swing_hits"):
		check_eq(h[2], [], "grazer ids stay grazers only")
	srv.free()

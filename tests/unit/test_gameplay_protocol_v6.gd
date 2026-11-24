extends TestCase
## Protocol v6 (Milestone 2 build-ahead, the old Week 04 "gentle wildlife"): the grazers that
## have run on the server since #145 go out to players as s2c_wildlife on Net/Play, about 5
## times a second, only the ones within GameConfig.VIEW_RANGE, plus a few empty sends when
## the last one leaves your view. Net's own RPCs are unchanged, so old clients still get
## "please update" (net_v5.gd is frozen for that).

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

const V6_RPCS := ["s2c_wildlife"]


func _player(srv: Node, id: int, pos: Vector3) -> void:
	var ch := CharacterData.normalize({"name": "p%d" % id})
	ch.x = pos.x
	ch.y = pos.y
	ch.z = pos.z
	srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
		"channel": {}, "login_attempts": 0, "inv_dirty": false}


func _move(srv: Node, id: int, pos: Vector3) -> void:
	var ch: Dictionary = srv.sessions[id].character
	ch.x = pos.x
	ch.y = pos.y
	ch.z = pos.z


func _wildlife_sends(srv: Node, id: int) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == "s2c_wildlife":
			out.append(m[2][0])
	return out


## A spot at least `margin` metres beyond VIEW_RANGE from every grazer.
func _far_from_all(srv: Node, margin: float) -> Vector3:
	for r in [400.0, 600.0, 800.0]:
		for a in 16:
			var p := Vector3(cos(TAU * a / 16.0) * r, 0.0, sin(TAU * a / 16.0) * r)
			var ok := true
			for c in srv.wildlife.creatures:
				if Vector2(c.pos.x - p.x, c.pos.z - p.z).length() < GameConfig.VIEW_RANGE + margin:
					ok = false
					break
			if ok:
				return p
	return Vector3(5000, 0, 5000)


func test_v6_adds_only_wildlife_on_play_and_v5_is_frozen() -> void:
	check_eq(GameConfig.PROTOCOL_VERSION, 6)
	var play := ProtocolCompat.rpc_names("res://shared/net_play.gd")
	var v5_play := ProtocolCompat.rpc_names("res://tests/protocol/net_play_v5.gd")
	var expected := Array(v5_play) + V6_RPCS
	expected.sort()
	check_eq(Array(play), expected, "v6 Play = v5 Play + s2c_wildlife")
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v5.gd"),
		"Net's own RPCs unchanged since v5")
	check(FileAccess.file_exists("res://tests/protocol/net_v5.gd"), "net_v5.gd frozen for the bump")


func test_wildlife_reemits_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.wildlife_changed.connect(func(e): got.append(e))
	net.play.s2c_wildlife(PackedFloat32Array([3, 50.0, 60.0, 1.5, 0]))
	net.play.s2c_wildlife(PackedFloat32Array())
	check_eq(got, [PackedFloat32Array([3, 50.0, 60.0, 1.5, 0]), PackedFloat32Array()])
	net.free()


func test_wire_is_packed_floats() -> void:
	# 4 bytes a value on the wire instead of a Variant Array's 12: keeps the per-player
	# bandwidth inside qa's perf budget (tests/bot_test/perf_budget.json).
	check_eq(typeof(Wildlife.to_wire(Wildlife.new_state())), TYPE_PACKED_FLOAT32_ARRAY)
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	_player(srv, 2, srv.wildlife.creatures[0].pos + Vector3(30, 0, 0))
	for i in srv.WILDLIFE_SEND_TICKS:
		srv._tick()
	var sends := _wildlife_sends(srv, 2)
	check_eq(sends.size(), 1)
	check_eq(typeof(sends[0]), TYPE_PACKED_FLOAT32_ARRAY, "sent packed")
	srv.free()


func test_wire_near_keeps_only_what_is_in_view() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = w.creatures[0]
	var near := Wildlife.to_wire_near(w, c.pos, 1.0)
	check(near.size() >= Wildlife.WIRE_STRIDE, "the creature you stand on is in view")
	check_eq(int(near[0]), int(c.id))
	check_eq(near.size() % Wildlife.WIRE_STRIDE, 0)
	var all := Wildlife.to_wire_near(w, Vector3.ZERO, 100000.0)
	check_eq(all, Wildlife.to_wire(w), "an endless view is the whole wire")
	var ids: Array = []
	for i in range(0, all.size(), Wildlife.WIRE_STRIDE):
		ids.append(int(all[i]))
	var sorted := ids.duplicate()
	sorted.sort()
	check_eq(ids, sorted, "in id order")
	check_eq(Wildlife.to_wire_near(w, Vector3(5000, 0, 5000), GameConfig.VIEW_RANGE).size(), 0, "none from far away")
	var c_wire := Wildlife.to_wire_near(w, c.pos, 0.5)
	check_near(c_wire[1], c.pos.x, 0.01, "x survives 32-bit floats")
	check_near(c_wire[2], c.pos.z, 0.01, "z survives 32-bit floats")


func test_sent_five_times_a_second_only_what_you_can_see() -> void:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var c: Dictionary = srv.wildlife.creatures[0]
	_player(srv, 2, c.pos + Vector3(30, 0, 0)) # in view of herd 0, not spooking it
	var far := _far_from_all(srv, 10.0)
	_player(srv, 3, far)
	for i in GameConfig.TICK_RATE: # one second
		srv._tick()
	var sends := _wildlife_sends(srv, 2)
	check_eq(sends.size(), GameConfig.TICK_RATE / srv.WILDLIFE_SEND_TICKS, "5 a second")
	check_eq(_wildlife_sends(srv, 3).size(), 0, "nothing for a player with no grazer in view")
	var here := CharacterData.position(srv.sessions[2].character)
	for e in sends:
		check_eq(e.size() % Wildlife.WIRE_STRIDE, 0)
		check(e.has(float(c.id)), "the herd beside you is in it")
		for i in range(0, e.size(), Wildlife.WIRE_STRIDE):
			var d := Vector2(float(e[i + 1]) - here.x, float(e[i + 2]) - here.z).length()
			check(d <= GameConfig.VIEW_RANGE, "creature %d is %.1f m away, beyond the view" % [e[i], d])
			check(int(e[i + 4]) >= 0 and int(e[i + 4]) < Wildlife.STATES.size(), "a real state")
	srv.free()


func test_a_few_empty_sends_when_the_last_one_leaves_view() -> void:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var c: Dictionary = srv.wildlife.creatures[0]
	_player(srv, 2, c.pos + Vector3(30, 0, 0))
	for i in srv.WILDLIFE_SEND_TICKS:
		srv._tick()
	check_eq(_wildlife_sends(srv, 2).size(), 1)
	srv.test_outbox.clear()
	_move(srv, 2, _far_from_all(srv, 10.0))
	for i in srv.WILDLIFE_SEND_TICKS * (srv.WILDLIFE_GOODBYES + 3):
		srv._tick()
	var sends := _wildlife_sends(srv, 2)
	check_eq(sends.size(), srv.WILDLIFE_GOODBYES, "a few goodbyes, then quiet")
	for e in sends:
		check_eq(e.size(), 0, "goodbye is an empty list")
	srv.free()


func test_the_bolt_reaches_the_player_who_caused_it() -> void:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var c: Dictionary = srv.wildlife.creatures[0]
	var away := Vector2(c.pos.x - c.home.x, c.pos.z - c.home.z)
	away = Vector2(1, 0) if away.length() < 0.1 else away.normalized()
	_player(srv, 2, c.pos + Vector3(away.x, 0, away.y) * (Wildlife.BOLT_RADIUS - 1.0))
	for i in srv.WILDLIFE_SEND_TICKS:
		srv._tick()
	var sends := _wildlife_sends(srv, 2)
	check_eq(sends.size(), 1)
	var e: PackedFloat32Array = sends[0]
	var at := -1
	for i in range(0, e.size(), Wildlife.WIRE_STRIDE):
		if int(e[i]) == int(c.id):
			at = i
	check(at >= 0 and at % Wildlife.WIRE_STRIDE == 0, "the spooked grazer is listed")
	check_eq(Wildlife.STATES[int(e[at + 4])], "flee", "and it is fleeing: the client's cue for the snort")
	# Its herd-mates bolted with it.
	var herd_fleeing := 0
	for i in range(0, e.size(), Wildlife.WIRE_STRIDE):
		var other := Wildlife.get_by_id(srv.wildlife, int(e[i]))
		if int(other.herd) == int(c.herd) and Wildlife.STATES[int(e[i + 4])] == "flee":
			herd_fleeing += 1
	check(herd_fleeing >= 2, "the herd bolts together (%d fleeing)" % herd_fleeing)
	srv.free()


func test_a_new_login_starts_fresh() -> void:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var far := _far_from_all(srv, 10.0)
	_player(srv, 2, far)
	for i in srv.WILDLIFE_SEND_TICKS * 3:
		srv._tick()
	check_eq(_wildlife_sends(srv, 2).size(), 0, "a login far from every herd hears nothing, not an empty list")
	srv.free()

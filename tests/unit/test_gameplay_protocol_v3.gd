extends TestCase
## Protocol v3 end to end on one machine, without sockets: Net creates Net/Play with every
## new RPC, each RPC re-emits its Net signal, the server's c2s handlers (press E, let go,
## Make) drive the real gather and craft paths, and every snapshot carries the receiving
## player's own ack_seq.

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const PlayScript := preload("res://shared/net_play.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

const V3_RPCS := ["c2s_craft", "c2s_gather_cancel", "c2s_gather_start", "s2c_craft_result",
	"s2c_gather_begin", "s2c_gather_end", "s2c_gather_result", "s2c_inventory", "s2c_node_state", "s2c_nodes"]


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _server(positions: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	for id in positions:
		var ch := CharacterData.normalize({"name": "P%d" % id})
		var p: Vector3 = positions[id]
		ch.x = p.x
		ch.y = p.y
		ch.z = p.z
		srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _sent(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[1] == method:
			out.append([m[0], m[2]])
	return out


func _run(srv: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		srv.test_now += GameConfig.TICK_DT
		t += GameConfig.TICK_DT
		srv._tick_channels(srv.test_now)
		srv._flush_inventories()


func test_v3_rpcs_live_on_play_not_net() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 3, "v3 or later")
	check_eq(Array(ProtocolCompat.rpc_names("res://tests/protocol/net_play_v3.gd")), V3_RPCS,
		"the frozen v3 Play carries exactly the v3 RPCs")
	var play_rpcs := ProtocolCompat.rpc_names("res://shared/net_play.gd")
	for m in V3_RPCS:
		check(play_rpcs.has(m), "today's Play still has v3's %s" % m)
	var net_rpcs := ProtocolCompat.rpc_names("res://shared/net.gd")
	check_eq(net_rpcs, ProtocolCompat.rpc_names("res://tests/protocol/net_v2.gd"),
		"Net's own RPC list is still v2's, so old clients get the update message")
	for m in V3_RPCS:
		check(not net_rpcs.has(m), "%s is not on Net" % m)
	var net: Node = NetScript.new()
	net._ready()
	check(net.play != null and net.play.name == "Play" and net.play.get_parent() == net, "Net/Play exists after _ready")
	for m in V3_RPCS:
		check(net.play.has_method(m), "Play has %s" % m)
	net.free()


func test_play_rpcs_reemit_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.gather_begun.connect(func(p, n, s): got.append(["begun", p, n, s]))
	net.gather_ended.connect(func(p, n, r): got.append(["ended", p, n, r]))
	net.gather_result.connect(func(i, c): got.append(["result", i, c]))
	net.inventory_changed.connect(func(items): got.append(["inv", items]))
	net.nodes_depleted.connect(func(ids): got.append(["nodes", ids]))
	net.node_state.connect(func(n, d): got.append(["node", n, d]))
	net.craft_result.connect(func(r, ok, t): got.append(["craft", r, ok, t]))
	net.gather_start_requested.connect(func(_p, n): got.append(["start", n]))
	net.gather_cancel_requested.connect(func(_p): got.append(["cancel"]))
	net.craft_requested.connect(func(_p, r): got.append(["make", r]))
	net.snapshot_ack.connect(func(a): got.append(["ack", a]))
	net.snapshot.connect(func(t, _e): got.append(["snap", t, net.last_ack_seq]))
	var play: Node = net.play
	play.s2c_gather_begin(2, 17, 2.0)
	play.s2c_gather_end(2, 17, "done")
	play.s2c_gather_result("stone", 2)
	play.s2c_inventory({"stone": 2})
	play.s2c_nodes([3, 9])
	play.s2c_node_state(17, true)
	play.s2c_craft_result("torch", true, "You make 3 torches.")
	play.c2s_gather_start(17)
	play.c2s_gather_cancel()
	play.c2s_craft("stone_axe")
	check_eq(net.last_ack_seq, -1, "no ack before the first snapshot")
	net.s2c_snapshot(5, [], 41)
	check_eq(got, [["begun", 2, 17, 2.0], ["ended", 2, 17, "done"], ["result", "stone", 2], ["inv", {"stone": 2}],
		["nodes", [3, 9]], ["node", 17, true], ["craft", "torch", true, "You make 3 torches."], ["start", 17],
		["cancel"], ["make", "stone_axe"], ["ack", 41], ["snap", 5, 41]], "every RPC reaches its signal, ack before snapshot")
	net.free()


func test_press_e_gathers_and_letting_go_cancels() -> void:
	var n := _first("stone")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0)})
	srv._on_gather_start(2, n.id)
	var begin := _sent(srv, "s2c_gather_begin")
	check_eq(begin.size(), 1, "c2s_gather_start starts a timed gather")
	srv._on_gather_cancel(2)
	check_eq(_sent(srv, "s2c_gather_end"), [[2, [2, n.id, "stopped"]]], "c2s_gather_cancel stops it")
	check_eq(int(srv.gathering.taken.get(n.id, 0)), 0, "no charge used")
	check_eq(Inventory.count(srv.sessions[2].character.inventory, "stone"), 0, "nothing paid out")
	# Straight away again: a cancel spends no cooldown.
	srv.test_outbox.clear()
	srv._on_gather_start(2, n.id)
	check_eq(_sent(srv, "s2c_gather_begin").size(), 1, "starts again at once")
	_run(srv, float(begin[0][1][2]) + 0.1)
	check_eq(_sent(srv, "s2c_gather_end")[-1][1][2], "done")
	check_eq(_sent(srv, "s2c_gather_result").size(), 1, "haul result for the toast")
	check(Inventory.count(srv.sessions[2].character.inventory, "stone") > 0, "stone in the pack")
	check_eq(_sent(srv, "s2c_inventory").size(), 1, "pack update")
	srv.free()


func test_handlers_ignore_players_not_logged_in() -> void:
	var n := _first("pine")
	var srv := _server({})
	srv.sessions[7] = {"logged_in": false, "character": {}, "channel": {}, "seq": -1}
	srv._on_gather_start(7, n.id)
	srv._on_gather_cancel(7)
	srv._on_craft(7, "torch")
	srv._on_gather_start(99, n.id) # unknown peer
	check(srv.test_outbox.is_empty(), "nothing sent to a peer that never logged in: %s" % [srv.test_outbox])
	srv.free()


func test_bad_node_id_is_refused_out_loud() -> void:
	var srv := _server({2: Vector3.ZERO})
	srv._on_gather_start(2, -5)
	check_eq(_sent(srv, "s2c_gather_end").size(), 1, "refusal ends the client's bar")
	check_eq(_sent(srv, "s2c_gather_begin").size(), 0)
	srv._on_gather_start(2, 1 << 30)
	check_eq(_sent(srv, "s2c_gather_end").size(), 2, "an id past the last node too")
	srv.free()


func test_make_button_crafts() -> void:
	var srv := _server({2: Crafting.workbench_pos()})
	var inv: Dictionary = srv.sessions[2].character.inventory
	for item in Crafting.RECIPES.torch.needs:
		Inventory.add(inv, item, int(Crafting.RECIPES.torch.needs[item]))
	srv._on_craft(2, "torch")
	var res := _sent(srv, "s2c_craft_result")
	check_eq(res.size(), 1, "one answer")
	check(res.size() == 1 and res[0][1][0] == "torch" and res[0][1][1] == true, "torch made: %s" % [res])
	srv._flush_inventories()
	check_eq(_sent(srv, "s2c_inventory").size(), 1, "one pack update for the whole craft")
	srv._on_craft(2, "torch")
	check_eq(_sent(srv, "s2c_craft_result")[-1][1][1], false, "second torch refused: nothing left")
	srv.free()


func test_snapshots_carry_each_players_own_ack() -> void:
	var srv := _server({2: Vector3(1, 0, 1), 3: Vector3(-1, 0, -1)})
	srv._on_input(2, 7, Vector2(1, 0), 0.0)
	srv._on_input(2, 5, Vector2(0, 1), 0.0) # older: ignored, ack stays 7
	srv._on_input(3, 12, Vector2.ZERO, 0.0)
	srv._tick()
	var snaps := _sent(srv, "s2c_snapshot")
	check_eq(snaps.size(), 2, "one snapshot per player")
	var acks := {}
	for s in snaps:
		check_eq(s[1].size(), 3, "tick, entries, ack_seq")
		acks[s[0]] = s[1][2]
		check_eq(s[1][1].size(), 10, "both players in the entries")
	check_eq(acks, {2: 7, 3: 12}, "each player gets their own last applied seq")
	srv.sessions[4] = srv.sessions[3].duplicate(true)
	srv.sessions[4].seq = -1
	srv.test_outbox.clear()
	srv._tick()
	var fresh := -2
	for s in _sent(srv, "s2c_snapshot"):
		if s[0] == 4:
			fresh = s[1][2]
	check_eq(fresh, -1, "a player who has sent no input yet gets -1")
	srv.free()


func test_watcher_who_walks_off_still_sees_the_end() -> void:
	# Otherwise their client shows the other player chopping forever.
	var n := _first("pine")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0), 3: n.pos + Vector3(-5.0, 0, 0)})
	srv._on_gather_start(2, n.id)
	check_eq(_sent(srv, "s2c_gather_begin").size(), 2, "both see it begin")
	var far: Vector3 = n.pos + Vector3(GameConfig.VIEW_RANGE + 30.0, 0, 0)
	srv.sessions[3].character.x = far.x
	srv.sessions[3].character.z = far.z
	srv._on_gather_cancel(2)
	var to := []
	for m in _sent(srv, "s2c_gather_end"):
		to.append(m[0])
	check_eq(to, [2, 3], "the end goes to everyone who saw the begin")
	srv.free()

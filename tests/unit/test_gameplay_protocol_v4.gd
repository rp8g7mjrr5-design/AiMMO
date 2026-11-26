extends TestCase
## Protocol v4 added four skills RPCs on Net/Play (s2c_skills, s2c_xp, s2c_level_up,
## s2c_level_up_seen). The leveling system is gone (owner direction, 2026-11-26), but RPCs are
## append-only: the four keep their place so every later RPC keeps its number and old clients
## still log in. The server never sends them and they do nothing on the client.
## Also the message contract: everything the server sends in a full scenario has an RPC on
## Net or Net/Play with the same number of arguments (_send only logs a gap once, so a
## server/net drift would otherwise ship silently).

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const PlayScript := preload("res://shared/net_play.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

const V4_RPCS := ["s2c_level_up", "s2c_level_up_seen", "s2c_skills", "s2c_xp"]


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _server(positions: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true # these tests run commands; the gate has its own test
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


func _run(srv: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		srv.test_now += GameConfig.TICK_DT
		t += GameConfig.TICK_DT
		srv._tick_channels(srv.test_now)
		srv._flush_inventories()


## [index in outbox, args] of every `method` sent to `id`.
func _sent(srv: Node, id: int, method: String) -> Array:
	var out: Array = []
	for i in srv.test_outbox.size():
		var m: Array = srv.test_outbox[i]
		if m[0] == id and m[1] == method:
			out.append([i, m[2]])
	return out


func test_v4_rpcs_live_on_play_and_v3_is_frozen() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 4, "v4 or later")
	var play := ProtocolCompat.rpc_names("res://tests/protocol/net_play_v4.gd") # as v4 shipped
	var v3_play := ProtocolCompat.rpc_names("res://tests/protocol/net_play_v3.gd")
	for m in V4_RPCS:
		check(play.has(m), "Play has %s" % m)
		check(not v3_play.has(m), "the frozen v3 Play does not have %s" % m)
	var expected := Array(v3_play) + V4_RPCS
	expected.sort()
	check_eq(Array(play), expected, "v4 Play = v3 Play + the four skills RPCs")
	var net_rpcs := ProtocolCompat.rpc_names("res://shared/net.gd")
	check_eq(net_rpcs, ProtocolCompat.rpc_names("res://tests/protocol/net_v3.gd"), "Net's own RPCs unchanged since v3")
	check_eq(net_rpcs, ProtocolCompat.rpc_names("res://tests/protocol/net_v2.gd"), "and since v2")
	check(FileAccess.file_exists("res://tests/protocol/net_v3.gd"), "net_v3.gd frozen for the bump")


func test_retired_v4_rpcs_do_nothing() -> void:
	var net: Node = NetScript.new()
	net._ready()
	for sig in ["skills_changed", "xp_gained", "level_up", "level_up_seen"]:
		check(not net.has_signal(sig), "Net has no %s signal any more" % sig)
	net.play.s2c_skills({"felling": 10})
	net.play.s2c_xp("felling", 10, 160)
	net.play.s2c_level_up("felling", 2, [])
	net.play.s2c_level_up_seen(7, "quarrying", 5)
	check(true, "an old server's skills messages are swallowed without error")
	net.free()


func test_gathering_and_crafting_send_no_skills_messages() -> void:
	var pine := _first("pine")
	var p: Vector3 = pine.pos
	var srv := _server({1: p, 2: p + Vector3(20, 0, 0)})
	srv.sessions[1].character.skills = {"felling": 145, "old_skill": 9}
	srv._send_world_state(1)
	for i in 3:
		check(srv.gather_request(1, pine.id).ok, "gather %d starts" % i)
		_run(srv, 2.3)
	srv.sessions[1].character.x = Crafting.workbench_pos().x
	srv.sessions[1].character.z = Crafting.workbench_pos().z
	srv.sessions[1].character.inventory = {"ash_wood": 3, "stone": 2}
	check(srv.craft_request(1, "stone_axe").ok, "crafts")
	for m in srv.test_outbox:
		check(not str(m[1]) in V4_RPCS, "never sends %s" % m[1])
	check_eq(srv.sessions[1].character.skills, {"felling": 145, "old_skill": 9}, "old XP kept exactly, nothing earned")
	srv.free()


## Argument count of every RPC on Net and Net/Play, by name.
func _rpc_arities() -> Dictionary:
	var out := {}
	for script in [NetScript, PlayScript]:
		var path: String = script.resource_path
		var names := ProtocolCompat.rpc_names(path)
		for m in script.get_script_method_list():
			if names.has(m.name):
				out[m.name] = m.args.size()
	return out


func test_every_message_the_server_sends_has_a_matching_rpc() -> void:
	var pine := _first("pine")
	var p: Vector3 = pine.pos
	var srv := _server({1: p, 2: p + Vector3(3, 0, 0)})
	srv._send_world_state(1)
	srv._broadcast_world_time()
	srv._reject(2, "test")
	srv._on_chat(2, "hello there")
	srv.test_now += 5.0
	srv._on_chat(2, "/time")
	srv._on_chat(2, "/time") # too fast
	# Gather a pine until it empties (start, done, depletion), one cancel by moving.
	for i in 4:
		srv.gather_request(1, pine.id)
		_run(srv, 2.3)
	srv.gather_request(2, pine.id) # refused: empty
	var stone := _first("stone")
	srv.sessions[2].character.x = stone.pos.x
	srv.sessions[2].character.z = stone.pos.z
	srv.gather_request(2, stone.id)
	_run(srv, 0.3)
	srv.sessions[2].character.x += 2.0
	_run(srv, 0.2)
	srv.gather_request(2, 999999) # no such node
	# Craft at the bench (ok and refused) and a bad recipe id.
	srv.sessions[2].character.x = Crafting.workbench_pos().x
	srv.sessions[2].character.z = Crafting.workbench_pos().z
	srv.sessions[2].character.inventory = {"ash_wood": 3, "stone": 2}
	srv.craft_request(2, "stone_axe")
	srv.craft_request(2, "stone_axe")
	srv.craft_request(2, "no_such_thing")
	# v5: Return to Spawn Meadow (ok, then too soon), and someone joined, so the roster goes out.
	srv._roster_dirty = true
	srv.sessions[2].character.x = 40.0
	srv.sessions[2].character.z = 40.0
	srv.unstuck_request(2)
	srv.unstuck_request(2)
	# The node comes back; a snapshot goes out.
	srv.test_now += 3600.0
	srv._respawn_nodes(srv.test_now)
	srv._tick()
	var arity := _rpc_arities()
	var seen := {}
	for m in srv.test_outbox:
		var method := str(m[1])
		seen[method] = true
		check(arity.has(method), "%s has an RPC on Net or Net/Play" % method)
		if arity.has(method):
			check_eq((m[2] as Array).size(), int(arity[method]), "%s argument count" % method)
	for must in ["s2c_inventory", "s2c_nodes", "s2c_world_time", "s2c_system", "s2c_chat",
			"s2c_gather_begin", "s2c_gather_end", "s2c_gather_result", "s2c_node_state", "s2c_craft_result",
			"s2c_snapshot", "s2c_login_result", "s2c_roster", "s2c_unstuck_result"]:
		check(seen.has(must), "the scenario covered %s (sent: %s)" % [must, seen.keys()])
	for never in V4_RPCS:
		check(not seen.has(never), "the retired %s is never sent" % never)
	srv.free()

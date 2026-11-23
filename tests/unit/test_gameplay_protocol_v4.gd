extends TestCase
## Protocol v4 (Milestone 1, part 2): skills and XP reach the client. s2c_skills after login,
## s2c_xp right after each gather or craft result, s2c_level_up (with the unlocks reached) to
## the player and s2c_level_up_seen to everyone else in view. All four RPCs live on Net/Play,
## so Net's own RPC numbering (and every old client's "please update") is unchanged.
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


func _index_of_line(srv: Node, id: int, prefix: String) -> int:
	for e in _sent(srv, id, "s2c_system"):
		if str(e[1][0]).begins_with(prefix):
			return int(e[0])
	return -1


func test_v4_rpcs_live_on_play_and_v3_is_frozen() -> void:
	check_eq(GameConfig.PROTOCOL_VERSION, 4)
	var play := ProtocolCompat.rpc_names("res://shared/net_play.gd")
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


func test_v4_rpcs_reemit_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.skills_changed.connect(func(sk): got.append(["skills", sk]))
	net.xp_gained.connect(func(s, g, t): got.append(["xp", s, g, t]))
	net.level_up.connect(func(s, l, u): got.append(["up", s, l, u]))
	net.level_up_seen.connect(func(p, s, l): got.append(["seen", p, s, l]))
	net.play.s2c_skills({"felling": 10})
	net.play.s2c_xp("felling", 10, 160)
	net.play.s2c_level_up("felling", 2, [])
	net.play.s2c_level_up_seen(7, "quarrying", 5)
	check_eq(got, [["skills", {"felling": 10}], ["xp", "felling", 10, 160], ["up", "felling", 2, []], ["seen", 7, "quarrying", 5]])
	net.free()


func test_login_sends_every_skill() -> void:
	var srv := _server({1: Vector3.ZERO})
	srv.sessions[1].character.skills = {"felling": 160, "old_skill": 9}
	srv._send_world_state(1)
	var s := _sent(srv, 1, "s2c_skills")
	check_eq(s.size(), 1, "one s2c_skills at login")
	if s.size() == 1:
		check_eq(s[0][1][0], {"felling": 160, "quarrying": 0, "tapping": 0, "toolcraft": 0},
			"all four skills, untouched ones at 0, unknown ids not sent")
	check_eq(srv.sessions[1].character.skills.get("old_skill"), 9, "the save keeps the unknown id")
	srv.free()


func test_xp_follows_the_gather_result() -> void:
	var pine := _first("pine")
	var srv := _server({1: pine.pos})
	check(srv.gather_request(1, pine.id).ok, "starts")
	_run(srv, 2.2)
	var res := _sent(srv, 1, "s2c_gather_result")
	var xp := _sent(srv, 1, "s2c_xp")
	check_eq(res.size(), 1)
	check_eq(xp.size(), 1, "one s2c_xp per gather")
	if res.size() == 1 and xp.size() == 1:
		check(int(xp[0][0]) > int(res[0][0]), "the XP comes right after the haul")
		check_eq(xp[0][1], ["felling", 10, 10])
	check(_sent(srv, 1, "s2c_level_up").is_empty(), "10 XP is no level-up")
	srv.free()


func test_cancelled_gather_sends_no_xp() -> void:
	var pine := _first("pine")
	var srv := _server({1: pine.pos})
	srv.gather_request(1, pine.id)
	_run(srv, 0.5)
	srv.gather_cancel(1, "stopped")
	_run(srv, 2.0)
	check(_sent(srv, 1, "s2c_xp").is_empty(), "no XP for a cancelled gather")
	srv.free()


func test_level_up_goes_to_the_player_and_the_burst_to_watchers() -> void:
	var pine := _first("pine")
	var p: Vector3 = pine.pos
	var srv := _server({1: p, 2: p + Vector3(20, 0, 0), 3: p + Vector3(GameConfig.VIEW_RANGE + 30.0, 0, 0)})
	srv.sessions[1].character.skills = {"felling": 145}
	srv.gather_request(1, pine.id)
	_run(srv, 2.2)
	var xp := _sent(srv, 1, "s2c_xp")
	var up := _sent(srv, 1, "s2c_level_up")
	check_eq(up.size(), 1, "one s2c_level_up")
	if xp.size() == 1 and up.size() == 1:
		check_eq(up[0][1], ["felling", 2, []], "level 2 has no named unlock")
		check(int(up[0][0]) > int(xp[0][0]), "level-up after the XP that caused it")
		var line := _index_of_line(srv, 1, "Felling is now level 2!")
		check(line > int(up[0][0]), "the system line still follows, for chat")
	var seen := _sent(srv, 2, "s2c_level_up_seen")
	check_eq(seen.size(), 1, "the player in view sees the burst")
	if seen.size() == 1:
		check_eq(seen[0][1], [1, "felling", 2])
	check(_sent(srv, 1, "s2c_level_up_seen").is_empty(), "you get s2c_level_up, not the seen one")
	check(_sent(srv, 3, "s2c_level_up_seen").is_empty(), "a player out of view doesn't")
	check(_sent(srv, 2, "s2c_level_up").is_empty() and _sent(srv, 2, "s2c_xp").is_empty(), "nor anyone else's XP")
	srv.free()


func test_level_up_carries_the_named_unlock() -> void:
	var pine := _first("pine")
	var srv := _server({1: pine.pos})
	srv.sessions[1].character.skills = {"felling": Skills.xp_for_level(5) - 5}
	srv.gather_request(1, pine.id)
	_run(srv, 2.2)
	var up := _sent(srv, 1, "s2c_level_up")
	check_eq(up.size(), 1)
	if up.size() == 1:
		check_eq(up[0][1][1], 5)
		var unlocks: Array = up[0][1][2]
		check_eq(unlocks.size(), 1, "one unlock at Felling 5")
		if unlocks.size() == 1:
			check_eq(unlocks[0].name, "Old ember ash")
			check_eq(int(unlocks[0].level), 5)
			check(unlocks[0].has("text"), "the banner gets the unlock's text")
	srv.free()


func test_craft_sends_toolcraft_xp_after_the_result() -> void:
	var srv := _server({1: Crafting.workbench_pos()})
	srv.sessions[1].character.inventory = {"ash_wood": 3, "stone": 2}
	var r: Dictionary = srv.craft_request(1, "stone_axe")
	check(r.ok, "crafts: %s" % r)
	var res := _sent(srv, 1, "s2c_craft_result")
	var xp := _sent(srv, 1, "s2c_xp")
	check_eq(xp.size(), 1)
	if res.size() == 1 and xp.size() == 1:
		check(int(xp[0][0]) > int(res[0][0]), "XP after the craft result")
		check_eq(xp[0][1][0], "toolcraft")
		check_eq(int(xp[0][1][1]), Skills.craft_xp("stone_axe"))
	srv.test_outbox.clear()
	srv.craft_request(1, "stone_axe")
	check(_sent(srv, 1, "s2c_xp").is_empty(), "a refused craft sends no XP")
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
	srv.sessions[1].character.skills = {"felling": 145}
	srv._send_world_state(1)
	srv._broadcast_world_time()
	srv._reject(2, "test")
	srv._on_chat(2, "hello there")
	srv.test_now += 5.0
	srv._on_chat(2, "/time")
	srv._on_chat(2, "/time") # too fast
	# Gather a pine until it empties (start, done, level-up, depletion), one cancel by moving.
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
	for must in ["s2c_inventory", "s2c_nodes", "s2c_skills", "s2c_world_time", "s2c_system", "s2c_chat",
			"s2c_gather_begin", "s2c_gather_end", "s2c_gather_result", "s2c_node_state", "s2c_craft_result",
			"s2c_xp", "s2c_level_up", "s2c_level_up_seen", "s2c_snapshot", "s2c_login_result"]:
		check(seen.has(must), "the scenario covered %s (sent: %s)" % [must, seen.keys()])
	srv.free()

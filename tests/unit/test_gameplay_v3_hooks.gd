extends TestCase
## The messages protocol v3 carries, produced by the real server functions on a server
## node with no network (messages land in test_outbox) and a fake clock (test_now):
## who sees a gather begin and end, the haul result, one s2c_inventory per tick, node
## depleted / respawned notices sent exactly once, the login world state, c2s_craft's
## answer, and how _send finds (or skips) an RPC.

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")


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
			"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


## Every message `method` sent, as [peer, args].
func _sent(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[1] == method:
			out.append([m[0], m[2]])
	return out


func _peers(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in _sent(srv, method):
		out.append(m[0])
	out.sort()
	return out


func _run(srv: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		srv.test_now += GameConfig.TICK_DT
		t += GameConfig.TICK_DT
		srv._tick_channels(srv.test_now)
		srv._flush_inventories()


func test_players_in_view() -> void:
	var srv := _server({2: Vector3.ZERO, 3: Vector3(GameConfig.VIEW_RANGE - 1.0, 40.0, 0), 4: Vector3(0, 0, GameConfig.VIEW_RANGE + 1.0)})
	srv.sessions[5] = {"logged_in": false, "character": {}, "channel": {}}
	check_eq(srv.players_in_view(Vector3.ZERO), [2, 3], "near ones, height ignored, not the far or the logging-in one")
	srv.free()


func test_gather_begin_and_done_reach_the_audience() -> void:
	var n := _first("pine")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0), 3: n.pos + Vector3(-5.0, 0, 0), 4: n.pos + Vector3(GameConfig.VIEW_RANGE + 10.0, 0, 0)})
	var r: Dictionary = srv.gather_request(2, n.id)
	check(r.ok, "started: %s" % r.reason)
	check_eq(_peers(srv, "s2c_gather_begin"), [2, 3], "gatherer and the player nearby see it start")
	check_eq(_sent(srv, "s2c_gather_begin")[0][1], [2, n.id, 2.0], "begin carries who, which node, how long")
	_run(srv, 2.1)
	check_eq(_peers(srv, "s2c_gather_end"), [2, 3], "both see it end")
	check_eq(_sent(srv, "s2c_gather_end")[0][1], [2, n.id, "done"])
	var res := _sent(srv, "s2c_gather_result")
	check_eq(res.size(), 1, "one haul result")
	check_eq(res[0], [2, ["pine_wood", int(ResourceNodes.kind_info("pine").amount)]], "to the gatherer: item and count")
	var inv := _sent(srv, "s2c_inventory")
	check_eq(inv.size(), 1, "one pack update")
	check_eq(inv[0][0], 2)
	check_eq(inv[0][1][0], {"pine_wood": int(ResourceNodes.kind_info("pine").amount)})
	check(_sent(srv, "s2c_node_state").is_empty(), "a pine with charges left is not announced")
	srv.free()


func test_cancel_and_disconnect_end_for_everyone() -> void:
	var n := _first("pine")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0), 3: n.pos + Vector3(-1.0, 0, 0)})
	check(srv.gather_request(2, n.id).ok, "2 started")
	srv.sessions[2].character.z += 0.8
	_run(srv, GameConfig.TICK_DT)
	var ends := _sent(srv, "s2c_gather_end")
	check_eq(ends.size(), 2, "both told: %s" % [ends])
	check_eq(ends[0][1], [2, n.id, "moved"])
	check(_sent(srv, "s2c_inventory").is_empty(), "a cancel changes no pack")
	check(srv.gather_request(3, n.id).ok, "3 started")
	srv.test_outbox.clear()
	srv.gather_cancel(3, "disconnected")
	check_eq(_peers(srv, "s2c_gather_end"), [2], "only the others hear that a leaver stopped")
	check_eq(_sent(srv, "s2c_gather_end")[0][1], [3, n.id, "disconnected"])
	srv.free()


func test_refused_start_tells_only_the_gatherer() -> void:
	var n := _first("ash")
	var srv := _server({2: n.pos + Vector3(ResourceNodes.GATHER_RANGE + 1.0, 0, 0), 3: n.pos})
	var r: Dictionary = srv.gather_request(2, n.id)
	check_eq(r.reason, "far")
	check_eq(_peers(srv, "s2c_gather_end"), [2], "the refusal is private")
	check_eq(_sent(srv, "s2c_gather_end")[0][1], [2, n.id, "far"])
	check(_peers(srv, "s2c_system") == [2], "with a line saying why")
	check(_sent(srv, "s2c_gather_begin").is_empty(), "nothing began")
	srv.test_outbox.clear()
	check_eq(srv.gather_request(2, -7).reason, "unknown")
	check_eq(_sent(srv, "s2c_system")[0][1][0], "There is nothing to gather there.")
	check_eq(srv.gather_request(99, n.id).reason, "offline", "unknown peer")
	srv.free()


func test_node_depleted_and_respawned_once() -> void:
	var n := _first("pine")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0), 3: Vector3(GameConfig.VIEW_RANGE * 2.0, 0, 0)})
	for i in Gathering.CHARGES.pine:
		check(srv.gather_request(2, n.id).ok, "gather %d started" % i)
		_run(srv, 2.1)
		srv.test_now += Gathering.COOLDOWN
	var states := _sent(srv, "s2c_node_state")
	check_eq(_peers(srv, "s2c_node_state"), [2, 3], "everyone online hears it emptied, near or far")
	check_eq(states[0][1], [n.id, true])
	# Login while it is empty: the newcomer gets the pack and the empty node list.
	srv.test_outbox.clear()
	srv._send_world_state(3)
	check_eq(_sent(srv, "s2c_nodes")[0][1], [[n.id]], "login: depleted ids")
	check_eq(_sent(srv, "s2c_inventory")[0][1], [{}], "login: the (empty) pack")
	# Comes back: one notice from the sweep, none from later calls.
	srv.test_outbox.clear()
	srv.test_now += float(ResourceNodes.kind_info("pine").respawn) + 1.0
	check_eq(srv._respawn_nodes(srv.test_now), [n.id])
	check_eq(srv._respawn_nodes(srv.test_now), [], "already back")
	srv.gather(2, "pine") # gather paths share the same sweep
	var back := _sent(srv, "s2c_node_state")
	check_eq(back.size(), 2, "announced once per player: %s" % [back])
	check_eq(back[0][1], [n.id, false])
	srv.free()


func test_instant_gather_also_updates_pack_and_nodes() -> void:
	var n := _first("ash")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0)})
	check(srv.gather(2, "ash").begins_with("You gather"), "dev /gather works")
	srv._flush_inventories()
	srv._flush_inventories()
	check_eq(_sent(srv, "s2c_inventory").size(), 1, "one update, not one per flush")
	srv.free()


func test_craft_request() -> void:
	var bench := Crafting.workbench_pos()
	var srv := _server({2: bench + Vector3(1.0, 0, 0)})
	var r: Dictionary = srv.craft_request(2, "banana")
	check(not r.ok and r.reason == "unknown", "unknown id")
	check_eq(_sent(srv, "s2c_craft_result")[0][1], ["banana", false, "You don't know how to make that."])
	check_eq(srv.craft_request(2, "axe").reason, "unknown", "only exact ids, no word guessing")
	check_eq(srv.craft_request(2, "stone_axe").reason, "missing", "nothing in the pack")
	var needs: Dictionary = Crafting.RECIPES.stone_axe.needs
	for item in needs:
		srv.sessions[2].character.inventory[item] = int(needs[item])
	srv.test_outbox.clear()
	r = srv.craft_request(2, "stone_axe")
	check(r.ok, "crafted: %s" % r.text)
	var res := _sent(srv, "s2c_craft_result")
	check(res.size() == 1 and res[0][1][0] == "stone_axe" and res[0][1][1] == true, "ok result: %s" % [res])
	srv._flush_inventories()
	var inv := _sent(srv, "s2c_inventory")
	check_eq(inv.size(), 1, "several take/give in one craft make one pack update")
	check_eq(inv[0][1][0], {"stone_axe": 1})
	check_eq(srv.craft_request(99, "stone_axe").reason, "offline")
	srv.free()


func test_send_routes_to_net_or_child_and_skips_unknown() -> void:
	var srv: Node = ServerScript.new()
	var net: Node = NetScript.new()
	srv.net = net
	check(srv._rpc_node(&"s2c_system") == net, "v2 RPCs live on Net")
	check(srv._rpc_node(&"s2c_gather_begin") == null, "Play only exists once Net is ready")
	net._ready() # what entering the tree does: creates Net/Play
	check(srv._rpc_node(&"s2c_gather_begin") == net.play, "v3 RPCs are found on Net/Play")
	srv._send(2, &"s2c_not_a_message", [1, true]) # in no protocol: skipped, logged once
	check(srv._not_in_protocol.has(&"s2c_not_a_message"), "noted as not sent")
	check(srv.test_outbox.is_empty(), "nothing captured with a real net")
	srv.net = null
	net.free()
	srv.free()


func test_wire_inventory() -> void:
	check_eq(Inventory.to_wire({}), {})
	check_eq(Inventory.to_wire({"stone": 3, "ash_wood": 0, "pine_wood": 2}).keys(), Inventory.held({"stone": 3, "pine_wood": 2}), "held items only, in held() order")

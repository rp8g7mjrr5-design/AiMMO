extends TestCase
## The timed gather: GatherChannel's rules, and the real server functions that run them
## (gather_start, gather_cancel, _tick_channels) on a server node with no network, a fake
## clock (test_now) and messages captured in test_outbox.

const ServerScript := preload("res://server/server.gd")


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


## A server with players logged in at `positions` (peer id -> Vector3), no network.
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
			"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0}
	return srv


func _texts(srv: Node, id: int) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == "s2c_system":
			out.append(str(m[2][0]))
	return out


## Runs the server's channel tick until `seconds` of fake time have passed.
func _run(srv: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		srv.test_now += GameConfig.TICK_DT
		t += GameConfig.TICK_DT
		srv._tick_channels(srv.test_now)


func _move(srv: Node, id: int, offset: Vector3) -> void:
	var ch: Dictionary = srv.sessions[id].character
	ch.x += offset.x
	ch.z += offset.z


func test_seconds_per_kind_and_tools() -> void:
	check_eq(GatherChannel.seconds_for("pine", {}), 2.0)
	check_eq(GatherChannel.seconds_for("stone", {}), 2.4)
	check_eq(GatherChannel.seconds_for("ember_sap", {}), 1.6)
	check_eq(GatherChannel.seconds_for("mystery", {}), GatherChannel.DEFAULT_SECONDS)
	check_near(GatherChannel.seconds_for("pine", {"stone_axe": 1}), 2.0 * Gathering.TOOL_SPEED, 0.0001, "axe speeds wood")
	check_near(GatherChannel.seconds_for("stone", {"stone_axe": 1}), 2.4, 0.0001, "axe does nothing for rock")
	check_near(GatherChannel.seconds_for("stone", {"stone_pickaxe": 1}), 2.4 * Gathering.TOOL_SPEED, 0.0001)
	for kind in ResourceNodes.KINDS:
		check(GatherChannel.SECONDS.has(kind), "a duration for every node kind: %s" % kind)


func test_channel_rules() -> void:
	var n := _first("ash")
	var pos: Vector3 = n.pos + Vector3(1.0, 0, 0)
	var ch := GatherChannel.start(n.id, pos, 10.0, 2.0)
	check(GatherChannel.is_active(ch), "active")
	check(not GatherChannel.is_active({}), "empty is idle")
	check(not GatherChannel.is_due(ch, 11.9), "not due early")
	check(GatherChannel.is_due(ch, 12.0), "due on time")
	check_near(GatherChannel.progress(ch, 11.0), 0.5, 0.0001)
	check_near(GatherChannel.progress(ch, 20.0), 1.0, 0.0001, "clamped")
	check_eq(GatherChannel.cancel_reason(ch, pos), "")
	check_eq(GatherChannel.cancel_reason(ch, pos + Vector3(0.3, 5.0, 0.3)), "", "small drift and height don't count")
	check_eq(GatherChannel.cancel_reason(ch, pos + Vector3(0, 0, 0.6)), "moved")
	var edge := GatherChannel.start(n.id, n.pos + Vector3(ResourceNodes.GATHER_RANGE + 0.2, 0, 0), 10.0, 2.0)
	check_eq(GatherChannel.cancel_reason(edge, edge.from), "far", "out of reach without moving")
	check(GatherChannel.begin_text(n.id, 2.0).begins_with("You start gathering the "), "begin text")
	check(GatherChannel.cancel_text("moved").begins_with("You stop gathering"), "cancel text")


func test_start_then_complete() -> void:
	var n := _first("pine")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0)})
	var r: Dictionary = srv.gather_start(2, n.id)
	check(r.ok, "started: %s" % r.reason)
	check_eq(r.seconds, 2.0)
	check(GatherChannel.is_active(srv.sessions[2].channel), "channel running")
	check_eq(Inventory.count(srv.sessions[2].character.inventory, "pine_wood"), 0, "nothing before the end")
	check_eq(srv.gather_start(2, n.id).reason, "busy", "one gather at a time")
	check(srv.gather(2, "pine").begins_with("Easy;"), "instant /gather refused while channelling")
	_run(srv, 1.9)
	check_eq(Inventory.count(srv.sessions[2].character.inventory, "pine_wood"), 0, "still nothing at 1.9 s")
	_run(srv, 0.2)
	check(not GatherChannel.is_active(srv.sessions[2].channel), "channel over")
	var got := Inventory.count(srv.sessions[2].character.inventory, "pine_wood")
	check_eq(got, int(ResourceNodes.kind_info("pine").amount), "pack filled at the end")
	check_eq(Gathering.charges_left(srv.gathering, n.id, srv.test_now), Gathering.CHARGES.pine - 1, "one charge used")
	var texts := _texts(srv, 2)
	check(texts.size() == 2 and texts[0].begins_with("You start gathering") and texts[1].begins_with("You gather"), "begin then success: %s" % [texts])
	var again: Dictionary = srv.gather_start(2, n.id)
	check(again.ok, "the next gather starts at once: the bar is the pacing, no dead time (%s)" % again.reason)
	check_eq(srv.gather_start(2, n.id).reason, "busy", "but only one at a time")
	srv.free()


func test_cancel_by_moving_costs_nothing() -> void:
	var n := _first("stone")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0)})
	check(srv.gather_start(2, n.id).ok, "started")
	_run(srv, 1.0)
	_move(srv, 2, Vector3(0.0, 0, 0.8))
	_run(srv, GameConfig.TICK_DT)
	check(not GatherChannel.is_active(srv.sessions[2].channel), "cancelled")
	check_eq(Inventory.total(srv.sessions[2].character.inventory), 0, "nothing given")
	check_eq(Gathering.charges_left(srv.gathering, n.id, srv.test_now), Gathering.CHARGES.stone, "no charge used")
	check_eq(srv.sessions[2].last_gather, -1000.0, "no cooldown spent")
	check(_texts(srv, 2).back() == GatherChannel.cancel_text("moved"), "told why: %s" % [_texts(srv, 2)])
	check(srv.gather_start(2, n.id).ok, "can start again right away")
	srv.free()


func test_cancel_on_request_and_disconnect() -> void:
	var n := _first("ash")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0), 3: n.pos + Vector3(-1.0, 0, 0)})
	check(srv.gather_start(2, n.id).ok, "2 started")
	srv.gather_cancel(2, "stopped")
	check(not GatherChannel.is_active(srv.sessions[2].channel), "stopped on request")
	check_eq(_texts(srv, 2).back(), GatherChannel.cancel_text("stopped"))
	check(srv.gather_start(3, n.id).ok, "3 started")
	srv.test_outbox.clear()
	srv.gather_cancel(3, "disconnected")
	check(not GatherChannel.is_active(srv.sessions[3].channel), "cleared on disconnect")
	check(_texts(srv, 3).is_empty(), "nothing sent to a peer that is gone")
	check_eq(Gathering.charges_left(srv.gathering, n.id, srv.test_now), Gathering.CHARGES.ash, "no charges used")
	srv.gather_cancel(3, "stopped") # nothing running: no-op
	check(_texts(srv, 3).is_empty(), "cancelling nothing says nothing")
	srv.free()


func test_contested_node() -> void:
	# A pine has 3 charges. Three players finish on it first, a fourth was still gathering
	# when it emptied: they get nothing, no charge, no cooldown, and are told it is spent.
	var n := _first("pine")
	var spots := {}
	for i in 4:
		spots[2 + i] = n.pos + Vector3(cos(i * 1.5), 0, sin(i * 1.5))
	var srv := _server(spots)
	for id in [2, 3, 4]:
		check(srv.gather_start(id, n.id).ok, "%d started" % id)
	_run(srv, 1.0)
	check(srv.gather_start(5, n.id).ok, "5 started a second later")
	_run(srv, 1.2)
	check(Gathering.is_depleted(srv.gathering, n.id, srv.test_now), "emptied by the first three")
	_run(srv, 1.0)
	for id in [2, 3, 4]:
		check(Inventory.count(srv.sessions[id].character.inventory, "pine_wood") > 0, "%d got wood" % id)
	check_eq(Inventory.total(srv.sessions[5].character.inventory), 0, "5 got nothing")
	check_eq(srv.sessions[5].last_gather, -1000.0, "5 spent no cooldown")
	check(not GatherChannel.is_active(srv.sessions[5].channel), "5's gather ended")
	check(_texts(srv, 5).back().begins_with("This pine is spent"), "5 told: %s" % [_texts(srv, 5)])
	check_eq(srv.gather_start(5, n.id).reason, "depleted", "and can't start again")
	srv.free()


func test_start_refusals() -> void:
	var n := _first("stone")
	var srv := _server({2: n.pos + Vector3(ResourceNodes.GATHER_RANGE + 1.0, 0, 0), 3: n.pos})
	check_eq(srv.gather_start(2, n.id).reason, "far")
	check_eq(srv.gather_start(2, -5).reason, "unknown")
	check_eq(srv.gather_start(99, n.id).reason, "offline")
	srv.sessions[3].character.inventory["stone"] = Inventory.MAX_STACK
	check_eq(srv.gather_start(3, n.id).reason, "full", "a full stack never starts")
	srv.free()


func test_channel_command_routing() -> void:
	check(ChatCommands.is_channel("/channel"), "/channel")
	check(ChatCommands.is_channel("/Channel stop"), "case-insensitive")
	check(not ChatCommands.is_channel("/gather"), "not /gather")
	check(not ChatCommands.HELP.contains("/channel"), "hidden from /help (chat is for talking)")
	var n := _first("ash")
	var srv := _server({2: n.pos + Vector3(1.0, 0, 0)})
	srv._channel_command(2, "")
	check(GatherChannel.is_active(srv.sessions[2].channel), "/channel starts on the node in reach")
	srv._channel_command(2, "")
	check(_texts(srv, 2).back().begins_with("Easy;"), "second /channel while busy")
	srv._channel_command(2, "stop")
	check(not GatherChannel.is_active(srv.sessions[2].channel), "/channel stop")
	srv._channel_command(2, "stop")
	check_eq(_texts(srv, 2).back(), "You are not gathering.")
	srv._channel_command(2, "banana")
	check(_texts(srv, 2).back().begins_with("Gather what?"), "unknown kind")
	srv.free()

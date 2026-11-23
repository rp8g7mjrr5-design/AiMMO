extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (qa): real gathering (protocol v3) never loses or invents an item, and every
## client sees the same nodes. Works next to gameplay_gather_v3 (which does the gathering);
## this one only watches, except in probe mode.
##
## On every bot:
##   - the pack across a reconnect: the first s2c_inventory after logging back in must equal
##     the last one before the disconnect (only a gather of ours finishing in the last
##     moments before the hang-up may explain a difference; see GatherLedger);
##   - the final pack goes into the stats as `final_pack`, and run_bot_test.py checks the
##     saved character holds exactly that (verify_store.gd), so the server's count, the
##     client's count and the database agree;
##   - nodes: the empty set from s2c_nodes / s2c_node_state; nobody may *start* gathering a
##     node this client shows empty (a desync between clients). Emptied nodes are reported
##     (`depleted`, with wall-clock times) so the harness can check one comes back;
##   - two players on one node at once (`shared_node_max`, from s2c_gather_begin/end);
##   - skills (Milestone 1): the least XP this bot is known to have in each skill, from the
##     login character and every "<Skill> is now level N!" line, goes into the stats as
##     `skills_floor`; verify_store.gd checks the saved character holds at least that, so a
##     level-up is never lost on logout.
##
## Probe mode (`--gather-probe=<node> --probe-due=<unix time>`, started by run_bot_test.py
## after the 8 bots, with --only-behaviour=qa_gather_ledger): a fresh player logs in while
## that node is still empty, must see it empty, must hear s2c_node_state(node, false) when it
## respawns, walks there, gathers it with c2s_gather_start, gets paid, and after a reconnect
## still sees it full.
##
## Pair mode (`--gather-pair=lead [--pair-avoid=<node>]` on one fresh bot and
## `--gather-pair=follow --pair-leader=<leader name>` on another, started by run_bot_test.py
## with the respawn probe): two players gather one node at the same time, on purpose rather
## than by luck. The leader walks to the live node nearest spawn and waits there; the follower
## waits until the leader stands still at a node, walks to the same one; each starts
## c2s_gather_start once the other player is in reach, so both channels overlap. Each must
## see two gatherers on that node (`shared_node_max` 2) and its own gather end "done", or
## "depleted" when the other's finish took the node's last charge.

const GatherLedger := preload("res://tests/bot_test/gather_ledger.gd")

const STOP_AT := 1.2
const SETTLE := 0.5
const RESPAWN_SLACK := 6.0 ## s2c_node_state(false) must arrive within this of the due time
const WALK_TIMEOUT := 25.0
const ANSWER_TIMEOUT := 3.0
const END_SLACK := 2.5

enum Probe { OFF, WAIT_RESPAWN, GOTO, START, RUNNING, DONE }
enum Pair { OFF, PICK, GOTO, WAIT_PARTNER, START, RUNNING, DONE }

const PAIR_PICK_TIMEOUT := 30.0 ## leader: s2c_nodes at login; follower: the leader settles at a node
const PAIR_PARTNER_TIMEOUT := 30.0 ## at the node, waiting for the other player to come into reach
const PAIR_STILL := 0.8 ## the follower trusts the leader's node once it has stood still this long

var _pack: Dictionary = {}
var _skills_floor: Dictionary = {} ## skill -> least XP we know this character has
var _have_pack := false
var _check_pack_at_login := false
var _pack_at_close: Dictionary = {}
var _running_at_close := -1
var _mine_running := -1
var _empty := {}
var _channels := {} ## peer -> node id, from s2c_gather_begin/end
var depleted: Array = [] ## [node_id, unix time, respawn seconds, night_only]
var respawned: Array = []
var shared_node_max := 0
var reconnect_checks := 0
var in_flight_payouts := 0
var my_done := 0

var _probe_node := -1
var _probe_due := 0.0
var _probe := Probe.OFF
var _probe_since := 0.0
var _probe_next := 0.0
var _probe_ends_by := 0.0
var _probe_pack_before := 0
var _probe_item := ""
var _probe_saw_empty := false
var _probe_saw_back := false
var _probe_paid := false
var _probe_logins := 0

var _pair := Pair.OFF
var _pair_role := ""
var _pair_avoid: Array = []
var _pair_leader_name := ""
var _pair_leader_peer := -1
var _pair_node := -1
var _pair_since := 0.0
var _pair_next := 0.0
var _pair_ends_by := 0.0
var _pair_together := false
var _pair_end := ""
var _pair_leader_pos := Vector3.INF
var _pair_leader_still_since := 0.0
var _nodes_seen := false
var _others_pos := {} ## peer -> position, from snapshots


func setup(net: Node) -> void:
	net.inventory_changed.connect(_on_inventory)
	net.nodes_depleted.connect(_on_nodes)
	net.node_state.connect(_on_node_state)
	net.gather_begun.connect(_on_begun)
	net.gather_ended.connect(_on_ended)
	net.system_message.connect(_on_system_skills)
	net.player_left.connect(func(id: int):
		_channels.erase(id)
		_others_pos.erase(id))
	net.player_joined.connect(_on_joined)
	var args: Dictionary = bot.args if "args" in bot else {}
	if args.has("gather-probe"):
		_probe_node = int(args["gather-probe"])
		_probe_due = float(args.get("probe-due", "0"))
		_probe = Probe.WAIT_RESPAWN
		# Stay on the first login until the gather is done (the probe then reconnects).
		bot.disconnect_at = float(bot.duration) - 6.0
	if args.has("gather-pair"):
		_pair_role = str(args["gather-pair"])
		if _pair_role not in ["lead", "follow"]:
			fail("--gather-pair must be lead or follow, got %s" % _pair_role)
			_pair_role = ""
		else:
			for part in str(args.get("pair-avoid", "")).split(",", false):
				_pair_avoid.append(int(part))
			_pair_leader_name = str(args.get("pair-leader", ""))
			if _pair_role == "follow" and _pair_leader_name == "":
				fail("--gather-pair=follow needs --pair-leader=<name>")
			_pair = Pair.PICK
			bot.disconnect_at = float(bot.duration) - 6.0


func _on_joined(id: int, player_name: String, _seed: int) -> void:
	if player_name == _pair_leader_name:
		_pair_leader_peer = id


func on_snapshot(_tick: int, entries: Array) -> void:
	var i := 0
	while i + 4 < entries.size():
		var id := int(entries[i])
		if id != int(bot.my_id):
			_others_pos[id] = Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
		i += 5


func on_login(reconnect: bool, character: Dictionary) -> void:
	var sk := Skills.normalize(character.get("skills", {}))
	for id in sk:
		_skills_floor[id] = maxi(int(_skills_floor.get(id, 0)), int(sk[id]))
	_channels.clear()
	_empty.clear()
	_others_pos.clear()
	_nodes_seen = false
	if _pair != Pair.OFF and _pair != Pair.DONE and reconnect:
		fail("pair: reconnected before the shared gather was done (state %s)" % Pair.keys()[_pair])
		_pair = Pair.DONE
	_pair_since = bot.elapsed
	_probe_logins += 1
	if reconnect:
		_check_pack_at_login = _have_pack
		_pack_at_close = _pack.duplicate()
		_running_at_close = _mine_running
	_mine_running = -1
	_have_pack = false


## "Felling is now level 2! ..." means at least the XP that level starts at.
func _on_system_skills(text: String) -> void:
	var lv := RegEx.create_from_string("^(\\w+) is now level (\\d+)!").search(text)
	if lv == null:
		return
	var id := lv.get_string(1).to_lower()
	if Skills.is_skill(id):
		_skills_floor[id] = maxi(int(_skills_floor.get(id, 0)), Skills.xp_for_level(lv.get_string(2).to_int()))


func _on_inventory(items: Dictionary) -> void:
	var pack := Inventory.normalize(items)
	if _check_pack_at_login:
		_check_pack_at_login = false
		reconnect_checks += 1
		var why := GatherLedger.reconnect_problem(_pack_at_close, pack, _running_at_close, _amount_of(_running_at_close))
		if why == "in_flight":
			in_flight_payouts += 1
		elif why != "":
			fail("pack changed across the reconnect: %s (before %s, after %s)" % [why, _pack_at_close, pack])
	_pack = pack
	_have_pack = true


## Items one gather of node `node_id` gives (0 for no node).
func _amount_of(node_id: int) -> int:
	if node_id < 0:
		return 0
	return int(ResourceNodes.kind_info(str(ResourceNodes.get_by_id(node_id).kind)).get("amount", 0))


func _on_nodes(ids: Array) -> void:
	_empty.clear()
	for id in ids:
		_empty[int(id)] = true
	_nodes_seen = true
	if _probe != Probe.OFF:
		var listed := _empty.has(_probe_node)
		var now := Time.get_unix_time_from_system()
		if _probe_logins == 1:
			if listed:
				_probe_saw_empty = true
			elif now < _probe_due - 1.0:
				fail("probe: node %d is not shown empty at login, %.1f s before it should respawn" % [_probe_node, _probe_due - now])
		elif listed:
			fail("probe: node %d shown empty again after the reconnect (we took one charge)" % _probe_node)


func _on_node_state(node_id: int, is_depleted: bool) -> void:
	if is_depleted:
		_empty[node_id] = true
		var info := ResourceNodes.kind_info(str(ResourceNodes.get_by_id(node_id).get("kind", "")))
		depleted.append([node_id, Time.get_unix_time_from_system(), float(info.get("respawn", 0.0)), bool(info.get("night_only", false))])
	else:
		_empty.erase(node_id)
		respawned.append(node_id)
		if node_id == _probe_node and _probe == Probe.WAIT_RESPAWN:
			_probe_saw_back = true
			_probe = Probe.GOTO
			_probe_since = bot.elapsed


func _on_begun(peer: int, node_id: int, seconds: float) -> void:
	if _empty.has(node_id):
		fail("peer %d started gathering node %d, which this client shows empty" % [peer, node_id])
	_channels[peer] = node_id
	shared_node_max = maxi(shared_node_max, GatherLedger.gatherers_on(_channels, node_id))
	if node_id == _pair_node and _pair in [Pair.START, Pair.RUNNING] and GatherLedger.gatherers_on(_channels, node_id) >= 2:
		_pair_together = true
	if peer == int(bot.my_id) and _pair == Pair.START and node_id == _pair_node:
		_pair = Pair.RUNNING
		_pair_ends_by = bot.elapsed + seconds + END_SLACK
	if peer == int(bot.my_id):
		_mine_running = node_id
		if _probe == Probe.START and node_id == _probe_node:
			_probe = Probe.RUNNING
			_probe_ends_by = bot.elapsed + seconds + END_SLACK


func _on_ended(peer: int, node_id: int, reason: String) -> void:
	_channels.erase(peer)
	if peer != int(bot.my_id):
		return
	_mine_running = -1
	if reason == "done":
		my_done += 1
	if node_id == _pair_node and _pair in [Pair.START, Pair.RUNNING]:
		_pair_end = reason
		_pair = Pair.DONE
		if reason not in ["done", "depleted"]:
			fail("pair: my gather on the shared node %d ended '%s'" % [node_id, reason])
		bot.disconnect_at = bot.elapsed + 1.5
		return
	if node_id != _probe_node or _probe not in [Probe.START, Probe.RUNNING]:
		return
	if reason == "done":
		_probe = Probe.DONE
		_probe_paid = true
		var item := _probe_item
		var before := _probe_pack_before
		bot.get_tree().create_timer(1.0).timeout.connect(func():
			if int(_pack.get(item, 0)) <= before:
				fail("probe: gathered the respawned node but the pack has no more %s" % item))
		bot.disconnect_at = bot.elapsed + 1.5
	else:
		fail("probe: gather on respawned node %d ended '%s'" % [node_id, reason])
		_probe = Probe.DONE


func on_play(delta: float) -> void:
	if _pair != Pair.OFF:
		_play_pair(delta)
	match _probe:
		Probe.WAIT_RESPAWN:
			bot.move = Vector2.ZERO
			if Time.get_unix_time_from_system() > _probe_due + RESPAWN_SLACK:
				fail("probe: node %d never came back (due %.1f s ago)" % [_probe_node, Time.get_unix_time_from_system() - _probe_due])
				_probe = Probe.DONE
		Probe.GOTO:
			var off: Vector3 = ResourceNodes.get_by_id(_probe_node).pos - bot.my_pos
			var flat := Vector2(off.x, off.z)
			if bot.elapsed - _probe_since > WALK_TIMEOUT:
				fail("probe: could not walk to node %d (%.1f m left)" % [_probe_node, flat.length()])
				_probe = Probe.DONE
			elif flat.length() > STOP_AT:
				bot.move = flat.normalized()
				bot.yaw = atan2(bot.move.x, bot.move.y)
			else:
				bot.move = Vector2.ZERO
				_probe = Probe.START
				_probe_next = bot.elapsed + SETTLE
				_probe_ends_by = INF
		Probe.START:
			bot.move = Vector2.ZERO
			if _probe_next > 0.0 and bot.elapsed >= _probe_next:
				_probe_next = 0.0
				_probe_item = str(ResourceNodes.kind_info(str(ResourceNodes.get_by_id(_probe_node).kind)).item)
				_probe_pack_before = int(_pack.get(_probe_item, 0))
				_probe_ends_by = bot.elapsed + ANSWER_TIMEOUT
				bot.net.play.c2s_gather_start.rpc_id(1, _probe_node)
			elif bot.elapsed > _probe_ends_by:
				fail("probe: c2s_gather_start(%d) was never answered" % _probe_node)
				_probe = Probe.DONE
		Probe.RUNNING:
			bot.move = Vector2.ZERO
			if bot.elapsed > _probe_ends_by:
				fail("probe: gather on node %d never ended" % _probe_node)
				_probe = Probe.DONE
		Probe.DONE:
			pass


## Pair mode, one frame. See the header.
func _play_pair(delta: float) -> void:
	match _pair:
		Pair.PICK:
			bot.move = Vector2.ZERO
			if _pair_role == "lead":
				if _nodes_seen:
					_pair_node = GatherLedger.pair_node(_empty, _pair_avoid, GameConfig.SPAWN_POINT)
					if _pair_node < 0:
						fail("pair: no live node to gather together")
						_pair = Pair.DONE
						return
					_pair = Pair.GOTO
					_pair_since = bot.elapsed
			elif _others_pos.has(_pair_leader_peer):
				var at: Vector3 = _others_pos[_pair_leader_peer]
				if _pair_leader_pos == Vector3.INF or at.distance_to(_pair_leader_pos) > 0.05:
					_pair_leader_pos = at
					_pair_leader_still_since = bot.elapsed
				elif bot.elapsed - _pair_leader_still_since >= PAIR_STILL:
					var id := GatherLedger.node_at(at, STOP_AT + 0.6)
					if id >= 0 and not _empty.has(id):
						_pair_node = id
						_pair = Pair.GOTO
						_pair_since = bot.elapsed
			if _pair == Pair.PICK and bot.elapsed - _pair_since > PAIR_PICK_TIMEOUT:
				fail("pair (%s): no node picked after %.0f s (leader peer %d)" % [_pair_role, PAIR_PICK_TIMEOUT, _pair_leader_peer])
				_pair = Pair.DONE
		Pair.GOTO:
			var off: Vector3 = ResourceNodes.get_by_id(_pair_node).pos - bot.my_pos
			var flat := Vector2(off.x, off.z)
			if bot.elapsed - _pair_since > WALK_TIMEOUT:
				fail("pair: could not walk to node %d (%.1f m left)" % [_pair_node, flat.length()])
				_pair = Pair.DONE
			elif flat.length() > STOP_AT:
				bot.move = flat.normalized()
				bot.yaw = atan2(bot.move.x, bot.move.y)
			else:
				bot.move = Vector2.ZERO
				_pair = Pair.WAIT_PARTNER
				_pair_since = bot.elapsed
		Pair.WAIT_PARTNER:
			bot.move = Vector2.ZERO
			var node_pos: Vector3 = ResourceNodes.get_by_id(_pair_node).pos
			var partner_in_reach := false
			for peer in _others_pos:
				var p: Vector3 = _others_pos[peer]
				if Vector2(p.x - node_pos.x, p.z - node_pos.z).length() <= ResourceNodes.GATHER_RANGE - 0.3:
					partner_in_reach = true
			if partner_in_reach:
				_pair = Pair.START
				_pair_next = bot.elapsed + SETTLE
				_pair_ends_by = INF
			elif bot.elapsed - _pair_since > PAIR_PARTNER_TIMEOUT:
				fail("pair: nobody else came to node %d within %.0f s" % [_pair_node, PAIR_PARTNER_TIMEOUT])
				_pair = Pair.DONE
		Pair.START:
			bot.move = Vector2.ZERO
			if _pair_next > 0.0 and bot.elapsed >= _pair_next:
				_pair_next = 0.0
				_pair_ends_by = bot.elapsed + ANSWER_TIMEOUT
				bot.net.play.c2s_gather_start.rpc_id(1, _pair_node)
			elif bot.elapsed > _pair_ends_by:
				fail("pair: c2s_gather_start(%d) was never answered" % _pair_node)
				_pair = Pair.DONE
		Pair.RUNNING:
			bot.move = Vector2.ZERO
			if bot.elapsed > _pair_ends_by:
				fail("pair: gather on node %d never ended" % _pair_node)
				_pair = Pair.DONE
		Pair.DONE:
			pass


func on_finish() -> void:
	stat("final_pack", _pack)
	stat("skills_floor", _skills_floor)
	stat("running_node", _mine_running)
	stat("running_amount", _amount_of(_mine_running))
	stat("depleted", depleted)
	stat("respawned", respawned)
	stat("shared_node_max", shared_node_max)
	stat("reconnect_checks", reconnect_checks)
	stat("in_flight_payouts", in_flight_payouts)
	stat("my_done", my_done)
	if _probe_node >= 0:
		stat("probe", {"node": _probe_node, "saw_empty": _probe_saw_empty, "saw_back": _probe_saw_back, "paid": _probe_paid})
		if not _probe_saw_empty:
			fail("probe: never saw node %d empty at login" % _probe_node)
		if not _probe_paid:
			fail("probe: never gathered the respawned node %d" % _probe_node)
	if _pair_role != "":
		stat("pair", {"role": _pair_role, "node": _pair_node, "together": _pair_together, "end": _pair_end})
		if not _pair_together:
			fail("pair (%s): never saw two players gathering node %d at the same time" % [_pair_role, _pair_node])
	if reconnect_checks == 0 and int(bot.stats.logins) >= 2:
		fail("no s2c_inventory after the reconnect")

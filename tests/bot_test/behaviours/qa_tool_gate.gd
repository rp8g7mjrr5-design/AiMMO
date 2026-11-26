extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (qa): tier-2 nodes refuse bare hands, and only that (no levels, owner
## direction 2026-11-26: the gate is the tool). Acts only on bots started with --tool-gate
## (run_bot_test.py's gate phase, next to the pair check, with --only-behaviour=qa_tool_gate);
## every other bot loads it and does nothing.
##
## `--tool-gate=fresh --gate-node=<id>`: a brand-new player walks to tier-2 node <id> and
## presses E. The server must answer s2c_gather_end(me, node, "tool") and the line "You need
## an axe to work this old ember ash." (or a pickaxe for a seam), never start a bar or pay an
## item. It then stands at the node a while (the veteran waits for that), reconnects, presses
## again and is still refused: a reconnect unlocks nothing.
##
## `--tool-gate=veteran --gate-node=<id> --gate-partner=<fresh bot's name>`: a character
## seeded by seed_veteran.gd with the node's tool and old XP from the retired skills, a few
## metres away. It walks up, waits until the fresh player has stood at the node (and so been
## refused), then works the node until it is empty: every one of its charges must pay, so the
## refusal took none (ToolGate.veteran_problem). After a reconnect it must still carry its
## tool, and the node must still show empty. Its old XP goes into the stats as `old_xp_kept`,
## which run_bot_test.py hands to verify_store.gd: the save must still hold it exactly.

const ToolGate := preload("res://tests/bot_test/tool_gate.gd")

const SETTLE := 0.5
const WALK_TIMEOUT := 40.0
const ANSWER_TIMEOUT := 3.0
const LINE_TIMEOUT := 2.0
const HOLD := 10.0 ## fresh: seconds to stand at the node after the refusal, before hanging up
const PARTNER_STILL := 2.0 ## veteran: the fresh player has stood at the node this long
const PARTNER_TIMEOUT := 60.0
const NEXT_PRESS := 0.6 ## veteran: gap between one gather ending and the next press
const GATHER_TIMEOUT := 8.0 ## veteran: one press must begin and end within this
const AFTER_RECONNECT := 6.0 ## seconds both play after the second login before stopping

enum S { OFF, WAIT_NODES, GOTO, SETTLING, PRESSED, HOLDING, WAIT_PARTNER, GATHERING, BETWEEN, EMPTIED, RECHECK, DONE }

var role := ""
var node_id := -1
var tool := ""
var item := ""
var partner_name := ""
var partner_peer := -1

var _s := S.OFF
var _since := 0.0
var _deadline := INF
var _logins := 0
var _pack: Dictionary = {}
var _pack_before: Dictionary = {}
var _empty := {}
var _nodes_seen := false
var _others := {} ## peer -> position
var _partner_pos := Vector3.INF
var _partner_still_since := 0.0

var refusals := 0 ## "tool" answers to our presses
var lines := 0 ## matching "You need an axe ..." lines
var _line_due := false
var _ended_reason := ""
var dones := 0
var emptied := false
var paid := 0
var _paid_seen := 0 ## veteran: items from s2c_gather_result
var reconnect_ok := false


func setup(net: Node) -> void:
	var args: Dictionary = bot.args if "args" in bot else {}
	if not args.has("tool-gate"):
		return
	role = str(args["tool-gate"])
	node_id = int(args.get("gate-node", "-1"))
	partner_name = str(args.get("gate-partner", ""))
	var node := ResourceNodes.get_by_id(node_id)
	if role not in ["fresh", "veteran"]:
		fail("--tool-gate must be fresh or veteran, got %s" % role)
		role = ""
		return
	if node.is_empty() or not Gathering.needs_tool(node):
		fail("--gate-node=%d is not a tool-gated node" % node_id)
		role = ""
		return
	if role == "veteran" and partner_name == "":
		fail("--tool-gate=veteran needs --gate-partner=<name>")
	tool = str(ToolGate.veteran_pack(node_id).keys()[0])
	item = str(ResourceNodes.info(node).item)
	bot.disconnect_at = float(bot.duration) - 6.0 # we decide when to hang up
	net.inventory_changed.connect(func(items: Dictionary): _pack = Inventory.normalize(items))
	net.nodes_depleted.connect(_on_nodes)
	net.node_state.connect(_on_node_state)
	net.gather_begun.connect(_on_begun)
	net.gather_ended.connect(_on_ended)
	net.gather_result.connect(func(it: String, n: int):
		if it == item:
			_paid_seen += n)
	net.system_message.connect(_on_system)
	net.player_joined.connect(func(id: int, n: String, _seed: int):
		if n == partner_name:
			partner_peer = id)
	net.player_left.connect(func(id: int): _others.erase(id))


func on_login(reconnect: bool, character: Dictionary) -> void:
	if role == "":
		return
	_logins += 1
	_empty.clear()
	_nodes_seen = false
	_others.clear()
	var inv := Inventory.normalize(character.get("inventory", {}))
	var node := ResourceNodes.get_by_id(node_id)
	if role == "veteran":
		if not Gathering.can_work(node, inv):
			fail("veteran logged in without a tool for node %d (pack %s)" % [node_id, inv])
		elif reconnect:
			reconnect_ok = true
	elif Gathering.can_work(node, inv):
		fail("fresh player logged in already carrying a tool for node %d (pack %s)" % [node_id, inv])
	if reconnect:
		# Fresh: stand where we were saved (at the node), let s2c_inventory land, press again.
		_to(S.SETTLING if role == "fresh" else S.RECHECK)
		_deadline = bot.elapsed + 1.0
		bot.duration = bot.elapsed + AFTER_RECONNECT
	else:
		_to(S.WAIT_NODES)


func on_snapshot(_tick: int, entries: Array) -> void:
	if role == "":
		return
	var i := 0
	while i + 4 < entries.size():
		var id := int(entries[i])
		if id != int(bot.my_id):
			_others[id] = Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
		i += 5


func _to(s: S) -> void:
	_s = s
	_since = bot.elapsed


func _on_nodes(ids: Array) -> void:
	_empty.clear()
	for id in ids:
		_empty[int(id)] = true
	_nodes_seen = true


func _on_node_state(id: int, is_depleted: bool) -> void:
	if is_depleted:
		_empty[id] = true
		if id == node_id and role == "veteran" and _s in [S.GATHERING, S.BETWEEN]:
			emptied = true
	else:
		_empty.erase(id)


func _on_begun(peer: int, id: int, _seconds: float) -> void:
	if peer != int(bot.my_id):
		return
	if role == "fresh":
		fail("the server started a gather bar on node %d for a bare-handed player" % id)
	elif role == "veteran" and id == node_id and _s == S.GATHERING:
		_deadline = bot.elapsed + GATHER_TIMEOUT


func _on_ended(peer: int, id: int, reason: String) -> void:
	if peer != int(bot.my_id) or id != node_id:
		return
	_ended_reason = reason
	if role == "fresh":
		if _s not in [S.PRESSED, S.RECHECK]:
			fail("gather on node %d ended '%s' without a press" % [id, reason])
			return
		if reason != "tool":
			fail("pressed E at tier-2 node %d bare-handed, answer '%s', not 'tool'" % [id, reason])
			_to(S.DONE)
			return
		refusals += 1
		_line_due = true
		_deadline = bot.elapsed + LINE_TIMEOUT
	elif role == "veteran" and _s == S.GATHERING:
		if reason == "done":
			dones += 1
			_to(S.BETWEEN)
			_deadline = bot.elapsed + NEXT_PRESS
		else:
			fail("veteran's gather %d on node %d ended '%s'" % [dones + 1, id, reason])
			_to(S.DONE)


func _on_system(text: String) -> void:
	if role == "" or not _line_due:
		return
	if text == ToolGate.refusal_text(node_id):
		lines += 1
		_line_due = false


func _walk_to_node() -> bool:
	var off: Vector3 = ResourceNodes.get_by_id(node_id).pos - bot.my_pos
	var flat := Vector2(off.x, off.z)
	if flat.length() <= ResourceNodes.GATHER_RANGE - 0.6:
		bot.move = Vector2.ZERO
		return true
	bot.move = flat.normalized()
	bot.yaw = atan2(bot.move.x, bot.move.y)
	return false


func on_play(_delta: float) -> void:
	if role == "":
		return
	bot.move = Vector2.ZERO
	if _line_due and bot.elapsed > _deadline and _s != S.DONE:
		fail("no '%s' line after the refusal" % ToolGate.refusal_text(node_id))
		_line_due = false
	match _s:
		S.WAIT_NODES:
			if _nodes_seen:
				if _empty.has(node_id):
					fail("tier-2 node %d is already empty at login" % node_id)
					_to(S.DONE)
				else:
					_to(S.GOTO)
			elif bot.elapsed - _since > 20.0:
				fail("no s2c_nodes after login")
				_to(S.DONE)
		S.GOTO:
			if _walk_to_node():
				_to(S.SETTLING)
				_deadline = bot.elapsed + SETTLE
			elif bot.elapsed - _since > WALK_TIMEOUT:
				fail("could not walk to tier-2 node %d in %.0f s" % [node_id, WALK_TIMEOUT])
				_to(S.DONE)
		S.SETTLING:
			if bot.elapsed >= _deadline:
				if role == "fresh":
					_press(S.PRESSED if _logins < 2 else S.RECHECK)
				else:
					_to(S.WAIT_PARTNER)
		S.PRESSED:
			if refusals >= 1 and not _line_due:
				# Give a stray s2c_inventory a moment to show up before judging the pack.
				if bot.elapsed - _since > 1.0:
					_check_pack_kept()
					_to(S.HOLDING)
					bot.disconnect_at = bot.elapsed + HOLD
			elif refusals == 0 and bot.elapsed - _since > ANSWER_TIMEOUT:
				fail("c2s_gather_start(%d) was never answered" % node_id)
				_to(S.DONE)
		S.HOLDING:
			pass
		S.WAIT_PARTNER:
			if _partner_stood_at_node():
				_pack_before = _pack.duplicate()
				_paid_seen = 0
				_press(S.GATHERING)
			elif bot.elapsed - _since > PARTNER_TIMEOUT:
				fail("the fresh player (%s) never stood at node %d" % [partner_name, node_id])
				_to(S.DONE)
		S.GATHERING:
			if bot.elapsed > _deadline:
				fail("veteran's gather %d on node %d never ended" % [dones + 1, node_id])
				_to(S.DONE)
		S.BETWEEN:
			if bot.elapsed >= _deadline:
				if emptied or _empty.has(node_id):
					emptied = true
					_to(S.EMPTIED)
					_deadline = bot.elapsed + 1.0
				else:
					_press(S.GATHERING)
		S.EMPTIED:
			if bot.elapsed >= _deadline:
				paid = int(_pack.get(item, 0)) - int(_pack_before.get(item, 0))
				var why := ToolGate.veteran_problem(node_id, dones, emptied, paid)
				if why != "":
					fail(why)
				if paid != _paid_seen:
					fail("pack gained %d %s but s2c_gather_result said %d" % [paid, item, _paid_seen])
				_to(S.HOLDING)
				bot.disconnect_at = bot.elapsed + 1.5
		S.RECHECK:
			if role == "fresh":
				if refusals >= 2 and not _line_due:
					_check_pack_kept()
					_to(S.DONE)
				elif refusals < 2 and bot.elapsed - _since > ANSWER_TIMEOUT:
					fail("after the reconnect, c2s_gather_start(%d) was never refused" % node_id)
					_to(S.DONE)
			elif _nodes_seen:
				if not _empty.has(node_id):
					fail("node %d shows full again after the reconnect, %d s into its respawn" % [node_id, int(bot.elapsed)])
				_to(S.DONE)
		S.DONE:
			pass


func _press(next: S) -> void:
	_pack_before = _pack.duplicate() if role == "fresh" else _pack_before
	_to(next)
	_deadline = bot.elapsed + GATHER_TIMEOUT
	bot.send_play("c2s_gather_start", [node_id])


func _check_pack_kept() -> void:
	if _pack != _pack_before:
		fail("a refused gather changed the pack: %s -> %s" % [_pack_before, _pack])


## The fresh player has stood within reach of our node for PARTNER_STILL seconds.
func _partner_stood_at_node() -> bool:
	if not _others.has(partner_peer):
		return false
	var at: Vector3 = _others[partner_peer]
	var node_pos: Vector3 = ResourceNodes.get_by_id(node_id).pos
	if Vector2(at.x - node_pos.x, at.z - node_pos.z).length() > ResourceNodes.GATHER_RANGE:
		_partner_pos = Vector3.INF
		return false
	if _partner_pos == Vector3.INF or at.distance_to(_partner_pos) > 0.05:
		_partner_pos = at
		_partner_still_since = bot.elapsed
		return false
	return bot.elapsed - _partner_still_since >= PARTNER_STILL


func on_finish() -> void:
	if role == "":
		return
	var out := {"role": role, "node": node_id, "refusals": refusals, "lines": lines}
	if role == "fresh":
		if refusals < 2:
			fail("refused %d times at tier-2 node %d, wanted 2 (before and after a reconnect)" % [refusals, node_id])
		if lines < refusals:
			fail("%d refusals but only %d '%s' lines" % [refusals, lines, ToolGate.refusal_text(node_id)])
	else:
		out.merge({"dones": dones, "emptied": emptied, "paid": paid, "tool": tool, "reconnect_ok": reconnect_ok})
		if _s != S.DONE:
			fail("veteran stopped in state %s" % S.keys()[_s])
		if not reconnect_ok:
			fail("veteran's tool was never checked after a reconnect")
		if Inventory.count(_pack, tool) < 1:
			fail("veteran lost its %s while working node %d" % [tool, node_id])
		stat("old_xp_kept", ToolGate.VETERAN_OLD_XP.duplicate())
	stat("gate", out)

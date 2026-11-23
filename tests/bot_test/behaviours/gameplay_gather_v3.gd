extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): protocol v3's real gathering, the way a player's press of E
## works, over Net/Play's RPCs instead of chat.
##
## Every login: the pack (s2c_inventory) and the empty-node list (s2c_nodes) must arrive, and
## snapshots must carry our own ack_seq (never ahead of the inputs we sent, never going back).
##
## In long runs (LONG_RUN; CI's 180 s run), once gameplay_gathering.gd is done steering the
## bot for this login (it runs after us each frame and would hold the bot still), the bot
## walks to the nearest wood or stone node and, with c2s_gather_start(node_id):
##   1. starts and walks away at once: the server must end it "moved"/"far", nothing paid;
##   2. starts and sends c2s_gather_cancel(): it must end "stopped", nothing paid;
##   3. starts and holds still: s2c_gather_end "done", then s2c_gather_result and a bigger
##      pack in s2c_inventory.
## With 8 bots and the client gather prompt, nodes run dry and are shared: a refusal or an
## emptied node sends the bot on to the next one (stat "contested"). It also watches other
## bots: every s2c_gather_begin from someone else must be followed by its s2c_gather_end, so
## no client is left showing a gather that never stops.
##
## It works one skill (FOCUS_KINDS, Felling: ash and pine are the most common nodes near the
## meadow) and keeps pressing E until that skill reaches LEVEL_GOAL, so most bots level up
## inside a 180 s run and qa can time the first level-up (qa's request, 2026-11-23). Nodes
## the server says are empty (s2c_nodes / s2c_node_state) are skipped, the next node is the
## nearest one from where the bot stands, and when every node in reach is empty it searches
## wider (SEARCH_RADII) and finally waits for a respawn instead of giving up. "Never started
## a single timed gather" fails only when a node it tried refused for a reason other than
## being empty (8 bots can drain every node near spawn; that's not a bug).
##
## Tier-2 gate (Milestone 1 part 3): once per login, before its first node, the bot asks to
## gather the nearest tier-2 node (an old ember ash or rich seam, level 5) from wherever it
## stands. Below the level the server must refuse it with reason "level" and a system line
## "Needs Felling 5. You're Felling N."; at or above it, it must not say "level". Tier-2
## nodes the bot can't work are never picked as targets.

const SETTLE := 1.0
const LONG_RUN := 120.0
const SEARCH_RADII := [40.0, 80.0, 120.0, 160.0]
const MAX_NODES := 40 ## per login
const RESPAWN_WAIT := 5.0 ## every node in the widest search is empty: look again after this
## gameplay_gathering steers first each login; go anyway if it hasn't let go after this.
const WAIT_FIRST_MAX := 30.0
const FOCUS_KINDS := ["ash", "pine"]
const FOCUS_SKILL := "felling"
const LEVEL_GOAL := 2
const STOP_AT := 1.2
const WALK_TIMEOUT := 20.0
const ANSWER_TIMEOUT := 3.0 ## a start must be answered (begin or end) within this
const RETRY_SOON := 0.6 ## after a "cooldown"/"busy" refusal
const END_SLACK := 2.5
const LOGIN_STATE_TIMEOUT := 6.0
## Standing still. (A first version drifted 1 mm/s so today's client prompt, which "holds E"
## with /gather whenever bot.move is zero, kept off the gather cooldown; timed gathers no
## longer use that cooldown, so the prompt and this behaviour can share a node like two
## players would.)
const STILL := Vector2.ZERO
## After the three checks, keep pressing E like a player working a node, this many gathers
## per login, moving on when a node empties.
const FARM_GATHERS := 4
## Don't press E in the last seconds before bot.gd's mid-run disconnect. bot.gd freezes the
## bot for 1.5 s before it drops the connection, without calling on_play, so a gather started
## just before would pay its XP inside that freeze; client_xp_meter then checks that gain's
## bar after the reconnect has cleared the meter and reads 0 (CI on PR #98). Longest gather
## (2.4 s) plus the freeze plus slack. Client's request for the real fix is in its backlog.
const QUIET_BEFORE_DISCONNECT := 5.0

enum Step { WAIT_FIRST, GATE, GOTO, START, RUNNING, IDLE, WAIT_RESPAWN }
enum Test { WALK_AWAY, CANCEL, HOLD, FARM, DONE }

var _step := Step.IDLE
var _test := Test.WALK_AWAY
var _targets: Array = []
var _target := -1
var _login_nodes := 0
var _radius_i := 0
var _empty := {} ## node id -> true while the server says it is depleted
var _focus_level := 1
var _live_refusals := 0 ## refusals for a reason other than an emptied node
var levelled := 0
var waited_respawn := 0
var _since := 0.0
var _next_at := 0.0
var _answer_by := 0.0
var _ends_by := 0.0
var _walk := Vector2.ZERO
var _cancel_sent := false
var _result_count := 0
var _pack_before := 0
var _item := ""
var _pack: Dictionary = {}
var _got_pack := false
var _got_nodes := false
var _login_at := 0.0
var _state_checked := false
var _last_ack := -1
var _others := {} ## peer -> [node, ends_by]
var started := 0
var completed := 0
var walked_off := 0
var stopped := 0
var contested := 0
var refused := 0
var nodes_tried := 0
var gave_up := 0
var saw_others := 0
var others_ended := 0
var acks := 0
var _farmed := 0
var farmed := 0
var refusal_reasons := {}
var _skills := {} ## skill id -> XP, as the server last told us
var _gate_node := -1
var _gate_text := false
var gate_refused := 0
var gate_lines := 0


func setup(net: Node) -> void:
	net.gather_begun.connect(_on_begun)
	net.gather_ended.connect(_on_ended)
	net.gather_result.connect(_on_result)
	net.inventory_changed.connect(func(items: Dictionary): _pack = items; _got_pack = true)
	net.nodes_depleted.connect(_on_nodes_depleted)
	net.node_state.connect(func(id: int, depleted: bool):
		if depleted:
			_empty[id] = true
		else:
			_empty.erase(id))
	net.skills_changed.connect(func(skills: Dictionary):
		_skills = skills.duplicate()
		_focus_level = Skills.level_for(int(skills.get(FOCUS_SKILL, 0))))
	net.xp_gained.connect(func(skill: String, _gained: int, total: int): _skills[skill] = total)
	net.system_message.connect(_on_system)
	net.level_up.connect(func(skill: String, level: int, _unlocks: Array):
		if skill == FOCUS_SKILL:
			if level >= LEVEL_GOAL and _focus_level < LEVEL_GOAL:
				levelled += 1
			_focus_level = maxi(_focus_level, level))
	net.snapshot_ack.connect(_on_ack)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_step = Step.WAIT_FIRST if float(bot.duration) >= LONG_RUN else Step.IDLE
	_test = Test.WALK_AWAY
	_farmed = 0
	_login_at = bot.elapsed
	_state_checked = false
	_got_pack = false
	_got_nodes = false
	_last_ack = -1
	_others.clear()


func _on_nodes_depleted(ids: Array) -> void:
	_got_nodes = true
	_empty.clear()
	for id in ids:
		_empty[int(id)] = true


func _on_ack(ack: int) -> void:
	acks += 1
	if ack > int(bot.seq):
		fail("ack_seq %d is ahead of the last input we sent (%d)" % [ack, bot.seq])
	if ack < _last_ack:
		fail("ack_seq went back from %d to %d" % [_last_ack, ack])
	_last_ack = ack


func _gathering() -> Object:
	for b in bot.behaviours:
		if b.name == "gameplay_gathering":
			return b
	return null


func _plan() -> void:
	_login_nodes = 0
	_radius_i = 0
	_fill_targets()
	var t2 := ResourceNodes.tier2()
	if t2.is_empty():
		_next_node()
		return
	# The nearest tier-2 node: ask from here, whatever the distance (the level answer comes first).
	var best: Dictionary = t2[0]
	for n in t2:
		if bot.my_pos.distance_to(n.pos) < bot.my_pos.distance_to(best.pos):
			best = n
	_gate_node = int(best.id)
	_target = _gate_node
	_gate_text = false
	_step = Step.GATE
	_answer_by = bot.elapsed + ANSWER_TIMEOUT
	bot.send_play("c2s_gather_start", [_gate_node])


func _fill_targets() -> void:
	_targets.clear()
	for n in ResourceNodes.near(bot.my_pos, SEARCH_RADII[_radius_i]):
		if n.kind in FOCUS_KINDS and Gathering.can_work(n, _skills):
			_targets.append(n.id)


func _on_system(text: String) -> void:
	if _step == Step.GATE and text.begins_with("Needs "):
		_gate_text = true


## The nearest node we haven't seen empty, from where we stand now. Widens the search when
## the list runs dry, and waits for a respawn at the widest.
func _next_node() -> void:
	if _login_nodes >= MAX_NODES:
		gave_up += 1
		_step = Step.IDLE
		return
	var best := -1
	var best_d := INF
	for id in _targets:
		if _empty.has(id):
			continue
		var d := Vector2(ResourceNodes.get_by_id(id).pos.x - bot.my_pos.x, ResourceNodes.get_by_id(id).pos.z - bot.my_pos.z).length()
		if d < best_d:
			best_d = d
			best = id
	if best < 0:
		if _radius_i < SEARCH_RADII.size() - 1:
			_radius_i += 1
			_fill_targets()
			_next_node()
		else:
			waited_respawn += 1
			_step = Step.WAIT_RESPAWN
			_next_at = bot.elapsed + RESPAWN_WAIT
		return
	_targets.erase(best)
	_target = best
	_login_nodes += 1
	nodes_tried += 1
	_since = bot.elapsed
	_step = Step.GOTO


## bot.gd is about to drop the connection for the reconnect check: hold E until after it.
func _disconnect_soon() -> bool:
	return str(bot.phase) == "playing_1" \
			and float(bot.disconnect_at) - float(bot.elapsed) < QUIET_BEFORE_DISCONNECT


func _start() -> void:
	_step = Step.START
	_answer_by = bot.elapsed + ANSWER_TIMEOUT
	_item = str(ResourceNodes.kind_info(str(ResourceNodes.get_by_id(_target).kind)).item)
	_pack_before = int(_pack.get(_item, 0))
	_result_count = 0
	_cancel_sent = false
	bot.send_play("c2s_gather_start", [_target])


func on_play(_delta: float) -> void:
	if not _state_checked and bot.elapsed - _login_at > LOGIN_STATE_TIMEOUT:
		_state_checked = true
		if not _got_pack:
			fail("no s2c_inventory after login")
		if not _got_nodes:
			fail("no s2c_nodes after login")
		if acks == 0:
			fail("no snapshot ack_seq after login")
	for peer in _others.keys():
		if bot.elapsed > float(_others[peer][1]):
			fail("saw peer %d start gathering node %d but never saw it end" % [peer, _others[peer][0]])
			_others.erase(peer)
	match _step:
		Step.WAIT_FIRST:
			var g = _gathering()
			# Done steering this login, whether it gathered or ran out of nodes.
			if g == null or (not g._active and bot.elapsed > g._start_at) \
					or bot.elapsed - _login_at > WAIT_FIRST_MAX:
				_plan()
		Step.GATE:
			bot.move = STILL
			if bot.elapsed > _answer_by:
				fail("c2s_gather_start(%d) on a tier-2 node was never answered" % _gate_node)
				_next_node()
		Step.WAIT_RESPAWN:
			if bot.elapsed >= _next_at:
				_fill_targets()
				_next_node()
		Step.GOTO:
			var node := ResourceNodes.get_by_id(_target)
			var off: Vector3 = node.pos - bot.my_pos
			var flat := Vector2(off.x, off.z)
			if bot.elapsed - _since > WALK_TIMEOUT:
				_next_node()
			elif flat.length() > STOP_AT:
				bot.move = flat.normalized()
				bot.yaw = atan2(bot.move.x, bot.move.y)
			else:
				bot.move = STILL
				_step = Step.START
				_next_at = bot.elapsed + SETTLE
				_answer_by = INF
		Step.START:
			bot.move = STILL
			if _answer_by == INF:
				if bot.elapsed >= _next_at and not _disconnect_soon():
					_start()
			elif bot.elapsed > _answer_by:
				fail("c2s_gather_start(%d) was never answered" % _target)
				_step = Step.IDLE
		Step.RUNNING:
			match _test:
				Test.WALK_AWAY:
					bot.move = _walk
					bot.yaw = atan2(_walk.x, _walk.y)
				Test.CANCEL:
					bot.move = STILL
					if not _cancel_sent and bot.elapsed >= _next_at:
						_cancel_sent = true
						bot.send_play("c2s_gather_cancel")
				_:
					bot.move = STILL
			if bot.elapsed > _ends_by:
				fail("gather on node %d (test %d) never ended" % [_target, _test])
				_step = Step.IDLE


func _on_begun(peer: int, node_id: int, seconds: float) -> void:
	if peer != int(bot.my_id):
		saw_others += 1
		_others[peer] = [node_id, bot.elapsed + seconds + END_SLACK]
		if _step == Step.RUNNING and node_id == _target:
			contested += 1
		return
	if _step != Step.START or node_id != _target:
		fail("begin for node %d we didn't ask for (target %d)" % [node_id, _target])
		return
	if seconds <= 0.0 or seconds > 10.0:
		fail("odd gather time %.2f s" % seconds)
	started += 1
	_ends_by = bot.elapsed + seconds + END_SLACK
	_step = Step.RUNNING
	if _test == Test.WALK_AWAY:
		var a: float = bot.rng.randf() * TAU
		_walk = Vector2(cos(a), sin(a))
	elif _test == Test.CANCEL:
		_next_at = bot.elapsed + minf(0.5, seconds * 0.3)


func _on_ended(peer: int, node_id: int, reason: String) -> void:
	if peer != int(bot.my_id):
		if _others.has(peer):
			others_ended += 1
			_others.erase(peer)
		return
	if node_id != _target:
		return
	# gameplay_roster_v5 asks "Return to Spawn Meadow" in the bot's last seconds. If our gather
	# start crossed that ask on the wire, the teleport ends it "moved" (or "far") while we
	# stood still: that is the unstuck working, not a gathering bug. Stop testing; it's the end.
	if reason in ["moved", "far"] and bot.elapsed - float(bot.get_meta("unstuck_at", -INF)) <= 3.0:
		_step = Step.IDLE
		return
	match _step:
		Step.GATE:
			var node := ResourceNodes.get_by_id(_gate_node)
			var below := not Gathering.can_work(node, _skills)
			if below and reason != "level":
				fail("tier-2 node %d (needs %s %d, we're %d) answered %s, not level" % [_gate_node, node.skill, node.min_level, Skills.level_of(_skills, node.skill), reason])
			elif not below and reason == "level":
				fail("tier-2 node %d refused for level at %s %d" % [_gate_node, node.skill, Skills.level_of(_skills, node.skill)])
			if reason == "level":
				gate_refused += 1
				# The system line is sent right after the end; look for it a moment later.
				bot.get_tree().create_timer(1.0).timeout.connect(func():
					if _gate_text:
						gate_lines += 1
					else:
						fail("tier-2 refusal without a \"Needs ...\" line"))
			bot.get_tree().create_timer(0.5).timeout.connect(func():
				if _step == Step.GATE:
					_next_node())
		Step.START:
			# Refused before it began.
			refused += 1
			refusal_reasons[reason] = int(refusal_reasons.get(reason, 0)) + 1
			if reason in ["cooldown", "busy"]:
				_answer_by = INF
				_next_at = bot.elapsed + RETRY_SOON
			else:
				if reason == "depleted":
					_empty[_target] = true
				else:
					_live_refusals += 1
				_next_node() # spent, out of reach, full: next node
		Step.RUNNING:
			match _test:
				Test.WALK_AWAY:
					if reason in ["moved", "far"]:
						walked_off += 1
						_test = Test.CANCEL
						_targets.push_front(_target) # its charge is still there
						_next_node()
					elif reason == "done":
						fail("walked away but the gather still paid out")
						_step = Step.IDLE
					else:
						contested += 1
						_next_node()
				Test.CANCEL:
					if reason == "stopped":
						stopped += 1
						_test = Test.HOLD
						_step = Step.START
						_answer_by = INF
						_next_at = bot.elapsed + SETTLE # same node, straight away: no cooldown spent
					elif reason == "done":
						# The cancel crossed the finish on the wire; possible on a short gather.
						_test = Test.HOLD
						_check_payout()
					elif reason in ["moved", "far"]:
						fail("cancel test: ended %s while standing still" % reason)
						_step = Step.IDLE
					else:
						contested += 1
						_next_node()
				Test.HOLD, Test.FARM:
					if reason == "done":
						_check_payout()
					elif reason in ["moved", "far", "stopped"]:
						fail("gather ended %s while standing still at %s" % [reason, bot.my_pos])
						_step = Step.IDLE
					else:
						contested += 1 # emptied by another bot while we worked
						_next_node()


func _on_result(item_id: String, count: int) -> void:
	if item_id == "" or count <= 0:
		fail("empty gather result %s x%d" % [item_id, count])
	_result_count += count


## After "done": the result (sent just before the end) and the pack update (next tick).
func _check_payout() -> void:
	completed += 1
	if _test == Test.FARM:
		farmed += 1
		_farmed += 1
	# A full stack still finishes "done" and pays XP, but sends no result (nothing landed).
	if _result_count <= 0 and int(_pack.get(_item, 0)) < Inventory.MAX_STACK:
		fail("gather done but no s2c_gather_result")
	var item := _item
	var before := _pack_before
	bot.get_tree().create_timer(1.0).timeout.connect(func():
		if int(_pack.get(item, 0)) <= before and int(_pack.get(item, 0)) < Inventory.MAX_STACK:
			fail("gather done but the pack never showed more %s (%d before, %s now)" % [item, before, _pack]))
	if _farmed < FARM_GATHERS or _focus_level < LEVEL_GOAL:
		# Press E again straight away: same node, no cooldown (the bar is the pacing).
		_test = Test.FARM
		_step = Step.START
		_answer_by = INF
		_next_at = bot.elapsed
	else:
		_test = Test.DONE
		_step = Step.IDLE


func on_finish() -> void:
	stat("started", started)
	stat("completed", completed)
	stat("walked_off", walked_off)
	stat("stopped", stopped)
	stat("contested", contested)
	stat("refused", refused)
	stat("nodes_tried", nodes_tried)
	stat("gave_up", gave_up)
	stat("saw_others", saw_others)
	stat("others_ended", others_ended)
	stat("acks", acks)
	stat("farmed", farmed)
	stat("refusal_reasons", refusal_reasons)
	stat("levelled", levelled)
	stat("focus_level", _focus_level)
	stat("gate_refused", gate_refused)
	stat("gate_lines", gate_lines)
	stat("waited_respawn", waited_respawn)
	if float(bot.duration) >= LONG_RUN and nodes_tried > 0 and started == 0 and _live_refusals > 0:
		fail("never started a single timed gather (%d refusals that weren't an emptied node)" % _live_refusals)

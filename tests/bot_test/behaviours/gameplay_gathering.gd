extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): gathering.
##
## Soon after each login the bot walks to one of the wood or stone nodes nearest to it,
## stands in reach and types /gather. Eight bots share about fourteen nodes near spawn, so a
## node may already be spent: the bot then walks to the next nearest one. One good gather per
## login is enough. On the second login the pack must still hold what the server said was
## in it after the first gather, which checks gathered items are saved.
##
## Only bare-hand wood is worked: stone needs a pickaxe the bots don't carry, and scrub's
## plant fibre is spent by client_craft_window's torch presses, which would read as a loss.
## Nodes the server says are empty (s2c_nodes at login, s2c_node_state live) are skipped, and
## each next target is the nearest live one from where the bot stands, so a bot on the far
## side of spawn doesn't spend a 15 s login walking to nodes it already knows are spent.

const FIRST_DELAY := 3.0 ## short: CI also runs a 45 s bot test, so a login can last only ~15 s
const SEARCH_RADIUS := 60.0 ## bot.gd keeps bots within about 60 m of spawn
const SPREAD := 4 ## start at one of the nearest few nodes, so bots don't all queue at one
const STOP_AT := 1.5 ## metres from the node centre (reach is ResourceNodes.GATHER_RANGE)
const RETRY_AFTER := 3.0 ## an unanswered /gather (chat cooldown) is sent again
const MAX_TRIES := 5
const TARGET_TIMEOUT := 30.0 ## give up on a node we can't reach in this long
const REPLIES := ["You gather", "This ", "Nothing to gather", "Easy;", "Your pack can't", "Gather what"]

var rng := RandomNumberGenerator.new()
var _targets: Array = []
var _target := -1
var _target_since := 0.0
var _active := false
var _start_at := 0.0
var _waiting := false
var _tries := 0
var _next_send := 0.0
var _phase_gathered := false
## item -> count the server reported after our last good gather
var _reported := {}
## node id -> true while the server says it is empty
var _depleted := {}
## the first node of a login: one of the nearest few, so bots spread out (-1 = none)
var _first := -1
var gathered := 0
var spent_seen := 0
var nodes_tried := 0


func setup(net: Node) -> void:
	rng.seed = hash(bot.bot_name + "/gathering")
	net.system_message.connect(_on_system)
	net.nodes_depleted.connect(_on_nodes_depleted)
	net.node_state.connect(_on_node_state)


func on_login(reconnect: bool, character: Dictionary) -> void:
	if reconnect:
		var inv: Dictionary = character.get("inventory", {})
		for item in _reported:
			if int(inv.get(item, 0)) < int(_reported[item]):
				fail("pack lost gathered %s: server said %d before logout, login has %d" % [item, _reported[item], int(inv.get(item, 0))])
	_targets.clear()
	_first = -1
	# Nearest first from where we stand, starting a few nodes in so bots spread out.
	var here := Vector3(character.x, character.y, character.z)
	for n in ResourceNodes.near(here, SEARCH_RADIUS):
		# Never a night-only seep, nor a tier-2 node (it needs a tool a new character lacks).
		var info := ResourceNodes.kind_info(n.kind)
		if not info.get("night_only", false) and not info.get("needs_tool", false) and n.kind != "scrub" and int(n.get("tier", 1)) == 1:
			_targets.append(n.id)
	if _targets.size() > 1:
		_first = int(_targets[rng.randi_range(0, mini(SPREAD, _targets.size()) - 1)])
	_target = -1
	_active = true
	_phase_gathered = false
	_waiting = false
	_start_at = bot.elapsed + FIRST_DELAY + rng.randf_range(0.0, 3.0)


func on_play(_delta: float) -> void:
	if not _active or bot.elapsed < _start_at:
		return
	if _target < 0 or bot.elapsed - _target_since > TARGET_TIMEOUT or _tries >= MAX_TRIES:
		if not _next_target():
			_active = false
			return
	var node := ResourceNodes.get_by_id(_target)
	var off: Vector3 = node.pos - bot.my_pos
	var flat := Vector2(off.x, off.z)
	if flat.length() > STOP_AT:
		bot.move = flat.normalized()
		bot.yaw = atan2(bot.move.x, bot.move.y)
		return
	bot.move = Vector2.ZERO
	if bot.elapsed < _next_send:
		return
	_tries += 1
	_waiting = true
	_next_send = bot.elapsed + RETRY_AFTER
	bot.send_command("/gather %s" % node.kind)


func _next_target() -> bool:
	# Nearest live node from here; known-empty ones go last (they may come back).
	var best := -1
	var best_d := INF
	for i in _targets.size():
		var n := ResourceNodes.get_by_id(int(_targets[i]))
		var d := Vector2(n.pos.x - bot.my_pos.x, n.pos.z - bot.my_pos.z).length()
		if _depleted.has(int(_targets[i])):
			d += 1000.0
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return false
	if _first >= 0 and not _depleted.has(_first) and _targets.has(_first):
		best = _targets.find(_first)
	_first = -1
	_target = int(_targets[best])
	_targets.remove_at(best)
	_target_since = bot.elapsed
	_tries = 0
	_next_send = 0.0
	_waiting = false
	nodes_tried += 1
	return true


func _on_system(text: String) -> void:
	if not _waiting:
		return
	var ours := false
	for p in REPLIES:
		if text.begins_with(p):
			ours = true
	if not ours:
		return # someone arriving or leaving, or another command's answer
	_waiting = false
	if text.begins_with("You gather"):
		gathered += 1
		var item := str(ResourceNodes.kind_info(ResourceNodes.get_by_id(_target).kind).item)
		var m := RegEx.create_from_string("\\((\\d+) in your pack\\)").search(text)
		if m == null:
			fail("gather reply without a pack count: %s" % text)
		else:
			_reported[item] = m.get_string(1).to_int()
		_phase_gathered = true
		_active = false
	elif text.begins_with("This ") or text.begins_with("Nothing to gather"):
		spent_seen += 1
		_target = -1 # spent, or we stood just out of reach: try the next node
	elif text.begins_with("Easy;"):
		pass # cooldown: the retry timer sends it again
	else:
		fail("unexpected gather reply: %s" % text)
		_active = false


func _on_nodes_depleted(ids: Array) -> void:
	_depleted.clear()
	for id in ids:
		_depleted[int(id)] = true


func _on_node_state(node_id: int, depleted: bool) -> void:
	if depleted:
		_depleted[node_id] = true
	else:
		_depleted.erase(node_id)
	if depleted and node_id == _target and not _waiting and _active:
		_target = -1 # emptied before we got there: pick the next one


func on_finish() -> void:
	stat("gathered", gathered)
	stat("spent_seen", spent_seen)
	stat("nodes_tried", nodes_tried)
	if gathered < 1:
		fail("never gathered anything (tried %d nodes, %d spent)" % [nodes_tried, spent_seen])

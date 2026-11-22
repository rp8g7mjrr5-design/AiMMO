extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): gathering.
##
## A while after each login the bot walks to a wood or stone node near Spawn Meadow, stands
## in reach and types /gather. Eight bots share about fourteen nodes, so a node may already
## be spent: the bot then walks to the next one on its (shuffled) list. One good gather per
## login is enough. On the second login the pack must still hold what the server said was
## in it after the first gather, which checks gathered items are saved.
##
## Ember-sap seeps are skipped: they only give at night and the bot test runs at any hour.

const FIRST_DELAY := 12.0 ## after the /time, /who and /bag behaviours have had their turn
const SEARCH_RADIUS := 60.0 ## bot.gd keeps bots within about 60 m of spawn
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
var gathered := 0
var spent_seen := 0
var nodes_tried := 0


func setup(net: Node) -> void:
	rng.seed = hash(bot.bot_name + "/gathering")
	net.system_message.connect(_on_system)


func on_login(reconnect: bool, character: Dictionary) -> void:
	if reconnect:
		var inv: Dictionary = character.get("inventory", {})
		for item in _reported:
			if int(inv.get(item, 0)) < int(_reported[item]):
				fail("pack lost gathered %s: server said %d before logout, login has %d" % [item, _reported[item], int(inv.get(item, 0))])
	_targets.clear()
	for n in ResourceNodes.near(GameConfig.SPAWN_POINT, SEARCH_RADIUS):
		if not ResourceNodes.kind_info(n.kind).get("night_only", false):
			_targets.append(n.id)
	_shuffle(_targets)
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
	bot.net.c2s_chat.rpc_id(1, "/gather %s" % node.kind)


func _next_target() -> bool:
	if _targets.is_empty():
		return false
	_target = _targets.pop_front()
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


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func on_finish() -> void:
	stat("gathered", gathered)
	stat("spent_seen", spent_seen)
	stat("nodes_tried", nodes_tried)
	if gathered < 1:
		fail("never gathered anything (tried %d nodes, %d spent)" % [nodes_tried, spent_seen])

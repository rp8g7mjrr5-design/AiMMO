extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the v3 gather prompt on a real server. Each bot runs the client's GatherPrompt
## and GatherWatch every frame from its real position and the server's clock, and feeds them
## exactly the protocol v3 events the client gets (s2c_gather_begin/end/result,
## s2c_inventory, s2c_nodes, s2c_node_state), applying the watch's hits and depletions to a
## real NodeProps world.
##
## It sends nothing of its own: gameplay_gather_v3.gd already presses E on this bot (and
## fails on any gather it didn't ask for), so this behaviour checks what the player would see
## of those gathers:
## - the prompt only targets nodes in reach, and never offers a node the server says is spent;
## - when the server begins your gather the prompt was offering a node right there, the bar
##   shows, fills over the server's seconds and never goes back, and goes when it ends;
## - every s2c_gather_result becomes a toast with the server's count and your pack's total;
## - refusals with words show their notice; hits and depletions land on real node props.

const PromptScript := preload("res://client/gather_prompt.gd")
const WatchScript := preload("res://client/gather_watch.gd")
const END_SLACK := 2.5

var _w: Control
var _watch: RefCounted
var _nodes: Node3D
var _synced := 0.0
var _synced_at := -1
var _last_bar := 0.0
var _ends_by := INF
var prompt_frames := 0
var own_gathers := 0
var bar_frames := 0
var toasts := 0
var notices := 0
var hits := 0
var depletions := 0


func setup(net: Node) -> void:
	_w = PromptScript.new()
	_w.setup(Theme.new())
	_watch = WatchScript.new()
	_nodes = NodeProps.build(ResourceNodes.all())
	net.world_time.connect(_on_world_time)
	net.gather_begun.connect(_on_begun)
	net.gather_ended.connect(_on_ended)
	net.gather_result.connect(_on_result)
	net.inventory_changed.connect(func(items: Dictionary): _w.pack = items)
	net.nodes_depleted.connect(_on_nodes)
	net.node_state.connect(_on_node_state)


func _on_world_time(world_seconds: float) -> void:
	_synced = world_seconds
	_synced_at = Time.get_ticks_msec()


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_w.hide_all()
	_watch.reset()
	_ends_by = INF


func _world_seconds() -> float:
	if _synced_at < 0:
		return WorldClock.now_seconds()
	return WorldClock.extrapolate(_synced, _synced_at, Time.get_ticks_msec())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func on_play(delta: float) -> void:
	if not bot.have_pos:
		return
	var now := _now()
	_w.update(delta, bot.my_pos, _world_seconds(), now, false, false, bot.move != Vector2.ZERO)
	var t: Dictionary = _w.current_target()
	if not t.is_empty():
		prompt_frames += 1
		if not ResourceNodes.in_range(int(t.id), bot.my_pos):
			fail("prompt targets node %d out of reach" % int(t.id))
		if bool(t.can) and _w.spent.has(int(t.id)):
			fail("prompt offers spent node %d" % int(t.id))
	if _w.gathering():
		bar_frames += 1
		if not _w.bar.visible:
			fail("own gather running but no bar")
		if _w.bar.value + 0.0001 < _last_bar:
			fail("bar went back from %.2f to %.2f" % [_last_bar, _w.bar.value])
		_last_bar = _w.bar.value
		if now > _ends_by:
			fail("bar still up %.1f s after it should have ended" % END_SLACK)
			_ends_by = INF
	_apply(_watch.tick(now))


func _on_begun(peer: int, node_id: int, seconds: float) -> void:
	_watch.begun(peer, node_id)
	if peer != int(bot.my_id):
		return
	own_gathers += 1
	if _w.current_target().is_empty() and ResourceNodes.in_range(node_id, bot.my_pos):
		fail("server began a gather on node %d but the prompt offered nothing there" % node_id)
	_w.on_begun(node_id, seconds, _now())
	_last_bar = 0.0
	_ends_by = _now() + seconds + END_SLACK


func _on_ended(peer: int, node_id: int, reason: String) -> void:
	_apply(_watch.ended(peer, node_id, reason))
	if peer != int(bot.my_id):
		return
	if _w.on_ended(node_id, reason) != "":
		notices += 1
		if _w.toast_label.text != PromptScript.notice_for(reason, node_id):
			fail("notice for %s shows %s" % [reason, _w.toast_label.text])
	if _w.gathering() and int(_w.channel().node_id) == node_id:
		fail("bar still up after its end (%s)" % reason)
	_ends_by = INF


func _on_result(item_id: String, count: int) -> void:
	_w.on_result(item_id, count)
	toasts += 1
	var want := "+%d " % count
	if not _w.toast_label.text.begins_with(want):
		fail("toast %s for +%d %s" % [_w.toast_label.text, count, item_id])
	if _w.pack.has(item_id) and not _w.toast_label.text.ends_with("(%d)" % int(_w.pack[item_id])):
		fail("toast %s but the pack holds %d %s" % [_w.toast_label.text, int(_w.pack[item_id]), item_id])
	if _w.toast_item() != item_id:
		fail("toast for %s shows the %s icon" % [item_id, _w.toast_item()])


func _on_nodes(ids: Array) -> void:
	var dead := {}
	for id in ids:
		dead[int(id)] = true
	_w.spent = dead
	for id in dead:
		if not NodeProps.set_depleted(_nodes, id, true):
			fail("s2c_nodes names unknown node %d" % id)


func _on_node_state(node_id: int, depleted: bool) -> void:
	if depleted:
		_w.spent[node_id] = true
	else:
		_w.spent.erase(node_id)
	_apply(_watch.node_state(node_id, depleted, _now()))


func _apply(ops: Array) -> void:
	for op in ops:
		var ok := false
		if op[0] == "hit":
			ok = NodeProps.play_hit(_nodes, int(op[1]))
			hits += 1
		else:
			ok = NodeProps.set_depleted(_nodes, int(op[1]), bool(op[2]))
			depletions += 1
		if not ok:
			fail("node op %s on an unknown node" % str(op))


func on_finish() -> void:
	stat("prompt_frames", prompt_frames)
	stat("own_gathers", own_gathers)
	stat("bar_frames", bar_frames)
	stat("toasts", toasts)
	stat("notices", notices)
	stat("hits", hits)
	stat("depletions", depletions)
	if bot.elapsed > 60.0 and prompt_frames == 0:
		fail("never stood at a node with the prompt showing")
	if own_gathers > 0 and bar_frames == 0:
		fail("%d gathers began but the bar never showed" % own_gathers)
	if _w:
		_w.free()
	if _nodes:
		_nodes.free()

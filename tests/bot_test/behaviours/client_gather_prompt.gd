extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the gather prompt on a real server. Each bot runs the client's GatherPrompt every
## frame from its real position and the server's clock, and "holds E" whenever it stands
## still, sending exactly what the client would send. Checks: the prompt only ever targets a
## node in reach, presses never come faster than GatherPrompt.PRESS_INTERVAL, every server
## answer to a press is a known gather reply, and every success line becomes a toast whose
## text matches the server's numbers.
##
## Plays nicely with gameplay_gathering.gd: that bot stands within 1.5 m of its node and nodes
## are at least 6 m apart, so the prompt targets the same node it is gathering.

const PromptScript := preload("res://client/gather_prompt.gd")
const REPLIES := ["You gather", "This ", "Nothing to gather", "Easy;", "Your pack can't", "The ", "Gather what"]

var _w: Control
var _synced := 0.0
var _synced_at := -1
var _pending := 0 ## presses still waiting for a reply
var _last_press := -INF
var prompt_frames := 0
var presses := 0
var toasts := 0
var refusals := 0


func setup(net: Node) -> void:
	_w = PromptScript.new()
	_w.setup(Theme.new())
	net.world_time.connect(_on_world_time)
	net.system_message.connect(_on_system)


func _on_world_time(world_seconds: float) -> void:
	_synced = world_seconds
	_synced_at = Time.get_ticks_msec()


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_pending = 0
	_w.hide_all()


func _world_seconds() -> float:
	if _synced_at < 0:
		return WorldClock.now_seconds()
	return WorldClock.extrapolate(_synced, _synced_at, Time.get_ticks_msec())


func on_play(delta: float) -> void:
	if not bot.have_pos:
		return
	var now: float = bot.elapsed
	var held: bool = bot.move == Vector2.ZERO
	var cmd: String = _w.update(delta, bot.my_pos, _world_seconds(), now, held)
	var t: Dictionary = _w.current_target()
	if not t.is_empty():
		prompt_frames += 1
		if not ResourceNodes.in_range(int(t.id), bot.my_pos):
			fail("prompt targets node %d out of reach" % int(t.id))
	if cmd == "":
		return
	if now - _last_press < PromptScript.PRESS_INTERVAL - 0.0001:
		fail("pressed again after %.2f s" % (now - _last_press))
	if cmd != "/gather %s" % t.kind:
		fail("prompt sent %s for a %s" % [cmd, t.kind])
	_last_press = now
	presses += 1
	_pending += 1
	bot.net.c2s_chat.rpc_id(1, cmd)


func _on_system(text: String) -> void:
	if _pending <= 0 and not text.begins_with("You gather"):
		return
	var ours := false
	for p in REPLIES:
		if text.begins_with(p):
			ours = true
	if not ours:
		return # someone arriving or leaving
	_pending = maxi(0, _pending - 1)
	if _w.on_system(text):
		toasts += 1
		var m := RegEx.create_from_string("^You gather (\\d+) .+\\((\\d+) in your pack\\)").search(text)
		var want := "+%s " % m.get_string(1) if m else "?"
		if m == null or not _w.toast_label.text.begins_with(want) or not _w.toast_label.text.ends_with("(%s)" % m.get_string(2)):
			fail("toast %s for %s" % [_w.toast_label.text, text])
	elif text.begins_with("You gather"):
		fail("success line made no toast: %s" % text)
	else:
		refusals += 1


func on_finish() -> void:
	stat("prompt_frames", prompt_frames)
	stat("presses", presses)
	stat("toasts", toasts)
	stat("refusals", refusals)
	if bot.elapsed > 60.0 and prompt_frames == 0:
		fail("never stood at a node with the prompt showing")
	if _w:
		_w.free()

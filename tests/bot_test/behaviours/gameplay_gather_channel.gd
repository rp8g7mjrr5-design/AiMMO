extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the timed gather (GatherChannel) through the hidden "/channel"
## dev command, the server path protocol v3's press-E will use.
##
## Starts once gameplay_gathering.gd is done for the login (its first good "/gather", or it
## gave up): that behaviour runs after this one each frame and sets bot.move while it is
## active, so starting earlier let it hold the bot still during the walk-away test and the
## gather paid out (the flaky "walked away but the gather still paid out"). Then the bot walks to the nearest wood or stone node and:
##   1. sends "/channel" and walks away as soon as it starts: the server must cancel it
##      ("You stop gathering: you moved.") and must not hand anything over;
##   2. sends "/channel" again and holds still: the items must come only at the end
##      ("You gather ..."), never a cancel.
## Only in long bot tests (LONG_RUN; CI's 180 s run): in CI's 45 s run every node near spawn
## is needed by bots still looking for their first gather, and a bot standing at a node for
## this lets the client's gather prompt drain it.
## With 8 bots (and the client's gather prompt "holding E" whenever a bot stands still) nodes
## run dry fast, so a refusal just sends the bot on to the next nearest node. Replies can't be
## told apart from the prompt's, so only "You start gathering" / "You stop gathering" and a
## "You gather" while our own gather runs move the steps on; the server refuses every other
## gather while one is running, which the unit tests check.

const SETTLE := 1.0
const LONG_RUN := 120.0 ## bot.duration from which this behaviour runs
const SEARCH_RADIUS := 40.0
const MAX_NODES := 8 ## nodes tried per login before giving up
const STOP_AT := 1.2 ## metres from the node centre (reach is ResourceNodes.GATHER_RANGE)
const WALK_TIMEOUT := 20.0
const RETRY_AFTER := 1.2 ## no answer (shared chat cooldown dropped the line): send again
const MAX_TRIES := 6
const END_SLACK := 2.5 ## a running gather must end within its time plus this
const REFUSALS := ["This ", "Nothing to gather", "Your pack can't", "The "]

enum Step { WAIT_FIRST, GOTO, START, HOLDING, WALKING, IDLE }

var _step := Step.IDLE
var _second := false ## false: the walk-away test, true: the hold-still test
var _targets: Array = []
var _target := -1
var _last_node := -1
var _login_nodes := 0
var _since := 0.0
var _next_at := 0.0
var _tries := 0
var _ends_by := 0.0
var _walk := Vector2.ZERO
var started := 0
var completed := 0
var cancelled := 0
var nodes_tried := 0
var gave_up := 0
var answered := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_step = Step.WAIT_FIRST if float(bot.duration) >= LONG_RUN else Step.IDLE
	_second = false


func _plan() -> void:
	_targets.clear()
	_login_nodes = 0
	for n in ResourceNodes.near(bot.my_pos, SEARCH_RADIUS):
		if not ResourceNodes.kind_info(n.kind).get("night_only", false):
			_targets.append(n.id)
	_next_node()


func _next_node() -> void:
	if _targets.is_empty() or _login_nodes >= MAX_NODES:
		gave_up += 1
		_step = Step.IDLE
		return
	_target = _targets.pop_front()
	_last_node = _target
	_login_nodes += 1
	nodes_tried += 1
	_since = bot.elapsed
	_step = Step.GOTO


## gameplay_gathering.gd's instance on this bot, or null when it isn't loaded.
func _gathering() -> Object:
	for b in bot.behaviours:
		if b.name == "gameplay_gathering":
			return b
	return null


func on_play(_delta: float) -> void:
	match _step:
		Step.WAIT_FIRST:
			var g = _gathering()
			if g != null and not g._active and g._phase_gathered:
				_plan()
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
				bot.move = Vector2.ZERO
				_step = Step.START
				_tries = 0
				_next_at = bot.elapsed + SETTLE
		Step.START:
			bot.move = Vector2.ZERO
			if bot.elapsed >= _next_at:
				if _tries >= MAX_TRIES:
					_next_node()
				else:
					_tries += 1
					_next_at = bot.elapsed + RETRY_AFTER
					bot.send_command("/channel")
		Step.HOLDING:
			bot.move = Vector2.ZERO
			if bot.elapsed > _ends_by:
				fail("timed gather never ended (at %s)" % bot.my_pos)
				_step = Step.IDLE
		Step.WALKING:
			bot.move = _walk
			bot.yaw = atan2(_walk.x, _walk.y)
			if bot.elapsed > _ends_by:
				fail("walked away but the gather was never cancelled")
				_step = Step.IDLE


func _on_system(text: String) -> void:
	match _step:
		Step.WAIT_FIRST:
			if _gathering() == null and text.begins_with("You gather"):
				_plan()
		Step.START:
			if text.begins_with("You start gathering"):
				answered += 1
				started += 1
				var m := RegEx.create_from_string("\\((\\d+\\.\\d) s\\)").search(text)
				var secs: float = m.get_string(1).to_float() if m else 0.0
				if secs <= 0.0:
					fail("start line without a duration: %s" % text)
				_ends_by = bot.elapsed + secs + END_SLACK
				if not _second:
					var a: float = bot.rng.randf() * TAU
					_walk = Vector2(cos(a), sin(a))
					_step = Step.WALKING
				else:
					_step = Step.HOLDING
			elif text.begins_with("Easy;"):
				answered += 1
				_next_at = bot.elapsed + 0.6 # a gather cooldown (ours or the prompt's): soon
			else:
				for p in REFUSALS:
					if text.begins_with(p):
						answered += 1
						_next_node() # spent, or not quite in reach: next node
						return
		Step.HOLDING:
			if text.begins_with("You gather"):
				completed += 1
				if not RegEx.create_from_string("\\((\\d+) in your pack\\)").search(text):
					fail("timed gather success without a pack count: %s" % text)
				_step = Step.IDLE
			elif text.begins_with("You stop gathering"):
				fail("gather cancelled while standing still at %s: %s" % [bot.my_pos, text])
				_step = Step.IDLE
			elif text.begins_with("This "):
				_next_node() # emptied by another bot while we gathered: the contested case
		Step.WALKING:
			if text.begins_with("You stop gathering"):
				cancelled += 1
				_second = true
				_targets.push_front(_last_node) # it still has the charge we didn't take
				_next_node()
			elif text.begins_with("You gather"):
				fail("walked away but the gather still paid out: %s" % text)
				_step = Step.IDLE


func on_finish() -> void:
	stat("started", started)
	stat("completed", completed)
	stat("cancelled", cancelled)
	stat("nodes_tried", nodes_tried)
	stat("gave_up", gave_up)
	if bot.elapsed > 60.0 and answered == 0 and nodes_tried > 0:
		fail("/channel was never answered")

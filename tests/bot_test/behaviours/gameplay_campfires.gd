extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): placed campfires, server side (Phase 2 build-ahead). Fires are not
## on the wire yet (s2c_campfires waits for a bump), so the bot feels one only through the
## hidden dev commands.
##
## One bot per run (the one named *_5), once, FIRST_DELAY seconds into its first login, between
## two of gameplay_gather_v3's gathers, borrows itself (bot meta "wildlife_stalking", which the
## gather, swing and vitals behaviours already respect), stands still and:
##   1. /place campfire: bots carry no campfire, so the answer must be the "no campfire"
##      refusal (Campfires.REFUSALS.no_item), and nothing is lit; a bot that somehow holds one
##      gets Server.PLACED_TEXT instead, which also counts;
##   2. /kindle: a fire catches in front of it ("A campfire catches ... (campfire N)."). A
##      refusal about the spot (a node, the bench, water, another fire) sends it walking for
##      a few seconds and it tries again, up to MAX_TRIES;
##   3. /kindle status: the nearest fire is that one ("Campfire N: 1.5 m from you, ...").
## A login too short to finish is counted, not failed.

const MY_SUFFIX := "_5"
const FIRST_DELAY := 20.0
const QUIET_BEFORE := 20.0 ## not this close to the end of the run
const ANSWER_TIMEOUT := 4.0
const WALK_ON := 3.0 ## seconds of walking after a spot refusal
const MAX_TRIES := 6
const NO_ITEM := "You have no campfire to set down. Make one at the workbench."
const PLACED := "You set down a campfire."
const CAUGHT := "A campfire catches in front of you (campfire "
const SPOT_REFUSALS := ["The ground here is too wet", "Too close to the edge", "There is a fire burning right here",
	"Not on top of something", "Not against the workbench", "You already have", "Too many fires are burning"]

enum Step { WAIT, PLACE, KINDLE, STATUS, DONE }

var _me := false
var _step := Step.WAIT
var _next_at := 0.0
var _sent_at := -1.0
var _holding := false
var _fire := -1
var _tries := 0
var refused_no_item := 0
var placed := 0
var kindled := 0
var spot_refusals := 0
var status_ok := 0
var skipped := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)


func on_login(reconnect: bool, _character: Dictionary) -> void:
	if _step != Step.WAIT and _step != Step.DONE:
		skipped += 1 # logged out mid-check
		_release(Step.DONE)
	if not reconnect:
		_me = str(bot.bot_name).ends_with(MY_SUFFIX)
		_step = Step.PLACE if _me else Step.DONE
		_sent_at = -1.0
		_next_at = bot.elapsed + FIRST_DELAY


func _lend_ok() -> bool:
	if bot.get_meta("wildlife_stalking", false):
		return false
	for b in bot.behaviours:
		if b.name == "gameplay_gather_v3":
			return b.ready_to_lend()
	return true


func _release(next: Step) -> void:
	_step = next
	_sent_at = -1.0
	if _holding:
		bot.set_meta("wildlife_stalking", false)
	_holding = false


func on_play(_delta: float) -> void:
	if _step == Step.WAIT or _step == Step.DONE:
		return
	if _holding and bot.elapsed >= _next_at:
		bot.move = Vector2.ZERO # stand still: the fire goes 1.5 m in front of where we stand
	if bot.elapsed < _next_at:
		return
	if _sent_at >= 0.0:
		if _sent_at <= bot.elapsed and bot.elapsed - _sent_at > ANSWER_TIMEOUT:
			fail("no answer to the %s line" % Step.keys()[_step].to_lower())
			_release(Step.DONE)
		return
	if not _holding:
		if float(bot.duration) - bot.elapsed < QUIET_BEFORE:
			skipped += 1
			_release(Step.DONE)
			return
		if not _lend_ok():
			_next_at = bot.elapsed + 0.5
			return
		bot.set_meta("wildlife_stalking", true)
		_holding = true
		bot.move = Vector2.ZERO
	match _step:
		Step.PLACE:
			_send("/place campfire")
		Step.KINDLE:
			_tries += 1
			_send("/kindle")
		Step.STATUS:
			_send("/kindle status")


func _send(line: String) -> void:
	_sent_at = bot.elapsed + 30.0 # until it actually goes out of the queue
	bot.send_command(line, func(): _sent_at = bot.elapsed)


func _on_system(text: String) -> void:
	if _sent_at < 0.0 or _sent_at > bot.elapsed:
		return
	match _step:
		Step.PLACE:
			if text == NO_ITEM:
				refused_no_item += 1
			elif text.begins_with(PLACED):
				placed += 1
			else:
				return
			_sent_at = -1.0
			_step = Step.KINDLE
		Step.KINDLE:
			if text.begins_with(CAUGHT):
				_fire = int(text.substr(CAUGHT.length()).trim_suffix(")."))
				kindled += 1
				_sent_at = -1.0
				_step = Step.STATUS
				return
			for r in SPOT_REFUSALS:
				if text.begins_with(r):
					spot_refusals += 1
					_sent_at = -1.0
					if _tries >= MAX_TRIES:
						fail("no spot for a fire after %d tries (last: %s)" % [_tries, text])
						_release(Step.DONE)
						return
					# Walk on a little (bot.gd's wander drives us), then stand and try again.
					_next_at = bot.elapsed + WALK_ON
					return
		Step.STATUS:
			if text.begins_with("Campfire %d:" % _fire):
				status_ok += 1
				_release(Step.DONE)
			elif text.begins_with("Campfire ") or text == "No campfire is burning near you.":
				fail("kindled campfire %d but /kindle status says: %s" % [_fire, text])
				_release(Step.DONE)


func on_finish() -> void:
	stat("refused_no_item", refused_no_item)
	stat("placed", placed)
	stat("kindled", kindled)
	stat("spot_refusals", spot_refusals)
	stat("status_ok", status_ok)
	stat("skipped", skipped)
	if _me and kindled > 0 and status_ok == 0 and skipped == 0:
		fail("kindled a fire and never read it back")
	if _me and kindled == 0 and skipped == 0 and _step != Step.DONE:
		fail("never got as far as kindling a fire (step %s)" % Step.keys()[_step])

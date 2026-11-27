extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): ruin loot (Loot, step 2 of the owner's survival plan, 2026-11-27).
##
## One bot (the one named *_7), once, FIRST_DELAY seconds into its first login:
##   1. /loot: searches the nearest loot spot (a stand-in grade 1 chest on Ashgrove, which has
##      no ruins). The answer starts "You search the chest and find", and the pack it gets
##      (s2c_inventory) holds more than before;
##   2. /loot again: the same spot is empty, "... Come back tomorrow.";
##   3. /loot refill: every spot is full again (so a later run starts the same).
## A login too short to finish is counted, not failed.

const MY_SUFFIX := "_7"
const FIRST_DELAY := 40.0
const QUIET_BEFORE := 15.0
const ANSWER_TIMEOUT := 4.0

enum Step { WAIT, FIRST, AGAIN, REFILL, DONE }

var _me := false
var _step := Step.WAIT
var _next_at := 0.0
var _sent_at := -1.0
var _pack_total := 0
var _before := -1
var found_ok := 0
var empty_ok := 0
var refilled := 0
var grew := 0
var skipped := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	net.inventory_changed.connect(_on_inventory)


func on_login(reconnect: bool, _character: Dictionary) -> void:
	if _step != Step.WAIT and _step != Step.DONE:
		skipped += 1
		_step = Step.DONE
	if not reconnect:
		_me = str(bot.bot_name).ends_with(MY_SUFFIX)
		_step = Step.FIRST if _me else Step.DONE
		_next_at = bot.elapsed + FIRST_DELAY


func _on_inventory(items: Dictionary) -> void:
	var t := 0
	for k in items:
		t += int(items[k])
	_pack_total = t
	if _before >= 0 and t > _before:
		grew += 1
		_before = -1


func on_play(_delta: float) -> void:
	if _step == Step.WAIT or _step == Step.DONE or bot.elapsed < _next_at:
		return
	if _sent_at >= 0.0:
		if _sent_at <= bot.elapsed and bot.elapsed - _sent_at > ANSWER_TIMEOUT:
			fail("no answer to /loot (%s)" % Step.keys()[_step].to_lower())
			_step = Step.DONE
		return
	if float(bot.duration) - bot.elapsed < QUIET_BEFORE:
		skipped += 1
		_step = Step.DONE
		return
	match _step:
		Step.FIRST:
			_before = _pack_total
			_send("/loot")
		Step.AGAIN:
			_send("/loot")
		Step.REFILL:
			_send("/loot refill")


func _send(line: String) -> void:
	_sent_at = bot.elapsed + 30.0 # until it actually goes out of the queue
	bot.send_command(line, func(): _sent_at = bot.elapsed)


func _on_system(text: String) -> void:
	if _sent_at < 0.0 or _sent_at > bot.elapsed:
		return
	match _step:
		Step.FIRST:
			if not text.begins_with("You search the"):
				return
			if text.begins_with("You search the chest and find"):
				found_ok += 1
			else:
				fail("/loot answered: %s" % text)
			_sent_at = -1.0
			_step = Step.AGAIN
			_next_at = bot.elapsed + 1.0
		Step.AGAIN:
			if text.begins_with("You've searched this"):
				if text.ends_with("Come back tomorrow."):
					empty_ok += 1
				else:
					fail("a searched spot answered: %s" % text)
			elif text.begins_with("You search the"):
				fail("a searched spot paid again: %s" % text)
			else:
				return
			_sent_at = -1.0
			_step = Step.REFILL
			_next_at = bot.elapsed + 1.0
		Step.REFILL:
			if text == "Every loot spot is full again.":
				refilled += 1
				_sent_at = -1.0
				_step = Step.DONE


func on_finish() -> void:
	stat("found_ok", found_ok)
	stat("empty_ok", empty_ok)
	stat("refilled", refilled)
	stat("pack_grew", grew)
	stat("skipped", skipped)
	if _me and skipped == 0:
		if found_ok == 0:
			fail("never found anything with /loot")
		if found_ok > 0 and grew == 0:
			fail("/loot found something but the pack never grew")
		if found_ok > 0 and empty_ok == 0:
			fail("a searched spot was never refused")

extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): protocol v5, the players panel's roster and the Esc menu's
## "Return to Spawn Meadow".
##
## Roster (s2c_roster): after every login one must arrive that lists us (our id and name);
## every roster is sorted by name (any case), has no id twice, and every level is at least 4
## (four skills at level 1). With other bots expected, some roster must list more than us.
##
## Return to Spawn Meadow (c2s_unstuck), twice per bot:
##   1. a second after the first login, still in the meadow: the server must say we are
##      already there (or, if we did wander out, take us home), and never leave it unanswered;
##   2. in the last few seconds of the second play phase, after the other behaviours have
##      done their work, and only while we aren't gathering: if we stand outside the meadow
##      it must answer ok, and our own next snapshots must put us within 3 m of spawn.
##      The final position the bot test checks after logout is then the spawn spot, so the
##      move is saved like any other.

const FIRST_ASK_AFTER := 1.0 ## seconds after the first login
const LAST_ASK_BEFORE_END := 5.0 ## seconds before the bot's duration ends
const ANSWER_TIMEOUT := 4.0

var _logins := 0
var _awaiting_roster := false
var _roster_wait := 0.0
var rosters := 0
var biggest := 0
var _gathering := false

var _asks := 0
var _asked_at := -1.0 ## bot.elapsed when the open ask went out, -1 when none is open
var _asked_from := Vector3.ZERO
var _first_done := false
var _last_done := false
var _login_at := 0.0
var _expect_home := false
var homes := 0
var already := 0


func setup(net: Node) -> void:
	net.roster_changed.connect(_on_roster)
	net.unstuck_result.connect(_on_unstuck)
	net.gather_begun.connect(func(peer: int, _node: int, _s: float):
		if peer == bot.my_id:
			_gathering = true)
	net.gather_ended.connect(func(peer: int, _node: int, _r: String):
		if peer == bot.my_id:
			_gathering = false)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_logins += 1
	_awaiting_roster = true
	_roster_wait = 0.0
	_login_at = bot.elapsed
	_gathering = false
	_asked_at = -1.0 # an ask from before the logout belongs to the old session
	_expect_home = false


func _on_roster(entries: Array) -> void:
	rosters += 1
	biggest = maxi(biggest, entries.size())
	var ids := {}
	var names: Array = []
	var me := false
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY or not (e.has("id") and e.has("name") and e.has("level")):
			fail("bad roster entry: %s" % [e])
			return
		if ids.has(int(e.id)):
			fail("peer %d twice in the roster" % int(e.id))
		ids[int(e.id)] = true
		names.append(str(e.name))
		if int(e.level) < Skills.ORDER.size():
			fail("%s has total level %d" % [e.name, int(e.level)])
		if int(e.id) == bot.my_id:
			me = true
			if str(e.name) != str(bot.bot_name):
				fail("the roster calls us %s, not %s" % [e.name, bot.bot_name])
	for i in range(1, names.size()):
		if names[i - 1].nocasecmp_to(names[i]) > 0:
			fail("roster not sorted by name: %s" % [names])
			break
	if me:
		_awaiting_roster = false


func _ask() -> void:
	_asks += 1
	_asked_at = bot.elapsed
	_asked_from = bot.my_pos
	bot.set_meta("unstuck_at", bot.elapsed) # gameplay_gather_v3 forgives a "moved" end now
	bot.send_play("c2s_unstuck")


func _on_unstuck(ok: bool, text: String, wait_seconds: float) -> void:
	if _asked_at < 0.0:
		fail("s2c_unstuck_result we didn't ask for: %s" % text)
		return
	_asked_at = -1.0
	_tell_fun_metrics()
	var from_spawn := Vector2(_asked_from.x - GameConfig.SPAWN_POINT.x, _asked_from.z - GameConfig.SPAWN_POINT.z).length()
	if ok:
		homes += 1
		if absf(wait_seconds - GameConfig.UNSTUCK_COOLDOWN) > 0.01:
			fail("ok but the cooldown is %.1f s" % wait_seconds)
		_expect_home = true
	elif text == "You're already in Spawn Meadow.":
		already += 1
		if from_spawn > GameConfig.UNSTUCK_NEAR + 3.0: # we may have walked a little since the ask
			fail("told we're in Spawn Meadow %.1f m from spawn" % from_spawn)
	elif text.begins_with("You can return to Spawn Meadow again in"):
		if wait_seconds <= 0.0:
			fail("cooldown refusal with no wait: %s" % text)
	else:
		fail("unexpected unstuck answer: %s" % text)


func on_snapshot(_tick: int, _entries: Array) -> void:
	if _expect_home:
		_expect_home = false
		var d := Vector2(bot.my_pos.x - GameConfig.SPAWN_POINT.x, bot.my_pos.z - GameConfig.SPAWN_POINT.z).length()
		# 3 m spot, plus one tick of walking if the bot was holding a key.
		if d > 3.0 + GameConfig.WALK_SPEED * GameConfig.TICK_DT * 2.0 + 0.05:
			fail("Return to Spawn Meadow said ok but we're %.1f m from spawn" % d)


func on_play(delta: float) -> void:
	if _awaiting_roster:
		_roster_wait += delta
		if _roster_wait > 5.0:
			_awaiting_roster = false
			fail("no s2c_roster listing us within 5 s of login %d" % _logins)
	if _asked_at >= 0.0:
		if bot.elapsed - _asked_at > ANSWER_TIMEOUT:
			fail("c2s_unstuck never answered")
			_asked_at = -1.0
		return
	if not _first_done and _logins == 1 and bot.elapsed - _login_at >= FIRST_ASK_AFTER:
		_first_done = true
		_ask()
	elif not _last_done and str(bot.phase) == "playing_2" and not _gathering \
			and bot.elapsed >= float(bot.duration) - LAST_ASK_BEFORE_END:
		_last_done = true
		_ask()


func on_finish() -> void:
	stat("rosters", rosters)
	stat("biggest_roster", biggest)
	stat("unstuck_asks", _asks)
	stat("unstuck_home", homes)
	stat("unstuck_already", already)
	if _logins > 0 and rosters == 0:
		fail("never got an s2c_roster")
	if int(bot.expect_peers) > 0 and biggest < 2:
		fail("never saw anyone else in the roster")
	if _logins > 0 and not _first_done:
		fail("never asked to return to Spawn Meadow")


## The answer to "Return to Spawn Meadow" is the game answering a press (the player is moved
## or told they are already home), but qa's fun metrics don't listen for s2c_unstuck_result
## yet, so since the ask goes through bot.send_play (an action) it counted as a 5 s wait with
## no feedback and failed --fun-check. Until qa hooks net.unstuck_result in
## qa_fun_metrics.gd (request filed in docs/workstreams/qa.md), report it here. Counting it
## twice later is harmless: feedback at the same moment changes nothing.
func _tell_fun_metrics() -> void:
	for b in bot.behaviours:
		var fm = b.get("m")
		if fm is Object and fm.has_method("feedback"):
			fm.feedback(bot.elapsed)

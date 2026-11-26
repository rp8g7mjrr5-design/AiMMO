extends RefCounted
## Fun metrics for one bot, worked out from what the server tells it (owner direction 1,
## "fun comes first"). Pure maths on timestamps so tests/unit/test_qa_fun_metrics.gd can
## check it without a server; tests/bot_test/behaviours/qa_fun_metrics.gd feeds it.
##
##   first_reward_s   seconds from the first login to the first item landing in the pack
##   longest_dead_s   longest stretch of play with no feedback from the game (a system line
##                    answering the player, an item, gather progress). Offline time and the
##                    gap across a disconnect do not count: each play stretch starts fresh.
##                    Includes time a bot just wanders, so it is reported, not limited.
##   longest_wait_s   "dead time while acting": longest time from the player doing something
##                    (a command or a press of E) to the game's next feedback. This is the one
##                    held to a limit: nobody should press a key and hear nothing.
##   rewards_per_min  items received per minute of play
##   loops_completed  crafts that used gathered items (gather -> craft); "use" joins it once
##                    tools do something players can see
##   gather_s         all seconds spent in timed gathers (holding a timed gather, ours only)
##                    (The level-up numbers went with the leveling system on 2026-11-26.)
##   swings, swings_refused, swings_hit, kills  combat (protocol v7): our own swings the
##                    server began (s2c_swing), refused (s2c_attack_refused), that struck
##                    something (s2c_swing_hits naming a creature), and creatures we brought
##                    down (the hunt's first drop arriving as s2c_gather_result). Each of the
##                    first three is the game answering a press, so it is feedback too; a
##                    kill's drops are rewards like a gather's haul.
##
## Where the numbers come from (protocol v3): a press of E, a cancel and a Craft press
## (bot.play_sent) are actions like a slash command; s2c_gather_begin/end for us and a failed
## s2c_craft_result are feedback; s2c_gather_result and an ok s2c_craft_result are rewards.
## The server also sends a text line for most of these ("You gather 2 ash wood ..."), right
## after the RPC, for the chat feed. echo() drops that line so nothing is counted twice; the dev commands'
## text-only answers (/gather, /craft) still count from the text.
##
## Other bots' chat and join/leave notices are not feedback here: they are bot chatter, and
## a player alone in the world would not get them.

var _first_login := -1.0
var _first_reward := -1.0
var _playing := false
var _last_feedback := 0.0
var _longest_dead := 0.0
var _longest_dead_at := 0.0
var _play_time := 0.0
var _play_started := 0.0
var _act_since := -1.0 ## first unanswered action since the last feedback, or -1
var _longest_wait := 0.0
var _gather_since := -1.0 ## when our running timed gather started, or -1
var _gather_time := 0.0
var rewards := 0
var loops := 0
var feedback_events := 0
var swings := 0
var swings_refused := 0
var swings_hit := 0
var kills := 0
## Text lines still expected after an RPC already counted them: [kind, at, count] (see echo()).
var _echoes: Array = []
## Seconds within which a text line after its RPC counts as the same answer. The server sends
## both in the same tick on the same reliable channel; the window only covers a frame split.
const ECHO_WINDOW := 0.5


## A play stretch starts (login). The dead-time clock starts here too.
func start_play(t: float) -> void:
	if _first_login < 0.0:
		_first_login = t
	_playing = true
	_play_started = t
	_last_feedback = t


## A play stretch ends (disconnect or end of test). The open gap counts up to here.
func stop_play(t: float) -> void:
	if not _playing:
		return
	_close_gap(t)
	_close_wait(t)
	gather_ended(t)
	_play_time += t - _play_started
	_playing = false


func feedback(t: float) -> void:
	if not _playing:
		return
	feedback_events += 1
	_close_gap(t)
	_close_wait(t)
	_last_feedback = t


## The player did something that should get an answer (sent a command, pressed E).
func act(t: float) -> void:
	if _playing and _act_since < 0.0:
		_act_since = t


func reward(t: float, count: int) -> void:
	if count <= 0:
		return
	feedback(t)
	rewards += count
	if _first_reward < 0.0 and _first_login >= 0.0:
		_first_reward = t - _first_login


## A craft finished: what it made is a reward, and a gather -> craft loop is done.
func crafted(t: float, count: int) -> void:
	reward(t, maxi(count, 1))
	loops += 1


## One of our timed gathers started (s2c_gather_begun for us). Only times the gathering;
## feedback is still counted from the server lines, as before, so the baseline holds.
func gather_begun(t: float) -> void:
	if _playing:
		gather_ended(t) # a new start replaces a running one
		_gather_since = t


## Our running gather stopped, for any reason (done, walked off, cancelled, disconnect).
func gather_ended(t: float) -> void:
	if _gather_since >= 0.0:
		_gather_time += maxf(0.0, t - _gather_since)
	_gather_since = -1.0


## Seconds spent gathering so far, a running gather included up to `t`.
func gather_time(t: float) -> float:
	return _gather_time + (maxf(0.0, t - _gather_since) if _gather_since >= 0.0 else 0.0)


## Our swing began (s2c_swing for us): the game answered the press.
func swing(t: float) -> void:
	if _playing:
		swings += 1
	feedback(t)


## Our swing was refused (s2c_attack_refused): a refusal is still an answer.
func swing_refused(t: float) -> void:
	if _playing:
		swings_refused += 1
	feedback(t)


## Our blow resolved (s2c_swing_hits for us; the swinger always gets it, maybe empty).
## `hit` is whether it struck anything.
func swing_landed(t: float, hit: bool) -> void:
	if _playing and hit:
		swings_hit += 1
	feedback(t)


## We brought a creature down. Its drops are counted by reward() as they arrive; this only
## counts the kill.
func kill(t: float) -> void:
	if _playing:
		kills += 1
	feedback(t)


## An RPC counted an answer the server will also send as text ("gather" with the item
## count): remember it so echo() can drop that line.
func expect_echo(kind: String, t: float, count: int = 0) -> void:
	_echoes = _echoes.filter(func(e: Array) -> bool: return t - float(e[1]) <= ECHO_WINDOW)
	_echoes.append([kind, t, count])


## True (and forgets it) when this text line repeats an answer an RPC already counted:
## same kind, same count, at most ECHO_WINDOW later. A text line nobody expected counts.
func echo(kind: String, t: float, count: int = 0) -> bool:
	for i in _echoes.size():
		var e: Array = _echoes[i]
		if e[0] == kind and int(e[2]) == count and t - float(e[1]) >= 0.0 and t - float(e[1]) <= ECHO_WINDOW:
			_echoes.remove_at(i)
			return true
	return false


func _close_gap(t: float) -> void:
	var gap := t - _last_feedback
	if gap > _longest_dead:
		_longest_dead = gap
		_longest_dead_at = _last_feedback


func _close_wait(t: float) -> void:
	if _act_since >= 0.0:
		_longest_wait = maxf(_longest_wait, t - _act_since)
	_act_since = -1.0


## Play time so far, including an open stretch up to `now`.
func play_time(now: float) -> float:
	return _play_time + ((now - _play_started) if _playing else 0.0)


## The bot's numbers. first_reward_s is -1 when nothing was ever received.
func result() -> Dictionary:
	var minutes := _play_time / 60.0
	var out := {
		"first_reward_s": snappedf(_first_reward, 0.01) if _first_reward >= 0.0 else -1.0,
		"longest_dead_s": snappedf(_longest_dead, 0.01),
		"longest_dead_from_s": snappedf(_longest_dead_at - maxf(_first_login, 0.0), 0.01),
		"longest_wait_s": snappedf(_longest_wait, 0.01),
		"rewards": rewards,
		"rewards_per_min": snappedf(rewards / minutes, 0.01) if minutes > 0.0 else 0.0,
		"loops_completed": loops,
		"feedback_events": feedback_events,
		"play_s": snappedf(_play_time, 0.01),
		"gather_s": snappedf(_gather_time, 0.01),
		"swings": swings,
		"swings_refused": swings_refused,
		"swings_hit": swings_hit,
		"kills": kills,
	}
	return out


## How many items a server line gave, or 0. "You gather 2 ash wood ..." gives 2; a craft
## line ("You craft ...") gives what it made (1 for a tool).
static func items_in(text: String) -> int:
	var m := RegEx.create_from_string("^You (gather|craft) (\\d+) ").search(text)
	if m:
		return m.get_string(2).to_int()
	if text.begins_with("You craft a"):
		return 1
	return 0


## True when s2c_gather_result(item, ...) is the first drop of a kill: the server sends one
## per drop in Wildlife.drops order, so the first drop of any creature kind marks one kill.
## No gather node yields a hunt drop (test_qa_fun_metrics checks), so a haul never counts.
static func is_kill_drop(item: String) -> bool:
	for kind in Wildlife.KINDS:
		var d: Array = Wildlife.drops(str(kind))
		if not d.is_empty() and str(d[0][0]) == item:
			return true
	return false


## True for server lines that are other players coming and going, not feedback to us.
static func is_notice(text: String) -> bool:
	return text.ends_with(" has arrived.") or text.ends_with(" has left.")

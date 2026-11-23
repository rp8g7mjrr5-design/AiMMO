extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): skills and XP (Milestone 1, server side).
##
## Every login must hand the client a character with a `skills` Dictionary (skill id -> XP),
## and after a reconnect it must hold at least the XP the server last reported: XP survives
## logout. While the other behaviours gather and craft, the bot asks the hidden /skills dev
## command (at most every ASK_GAP seconds, after it has gathered something) and checks:
## - XP never goes down, in any skill, within a login or across one;
## - once a gather of ours paid out (s2c_gather_result), some gathering skill shows XP;
## - every level-up line ("Felling is now level 2! ...") names a real skill, a level above
##   1, and matches what the next /skills reply says.
## Commands go through bot.send_command like every behaviour; TOO_FAST resends soon.

const FIRST_DELAY := 14.0 ## after the chat-command and /bag behaviours' first lines
const ASK_GAP := 20.0
const RETRY_AFTER := 3.0
const MAX_TRIES := 5
const MAX_TOO_FAST := 12
const GATHER_SKILLS := ["felling", "quarrying", "tapping"]

var _next_at := 0.0
var _waiting := false
var _tries := 0
var _too_fast := 0
var _logins := 0
var _results := 0 ## our own gathers that paid out, this run
var _results_at_ask := 0
var _last := {} ## skill -> XP from the latest /skills reply (or login), this run
var _levels_claimed := {} ## skill -> highest level a level-up line announced
var answers := 0
var level_ups := 0
var persisted_checks := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)
	net.gather_result.connect(func(_item: String, count: int):
		if count > 0:
			_results += 1)


func on_login(reconnect: bool, character: Dictionary) -> void:
	_logins += 1
	var sk = character.get("skills")
	if typeof(sk) != TYPE_DICTIONARY:
		fail("login character has no skills Dictionary: %s" % character.keys())
		sk = {}
	var now := Skills.normalize(sk)
	if reconnect:
		for id in _last:
			if Skills.xp_of(now, id) < int(_last[id]):
				fail("%s XP went from %d to %d across a reconnect" % [id, int(_last[id]), Skills.xp_of(now, id)])
		persisted_checks += 1
	for id in now:
		_last[id] = maxi(int(_last.get(id, 0)), int(now[id]))
	_waiting = false
	_tries = 0
	_too_fast = 0
	_next_at = bot.elapsed + FIRST_DELAY + bot.rng.randf_range(0.0, 2.0)


func on_play(_delta: float) -> void:
	if bot.elapsed < _next_at:
		return
	if _waiting:
		if _tries >= MAX_TRIES:
			fail("no reply to /skills after %d tries" % _tries)
			_waiting = false
			_next_at = bot.elapsed + ASK_GAP
			return
	elif answers > 0 and _results == _results_at_ask:
		return # nothing new to look at since the last answer
	_tries += 1
	_waiting = true
	_results_at_ask = _results
	_next_at = bot.elapsed + RETRY_AFTER
	bot.send_command("/skills")


func _on_system(text: String) -> void:
	var lv := RegEx.create_from_string("^(\\w+) is now level (\\d+)!").search(text)
	if lv != null:
		_on_level_up(lv.get_string(1), lv.get_string(2).to_int(), text)
		return
	if _waiting and text == ChatCommands.TOO_FAST and _too_fast < MAX_TOO_FAST:
		_too_fast += 1
		_tries = maxi(0, _tries - 1)
		_next_at = minf(_next_at, bot.elapsed + 0.6 + bot.rng.randf_range(0.0, 0.3))
		return
	if not _waiting or not text.begins_with("Skills: "):
		return
	_waiting = false
	_tries = 0
	_too_fast = 0
	answers += 1
	_next_at = bot.elapsed + ASK_GAP
	var got := _parse(text)
	if got.is_empty():
		fail("unreadable /skills reply: %s" % text)
		return
	var gathered_xp := 0
	for id in got:
		if int(got[id]) < int(_last.get(id, 0)):
			fail("%s XP went down: %d then %d" % [id, int(_last.get(id, 0)), int(got[id])])
		_last[id] = maxi(int(_last.get(id, 0)), int(got[id]))
		if id in GATHER_SKILLS:
			gathered_xp += int(got[id])
	if _results_at_ask > 0 and gathered_xp <= 0:
		fail("%d gathers paid out but no gathering skill has XP: %s" % [_results_at_ask, text])
	for id in _levels_claimed:
		if Skills.level_for(int(got.get(id, 0))) < int(_levels_claimed[id]):
			fail("told %s reached %d but /skills says %s" % [id, int(_levels_claimed[id]), text])


func _on_level_up(skill_label: String, level: int, text: String) -> void:
	var id := skill_label.to_lower()
	if not Skills.is_skill(id):
		fail("level-up for an unknown skill: %s" % text)
		return
	if level < 2 or level > Skills.CAP:
		fail("impossible level in: %s" % text)
		return
	level_ups += 1
	_levels_claimed[id] = maxi(int(_levels_claimed.get(id, 0)), level)


## "Skills: Felling 2 (10/325 XP), ..., Toolcraft 100 (max)." -> {felling: 160, ...}
static func _parse(text: String) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("(\\w+) (\\d+) \\((?:(\\d+)/\\d+ XP|max)\\)")
	for m in re.search_all(text):
		var id := m.get_string(1).to_lower()
		if not Skills.is_skill(id):
			continue
		var into := m.get_string(3).to_int() if m.get_string(3) != "" else 0
		out[id] = Skills.xp_for_level(m.get_string(2).to_int()) + into
	return out if out.size() == Skills.SKILLS.size() else {}


func on_finish() -> void:
	stat("skills_answers", answers)
	stat("level_ups", level_ups)
	stat("xp_total", _last.values().reduce(func(a, b): return int(a) + int(b), 0))
	stat("persisted_checks", persisted_checks)
	if answers < 1:
		fail("/skills answered %d times over %d logins" % [answers, _logins])

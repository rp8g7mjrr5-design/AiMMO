extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): protocol v4's skills messages, the ones the client's XP popups,
## level-up banner, burst and skills window read. Purely passive: it listens while the other
## behaviours gather and craft, and checks:
## - every login is followed by one s2c_skills with all four skills, matching the login
##   character, and never lower than what the last login's s2c_xp said (XP survives logout);
## - every s2c_xp names a real skill, gains more than 0, and its total is exactly the last
##   total plus the gain (the client can keep a running total without asking again);
## - every s2c_level_up names the level that the last s2c_xp total reaches, above the last
##   level we knew, and its unlocks are the table's ({level, name, text});
## - our timed gathers that paid out (s2c_gather_result) earned gathering XP;
## - s2c_level_up_seen is never about ourselves and always names a real skill.

const GATHER_SKILLS := ["felling", "quarrying", "tapping"]

var _logins := 0
var _skills_msgs := 0
var _awaiting_skills := false
var _login_skills := {} ## the login character's skills, until s2c_skills arrives
var _total := {} ## skill -> XP as the server last told us (s2c_skills or s2c_xp)
var _results := 0
var _gather_xp_msgs := 0
var xp_msgs := 0
var level_ups := 0
var seen := 0


func setup(net: Node) -> void:
	net.skills_changed.connect(_on_skills)
	net.xp_gained.connect(_on_xp)
	net.level_up.connect(_on_level_up)
	net.level_up_seen.connect(_on_seen)
	net.gather_result.connect(func(_item: String, count: int):
		if count > 0:
			_results += 1)


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_logins += 1
	_awaiting_skills = true
	_login_skills = Skills.normalize(character.get("skills", {}))



func _on_skills(skills: Dictionary) -> void:
	_skills_msgs += 1
	if not _awaiting_skills:
		fail("s2c_skills outside a login")
	_awaiting_skills = false
	for id in Skills.ORDER:
		if not skills.has(id):
			fail("s2c_skills is missing %s: %s" % [id, skills])
			continue
		var xp := int(skills[id])
		if xp != Skills.xp_of(_login_skills, id):
			fail("s2c_skills says %s %d but the login character has %d" % [id, xp, Skills.xp_of(_login_skills, id)])
		if xp < int(_total.get(id, 0)):
			fail("%s XP went from %d to %d across a reconnect" % [id, int(_total.get(id, 0)), xp])
		_total[id] = xp


func _on_xp(skill: String, gained: int, total_xp: int) -> void:
	xp_msgs += 1
	if not Skills.is_skill(skill):
		fail("s2c_xp for an unknown skill %s" % skill)
		return
	if gained <= 0:
		fail("s2c_xp gained %d" % gained)
	if _awaiting_skills:
		fail("s2c_xp before s2c_skills")
	var before := int(_total.get(skill, 0))
	if total_xp != before + gained:
		fail("%s: %d + %d should be %d, got %d" % [skill, before, gained, before + gained, total_xp])
	_total[skill] = total_xp
	if skill in GATHER_SKILLS:
		_gather_xp_msgs += 1


func _on_level_up(skill: String, level: int, unlocks: Array) -> void:
	level_ups += 1
	if not Skills.is_skill(skill):
		fail("s2c_level_up for an unknown skill %s" % skill)
		return
	var expect := Skills.level_for(int(_total.get(skill, 0)))
	if level != expect:
		fail("s2c_level_up says %s %d but our XP (%d) is level %d" % [skill, level, int(_total.get(skill, 0)), expect])
	if level < 2:
		fail("s2c_level_up to level %d" % level)
	for u in unlocks:
		if typeof(u) != TYPE_DICTIONARY or not (u.has("name") and u.has("text") and u.has("level")):
			fail("bad unlock in s2c_level_up: %s" % [u])
			continue
		var want = Skills.unlock_at(skill, int(u.level))
		if want == null or str(want.name) != str(u.name) or int(u.level) > level:
			fail("s2c_level_up unlock %s is not %s's table entry" % [u, skill])


func _on_seen(peer_id: int, skill: String, level: int) -> void:
	seen += 1
	if peer_id == bot.my_id:
		fail("s2c_level_up_seen about ourselves")
	if not Skills.is_skill(skill) or level < 2:
		fail("bad s2c_level_up_seen: %s %d" % [skill, level])


func on_finish() -> void:
	stat("skills_msgs", _skills_msgs)
	stat("xp_msgs", xp_msgs)
	stat("v4_level_ups", level_ups)
	stat("level_ups_seen", seen)
	if _skills_msgs < _logins - (1 if _awaiting_skills else 0):
		fail("%d logins but only %d s2c_skills" % [_logins, _skills_msgs])
	if _results > 0 and _gather_xp_msgs < _results:
		fail("%d gathers paid out but only %d gathering s2c_xp" % [_results, _gather_xp_msgs])

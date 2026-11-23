extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the skills window and next-goal line (Milestone 1, part 3). Network-only (art bible
## section 7: no window is built). Each bot keeps the server's skill totals from s2c_skills
## and s2c_xp, as the client's SkillsWindow does, and checks on every gain:
## - the window's level and "XP to level N" texts match the shared Skills rules for that total;
## - the total level is the sum of the four skill levels;
## - the goal line always names a real, built unlock that is still ahead, and the XP it says is
##   left equals the threshold minus the server's total; it never goes up for the same goal;
## - the goal follows what the bot trains: a skill it has XP in (or the first skill before any).

var _skills := {}
var _gains := 0
var _goals_reached := 0
var _goal_key := ""
var _goal_need := -1
var _trained_goals := 0


func setup(net: Node) -> void:
	net.skills_changed.connect(func(skills: Dictionary):
		_skills = Skills.normalize(skills)
		_goal_key = ""
		_check_goal())
	net.xp_gained.connect(_on_xp)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_skills = {}
	_goal_key = ""
	_goal_need = -1


func _on_xp(skill: String, _gained: int, total_xp: int) -> void:
	if not Skills.is_skill(skill):
		return
	_gains += 1
	_skills[skill] = total_xp
	var lv := Skills.level_for(total_xp)
	if SkillsWindow.level_text(_skills, skill) != "%s %d" % [Skills.label(skill), lv]:
		fail("level text %s at %d XP" % [SkillsWindow.level_text(_skills, skill), total_xp])
	if lv < Skills.CAP and not SkillsWindow.xp_text(_skills, skill).ends_with("XP to level %d" % (lv + 1)):
		fail("xp text %s at level %d" % [SkillsWindow.xp_text(_skills, skill), lv])
	var sum := 0
	for s in Skills.ORDER:
		sum += Skills.level_of(_skills, s)
	if SkillsWindow.total_level(_skills) != sum:
		fail("total level %d, levels add up to %d" % [SkillsWindow.total_level(_skills), sum])
	_check_goal()


func _check_goal() -> void:
	var g := SkillsWindow.next_goal(_skills)
	if g.is_empty():
		return
	var u = Skills.unlock_at(str(g.skill), int(g.level))
	if u == null or u.get("soon", false):
		fail("goal %s is not a built unlock" % g)
		return
	var xp := Skills.xp_of(_skills, str(g.skill))
	var trained := Skills.ORDER.filter(func(s): return Skills.xp_of(_skills, s) > 0)
	if trained.is_empty():
		if str(g.skill) != str(Skills.ORDER[0]):
			fail("a fresh character's goal is %s, not the first skill" % g)
	elif xp <= 0 and not SkillsWindow._closest(_skills, trained).is_empty():
		fail("goal %s is in a skill the bot never trained (trained: %s)" % [g, trained])
	else:
		_trained_goals += 1
	if Skills.level_for(xp) >= int(g.level):
		fail("goal %s is already reached at %d XP" % [g, xp])
	if int(g.need) != Skills.xp_for_level(int(g.level)) - xp:
		fail("goal says %d XP left, server total says %d" % [int(g.need), Skills.xp_for_level(int(g.level)) - xp])
	if not SkillsWindow.goal_text(_skills).begins_with("Next: %s %d unlocks " % [Skills.label(str(g.skill)), int(g.level)]):
		fail("goal line %s" % SkillsWindow.goal_text(_skills))
	var key := SkillsWindow.goal_key(_skills)
	if key == _goal_key and _goal_need >= 0 and int(g.need) > _goal_need:
		fail("goal %s went from %d to %d XP left" % [key, _goal_need, int(g.need)])
	if _goal_key != "" and key != _goal_key:
		_goals_reached += 1
	_goal_key = key
	_goal_need = int(g.need)


func on_finish() -> void:
	stat("gains", _gains)
	stat("goal_changes", _goals_reached)
	stat("goals_in_trained_skills", _trained_goals)

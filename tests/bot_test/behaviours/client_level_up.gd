extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the level-up moment (Milestone 1, part 2). Network-only (art bible section 7: the
## banner's look is in tests/unit/test_client_level_up.gd). While gameplay's bots level up,
## each bot checks the messages the banner is built from:
## - s2c_level_up's level matches the total XP of the last s2c_xp for that skill;
## - its unlocks are exactly the shared table's unlock at that level (or none);
## - the banner's title and next-goal texts come out non-empty and name the skill;
## - the server's level-up system line equals LevelUpBanner.announcement(...), so the client
##   keeps it out of chat (chat is for talking).

const BannerScript := preload("res://client/level_up_banner.gd")

var _totals := {}
var _levels := 0
var _expect_line := ""
var _swallowed := 0


func setup(net: Node) -> void:
	net.skills_changed.connect(func(skills: Dictionary): _totals = Skills.normalize(skills))
	net.xp_gained.connect(func(skill: String, _g: int, total: int): _totals[skill] = total)
	net.level_up.connect(_on_level_up)
	net.system_message.connect(_on_system)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_expect_line = ""


func _on_level_up(skill: String, level: int, unlocks: Array) -> void:
	_levels += 1
	if not Skills.is_skill(skill):
		fail("level-up for unknown skill %s" % skill)
		return
	if _totals.has(skill) and Skills.level_for(int(_totals[skill])) != level:
		fail("level-up says %s %d, last XP total %d is level %d" % [skill, level, _totals[skill], Skills.level_for(int(_totals[skill]))])
	var u = Skills.unlock_at(skill, level)
	var want := 0 if u == null else 1
	if unlocks.size() != want:
		fail("%s %d came with %d unlocks, the table has %d" % [skill, level, unlocks.size(), want])
	elif want == 1 and str(unlocks[0].get("name", "")) != str(u.name):
		fail("%s %d unlock %s, table says %s" % [skill, level, unlocks[0].get("name"), u.name])
	if BannerScript.title_text(skill, level) != "%s %d" % [Skills.label(skill), level]:
		fail("banner title %s" % BannerScript.title_text(skill, level))
	if BannerScript.unlock_text(skill, unlocks) == "" and skill != "toolcraft":
		fail("a %s level-up with nothing to say" % skill)
	_expect_line = BannerScript.announcement(skill, level, unlocks)


func _on_system(text: String) -> void:
	if _expect_line == "" or not text.contains(" is now level "):
		return
	if text != _expect_line:
		fail("level-up line %s doesn't match the banner's %s, so it would show in chat" % [text, _expect_line])
	else:
		_swallowed += 1
	_expect_line = ""


func on_finish() -> void:
	stat("level_ups", _levels)
	stat("lines_kept_out_of_chat", _swallowed)

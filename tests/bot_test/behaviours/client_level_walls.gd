extends "res://tests/bot_test/bot_behaviour.gd"
## Client: level walls read from the server's own skills (Milestone 1, tier-2 nodes and
## Toolcraft 5 recipes). Network-only: no art classes, no messages of its own.
## Each bot keeps the skills the real client keeps (skills_changed at login, then every
## xp_gained total) and, whenever they change, checks the client's rules against the
## shared ones the server uses:
## - every tier-2 node's gather prompt is greyed with "<Node> · <Skill> N (X XP to go)"
##   exactly while Gathering.can_work says no, and offers E exactly when it says yes;
## - every level-gated workbench row says "Needs Toolcraft 5 · ..." exactly while
##   Crafting.level_ok says no;
## - a "level" refusal of one of our gathers (if a bot ever walks into one) is for a node
##   the prompt was showing as walled, and its centre words name the skill.

var _skills := {}
var _known := false
var checks := 0
var walls_seen := 0
var level_refusals := 0
var _day := 0.0


func setup(net: Node) -> void:
	net.skills_changed.connect(func(all: Dictionary):
		_skills = Skills.normalize(all)
		_known = true
		_check_all())
	net.xp_gained.connect(func(skill: String, _gained: int, total: int):
		if Skills.is_skill(skill):
			_skills[skill] = total
			_check_all())
	net.gather_ended.connect(_on_gather_ended)
	for i in 96: # a daytime moment, so night-only seeps never muddy the tier-2 check
		var t := i * WorldClock.DAY_SECONDS / 96.0
		if not WorldClock.is_night(t):
			_day = t
			break


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_known = false


func _check_all() -> void:
	for n in ResourceNodes.tier2():
		var t := GatherPrompt.target(n.pos, _day, Vector3.ZERO, Vector3.ZERO, {}, _skills)
		if t.is_empty() or int(t.id) != int(n.id):
			continue
		checks += 1
		var ok := Gathering.can_work(n, _skills)
		if bool(t.can) != ok or bool(t.needs_level) == ok:
			fail("node %d: prompt can=%s, server rule can_work=%s (skills %s)" % [n.id, t.can, ok, _skills])
		if not ok:
			walls_seen += 1
			if str(t.text) != GatherPrompt.need_text(n, _skills) or not str(t.text).contains("XP to go"):
				fail("node %d walled prompt says '%s'" % [n.id, t.text])
	for id in Crafting.RECIPE_ORDER:
		if Crafting.required(id).is_empty():
			continue
		checks += 1
		var r := CraftWindow.row({}, id, Crafting.workbench_pos(), _skills)
		var ok := Crafting.level_ok(id, _skills)
		if (r.reason == "level") == ok:
			fail("%s: row reason '%s', server level_ok=%s" % [id, r.reason, ok])
		if not ok and not str(r.hint).begins_with("Needs "):
			fail("%s walled row hint '%s'" % [id, r.hint])


func _on_gather_ended(peer: int, node_id: int, reason: String) -> void:
	if peer != int(bot.my_id) or reason != "level":
		return
	level_refusals += 1
	var n := ResourceNodes.get_by_id(node_id)
	if _known and Gathering.can_work(n, _skills):
		fail("server refused node %d for level, but our skills %s can work it" % [node_id, _skills])
	if not GatherPrompt.notice_for(reason, node_id).begins_with("Needs "):
		fail("level refusal notice '%s'" % GatherPrompt.notice_for(reason, node_id))


func on_finish() -> void:
	stat("checks", checks)
	stat("walls_seen", walls_seen)
	stat("level_refusals", level_refusals)
	if not _known and checks == 0:
		fail("never got skills from the server")
	if checks < 1:
		fail("never checked a level wall")

extends "res://tests/bot_test/bot_behaviour.gd"
## Client: XP you can see (Milestone 1, part 1). Each bot runs the real XpMeter on the
## server's s2c_skills and s2c_xp while the other behaviours gather and craft, and checks:
## - every gain shows "+N Skill" and the skill's "Skill L · N XP to L+1" line straight away;
## - the meter's running total for that skill equals the server's total (no drift);
## - the bar lands on the server's progress for that total and then fades away;
## - a gain that crosses a level holds the bar full (brightened) before it wraps.

const MeterScript := preload("res://client/xp_meter.gd")

var _meter: Control
var _gains := 0
var _landed := 0
var _faded := 0
var _pending := false ## a gain whose bar hasn't been checked yet
var _expect := 0.0
var _age := 0.0
var _held := 0 ## level-up gains seen holding the bar full
var _hold_seen := false


func setup(net: Node) -> void:
	net.skills_changed.connect(func(skills: Dictionary):
		if _meter != null:
			_meter.on_skills(skills))
	net.xp_gained.connect(_on_xp)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _meter == null:
		_meter = MeterScript.new()
		_meter.setup(Theme.new())
	else:
		_meter.hide_all() # as the client does on disconnect; s2c_skills seeds it again
	# A gain that landed in the pause before the disconnect was cleared with the bar: don't
	# check it (gameplay's request, 2026-11-23).
	_pending = false
	_age = 0.0


func _on_xp(skill: String, gained: int, total_xp: int) -> void:
	if _meter == null:
		return
	_gains += 1
	_meter.on_gain(skill, gained, total_xp)
	var want := "+%d %s" % [gained, Skills.label(skill)]
	if _meter.gain_label.text != want:
		fail("floater says %s, want %s" % [_meter.gain_label.text, want])
	if not _meter.level_label.text.begins_with("%s %d" % [Skills.label(skill), Skills.level_for(total_xp)]):
		fail("bar label %s doesn't match %s at %d XP" % [_meter.level_label.text, skill, total_xp])
	if int(_meter.skills.get(skill, -1)) != total_xp:
		fail("meter total %s for %s, server says %d" % [_meter.skills.get(skill), skill, total_xp])
	if not _meter.showing():
		fail("a gain didn't show")
	_pending = true
	_expect = Skills.progress(total_xp)
	_age = 0.0
	_hold_seen = false


func on_play(delta: float) -> void:
	if _meter == null:
		return
	var was: bool = _meter.showing()
	_meter.step(delta)
	_age += delta
	if _pending and not _hold_seen and MeterScript.holding_full(_meter.levels_crossed(), _age):
		_hold_seen = true
		_held += 1
		if absf(_meter.bar.value - 1.0) > 0.001:
			fail("a level-up gain should hold the bar full, it shows %.3f" % _meter.bar.value)
	if _pending and _meter.settled():
		_pending = false
		_landed += 1
		if absf(_meter.bar.value - _expect) > 0.001:
			fail("bar landed at %.3f, server progress is %.3f" % [_meter.bar.value, _expect])
	if was and not _meter.showing():
		_faded += 1


func on_finish() -> void:
	stat("gains", _gains)
	stat("landed", _landed)
	stat("faded", _faded)
	stat("level_holds", _held)
	if _meter != null:
		_meter.free()

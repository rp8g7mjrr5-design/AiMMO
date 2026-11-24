extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the health and stamina bar (protocol v7 s2c_vitals). Each bot runs the real
## VitalsBar on the server's s2c_vitals while gameplay_vitals hurts and knocks it down and
## gameplay_first_swing spends stamina, and checks, network-visible only:
## - the first message after each login is full health and doesn't pop the bars up;
## - the bar's numbers always equal the server's (no drift across many 1-point updates);
## - a loss drops the fill to the server's share at once and leaves the chip at or above it;
## - while anything is below full the bars stay on screen;
## - back at full, the bars are gone within HOLD_SECONDS + FADE_SECONDS.

const BarScript := preload("res://client/vitals_bar.gd")

var _bar: Control
var _messages := 0
var _hits := 0
var _thumps := 0
var _faded := 0
var _first_pending := false
var _full_for := 0.0


func setup(net: Node) -> void:
	net.vitals_changed.connect(_on_vitals)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _bar == null:
		_bar = BarScript.new()
		_bar.setup(Theme.new())
	else:
		_bar.hide_all() # as the client does on disconnect
	_first_pending = true
	_full_for = 0.0


func _on_vitals(hp: int, max_hp: int, stamina: int, max_stamina: int) -> void:
	if _bar == null:
		return
	_messages += 1
	var c: Dictionary = _bar.on_vitals(hp, max_hp, stamina, max_stamina)
	if _first_pending:
		_first_pending = false
		if hp != max_hp:
			fail("first s2c_vitals after login is %d/%d, login should be full health" % [hp, max_hp])
		if c.hurt:
			fail("the login message counted as a hit")
		if hp == max_hp and stamina == max_stamina and _bar.showing():
			fail("full at login, but the bars popped up")
	if _bar.hp != hp or _bar.max_hp != max_hp or _bar.stamina != stamina or _bar.max_stamina != max_stamina:
		fail("bar says %d/%d %d/%d, server %d/%d %d/%d" % [_bar.hp, _bar.max_hp, _bar.stamina, _bar.max_stamina, hp, max_hp, stamina, max_stamina])
	if c.hurt:
		_hits += 1
		var want := BarScript.fraction(hp, max_hp)
		if absf(_bar.shown_hp - want) > 0.001:
			fail("a hit should drop the fill at once to %.2f, it shows %.2f" % [want, _bar.shown_hp])
		if _bar.current_chip() < want - 0.001:
			fail("the chip sits under the fill")
		if not _bar.showing():
			fail("a hit didn't show the bars")
	if c.get("thump", false):
		_thumps += 1


func on_play(delta: float) -> void:
	if _bar == null or not _bar.known:
		return
	var was: bool = _bar.showing()
	_bar.step(delta)
	if not _bar.full():
		_full_for = 0.0
		if not _bar.showing():
			fail("health or stamina below full, but the bars are hidden")
	else:
		_full_for += delta
		if _full_for > BarScript.HOLD_SECONDS + BarScript.FADE_SECONDS + 0.2 and _bar.showing():
			fail("full for %.1f s and the bars are still up" % _full_for)
	if was and not _bar.showing():
		_faded += 1


func on_finish() -> void:
	stat("messages", _messages)
	stat("hits", _hits)
	stat("thumps", _thumps)
	stat("faded", _faded)
	if _bar != null:
		_bar.free()

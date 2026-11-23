extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the F1 controls overlay. Each bot installs the client's default keys, builds the
## real overlay window, and opens and closes it a few times while it plays (as a player
## checking the keys would), failing if any listed action has no key, a row comes out empty,
## or the corner hint still sends players to "/help" in chat.

const OverlayScript := preload("res://client/controls_overlay.gd")

var _w: PanelContainer
var _t := 0.0
var _opens := 0
var _closes := 0


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _w != null:
		return
	OverlayScript.install_input()
	_w = OverlayScript.new()
	_w.setup(Theme.new())
	_w.closed.connect(func(): _closes += 1)
	for action in OverlayScript.listed_actions():
		if OverlayScript.key_text(action) == "?":
			fail("%s has no key in the controls list" % action)
	for r in OverlayScript.rows():
		if (r[2] as Array).is_empty() or (r[2] as Array).has("?"):
			fail("row %s shows no key" % r[1])
	if OverlayScript.corner_hint().contains("/help"):
		fail("corner hint still points at /help")


func on_play(delta: float) -> void:
	if _w == null:
		return
	_t += delta
	if _t < 7.0:
		return
	_t = 0.0
	_w.toggle()
	if _w.visible:
		_opens += 1


func on_finish() -> void:
	stat("opens", _opens)
	stat("closes", _closes)
	if bot.stats.get("logins", 0) > 0 and _opens == 0:
		fail("never opened the controls list")
	if _w != null:
		_w.free()

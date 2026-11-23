extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the Graphics quality setting and the F3 overlay. While it plays, each bot picks
## Low, Medium and High in turn as a player trying them would, saves and reloads its settings
## file (one per bot), and checks the level, shadows and view distance survive the round trip
## and match the preset. It also runs the real F3 overlay on its own frames and checks it
## shows a frame rate and the level it picked.

const SettingsScript := preload("res://client/settings.gd")
const OverlayScript := preload("res://client/perf_overlay.gd")
const QualityScript := preload("res://client/quality.gd")

var _overlay: PanelContainer
var _t := 0.0
var _picks := 0
var _redraws := 0
var _path := ""


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	if _overlay != null:
		return
	_path = "user://bot_settings_%s.cfg" % bot.bot_name
	_overlay = OverlayScript.new()
	_overlay.setup(Theme.new())
	_overlay.toggle()


func on_play(delta: float) -> void:
	if _overlay == null:
		return
	if _overlay.step(delta):
		_redraws += 1
		var text: String = _overlay.text()
		if text.begins_with("0 fps"):
			fail("F3 overlay shows 0 fps after %d frames" % _redraws)
		if not text.contains("Graphics: " + QualityScript.level_name()):
			fail("F3 overlay doesn't name the level: %s" % text)
	_t += delta
	if _t < 9.0:
		return
	_t = 0.0
	var level: int = (_picks + bot.rng.randi_range(0, 2)) % 3
	_picks += 1
	var s = SettingsScript.new()
	s.apply_quality(level)
	if s.save_to(_path) != OK:
		fail("could not save settings")
		return
	var back = SettingsScript.load_from(_path)
	var p: Dictionary = QualityScript.preset(level)
	if back.graphics_quality != level:
		fail("picked %s, reloaded %d" % [QualityScript.level_name(level), back.graphics_quality])
	if back.shadow_quality != int(p.shadow_quality) or absf(back.draw_distance - float(p.draw_distance)) > 0.01:
		fail("%s didn't set its shadows and distance" % QualityScript.level_name(level))


func on_finish() -> void:
	stat("picks", _picks)
	stat("overlay_redraws", _redraws)
	if bot.stats.get("logins", 0) > 0 and (_picks == 0 or _redraws == 0):
		fail("never tried the Graphics setting or the F3 overlay")
	if _overlay != null:
		_overlay.free()
	if _path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))

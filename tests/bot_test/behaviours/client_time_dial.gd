extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the time dial on the real server clock. Each bot works out what its dial would
## show from every s2c_world_time, and checks it agrees with the server's clock, never runs
## backwards (beyond a day wrapping), and only ever shows a body that is above the horizon.
## Across a reconnect the readout must carry on, not reset. The hover tooltip (which replaces
## /time) must name the phase the server's clock says comes next with a countdown that matches
## it to the minute, and the "· Night soon" warning shows exactly in a phase's last 90 s.

const TimeDialScript := preload("res://client/time_dial.gd")

var _syncs := 0
var _last_seconds := NAN
var _last_text := ""
var _logins := 0
var _tooltips := 0
var _warnings := 0


func setup(net: Node) -> void:
	net.world_time.connect(_on_world_time)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_logins += 1


func _on_world_time(world_seconds: float) -> void:
	_syncs += 1
	if not is_finite(world_seconds):
		fail("server sent a broken world time %s" % str(world_seconds))
		return
	var st: Dictionary = TimeDialScript.state(world_seconds)
	_last_text = st.text
	if st.day != WorldClock.day_number(world_seconds) or st.phase != WorldClock.phase(world_seconds):
		fail("dial %s disagrees with the clock (%s)" % [st.text, WorldClock.describe(world_seconds)])
	if st.offset.y > 0.0001:
		fail("dial shows the %s below the horizon at %s" % [st.body, st.text])
	if (st.body == "sun") != (WorldClock.sun_elevation(world_seconds) >= 0.0):
		fail("dial shows the %s at %s" % [st.body, st.text])
	if not is_nan(_last_seconds) and world_seconds + 0.5 < _last_seconds:
		fail("server clock ran backwards: %.2f after %.2f" % [world_seconds, _last_seconds])
	_last_seconds = world_seconds
	_check_tooltip(world_seconds, st)


func _check_tooltip(world_seconds: float, st: Dictionary) -> void:
	var lines: PackedStringArray = TimeDialScript.tooltip_text_at(world_seconds).split("\n")
	_tooltips += 1
	if lines.size() != 4 or not st.text.begins_with(lines[0].replace(",", " ·")):
		fail("tooltip %s disagrees with the readout %s" % [" / ".join(lines), st.text])
		return
	var until := WorldClock.seconds_until_next_phase(world_seconds)
	var nxt: String = TimeDialScript.PHASE_NAMES[WorldClock.next_phase(world_seconds)]
	if lines[1] != "%s %s" % [nxt, TimeDialScript.until_text(until)]:
		fail("tooltip says %s, server clock has %s in %.0f s" % [lines[1], nxt, until])
	var warn: String = st.get("soon", "")
	if (warn != "") != (until <= TimeDialScript.SOON_SECONDS) or (warn != "" and warn != nxt + " soon"):
		fail("readout warning '%s' with %s %.0f s away" % [warn, nxt, until])
	if warn != "":
		_warnings += 1


func on_finish() -> void:
	stat("dial_syncs", _syncs)
	stat("dial_text", _last_text)
	stat("tooltips", _tooltips)
	stat("soon_warnings", _warnings)
	if _logins == 0:
		return # the bot never got in; bot.gd reports why
	if _syncs < _logins:
		fail("got %d clock syncs for %d logins (expected one per login at least)" % [_syncs, _logins])

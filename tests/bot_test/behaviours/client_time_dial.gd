extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the time dial on the real server clock. Each bot works out what its dial would
## show from every s2c_world_time, and checks it agrees with the server's clock, never runs
## backwards (beyond a day wrapping), and only ever shows a body that is above the horizon.
## Across a reconnect the readout must carry on, not reset.

const TimeDialScript := preload("res://client/time_dial.gd")

var _syncs := 0
var _last_seconds := NAN
var _last_text := ""
var _logins := 0


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


func on_finish() -> void:
	stat("dial_syncs", _syncs)
	stat("dial_text", _last_text)
	if _logins == 0:
		return # the bot never got in; bot.gd reports why
	if _syncs < _logins:
		fail("got %d clock syncs for %d logins (expected one per login at least)" % [_syncs, _logins])

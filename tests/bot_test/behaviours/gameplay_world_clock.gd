extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): checks the shared world clock.
##
## Every bot must get s2c_world_time after each login, the values must be finite and move
## forward like real time, and two bots on the same server must agree on the time.
## Ported to qa's behaviour interface (bot_behaviour.gd) by the integrator when merging.

var syncs := 0
var logins := 0
var first_seconds := NAN
var first_at_msec := 0
var last_seconds := NAN


func setup(net: Node) -> void:
	net.world_time.connect(_on_world_time)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	logins += 1


func _on_world_time(world_seconds: float) -> void:
	syncs += 1
	var now := Time.get_ticks_msec()
	if not is_finite(world_seconds):
		fail("world time not finite: %s" % world_seconds)
		return
	if is_nan(first_seconds):
		first_seconds = world_seconds
		first_at_msec = now
	else:
		# The server clock should track this bot's local clock. Allow generous slack for
		# scheduling and network delay, but catch a frozen, reset, or racing clock.
		var expected := WorldClock.extrapolate(first_seconds, first_at_msec, now)
		if absf(world_seconds - expected) > 5.0:
			fail("world time drifted: got %.2f, expected about %.2f" % [world_seconds, expected])
	if not is_nan(last_seconds) and world_seconds + 0.5 < last_seconds:
		fail("world time ran backwards: %.2f after %.2f" % [world_seconds, last_seconds])
	last_seconds = world_seconds


func on_finish() -> void:
	stat("world_time_syncs", syncs)
	stat("world_time_last", WorldClock.describe(last_seconds) if not is_nan(last_seconds) else "")
	# One sync per login at minimum; bots log in twice (initial + reconnect).
	if syncs < logins:
		fail("got %d world time syncs for %d logins" % [syncs, logins])

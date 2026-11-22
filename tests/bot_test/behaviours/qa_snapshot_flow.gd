extends "res://tests/bot_test/bot_behaviour.gd"
## QA: while a bot is playing, snapshots must keep flowing at a reasonable rate.
## Catches a server tick that stalls or a broadcast that silently stops for one peer.
## Thresholds are deliberately loose: CI runs 9 Godot processes on a 2-core runner.

const MIN_RATE_FRACTION := 0.25  # of GameConfig.TICK_RATE, averaged over play time
const MAX_GAP_S := 5.0           # longest silence allowed while playing

var _play_time := 0.0
var _snapshots_while_playing := 0
var _last_snapshot_at := -1.0
var _max_gap := 0.0


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	# A fresh connection: don't count the offline period as a gap.
	_last_snapshot_at = bot.elapsed


func on_play(delta: float) -> void:
	_play_time += delta
	if _last_snapshot_at >= 0.0:
		_max_gap = maxf(_max_gap, bot.elapsed - _last_snapshot_at)


func on_snapshot(_tick: int, _entries: Array) -> void:
	if str(bot.phase).begins_with("playing"):
		_snapshots_while_playing += 1
	_last_snapshot_at = bot.elapsed


func on_finish() -> void:
	var rate := _snapshots_while_playing / maxf(_play_time, 0.001)
	stat("snapshot_rate", snappedf(rate, 0.01))
	stat("max_gap_s", snappedf(_max_gap, 0.01))
	if _play_time < 5.0:
		return  # the bot failed early; bot.gd already reports why
	if rate < GameConfig.TICK_RATE * MIN_RATE_FRACTION:
		fail("snapshot rate %.1f/s while playing, expected at least %.1f/s" % [rate, GameConfig.TICK_RATE * MIN_RATE_FRACTION])
	if _max_gap > MAX_GAP_S:
		fail("no snapshot for %.1fs while playing (limit %.1fs)" % [_max_gap, MAX_GAP_S])

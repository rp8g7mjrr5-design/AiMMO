extends "res://tests/bot_test/bot_behaviour.gd"
## Client: runs the client's prediction (game/client/prediction.gd) for the bot's own
## character on the real server, the way client.gd does: every frame walks the bot's own
## input locally, every snapshot reconciles with the server's position and ack_seq. Network
## only (no visuals): the check is that what you see and what the server says agree.
##
## Fails if a prediction ever goes non-finite, if the average disagreement while playing is
## more than a short step, or if it snaps (a disagreement past Prediction.SNAP_DISTANCE) more
## often than the run's real teleports (gameplay_roster_v5 sends the bot home twice) explain.

const PredictionScript := preload("res://client/prediction.gd")
## Return to Spawn Meadow twice per play phase at most, plus a spare for a long hitch.
const MAX_SNAPS := 5
## Average disagreement (m) allowed. A tick of walk is 0.3 m; the replay should do far better.
const MAX_MEAN_ERROR := 0.5

var _pred: Prediction
var _errors := 0.0
var _count := 0
var _max_error := 0.0
var _snaps := 0
var _lead := 0.0
var _lead_count := 0


func setup(_net: Node) -> void:
	_pred = PredictionScript.new()


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_snaps += _pred.snaps
	_pred.reset() # a new session: seqs start over on the server
	if character.has("x"):
		_pred.place(Terrain.clamp_to_world(Vector3(float(character.x), float(character.y), float(character.z))))


func on_play(delta: float) -> void:
	# Other behaviours may still change bot.move this frame (stand still to gather), and bot.gd
	# sends after them: walk what was actually sent, once the frame's input has gone out.
	_walk_sent.call_deferred(delta)


func _walk_sent(delta: float) -> void:
	if bot.phase != "playing_1" and bot.phase != "playing_2":
		return
	_pred.advance(bot.seq, bot.move, delta)
	if not _pred.position.is_finite():
		fail("prediction went non-finite: %s" % _pred.position)


func on_snapshot(_tick: int, entries: Array) -> void:
	var i := 0
	while i + 4 < entries.size():
		if int(entries[i]) == bot.my_id:
			var server := Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
			var had := _pred.has_position
			var before := _pred.snaps
			var err := _pred.reconcile(server, int(bot.net.last_ack_seq))
			if had and _pred.snaps == before:
				_errors += err
				_count += 1
				_max_error = maxf(_max_error, err)
				if bot.move != Vector2.ZERO:
					_lead += _pred.position.distance_to(server)
					_lead_count += 1
			return
		i += 5


func on_finish() -> void:
	_snaps += _pred.snaps
	var mean := _errors / _count if _count > 0 else 0.0
	stat("reconciles", _count)
	stat("mean_error_m", snappedf(mean, 0.001))
	stat("max_error_m", snappedf(_max_error, 0.001))
	stat("snaps", _snaps)
	stat("mean_lead_m", snappedf(_lead / _lead_count, 0.001) if _lead_count > 0 else 0.0)
	if _count < 100:
		return # the bot barely played; bot.gd reports why
	if mean > MAX_MEAN_ERROR:
		fail("prediction disagreed with the server by %.2f m on average (max %.2f m)" % [mean, _max_error])
	if _snaps > MAX_SNAPS:
		fail("prediction snapped %d times (only teleports should snap)" % _snaps)

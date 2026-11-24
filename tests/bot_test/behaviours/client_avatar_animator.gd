extends "res://tests/bot_test/bot_behaviour.gd"
## Client: runs the traveller's animation state machine (AvatarAnimator) on the real snapshot
## stream, the way the client does for every avatar it sees. No skeleton here: behaviours stay
## art-free (the skinned traveller is covered by unit tests and the client smoke test).
## Other bots walk around, so at least one avatar must break into a stride, and no pose may
## ever be NaN or wild, however the server's positions jump (spawns, reconnects, corrections).
## It also fires a knock-down, a get-up and a sit on one avatar now and then, so every body
## state runs on live, moving data.

var _anims := {} ## peer id -> AvatarAnimator
var _last_tick_at := -1.0
var _poses := 0
var _max_speed := 0.0
var _states := {}
var _ticks := 0


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_anims.clear() # peer ids change across reconnects
	_last_tick_at = -1.0


func on_snapshot(_tick: int, entries: Array) -> void:
	var dt: float = bot.elapsed - _last_tick_at if _last_tick_at >= 0.0 else GameConfig.TICK_DT
	_last_tick_at = bot.elapsed
	if dt <= 0.0:
		return
	_ticks += 1
	var i := 0
	while i + 4 < entries.size():
		var id: int = entries[i]
		if id != bot.my_id:
			if not _anims.has(id):
				_anims[id] = AvatarAnimator.new()
			var anim: AvatarAnimator = _anims[id]
			# Every few seconds put one avatar through the moves the server will send (v8).
			match _ticks % 300:
				60:
					anim.knock_down()
				150:
					anim.get_up()
				220:
					anim.sit()
				280:
					anim.stand()
			anim.step(dt, {"pos": Vector3(entries[i + 1], entries[i + 2], entries[i + 3]), "yaw": float(entries[i + 4])})
			_states[anim.body] = true
			_max_speed = maxf(_max_speed, anim.speed)
			var p := anim.pose()
			_poses += 1
			for k in p:
				var v = p[k]
				if not v is Vector3:
					continue
				var bad: bool = not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z))
				if bad or (k != "root_pos" and maxf(absf(v.x), maxf(absf(v.y), absf(v.z))) > 3.3):
					fail("bad pose %s=%s for peer %d in %s" % [k, str(v), id, anim.body])
					return
		i += 5


func on_finish() -> void:
	stat("poses", _poses)
	stat("max_speed", snappedf(_max_speed, 0.01))
	stat("body_states", ",".join(_states.keys()))
	if _poses < 50:
		return # the bot barely played; bot.gd reports why
	if _max_speed < 1.5:
		fail("no other avatar ever broke into a stride (max %.2f m/s)" % _max_speed)

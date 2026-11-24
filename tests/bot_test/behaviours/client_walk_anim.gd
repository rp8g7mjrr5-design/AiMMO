extends "res://tests/bot_test/bot_behaviour.gd"
## Client: runs the client's walk animation on the real snapshot stream, the way the client
## does for every avatar it sees. Other bots walk around, so at least one avatar must break
## into a walk, and no pose may ever be out of range or NaN, however the server's positions
## jump (spawns, reconnects, corrections), and the legs and roll stay inside the adult stride.

const WalkAnimScript := preload("res://client/walk_anim.gd")

var _anims := {} ## peer id -> WalkAnim
var _last_tick_at := -1.0
var _poses := 0
var _max_amount := 0.0


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_anims.clear() # peer ids change across reconnects
	_last_tick_at = -1.0


func on_snapshot(_tick: int, entries: Array) -> void:
	var dt: float = bot.elapsed - _last_tick_at if _last_tick_at >= 0.0 else GameConfig.TICK_DT
	_last_tick_at = bot.elapsed
	if dt <= 0.0:
		return
	var i := 0
	while i + 4 < entries.size():
		var id: int = entries[i]
		if id != bot.my_id:
			if not _anims.has(id):
				_anims[id] = WalkAnimScript.new()
			var anim: WalkAnim = _anims[id]
			anim.step(Vector3(entries[i + 1], entries[i + 2], entries[i + 3]), dt)
			var p: Dictionary = anim.pose()
			_poses += 1
			_max_amount = maxf(_max_amount, anim.amount())
			for k in p:
				var v: float = p[k]
				if is_nan(v) or is_inf(v) or absf(v) > 1.0:
					fail("bad walk pose %s=%s for peer %d" % [k, str(v), id])
					return
			# Adult stride (art bible section 3): however the server's positions jump, a walk
			# never goes past the tuned leg swing or roll (no goose-step, no waddle).
			if absf(p.leg) > WalkAnimScript.LEG_SWING + 0.0001 or absf(p.roll) > WalkAnimScript.SWAY_ROLL + 0.0001:
				fail("walk pose past the adult limits for peer %d: leg %.3f roll %.3f" % [id, p.leg, p.roll])
				return
		i += 5


func on_finish() -> void:
	stat("poses", _poses)
	stat("max_gait", snappedf(_max_amount, 0.01))
	if _poses < 50:
		return # the bot barely played; bot.gd reports why
	if _max_amount < 0.3:
		fail("no other avatar ever broke into a walk (max gait %.2f)" % _max_amount)

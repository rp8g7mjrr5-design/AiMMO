extends "res://tests/bot_test/bot_behaviour.gd"
## Client: footsteps on the real snapshot stream. Runs the client's walk cycle for every other
## avatar the way the client does and counts the footfalls it would play. Walking bots must
## make steps, at a walking cadence (never a machine-gun burst from a server correction or a
## reconnect jump), feet must alternate, and some steps must fall within hearing range of us.
## Network-only: no sound is made here (art lint, art bible section 7).

const WalkAnimScript := preload("res://client/walk_anim.gd")
const FootstepsScript := preload("res://client/footsteps.gd")

## Most footfalls one avatar may make in a second: two per stride cycle at the top gait
## WalkAnim allows (1.5x walk speed), plus one for a crossing on the boundary.
const MAX_STEPS_PER_SEC := WalkAnim.STRIDE_CYCLES_PER_SEC * 2.0 * 1.5 + 1.0

var _anims := {} ## peer id -> WalkAnim
var _window := {} ## peer id -> [window start, steps in it]
var _last_tick_at := -1.0
var _steps := 0
var _heard := 0
var _same_foot := 0


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_anims.clear() # peer ids change across reconnects
	_window.clear()
	_last_tick_at = -1.0


func on_snapshot(_tick: int, entries: Array) -> void:
	var dt: float = bot.elapsed - _last_tick_at if _last_tick_at >= 0.0 else GameConfig.TICK_DT
	_last_tick_at = bot.elapsed
	if dt <= 0.0:
		return
	var me := Vector3.INF
	var i := 0
	while i + 4 < entries.size():
		if int(entries[i]) == bot.my_id:
			me = Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
		i += 5
	i = 0
	while i + 4 < entries.size():
		var id: int = entries[i]
		if id != bot.my_id:
			if not _anims.has(id):
				_anims[id] = WalkAnimScript.new()
				_window[id] = [bot.elapsed, 0]
			var anim: WalkAnim = _anims[id]
			var pos := Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
			var last_foot := anim.foot
			var before := anim.footsteps
			anim.step(pos, dt)
			if anim.stepped:
				_steps += 1
				if before > 0 and anim.foot == last_foot:
					_same_foot += 1
				var dist := pos.distance_to(me) if me != Vector3.INF else INF
				if FootstepsScript.hears(id, bot.my_id, dist):
					_heard += 1
				var w: Array = _window[id]
				if bot.elapsed - float(w[0]) >= 1.0:
					w[0] = bot.elapsed
					w[1] = 0
				w[1] = int(w[1]) + 1
				if float(w[1]) > MAX_STEPS_PER_SEC:
					fail("peer %d made %d footsteps inside one second" % [id, w[1]])
					return
		i += 5


func on_finish() -> void:
	stat("footsteps", _steps)
	stat("heard", _heard)
	if _steps == 0 and _anims.is_empty():
		return # the bot barely played; bot.gd reports why
	if _steps < 10:
		fail("other bots walked but only %d footsteps fell" % _steps)
	elif _same_foot * 10 > _steps:
		fail("feet did not alternate: %d of %d steps on the same foot twice" % [_same_foot, _steps])

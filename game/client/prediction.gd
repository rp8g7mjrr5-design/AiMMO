class_name Prediction
extends RefCounted
## Client-side prediction and reconciliation for your own character.
##
## Your avatar walks the moment you press W: every frame the client runs the same pure
## `Movement.step` the server runs, instead of waiting a round trip for a snapshot. Each frame's
## walk is also kept in `pending`, labelled with the input seq that carries it to the server.
## When a snapshot arrives with the server's position for you and `ack_seq` (the last input it
## applied), the walks the server has not seen yet are replayed on top of its position. That is
## where you should be; the difference from where you are drawn is eased out over a few frames
## (`CORRECTION_RATE`), so small disagreements never pop and nothing rubber-bands. A big one
## (a teleport, the unstuck button, a reconnect) snaps (`SNAP_DISTANCE`).
##
## The server stays authoritative: this only decides where your own avatar is drawn.
## Pure (no nodes), so tests/unit/test_client_prediction.gd and the client_prediction bot
## behaviour drive it directly.

## Further than this from where the server says you are, after replaying your unseen input:
## snap there, it was a teleport, not a disagreement. A frame hitch at full speed is ~1 m.
const SNAP_DISTANCE := 4.0
## How fast a small disagreement is eased out, per second (about 95% gone in 0.3 s).
const CORRECTION_RATE := 10.0
## Disagreements smaller than this are left alone while you walk: the server steps whole ticks
## and the client whole frames, so up to a tick of walk (0.3 m) is timing, not error. Standing
## still, everything settles exactly onto the server's position.
const WALK_DEADZONE := GameConfig.WALK_SPEED * GameConfig.TICK_DT * 1.2
## At most this many walk entries waiting for an ack (merged per seq and move, so ~one per tick;
## 256 ticks is 12.8 s of lost acks). Older ones are dropped.
const MAX_PENDING := 256

## Where your avatar is drawn.
var position := Vector3.ZERO
## False until the first snapshot (or place) puts you in the world.
var has_position := false
## [seq, move: Vector2, seconds] walks the server has not acknowledged yet, oldest first
## (frames standing still aren't kept: they replay as nothing).
var pending: Array = []
## The disagreement still being eased out (server-replayed minus drawn).
var correction := Vector3.ZERO
## Size of the last snapshot's disagreement, before easing, for tests and the F3 panel.
var last_error := 0.0
## Biggest disagreement that was eased (not snapped) since reset.
var max_error := 0.0
var snaps := 0
var reconciles := 0


## Forget everything (logout, reconnect: seqs and ids start over).
func reset() -> void:
	position = Vector3.ZERO
	has_position = false
	pending.clear()
	correction = Vector3.ZERO
	last_error = 0.0
	max_error = 0.0
	snaps = 0
	reconciles = 0


## Put yourself at `pos` with nothing in flight (first sighting, or a snap).
func place(pos: Vector3) -> void:
	position = pos
	has_position = true
	correction = Vector3.ZERO


## One frame of walking with `move` (camera-relative, already in world space like
## c2s_input's) for `dt` seconds. `seq` is the input seq that will carry this walk to the
## server: the next one to be sent. Returns where you are drawn now.
func advance(seq: int, move: Vector2, dt: float) -> Vector3:
	if not has_position or dt <= 0.0 or not is_finite(dt):
		return position
	if not is_finite(move.x) or not is_finite(move.y):
		move = Vector2.ZERO
	move = move.limit_length(1.0)
	if move != Vector2.ZERO: # standing still replays as nothing, so it isn't kept
		_record(seq, move, dt)
	position = Movement.step(position, move, dt)
	if correction != Vector3.ZERO:
		var k := 1.0 - exp(-CORRECTION_RATE * dt)
		var step := correction * k
		correction -= step
		if correction.length() < 0.001:
			step += correction
			correction = Vector3.ZERO
		position = Terrain.clamp_to_world(position + step)
	return position


## A snapshot says the server has you at `server_pos` after applying input `ack_seq`. Replays
## what it has not seen and starts easing out the difference (or snaps). Returns the size of
## the disagreement.
func reconcile(server_pos: Vector3, ack_seq: int) -> float:
	if not (is_finite(server_pos.x) and is_finite(server_pos.y) and is_finite(server_pos.z)):
		return 0.0
	while not pending.is_empty() and int(pending[0][0]) <= ack_seq:
		pending.pop_front()
	if not has_position:
		place(server_pos)
		return 0.0
	var target := replay(server_pos)
	var err := target - position
	last_error = err.length()
	reconciles += 1
	if last_error > SNAP_DISTANCE:
		snaps += 1
		place(target)
		return last_error
	max_error = maxf(max_error, last_error)
	if not pending.is_empty() and last_error < WALK_DEADZONE: # walking (only walks are kept)
		correction = Vector3.ZERO
	else:
		correction = err
	return last_error


## `from` with every unacknowledged walk applied, the way the server will apply it.
func replay(from: Vector3) -> Vector3:
	var p := from
	for e in pending:
		p = Movement.step(p, e[1], e[2])
	return p


## Seconds of walk waiting for an ack.
func pending_seconds() -> float:
	var s := 0.0
	for e in pending:
		s += float(e[2])
	return s


func _record(seq: int, move: Vector2, dt: float) -> void:
	if not pending.is_empty():
		var last: Array = pending[-1]
		if int(last[0]) == seq and last[1] == move:
			last[2] = float(last[2]) + dt
			return
	pending.append([seq, move, dt])
	while pending.size() > MAX_PENDING:
		pending.pop_front()

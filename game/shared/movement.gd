class_name Movement
## Authoritative movement step. Pure function so it is easy to test and reuse.

## You run where you face, not backwards (owner, 2026-11-25: "I shouldn't be able to run
## backwards"). The move is capped by where it points against your facing: full speed ahead,
## a jog straight sideways, a walk straight back. The client caps what it predicts and sends
## with `limit_for_facing`, and the server caps every c2s_input again the same way, so a
## hacked client can't backpedal at a run either.
const SIDE_SPEED := 0.75 ## share of GameConfig.WALK_SPEED straight sideways (4.5 m/s, a jog)
const BACK_SPEED := 0.38 ## share straight back (about 2.3 m/s: a walk, the gait's walk band)


## Returns the new position after walking with `input` (x = strafe, y = forward in world
## space, length clamped to 1) for `dt` seconds.
static func step(pos: Vector3, input: Vector2, dt: float) -> Vector3:
	if not is_finite(input.x) or not is_finite(input.y):
		input = Vector2.ZERO
	if input.length() > 1.0:
		input = input.normalized()
	var next := pos + Vector3(input.x, 0, input.y) * GameConfig.WALK_SPEED * dt
	return Terrain.clamp_to_world(next)


## How long a move pointing along `dir` (world x, z) may be for someone facing `yaw` (the
## heading c2s_input carries: facing (sin yaw, cos yaw)): 1 ahead, SIDE_SPEED sideways,
## BACK_SPEED straight back, eased in between.
static func facing_cap(dir: Vector2, yaw: float) -> float:
	if dir == Vector2.ZERO or not is_finite(yaw):
		return 1.0
	var c := dir.normalized().dot(Vector2(sin(yaw), cos(yaw))) # 1 ahead, -1 straight back
	if c >= 0.0:
		return lerpf(SIDE_SPEED, 1.0, c)
	return lerpf(SIDE_SPEED, BACK_SPEED, sqrt(-c))


## `move` (world x, z, length up to 1) capped for someone facing `yaw`. Applying it twice
## changes nothing, so the client's capped move passes the server's cap untouched.
static func limit_for_facing(move: Vector2, yaw: float) -> Vector2:
	if not is_finite(move.x) or not is_finite(move.y):
		return Vector2.ZERO
	move = move.limit_length(1.0)
	return move.limit_length(facing_cap(move, yaw))

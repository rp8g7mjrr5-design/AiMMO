class_name Movement
## Authoritative movement step. Pure function so it is easy to test and reuse.


## Returns the new position after walking with `input` (x = strafe, y = forward in world
## space, length clamped to 1) for `dt` seconds.
static func step(pos: Vector3, input: Vector2, dt: float) -> Vector3:
	if not is_finite(input.x) or not is_finite(input.y):
		input = Vector2.ZERO
	if input.length() > 1.0:
		input = input.normalized()
	var next := pos + Vector3(input.x, 0, input.y) * GameConfig.WALK_SPEED * dt
	return Terrain.clamp_to_world(next)

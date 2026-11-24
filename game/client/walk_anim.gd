class_name WalkAnim
extends RefCounted
## Procedural walk cycle for one avatar, driven only by how fast its rendered position moves.
## No keyframes and no server data: the client already smooths every avatar towards the
## server's snapshots, so the speed of that smoothed motion is what the player sees, and the
## gait follows it. Idle avatars breathe gently instead.
##
## Footfalls: after each `step()`, `stepped` is true on the frame a foot comes down (two per
## stride cycle), so the client can play a footstep sound exactly in time with the legs.
##
## Usage: call `step(node.position, delta)` once per frame, then `apply(body)` on the child
## that holds the avatar's meshes (pivot at the feet, facing +Z). Arms or legs named ArmL,
## ArmR, LegL, LegR under that child also swing, if the avatar has them.

## Tuned for the lean 1.78 m adult (art bible section 3, "Characters"): long straight legs
## from hips at 0.92 m and 0.63 m arms. Angles that read right on the old stubby figure were a
## goose-step and a waddle on these limbs, so the stride is narrower, the arms swing close to
## the body, the side-to-side roll is nearly gone, and the weight goes into a little more bob.
const STRIDE_CYCLES_PER_SEC := 1.55 ## full left+right cycles per second at WALK_SPEED
const BOB_HEIGHT := 0.08            ## metres the body rises on each step
const SWAY_ROLL := 0.018            ## radians of side-to-side roll (was 0.06: a waddle)
const LEAN := 0.09                  ## radians of forward lean at full speed
const ARM_SWING := 0.4              ## radians each arm swings (was 0.65)
const LEG_SWING := 0.34             ## radians each leg swings (was 0.5: a goose-step)
const BREATH_HEIGHT := 0.012        ## metres of idle breathing
const TELEPORT_DIST := 3.0          ## metres in one frame that count as a jump, not a walk
const FOOTSTEP_MIN_GAIT := 0.3      ## below this much walking, a phase crossing is not a step

var footsteps := 0 ## footfalls so far (the phase crossing 0 or PI while walking)
var stepped := false ## true for the one step() call in which a foot came down
var foot := 0 ## which foot came down last: 0 left (phase crossed PI), 1 right (crossed 0)

var phase := 0.0   ## stride phase in radians; one full cycle is two footsteps
var speed := 0.0   ## smoothed planar speed in m/s
var idle_time := 0.0
var _last := Vector3.ZERO
var _has_last := false


## Amount of walking, 0 (standing) to 1 (full walk speed).
func amount() -> float:
	return clampf(speed / GameConfig.WALK_SPEED, 0.0, 1.0)


func step(pos: Vector3, delta: float) -> void:
	if delta <= 0.0:
		stepped = false
		return
	var measured := 0.0
	if _has_last:
		var d := Vector2(pos.x - _last.x, pos.z - _last.z).length()
		# A spawn snap or a server correction moves far in one frame: don't run on the spot.
		measured = 0.0 if d > TELEPORT_DIST else d / delta
	_last = pos
	_has_last = true
	measured = minf(measured, GameConfig.WALK_SPEED * 1.5)
	speed = lerpf(speed, measured, 1.0 - exp(-10.0 * delta))
	if speed < 0.05:
		speed = 0.0
	var a := amount()
	var before := phase
	phase = fmod(phase + delta * TAU * STRIDE_CYCLES_PER_SEC * a, TAU)
	# A foot lands when the stride phase crosses PI (left) or wraps past 0 (right). Only a real
	# walk counts: the settle below eases the phase too, but that is feet coming to rest.
	stepped = false
	if a >= FOOTSTEP_MIN_GAIT:
		if phase < before:
			stepped = true
			foot = 1
		elif before < PI and phase >= PI:
			stepped = true
			foot = 0
		if stepped:
			footsteps += 1
	if a < 0.05:
		# Settle the feet: ease the phase back to a rest pose instead of freezing mid-stride.
		var rest := 0.0 if phase < PI * 0.5 or phase > PI * 1.5 else PI
		phase = lerp_angle(phase, rest, 1.0 - exp(-6.0 * delta))
		if phase < 0.0:
			phase += TAU
	idle_time += delta


## The pose for the current state: {bob, roll, lean, arm, leg}. Pure, for tests.
func pose() -> Dictionary:
	var a := amount()
	var s := sin(phase)
	var breath := sin(idle_time * 2.1) * BREATH_HEIGHT * (1.0 - a)
	return {
		"bob": absf(s) * BOB_HEIGHT * a + breath,
		"roll": s * SWAY_ROLL * a,
		"lean": LEAN * a,
		"arm": s * ARM_SWING * a,
		"leg": s * LEG_SWING * a,
	}


func apply(body: Node3D) -> void:
	var p := pose()
	body.position.y = p.bob
	body.rotation = Vector3(p.lean, 0.0, p.roll)
	_swing(body, "ArmL", p.arm)
	_swing(body, "ArmR", -p.arm)
	_swing(body, "LegL", -p.leg)
	_swing(body, "LegR", p.leg)


static func _swing(body: Node3D, part: String, angle: float) -> void:
	var n := body.get_node_or_null(part) as Node3D
	if n != null:
		n.rotation.x = angle

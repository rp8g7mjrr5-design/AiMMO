class_name WalkAnim
extends RefCounted
## Procedural walk cycle for one avatar, driven only by how fast its rendered position moves.
## No keyframes and no server data: the client already smooths every avatar towards the
## server's snapshots, so the speed of that smoothed motion is what the player sees, and the
## gait follows it. Idle avatars breathe gently instead.
##
## Usage: call `step(node.position, delta)` once per frame, then `apply(body)` on the child
## that holds the avatar's meshes (pivot at the feet, facing +Z). Arms or legs named ArmL,
## ArmR, LegL, LegR under that child also swing, if the avatar has them.

const STRIDE_CYCLES_PER_SEC := 1.55 ## full left+right cycles per second at WALK_SPEED
const BOB_HEIGHT := 0.07            ## metres the body rises on each step
const SWAY_ROLL := 0.06             ## radians of side-to-side waddle
const LEAN := 0.09                  ## radians of forward lean at full speed
const ARM_SWING := 0.65             ## radians each arm swings
const LEG_SWING := 0.5              ## radians each leg swings
const BREATH_HEIGHT := 0.012        ## metres of idle breathing
const TELEPORT_DIST := 3.0          ## metres in one frame that count as a jump, not a walk

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
	phase = fmod(phase + delta * TAU * STRIDE_CYCLES_PER_SEC * a, TAU)
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

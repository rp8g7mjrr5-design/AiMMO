class_name ActionCamera
extends RefCounted
## The over-the-shoulder action camera (design bible, "Owner directions → 2. The camera").
##
## The camera hangs on an arm behind a pivot at head height, pushed out over your right (or
## left) shoulder. The mouse always turns it while the cursor is captured. Movement is
## camera-relative and your character turns to face where the camera looks while you move;
## hold Alt to look around without turning. The arm pulls in when the ground, a tree or a rock
## is in the way and eases back out, and the pivot eases after the character so nothing
## jitters or snaps.
##
## Everything that is maths is a static function, so it is unit tested headless and the bot
## test runs the same code on real server positions. `step()` is the only stateful part.
##
## Conventions (same as the rest of the client): yaw 0 looks north (-Z), positive pitch looks
## up, forward(yaw) = (-sin yaw, 0, -cos yaw). Avatars face atan2(dir.x, dir.z).

const PIVOT_HEIGHT := 1.65 ## metres above the character's feet: about head height
const SHOULDER := 0.6 ## metres the pivot is pushed sideways over the shoulder
const DIST_DEFAULT := 3.5
const DIST_MIN := 1.5
const DIST_MAX := 6.0
const ZOOM_STEP := 0.35 ## metres per wheel notch
const ARM_MIN := 0.35 ## the arm never pulls in closer than this, even against a wall
const CLEARANCE := 0.35 ## metres kept between the camera and the ground or a prop
const ARM_SAMPLE := 0.1 ## metres between collision samples along the arm
const PITCH_MIN := -1.25 ## looking down
const PITCH_MAX := 0.85 ## looking up
const PITCH_DEFAULT := -0.18
const FOLLOW_RATE := 16.0 ## pivot easing after the character (1/s, exponential)
const PULL_IN_RATE := 30.0 ## the arm shortens fast so the camera never sits inside a hill
const EASE_OUT_RATE := 4.0 ## and grows back slowly so it doesn't bounce
const SHOULDER_RATE := 8.0 ## shoulder swap slides across instead of snapping
const RETURN_RATE := 10.0 ## after free-look the camera swings back to your heading
## Look-to-interact: a node counts as "under the reticle" within this angle of the look ray.
const AIM_CONE := deg_to_rad(28.0)

var yaw := 0.0
var pitch := PITCH_DEFAULT
var distance := DIST_DEFAULT ## the zoom the player asked for
var arm := DIST_DEFAULT ## the arm length after collision, eased
var side := 1.0 ## +1 right shoulder, -1 left
var side_eased := 1.0
var pivot := Vector3.ZERO
var free_look := false
var heading := 0.0 ## the yaw the character keeps while free-looking
var _returning := false
var _placed := false


## The flat direction the camera looks along.
static func forward(p_yaw: float) -> Vector3:
	return Vector3(-sin(p_yaw), 0.0, -cos(p_yaw))


## The flat direction to the camera's right.
static func right(p_yaw: float) -> Vector3:
	return Vector3(cos(p_yaw), 0.0, -sin(p_yaw))


## The full direction the camera looks along (the reticle ray).
static func look_dir(p_yaw: float, p_pitch: float) -> Vector3:
	return Vector3(-sin(p_yaw) * cos(p_pitch), sin(p_pitch), -cos(p_yaw) * cos(p_pitch))


## The camera's basis for a yaw and pitch: -Z along look_dir.
static func basis_for(p_yaw: float, p_pitch: float) -> Basis:
	return Basis.from_euler(Vector3(p_pitch, p_yaw, 0.0))


## Where the arm starts: head height above `feet`, out over the shoulder (`p_side` +1 right).
static func shoulder_point(feet: Vector3, p_yaw: float, p_side: float) -> Vector3:
	return feet + Vector3.UP * PIVOT_HEIGHT + right(p_yaw) * SHOULDER * p_side


## The camera's position for an arm of length `p_arm` from `shoulder`.
static func camera_point(shoulder: Vector3, p_yaw: float, p_pitch: float, p_arm: float) -> Vector3:
	return shoulder - look_dir(p_yaw, p_pitch) * p_arm


static func clamp_distance(d: float) -> float:
	return clampf(d, DIST_MIN, DIST_MAX)


static func clamp_pitch(p: float) -> float:
	return clampf(p, PITCH_MIN, PITCH_MAX)


## The yaw an avatar has when it faces the camera's heading (what the server is sent).
static func facing_yaw(p_yaw: float) -> float:
	return wrapf(p_yaw + PI, -PI, PI)


## Camera-relative movement: forward/back `f` and right/left `r` (each -1..1) turned into the
## world (x, z) move the server expects, never longer than 1.
static func move_vector(f: float, r: float, p_yaw: float) -> Vector2:
	if f == 0.0 and r == 0.0:
		return Vector2.ZERO
	var m := forward(p_yaw) * f + right(p_yaw) * r
	if m.length() > 1.0:
		m = m.normalized()
	return Vector2(m.x, m.z)


## True if point `p` is inside a resource node prop (plus `margin`). World owns the exact
## shapes (`NodeProps.solid_columns`, scaled per node and unit-tested against every vertex of
## every live and depleted prop), so the camera and the meshes can never drift apart.
static func inside_prop(p: Vector3, node: Dictionary, margin: float) -> bool:
	return NodeProps.inside_solid(p, node, margin)


## Everything the camera keeps out of near `pos`: the resource node props
## (`ResourceNodes.near`) plus world's decorative solids (`WorldSolids.near`: scatter trees and
## rocks, birches, boulders, meadow lanterns, the workbench). Only the camera uses decoration;
## gathering and look-to-interact keep using `ResourceNodes.near` (decoration isn't gatherable).
static func camera_solids(pos: Vector3, radius: float = DIST_MAX + 3.0) -> Array:
	return ResourceNodes.near(pos, radius) + WorldSolids.near(pos, radius)


## How long the arm can be, up to `want`, before the camera would sit within CLEARANCE of
## the ground (`height` is a Callable(x, z) -> float, normally Terrain.height) or a prop in
## `props` (resource nodes and decorative solids, see camera_solids). Never shorter than ARM_MIN.
static func clear_arm(shoulder: Vector3, p_yaw: float, p_pitch: float, want: float, height: Callable, props: Array = []) -> float:
	var back := -look_dir(p_yaw, p_pitch)
	var t := ARM_SAMPLE
	while t <= want + 0.0001:
		var p := shoulder + back * t
		var q := shoulder + back * (t + CLEARANCE) # keep clear of a steep face behind, too
		var blocked: bool = p.y < float(height.call(p.x, p.z)) + CLEARANCE or q.y < float(height.call(q.x, q.z))
		if not blocked:
			for n in props:
				if inside_prop(p, n, CLEARANCE):
					blocked = true
					break
		if blocked:
			return maxf(ARM_MIN, t - ARM_SAMPLE)
		t += ARM_SAMPLE
	return want


## Eases the arm: pulls in quickly and grows back out slowly. (step() also never lets the arm
## stay longer than the clear length, so the camera is never left inside a hill.)
static func ease_arm(current: float, target: float, delta: float) -> float:
	var rate := PULL_IN_RATE if target < current else EASE_OUT_RATE
	return lerpf(current, target, 1.0 - exp(-rate * delta))


## Frame-rate independent exponential follow.
static func follow(current: Vector3, target: Vector3, rate: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-rate * delta))


## Look-to-interact: of the nodes in `in_reach` (resource node dictionaries), the one nearest
## the reticle ray from `eye` along `dir`, if any is within AIM_CONE; else {} (the caller
## falls back to the nearest node).
static func aimed_node(eye: Vector3, dir: Vector3, in_reach: Array) -> Dictionary:
	var best := {}
	var best_angle := AIM_CONE
	for n in in_reach:
		var centre: Vector3 = n.pos + Vector3.UP * 1.0
		var to := centre - eye
		if to.length() < 0.001:
			continue
		var a := dir.angle_to(to)
		if a <= best_angle:
			best_angle = a
			best = n
	return best


## Turns the camera by a mouse delta already scaled by sensitivity (see client.look_delta).
func turn(look: Vector2) -> void:
	yaw = wrapf(yaw + look.x, -PI, PI)
	pitch = clamp_pitch(pitch + look.y)
	_returning = false


func zoom(notches: float) -> void:
	distance = clamp_distance(distance + notches * ZOOM_STEP)


func swap_shoulder() -> void:
	side = -side


## Starts or stops free-look (Alt). While free-looking the character keeps `heading`; on
## release the camera swings back behind them.
func set_free_look(on: bool) -> void:
	if on == free_look:
		return
	free_look = on
	if on:
		heading = yaw
	else:
		_returning = true


## The yaw movement and facing follow: the camera's, or the kept heading in free-look.
func move_yaw() -> float:
	return heading if free_look or _returning else yaw


## Snaps everything to a fresh spot (login, teleport) so the camera doesn't fly in.
func place(feet: Vector3, p_yaw: float) -> void:
	yaw = wrapf(p_yaw, -PI, PI)
	heading = yaw
	pitch = PITCH_DEFAULT
	pivot = feet
	arm = distance
	side_eased = side
	free_look = false
	_returning = false
	_placed = true


## Moves the camera with a teleported character (Return to Spawn Meadow, a big correction):
## the pivot jumps to `feet` instead of flying across the map, and the look direction, zoom
## and shoulder stay as the player left them.
func jump_to(feet: Vector3) -> void:
	if not _placed:
		place(feet, yaw)
		return
	pivot = feet


## Advances one frame for a character whose feet are at `feet`. Returns the camera's world
## transform. `height` and `props` are as in clear_arm.
func step(feet: Vector3, delta: float, height: Callable, props: Array = []) -> Transform3D:
	if not _placed:
		place(feet, yaw)
	if _returning:
		yaw = lerp_angle(yaw, heading, 1.0 - exp(-RETURN_RATE * delta))
		if absf(angle_difference(yaw, heading)) < 0.01:
			yaw = heading
			_returning = false
	elif not free_look:
		heading = yaw
	pivot = follow(pivot, feet, FOLLOW_RATE, delta)
	side_eased = lerpf(side_eased, side, 1.0 - exp(-SHOULDER_RATE * delta))
	var shoulder := shoulder_point(pivot, yaw, side_eased)
	var want := clear_arm(shoulder, yaw, pitch, distance, height, props)
	arm = ease_arm(arm, want, delta)
	if want < arm:
		arm = want # never lag behind into the ground: the ease only smooths growing back out
	var pos := camera_point(shoulder, yaw, pitch, arm)
	pos.y = maxf(pos.y, float(height.call(pos.x, pos.z)) + CLEARANCE * 0.5)
	return Transform3D(basis_for(yaw, pitch), pos)


## The reticle ray's origin for the current frame (the camera position for `xf`).
static func eye_of(xf: Transform3D) -> Vector3:
	return xf.origin


## Whether the cursor should be captured: playing, and no window or text box wants it.
static func wants_capture(playing: bool, typing: bool, window_open: bool, app_focused: bool) -> bool:
	return playing and not typing and not window_open and app_focused

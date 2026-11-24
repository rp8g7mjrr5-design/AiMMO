class_name AvatarAnimator
extends RefCounted
## One avatar's animation state machine, on the traveller's skeleton (AvatarSkeleton). It
## replaces WalkAnim and GatherSwing once the skinned traveller lands; until then it runs on
## the preview mannequin and in tests. Everything it shows comes from what the client already
## knows (rendered position, the gather and swing events) plus the events the server will send
## for jumping, knock-downs and resting (docs/workstreams/gameplay.d/from-client-animation-events.md).
##
## Two layers:
## - The BODY state owns the whole skeleton:
##     move      idle / walk / run, blended by the avatar's rendered speed (AvatarClips.gait)
##     takeoff   the dip before a jump leaves the ground
##     air       off the ground (height above the turf > AIR_HEIGHT)
##     land      soaking up the landing
##     down      knocked down: the fall, then lying there
##     getup     getting back up
##     sit       sitting down, sitting, then standing up again (stand)
##   Every change of body state cross-fades from the pose that was showing, so nothing snaps.
## - The ACTION layer (gather, craft, swing) owns the upper body (AvatarSkeleton.UPPER) on top of
##   move, with its own weight that eases in and out. Standing still, its stance (crouch and
##   foot placement) also takes the legs; walking, the legs keep their stride. Down, getting up
##   and sitting suppress it.
##
## Usage, every frame:
##   anim.step(delta, {pos, yaw, gather = {kind, pos} or {}, height = metres above the turf})
##   anim.apply(skeleton)
## and on events: anim.jump(), anim.swing(kind, windup, active, recovery), anim.craft(),
## anim.knock_down(), anim.get_up(), anim.sit(), anim.stand().
##
## Footsteps keep WalkAnim's interface (stepped, foot, footsteps), so Footsteps plays in time
## with the new legs too.

const TELEPORT_DIST := 3.0 ## metres in one frame that count as a snap, not a walk
const MAX_SPEED := 9.0 ## m/s the measured speed is clamped to
const SPEED_EASE := 10.0 ## 1/s
const AIR_HEIGHT := 0.08 ## metres above the turf that count as off the ground
const FOOTSTEP_MIN := 0.6 ## m/s; slower than this a foot coming down is not a step
const ACTION_IN := 12.0 ## 1/s
const ACTION_OUT := 6.0 ## 1/s
const TURN_RATE := 9.0 ## 1/s, the body turning to face the node being gathered
const MIN_FACE_DIST := 0.15
const XFADE := {"move": 0.25, "takeoff": 0.08, "air": 0.12, "land": 0.06, "down": 0.08, "getup": 0.15, "sit": 0.2, "stand": 0.1}
const CRAFT_SECONDS := 1.9 ## a craft plays two beats at the bench

# Footsteps (WalkAnim's interface)
var footsteps := 0
var stepped := false
var foot := 0 ## 0 left, 1 right

var speed := 0.0
var phase := 0.0 ## stride phase 0..1, the left foot strikes at 0
var clock := 0.0 ## seconds alive, for idle breathing
var body := "move"
var body_t := 0.0 ## seconds in the current body state
var action := "" ## "", "gather", "craft", "swing"
var action_t := 0.0
var action_weight := 0.0
var action_args := {}
var gather_style := "chop"
var turn := 0.0 ## the body's yaw relative to the avatar root
var vy := 0.0 ## vertical speed while airborne, m/s
var height := 0.0
var land_hard := 0.0

var _last := Vector3.ZERO
var _has_last := false
var _from := {} ## the pose showing when the body state last changed
var _xfade := 0.0 ## seconds of cross-fade left
var _xfade_len := 0.0
var _pose := {}
var _sit_hold := false


## Walking amount 0..1, as WalkAnim had it (for anything that keys off "is it walking").
func amount() -> float:
	return clampf(speed / GameConfig.WALK_SPEED, 0.0, 1.0)


func jump() -> void:
	if body in ["move", "land"]:
		_go("takeoff")


func knock_down() -> void:
	if body != "down":
		action = ""
		_go("down")


func get_up() -> void:
	if body == "down":
		_go("getup")


func sit() -> void:
	if body in ["move", "land"]:
		_sit_hold = true
		action = ""
		_go("sit")


func stand() -> void:
	_sit_hold = false
	if body == "sit":
		_go("stand")


func swing(kind: String, windup: float, active: float, recovery: float) -> void:
	if not body in ["down", "getup", "sit", "stand"]:
		action = "swing"
		action_t = 0.0
		action_args = {"kind": kind, "windup": windup, "active": active, "recovery": recovery}


func craft() -> void:
	if body == "move":
		action = "craft"
		action_t = 0.0


func busy() -> bool:
	return body != "move" or action != ""


## Advance one frame. ctx: pos (rendered position), yaw (root yaw), gather ({kind, pos} or
## empty), height (metres above the turf; 0 if not given).
func step(delta: float, ctx: Dictionary) -> void:
	stepped = false
	if delta <= 0.0:
		return
	clock += delta
	body_t += delta
	_measure(ctx.get("pos", Vector3.ZERO), delta)
	_air(float(ctx.get("height", 0.0)), delta)
	_body_transitions()
	_actions(delta, ctx)
	# Stride phase: advance with cadence, and only count footsteps while really moving.
	var before := phase
	var f := AvatarClips.cadence(speed) if speed > 0.05 else 0.0
	phase = fposmod(phase + delta * f, 1.0)
	if body == "move" and speed >= FOOTSTEP_MIN:
		if phase < before:
			_step_foot(0)
		elif before < 0.5 and phase >= 0.5:
			_step_foot(1)
	if _xfade > 0.0:
		_xfade = maxf(_xfade - delta, 0.0)
	_pose = _compose()


func _step_foot(which: int) -> void:
	stepped = true
	foot = which
	footsteps += 1


func _measure(pos: Vector3, delta: float) -> void:
	var measured := 0.0
	if _has_last:
		var d := Vector2(pos.x - _last.x, pos.z - _last.z).length()
		measured = 0.0 if d > TELEPORT_DIST else d / delta
	_last = pos
	_has_last = true
	speed = lerpf(speed, minf(measured, MAX_SPEED), 1.0 - exp(-SPEED_EASE * delta))
	if speed < 0.05:
		speed = 0.0


func _air(h: float, delta: float) -> void:
	var was := height
	height = maxf(h, 0.0)
	vy = (height - was) / delta
	if height > AIR_HEIGHT and body in ["move", "takeoff", "land"]:
		_go("air")
	elif body == "air" and height <= AIR_HEIGHT * 0.5:
		land_hard = clampf(-vy / 6.0, 0.3, 1.0)
		_go("land")


func _body_transitions() -> void:
	match body:
		"takeoff":
			# Without a server jump (or before its first lifted snapshot) the dip settles back.
			if body_t > AvatarClips.TAKEOFF + 0.35:
				_go("move")
		"land":
			if body_t >= AvatarClips.LAND:
				_go("move")
		"getup":
			if body_t >= AvatarClips.GETUP:
				_go("move")
		"stand":
			if body_t >= AvatarClips.STAND:
				_go("move")
		"sit":
			if not _sit_hold or speed > 1.0:
				_sit_hold = false
				_go("stand")


func _actions(delta: float, ctx: Dictionary) -> void:
	var node: Dictionary = ctx.get("gather", {})
	if not node.is_empty() and action in ["", "gather"] and body == "move":
		var st := GatherSwing.style_for(str(node.get("kind", "")))
		if action == "" or st != gather_style:
			gather_style = st
			if action_weight < 0.05:
				action_t = 0.0 # start a fresh swing from the bottom, winding up
		action = "gather"
	elif action == "gather" and node.is_empty():
		action = ""
	if action != "":
		action_t += delta
		if action == "swing":
			var a := action_args
			if action_t >= float(a.windup) + float(a.active) + float(a.recovery):
				action = ""
		elif action == "craft" and action_t >= CRAFT_SECONDS:
			action = ""
	var suppressed := body in ["down", "getup", "sit", "stand"]
	var want := 0.0 if action == "" or suppressed else 1.0
	var rate := ACTION_IN if want > action_weight else ACTION_OUT
	action_weight = lerpf(action_weight, want, 1.0 - exp(-rate * delta))
	if action_weight < 0.002:
		action_weight = 0.0
	# Face the node being gathered, as GatherSwing did; ease back otherwise.
	var turn_to := 0.0
	if action == "gather":
		var root_pos: Vector3 = ctx.get("pos", Vector3.ZERO)
		var p: Vector3 = node.get("pos", root_pos)
		if Vector2(p.x - root_pos.x, p.z - root_pos.z).length() > MIN_FACE_DIST:
			turn_to = wrapf(GatherSwing.face_yaw(root_pos, p) - float(ctx.get("yaw", 0.0)), -PI, PI)
		else:
			turn_to = turn
	turn = wrapf(lerp_angle(turn, turn_to, 1.0 - exp(-TURN_RATE * delta)), -PI, PI)


func _go(state: String) -> void:
	if state == body:
		return
	_from = _pose.duplicate() if not _pose.is_empty() else AvatarClips.rest()
	_xfade_len = float(XFADE.get(state, 0.15))
	_xfade = _xfade_len
	body = state
	body_t = 0.0


## The body state's own pose this frame (before the action layer and the cross-fade).
func body_pose() -> Dictionary:
	match body:
		"takeoff":
			return AvatarClips.jump_takeoff(body_t)
		"air":
			return AvatarClips.jump_air(body_t, vy)
		"land":
			return AvatarClips.jump_land(body_t, land_hard)
		"down":
			if body_t < AvatarClips.KNOCKDOWN:
				return AvatarClips.knockdown(body_t)
			return AvatarClips.lying(body_t - AvatarClips.KNOCKDOWN)
		"getup":
			return AvatarClips.getup(body_t)
		"sit":
			if body_t < AvatarClips.SIT:
				return AvatarClips.sit_down(body_t)
			return AvatarClips.sitting(body_t - AvatarClips.SIT)
		"stand":
			return AvatarClips.stand_up(body_t)
	# move: idle blended into the gait as speed picks up.
	var g := AvatarClips.gait(phase, speed)
	var still := 1.0 - clampf(speed / 0.8, 0.0, 1.0)
	if still > 0.0:
		return AvatarClips.blend(g, AvatarClips.idle(clock), still)
	return g


## The action layer's pose this frame, or {} when there is none.
func action_pose() -> Dictionary:
	match action:
		"gather":
			var period: float = GatherSwing.STYLES.get(gather_style, GatherSwing.STYLES.chop).period
			return AvatarClips.gather(gather_style, fposmod(action_t / period, 1.0))
		"craft":
			return AvatarClips.craft(action_t)
		"swing":
			var a := action_args
			return AvatarClips.swing(str(a.kind), action_t, float(a.windup), float(a.active), float(a.recovery))
	return {}


func _compose() -> Dictionary:
	var p := body_pose()
	if action_weight > 0.0:
		var act := action_pose()
		if not act.is_empty():
			p = AvatarClips.blend(p, act, action_weight, AvatarSkeleton.UPPER)
			# Standing still, the action's stance takes the legs too: feet set, hips sunk.
			var planted := action_weight * (1.0 - clampf(speed / 1.5, 0.0, 1.0))
			if planted > 0.0 and body == "move":
				var legs := p.duplicate()
				var feet: Vector2 = act.get("feet", Vector2(0.02, -0.02))
				legs.root_pos = p.root_pos * 0.3
				AvatarClips.stand_legs(legs, float(act.get("crouch", 0.0)), feet.x, feet.y)
				p = AvatarClips.blend(p, legs, planted, AvatarSkeleton.LEGS + ["root_pos"])
	if _xfade > 0.0 and not _from.is_empty():
		var k := smoothstep(0.0, 1.0, 1.0 - _xfade / maxf(_xfade_len, 0.0001))
		p = AvatarClips.blend(_from, p, k)
	p["Root"] = Vector3(0.0, turn, 0.0)
	return p


## The pose last composed by step().
func pose() -> Dictionary:
	return _pose if not _pose.is_empty() else AvatarClips.rest()


## Put the current pose on `sk` (a skeleton built by AvatarSkeleton).
func apply(sk: Skeleton3D) -> void:
	apply_pose(sk, pose())


static func apply_pose(sk: Skeleton3D, p: Dictionary) -> void:
	for i in sk.get_bone_count():
		var bone := sk.get_bone_name(i)
		var e: Vector3 = p.get(bone, Vector3.ZERO)
		sk.set_bone_pose_rotation(i, Quaternion.from_euler(e))
		var rest_pos := sk.get_bone_rest(i).origin
		if bone == "Root":
			sk.set_bone_pose_position(i, rest_pos + p.get("root_pos", Vector3.ZERO))
		else:
			sk.set_bone_pose_position(i, rest_pos)

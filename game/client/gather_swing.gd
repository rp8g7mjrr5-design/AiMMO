class_name GatherSwing
extends RefCounted
## The gather swing: while an avatar is gathering a node (yours or anyone's, from
## `GatherWatch.running`), its rendered body turns to face the node and its arms work it in
## a loop, a different motion per kind:
## - ash and pine: a two-handed chop, slow wind-up over the head, fast bite down;
## - stone: the same but heavier and slower, with a deeper lean into each blow;
## - ember sap: both hands low and forward, dipping and lifting gently.
## It blends in and out over a fraction of a second, so starting, finishing and cancelling
## never snap the pose.
##
## Only the rendered body ("Body" under the avatar root, see client.wrap_avatar) turns: the
## root's yaw stays the server's, so nothing here touches movement or the camera.
##
## Usage, every frame after `WalkAnim.apply(body)`:
##   swing.step(delta, node_or_empty, root_position, root_yaw)
##   swing.apply(body)
## `pose()` and the static helpers are pure, for tests and bots.

const BLEND_IN := 10.0  ## 1/s, exponential ease towards swinging
const BLEND_OUT := 7.0  ## 1/s, ease back to the walk pose
const TURN_RATE := 9.0  ## 1/s, exponential turn of the body towards the node
const MIN_FACE_DIST := 0.15 ## metres; closer than this there is no direction to face

## Per kind: period (s), arm angle at the top and bottom of the stroke (rotation.x of both
## arms; negative raises them forward, -PI is straight up), the share of the period spent
## winding up, and the forward lean (rad) at the bottom of the stroke.
const STYLES := {
	"chop": {"period": 0.8, "top": -2.7, "bottom": -0.75, "wind": 0.62, "lean": 0.16},
	"mine": {"period": 1.0, "top": -2.85, "bottom": -0.55, "wind": 0.66, "lean": 0.24},
	"collect": {"period": 1.4, "top": -1.25, "bottom": -0.7, "wind": 0.5, "lean": 0.2},
}
const KIND_STYLE := {"ash": "chop", "pine": "chop", "stone": "mine", "ember_sap": "collect"}

var weight := 0.0  ## 0 = walk pose only, 1 = full swing
var phase := 0.0   ## 0..1 through the current stroke
var turn := 0.0    ## the body's yaw relative to the root, radians
var style := "chop"
var _active := false


static func style_for(kind: String) -> String:
	return KIND_STYLE.get(kind, "chop")


## The world yaw at which an avatar at `from` faces `to` (the avatar faces +Z at yaw 0).
static func face_yaw(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## Arm angle and lean for a stroke `style` at stroke phase `p` (0..1). Pure.
## The wind-up eases up slowly; the remaining share bites down fast.
static func stroke(style_name: String, p: float) -> Dictionary:
	var s: Dictionary = STYLES.get(style_name, STYLES.chop)
	var wind: float = s.wind
	var u: float # 0 at the bottom of the stroke, 1 at the top
	if p < wind:
		u = smoothstep(0.0, 1.0, p / wind)
	else:
		var d := (p - wind) / (1.0 - wind)
		u = 1.0 - d * d # accelerate into the blow
	return {
		"arm": lerpf(float(s.bottom), float(s.top), u),
		"lean": float(s.lean) * (1.0 - u),
	}


## Advance one frame. `node` is the node being gathered ({kind, pos} from ResourceNodes) or
## empty when this avatar isn't gathering. `root_pos` and `root_yaw` are the avatar root's.
func step(delta: float, node: Dictionary, root_pos: Vector3, root_yaw: float) -> void:
	if delta <= 0.0:
		return
	var was := _active
	_active = not node.is_empty()
	if _active:
		var st := style_for(str(node.get("kind", "")))
		if not was or st != style:
			style = st
			if weight < 0.05:
				phase = 0.0 # start each fresh swing from the bottom, winding up
		phase = fmod(phase + delta / float(STYLES[style].period), 1.0)
		weight = lerpf(weight, 1.0, 1.0 - exp(-BLEND_IN * delta))
		var pos: Vector3 = node.get("pos", root_pos)
		var flat := Vector2(pos.x - root_pos.x, pos.z - root_pos.z)
		if flat.length() > MIN_FACE_DIST:
			var want := wrapf(face_yaw(root_pos, pos) - root_yaw, -PI, PI)
			turn = lerp_angle(turn, want, 1.0 - exp(-TURN_RATE * delta))
	else:
		weight = lerpf(weight, 0.0, 1.0 - exp(-BLEND_OUT * delta))
		turn = lerp_angle(turn, 0.0, 1.0 - exp(-TURN_RATE * delta))
		if weight < 0.002:
			weight = 0.0
	turn = wrapf(turn, -PI, PI)


func swinging() -> bool:
	return weight > 0.0


## The swing's share of the pose: {arm, lean, turn, weight}. Pure.
func pose() -> Dictionary:
	var s := stroke(style, phase)
	return {"arm": s.arm, "lean": s.lean, "turn": turn, "weight": weight}


## Blend the swing over the walk pose WalkAnim.apply just set on `body`.
func apply(body: Node3D) -> void:
	if weight <= 0.0 and absf(turn) < 0.0005:
		return
	var p := pose()
	body.rotation.y = turn
	body.rotation.x = lerpf(body.rotation.x, p.lean, weight)
	for part in ["ArmL", "ArmR"]:
		var n := body.get_node_or_null(part) as Node3D
		if n != null:
			n.rotation.x = lerpf(n.rotation.x, p.arm, weight)

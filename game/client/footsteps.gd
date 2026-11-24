class_name Footsteps
extends RefCounted
## Footstep sounds in time with every avatar's walk cycle. The animator's `stepped`
## (AvatarAnimator, the same interface WalkAnim had) says on which frame a foot comes down; this plays a soft turf step right then. Your own steps are heard
## flat (they are always under you); other players' steps come from where they walk and fade
## out with distance, so a player passing close by is heard before they reach the screen edge.
##
## Usage: `build(parent)` once, then `step(id, node, anim, my_id, my_pos)` for each avatar
## after its `anim.step()`, and `forget(id)` when an avatar leaves.

const OWN_DB := -15.0       ## your own steps: quiet, under the world
const OTHER_DB := -9.0      ## another player's steps at a metre (3D falloff from there)
const SLOW_DROP_DB := -6.0  ## extra quiet at the slowest gait that still steps
const HEAR_RANGE := 18.0    ## metres; further steps are not played at all
const PITCH_SPREAD := 0.06  ## each step's pitch varies by up to this much either way

var streams: Array[AudioStreamWAV] = []
var own: AudioStreamPlayer
var voices := {} ## peer id -> AudioStreamPlayer3D on that avatar
var played := 0  ## steps actually played, for tests and the bot behaviour
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 31337
	for v in Sfx.FOOTSTEP_VARIANTS:
		streams.append(Sfx.footstep(v))


## Makes the player for your own steps under `parent`.
func build(parent: Node) -> void:
	own = AudioStreamPlayer.new()
	own.name = "Footsteps"
	own.volume_db = OWN_DB
	own.max_polyphony = 2
	parent.add_child(own)


## The variant for an avatar's nth footfall: walks through all four, starting where the
## avatar's id puts it, so two players side by side don't step with the same sound.
static func variant_for(id: int, count: int) -> int:
	return posmod(id + count, Sfx.FOOTSTEP_VARIANTS)


## How much quieter a step is at gait `amount` (0..1): full at a walk, softer when easing in.
static func gait_db(amount: float) -> float:
	var span := 1.0 - WalkAnim.FOOTSTEP_MIN_GAIT
	var k := clampf((amount - WalkAnim.FOOTSTEP_MIN_GAIT) / span, 0.0, 1.0)
	return lerpf(SLOW_DROP_DB, 0.0, k)


## Whether this avatar's footfall should be heard at all.
static func hears(id: int, my_id: int, distance: float) -> bool:
	return id == my_id or distance <= HEAR_RANGE


## What a footfall would play right now: {} when nothing (no foot down, or too far), else
## {own: bool, variant: int, pitch: float, db: float}. Pure apart from the pitch dice.
func pick(id: int, node: Node3D, anim, my_id: int, my_pos: Vector3) -> Dictionary:
	if not anim.stepped or node == null:
		return {}
	if not hears(id, my_id, node.position.distance_to(my_pos)):
		return {}
	var own_step := id == my_id
	return {
		"own": own_step,
		"variant": variant_for(id, anim.footsteps),
		"pitch": 1.0 + _rng.randf_range(-PITCH_SPREAD, PITCH_SPREAD),
		"db": (OWN_DB if own_step else OTHER_DB) + gait_db(anim.amount()),
	}


## Call after `anim.step()`. Plays a step if a foot just came down. Returns true if it did.
func step(id: int, node: Node3D, anim, my_id: int, my_pos: Vector3) -> bool:
	var k := pick(id, node, anim, my_id, my_pos)
	if k.is_empty() or not node.is_inside_tree():
		return false
	var p: Node = own if k.own else voice(id, node)
	if p == null or not p.is_inside_tree():
		return false
	p.set("stream", streams[k.variant])
	p.set("pitch_scale", k.pitch)
	p.set("volume_db", k.db)
	p.call("play")
	played += 1
	return true


## Drops the voice of an avatar that left (its node is freed with it).
func forget(id: int) -> void:
	voices.erase(id)


## The 3D voice riding avatar `node`, made on first use.
func voice(id: int, node: Node3D) -> AudioStreamPlayer3D:
	var had: Variant = voices.get(id) # untyped: the avatar (and its voice) may have been freed
	if had != null and is_instance_valid(had) and (had as Node).get_parent() == node:
		return had
	var p := AudioStreamPlayer3D.new()
	p.name = "Footsteps"
	p.unit_size = 3.0
	p.max_distance = HEAR_RANGE
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_polyphony = 2
	node.add_child(p)
	voices[id] = p
	return p

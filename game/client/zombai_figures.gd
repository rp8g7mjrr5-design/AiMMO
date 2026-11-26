class_name ZombaiFigures
extends Node3D
## Draws the Zombai walkers in view (from a ZombaiView) and gives them their voices.
##
## Each walker is a traveller's skeleton wearing one of ZombaiBody's VARIANTS drained bodies
## (built once at setup and shared, so a walker that comes into view costs a node, never a
## mesh build): one draw call a walker, at most Gloam.MAX_WALKERS of them. It shambles with
## the measured ground speed (feet planted, the traveller's own IK), raises its arms through
## the grab's windup timed to the server's windup_left, jerks when struck, rocks back from a
## heavy blow, and when it's put down it goes over and lies where it fell, then sinks away.
##
## Sound (all generated, Sfx): a low groan now and then, more often once it has seen you; a
## rasp as its arms come up (the grab you can hear coming); a dull thud as a body hits the
## ground.
##
## Usage: `figures.setup()`, add it to the world, then each frame `figures.sync(view, now,
## delta)`, and pass ZombaiView's events to `play_events(events, view, now)`.

const POSE_RATE := 9.0 ## per second: changes of state blend instead of snapping
const GRAB_RATE := 30.0 ## the windup follows its timeline closely: the telegraph is exact
const SPEED_RATE := 8.0
const FLINCH_KICK := 0.35 ## rad a struck walker's upper body jerks back
const GROAN_HUNT := Vector2(3.5, 7.0) ## seconds between groans once it's after someone
const GROAN_IDLE := Vector2(9.0, 18.0) ## ... and while it wanders
const HEAR_RANGE := 45.0

var _meshes: Array = [] ## ArrayMesh per ZombaiBody variant
var _groans: Array = [] ## AudioStreamWAV per Sfx groan variant
var _rasp: AudioStreamWAV
var _thud: AudioStreamWAV
## id -> {node: Node3D, sk: Skeleton3D, voice: AudioStreamPlayer3D, last: Vector3, phase,
## speed, t, pose: Dictionary, groan_at: float, thudded: bool}
var _figs := {}
var drawn := 0 ## walkers and bodies drawn last sync (tests and the F3 panel)
var poses := {} ## id -> the pose last drawn (tests)


## Builds the walker bodies and the sounds. Call once.
func setup() -> void:
	name = "Zombai"
	for v in ZombaiBody.VARIANTS:
		_meshes.append(Toon.zombai_mesh(v))
	for v in Sfx.GROAN_VARIANTS:
		_groans.append(Sfx.groan(v))
	_rasp = Sfx.rasp()
	_thud = Sfx.thwack()


## The pose a walker should be in this frame, before blending: pure, for tests.
## `st` is the view's state; `k` the windup (0..1); the times are seconds since a stagger,
## a flinch and going down.
static func pose_for(st: String, phase: float, speed: float, t: float, k: float, since_stagger: float,
		since_flinch: float, since_down: float, sd: float) -> Dictionary:
	var p: Dictionary
	match st:
		"down":
			return ZombaiBody.fall(since_down)
		"grab":
			p = ZombaiBody.grab(k, sd)
		"recover":
			p = ZombaiBody.grab(1.0, sd) # it hangs there a beat, arms out, then sags (the blend)
		"stagger":
			p = ZombaiBody.stagger(minf(since_stagger, ZombaiBody.STAGGER), sd)
		_:
			p = ZombaiBody.shamble(phase, speed, t, sd)
	if since_flinch >= 0.0 and since_flinch < ZombaiView.FLINCH_SECONDS:
		var j := FLINCH_KICK * (1.0 - since_flinch / ZombaiView.FLINCH_SECONDS)
		p["Spine"] = (p.get("Spine", Vector3.ZERO) as Vector3) - Vector3(j, 0.0, 0.0)
		p["Head"] = (p.get("Head", Vector3.ZERO) as Vector3) - Vector3(j * 0.8, 0.0, 0.0)
	return p


## Draws every walker and body the view knows at `now`; nodes for ones it no longer knows go.
func sync(view: ZombaiView, now: float, delta: float) -> void:
	drawn = 0
	view.expire(now)
	var live := {}
	for id in view.ids() + view.bodies():
		live[id] = true
		var pos := view.position(id, now)
		var f: Dictionary = _figs.get(id, {})
		if f.is_empty():
			f = _make(id, pos, now)
		var st := view.state(id)
		var moved := Vector2(pos.x - f.last.x, pos.z - f.last.z).length()
		if moved > ZombaiView.SNAP_DIST:
			moved = 0.0
		var measured := moved / delta if delta > 0.0 else 0.0
		f.speed = lerpf(float(f.speed), measured, 1.0 - exp(-SPEED_RATE * delta))
		# Short dragging steps, as many a metre as the legs' gait needs for a planted foot to
		# hold still on the ground (no skating, at a day shuffle or a night hunt).
		# The toon's short legs (Toon.LEG_SCALE) are drawn at the speed long legs would need, and
		# take that many more steps a metre.
		var gs := float(f.speed) / Toon.LEG_SCALE
		f.phase = fposmod(float(f.phase) + moved * ZombaiBody.strides_per_metre(gs) / Toon.LEG_SCALE, 1.0)
		f.t = float(f.t) + delta
		f.last = pos
		var sd := ZombaiBody.lean_side(id)
		var target := pose_for(st, f.phase, gs, f.t, view.windup(id, now), view.since_stagger(id, now),
			view.since_flinch(id, now), view.since_down(id, now), sd)
		var rate := GRAB_RATE if st in ["grab", "down"] else POSE_RATE
		f.pose = target if (f.pose as Dictionary).is_empty() else AvatarClips.blend(f.pose, target, 1.0 - exp(-rate * delta))
		poses[id] = f.pose
		var node: Node3D = f.node
		node.position = pos
		node.rotation = Vector3(0.0, view.facing(id, now), 0.0)
		AvatarAnimator.apply_pose(f.sk, f.pose, Toon.LEG_SCALE)
		if st == "down" and not bool(f.thudded) and view.since_down(id, now) >= AvatarClips.KNOCKDOWN * 0.7:
			f.thudded = true
			_say(f, _thud, 0.55, -4.0)
		elif st != "down" and now >= float(f.groan_at):
			_say(f, _groans[posmod(id + int(f.t), _groans.size())], 0.92 + 0.16 * fposmod(float(id) * 0.37, 1.0), -3.0)
			f.groan_at = now + _next_groan(id, st, f.t)
		_figs[id] = f
		drawn += 1
	for id in _figs.keys():
		if not live.has(id):
			_drop(id)


## Plays a feed's or a blow's moments: a rasp when arms come up, a groan when one turns on
## someone. Returns how many sounds it started.
func play_events(events: Array, view: ZombaiView, now: float) -> int:
	var n := 0
	for e in events:
		var f: Dictionary = _figs.get(int(e.id), {})
		if f.is_empty():
			continue
		match str(e.event):
			"windup":
				_say(f, _rasp, 1.0, 0.0)
				n += 1
			"hunt":
				_say(f, _groans[posmod(int(e.id), _groans.size())], 1.05, -1.0)
				f.groan_at = now + _next_groan(int(e.id), "hunt", f.t)
				n += 1
	return n


static func _next_groan(id: int, st: String, t: float) -> float:
	var r := GROAN_HUNT if st in ["hunt", "drawn", "grab"] else GROAN_IDLE
	return lerpf(r.x, r.y, fposmod(float(id) * 0.6180339 + t * 0.137, 1.0))


func _make(id: int, pos: Vector3, now: float) -> Dictionary:
	var node := Node3D.new()
	node.name = "Walker%d" % id
	node.scale = Vector3.ONE * ZombaiBody.size_of(id)
	var sk := Toon.rig(_meshes[ZombaiBody.variant_of(id)])
	node.add_child(sk)
	var voice := AudioStreamPlayer3D.new()
	voice.name = "Voice"
	voice.unit_size = 5.0
	voice.max_distance = HEAR_RANGE
	voice.position = Vector3(0.0, 1.5, 0.0)
	node.add_child(voice)
	add_child(node)
	return {"node": node, "sk": sk, "voice": voice, "last": pos, "phase": fposmod(float(id) * 0.37, 1.0),
		"speed": 0.0, "t": float(id) * 1.3, "pose": {}, "groan_at": now + 1.0 + fposmod(float(id) * 0.71, 1.0) * 4.0,
		"thudded": false}


func _say(f: Dictionary, stream: AudioStream, pitch: float, db: float) -> void:
	var v: AudioStreamPlayer3D = f.voice
	if v == null or not is_instance_valid(v) or not v.is_inside_tree():
		return
	v.stream = stream
	v.pitch_scale = pitch
	v.volume_db = db
	v.play()


func _drop(id: int) -> void:
	var f: Dictionary = _figs[id]
	if is_instance_valid(f.node):
		(f.node as Node3D).queue_free()
	_figs.erase(id)
	poses.erase(id)


## How many walker nodes exist right now (tests: nothing leaks as walkers come and go).
func live_nodes() -> int:
	return _figs.size()


## Forget everyone (logout, disconnect).
func clear() -> void:
	for id in _figs.keys():
		_drop(id)

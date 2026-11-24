class_name GrazerFigures
extends Node3D
## Draws the grazers in view (from a HerdView) with world's procedural critter model
## (`Grazers`): small deer-like animals in a fawn coat with a cream belly and pale rump, tall
## ears, dark hooves, each a touch lighter, darker or redder than the next. Heads go down to
## graze and snap up when someone comes close, legs walk and bound with the smoothed speed
## (never sliding on the ground), bodies tilt with the slope, a resting grazer folds down, and
## a bolt kicks up a puff of dust clods and a snort you hear from where it stands.
##
## Cheap on purpose (art bible section 7): every grazer's bodies share one MultiMesh, heads
## another, legs a third and dust a fourth, so the whole herd system is four draw calls however
## many are in view. Every instance is made once at setup (slot = creature id, ids are the
## spawn list's indices); nothing is created or freed while playing. The look and the poses
## are world's (`Grazers.meshes`, `pose_for`, `xforms`); this node owns the smoothing glue
## (HerdView's positions, the gait, blending one pose into the next), the dust and the snort.
##
## Usage: `figures.setup()`, add it to the world, then each frame `figures.sync(herd, now,
## delta)`; on a HerdView "bolt" event call `figures.bolt(id, herd, now)`.

const SIZE_SPREAD := 0.12 ## each grazer is up to this much bigger or smaller, from its id
const DRAW_RANGE := 160.0 ## the art bible's prop fade distance
const POSE_RATE := Grazers.POSE_RATE ## per second: a state change blends instead of snapping
const ALERT_RATE := Grazers.ALERT_RATE ## the head snaps up fast: that's the "freeze now" cue
const SPEED_RATE := 8.0 ## how fast the measured ground speed settles, per second

const DUST_POOL := 48
const DUST_PER_BOLT := 6
const DUST_LIFE := 0.7
const SNORT_VOICES := 4
const SNORTS_PER_BOLT_WAVE := 2 ## a whole herd bolts on one tick: two snorts, not five

var count := 0
var _body: MultiMesh
var _head: MultiMesh
var _legs: MultiMesh
var _dust: MultiMesh
var _gait := {} ## id -> {last: Vector3, phase: float (0..1), speed: float (m/s), t: float, pose: Dictionary}
var _puffs: Array = [] ## {slot, origin: Vector3, vel: Vector3, born: float}
var _next_puff := 0
var _voices: Array = [] ## AudioStreamPlayer3D
var _next_voice := 0
var drawn := 0 ## grazers drawn last sync (tests and the F3 panel)
## id -> the body transform last written (the headless renderer keeps no MultiMesh data, so
## tests read this).
var bodies := {}
## id -> the pose last drawn (tests check the blend).
var poses := {}


## Builds the four MultiMeshes and the snort voices. Call once.
func setup() -> void:
	name = "Grazers"
	count = Wildlife.spawns().size()
	var m := Grazers.meshes()
	_body = _layer("Bodies", m.body, count, true)
	_head = _layer("Heads", m.head, count, true)
	_legs = _layer("Legs", m.leg, count * Grazers.LEGS, true)
	_dust = _layer("Dust", Emberlight.paint(_clod(), Palette.SAND.lerp(Palette.HAZE, 0.5), 0.25), DUST_POOL, false)
	for id in count:
		var tint := Grazers.coat_tint(id)
		_body.set_instance_color(id, tint)
		_head.set_instance_color(id, tint)
		for l in Grazers.LEGS:
			_legs.set_instance_color(id * Grazers.LEGS + l, tint)
	for i in SNORT_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.stream = Sfx.snort()
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.volume_db = -2.0
		add_child(p)
		_voices.append(p)
	_hide_all()


func _layer(layer_name: String, mesh: Mesh, instances: int, tinted: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = tinted # per-grazer coat tint (Grazers.coat_tint), multiplied into the baked colours
	mm.mesh = mesh
	mm.instance_count = instances
	var mmi := MultiMeshInstance3D.new()
	mmi.name = layer_name
	mmi.multimesh = mm
	mmi.material_override = Emberlight.material("solid")
	mmi.visibility_range_end = DRAW_RANGE
	# No sun shadows: the spawn shot is near the 300 draw-call ceiling, and shadows would
	# double the herd's cost through both cascades. A layer with nothing in it is hidden.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	return mm


static func _clod() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 0.7
	m.radial_segments = 5
	m.rings = 3
	return m


## A grazer's size from its id: steady across sessions, a little different per animal.
static func size_of(id: int) -> float:
	return 1.0 + SIZE_SPREAD * (fposmod(float(id) * 0.6180339, 1.0) * 2.0 - 1.0)


## Every part's world transform for one grazer, unblended: {body, head, legs: [4]}.
## `gait_phase` in radians, `gait` 0 (standing) to 1 (full trot). World's model, same
## signature as before the swap, so callers and tests didn't change.
static func part_xforms(pos: Vector3, yaw: float, state_name: String, gait_phase: float, gait: float, size: float = 1.0) -> Dictionary:
	return Grazers.part_xforms(pos, yaw, state_name, gait_phase, gait, size)


## One grazer's next gait record after `delta` seconds, now drawn at `pos` in `state_name`:
## legs advance by the ground really covered (world's stride for the state, so a bound is
## long and a walk is short), the measured speed settles, and the pose blends toward the
## state's own (fast for "alert", gently otherwise). Pure, for tests.
static func step_gait(g: Dictionary, pos: Vector3, state_name: String, delta: float) -> Dictionary:
	var out := g.duplicate()
	var moved := Vector2(pos.x - g.last.x, pos.z - g.last.z).length()
	if moved > HerdView.SNAP_DIST:
		moved = 0.0 # a jump is a jump: no blur of legs
	var measured := moved / delta if delta > 0.0 else 0.0
	out.speed = lerpf(float(g.speed), measured, 1.0 - exp(-SPEED_RATE * delta))
	out.phase = fposmod(float(g.phase) + moved * Grazers.cycles_per_metre(state_name), 1.0)
	out.t = float(g.t) + delta
	out.last = pos
	var rate := ALERT_RATE if state_name == "alert" else POSE_RATE
	var target := Grazers.pose_for(state_name, out.t, out.phase, out.speed)
	out.pose = Grazers.blend(g.pose, target, 1.0 - exp(-rate * delta))
	return out


## A fresh gait record for a grazer first seen at `pos`: already in its state's pose (it
## appears grazing, not standing up into it), legs at a phase of its own.
static func new_gait(id: int, pos: Vector3, state_name: String) -> Dictionary:
	var t := float(id) * 1.7
	var phase := fposmod(float(id) * 0.37, 1.0)
	return {"last": pos, "phase": phase, "speed": 0.0, "t": t, "pose": Grazers.pose_for(state_name, t, phase, 0.0)}


## Where one dust clod is `age` seconds after a bolt, and how big. Scale 0 once it's done.
static func dust_xform(origin: Vector3, vel: Vector3, age: float) -> Transform3D:
	if age < 0.0 or age >= DUST_LIFE:
		return Transform3D(Basis().scaled(Vector3.ZERO), origin)
	var k := age / DUST_LIFE
	var pos := origin + vel * age * (1.0 - 0.5 * k) + Vector3(0.0, 0.5 * age, 0.0)
	var s := 0.32 * sin(PI * sqrt(k))
	return Transform3D(Basis().scaled(Vector3(s, s * 0.7, s)), pos)


## Draws every grazer the herd knows at `now`; everyone else's slot is hidden.
func sync(herd: HerdView, now: float, delta: float) -> void:
	drawn = 0
	var live := {}
	for id in herd.ids():
		if id < 0 or id >= count:
			continue
		live[id] = true
		var pos := herd.position(id, now)
		var state_name := herd.state(id)
		var g: Dictionary = _gait.get(id, {})
		g = new_gait(id, pos, state_name) if g.is_empty() else step_gait(g, pos, state_name, delta)
		_gait[id] = g
		var basis := Grazers.ground_basis(pos.x, pos.z, herd.facing(id, now)).scaled(Vector3.ONE * size_of(id))
		var x := Grazers.xforms(Transform3D(basis, pos), g.pose)
		_body.set_instance_transform(id, x.body)
		bodies[id] = x.body
		poses[id] = g.pose
		_head.set_instance_transform(id, x.head)
		for l in Grazers.LEGS:
			_legs.set_instance_transform(id * Grazers.LEGS + l, x.legs[l])
		drawn += 1
	_show_layers(drawn > 0)
	for id in _gait.keys():
		if not live.has(id):
			_gait.erase(id)
			_hide(id)
	_step_dust(now)


## A bolt: dust clods kick up behind it and (a few per wave) it snorts.
func bolt(id: int, herd: HerdView, now: float, snort: bool = true) -> void:
	if not herd.has(id):
		return
	var pos := herd.position(id, now)
	var yaw := herd.facing(id, now)
	var back := -Vector3(sin(yaw), 0.0, cos(yaw))
	for i in DUST_PER_BOLT:
		var side := Vector3(cos(yaw), 0.0, -sin(yaw)) * (float(i % 3) - 1.0) * 0.8
		var vel := back * (1.6 + 0.3 * float(i % 2)) + side + Vector3(0.0, 0.6 + 0.15 * float(i), 0.0)
		var origin := pos + back * 0.4 + Vector3(0.0, 0.1, 0.0)
		var slot := _next_puff
		_next_puff = (_next_puff + 1) % DUST_POOL
		_puffs = _puffs.filter(func(p): return int(p.slot) != slot)
		_puffs.append({"slot": slot, "origin": origin, "vel": vel, "born": now})
	if snort and not _voices.is_empty() and is_inside_tree():
		var v: AudioStreamPlayer3D = _voices[_next_voice]
		_next_voice = (_next_voice + 1) % _voices.size()
		v.position = pos + Vector3(0.0, 1.0, 0.0)
		v.pitch_scale = 0.9 + 0.2 * fposmod(float(id) * 0.37, 1.0)
		v.play()


## Plays a feed's events: dust for every bolt, snorts for the first few of the wave.
func play_events(events: Array, herd: HerdView, now: float) -> int:
	var snorts := 0
	for e in events:
		if str(e.event) == "bolt":
			bolt(int(e.id), herd, now, snorts < SNORTS_PER_BOLT_WAVE)
			snorts += 1
	return snorts


func live_puffs() -> int:
	return _puffs.size()


func _show_layers(on: bool) -> void:
	for n in ["Bodies", "Heads", "Legs"]:
		var mmi := get_node(n) as MultiMeshInstance3D
		if mmi.visible != on:
			mmi.visible = on


func _step_dust(now: float) -> void:
	var keep: Array = []
	for p in _puffs:
		var age: float = now - float(p.born)
		_dust.set_instance_transform(int(p.slot), dust_xform(p.origin, p.vel, age))
		if age < DUST_LIFE:
			keep.append(p)
	_puffs = keep
	var dust := get_node("Dust") as MultiMeshInstance3D
	if dust.visible != not _puffs.is_empty():
		dust.visible = not _puffs.is_empty()


## Forget everyone (logout, disconnect).
func clear() -> void:
	_gait.clear()
	_puffs.clear()
	_hide_all()
	_show_layers(false)
	(get_node("Dust") as MultiMeshInstance3D).visible = false


func _hide(id: int) -> void:
	bodies.erase(id)
	poses.erase(id)
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	_body.set_instance_transform(id, gone)
	_head.set_instance_transform(id, gone)
	for l in Grazers.LEGS:
		_legs.set_instance_transform(id * Grazers.LEGS + l, gone)


func _hide_all() -> void:
	for id in count:
		_hide(id)
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in DUST_POOL:
		_dust.set_instance_transform(i, gone)

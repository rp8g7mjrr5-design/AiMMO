class_name GrazerFigures
extends Node3D
## Draws the grazers in view (from a HerdView) until world's procedural critter model lands:
## a chunky low-poly four-legged grazer in warm fawn, painted on the world's shared Emberlight
## "solid" material. Heads go down to graze, snap up when someone comes close, legs walk with
## the smoothed speed, a resting grazer lies down, and a bolt kicks up a puff of dust clods and
## a snort you hear from where it stands.
##
## Cheap on purpose (art bible section 7): every grazer's bodies share one MultiMesh, heads
## another, legs a third and dust a fourth, so the whole herd system is four draw calls however
## many are in view. Every instance is made once at setup (slot = creature id, ids are the
## spawn list's indices); nothing is created or freed while playing. The pose maths is static
## (`part_xforms`, `dust_xform`), so unit tests check it without a window.
##
## Usage: `figures.setup()`, add it to the world, then each frame `figures.sync(herd, now,
## delta)`; on a HerdView "bolt" event call `figures.bolt(id, herd, now)`.

const BODY_RADIUS := 0.3
const BODY_LENGTH := 1.2
const BODY_HEIGHT := 0.8 ## metres from the ground to the body's middle, standing
const NECK := Vector3(0.0, 1.0, 0.5) ## head pivot, relative to the feet
const HEAD_LENGTH := 0.52
const HIP_Y := 0.66
const HIP_X := 0.17
const HIP_Z := 0.4
const LEG_LENGTH := 0.66
const LEG_SWING := 0.6 ## radians at a full trot
const STRIDE := 1.5 ## metres per gait cycle
const TROT_SPEED := 4.0 ## m/s that counts as full swing
const SIZE_SPREAD := 0.12 ## each grazer is up to this much bigger or smaller, from its id
const DRAW_RANGE := 160.0 ## the art bible's prop fade distance

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
var _gait := {} ## id -> {last: Vector3, phase: float, speed: float}
var _puffs: Array = [] ## {slot, origin: Vector3, vel: Vector3, born: float}
var _next_puff := 0
var _voices: Array = [] ## AudioStreamPlayer3D
var _next_voice := 0
var drawn := 0 ## grazers drawn last sync (tests and the F3 panel)
## id -> the body transform last written (the headless renderer keeps no MultiMesh data, so
## tests read this).
var bodies := {}


## Builds the four MultiMeshes and the snort voices. Call once.
func setup() -> void:
	name = "Grazers"
	count = Wildlife.spawns().size()
	var hide := Palette.TRUNK.lerp(Palette.ROCK, 0.5).lerp(Palette.HAZE, 0.3) # muted fawn hide: warm, but well clear of ember orange
	var dark := Palette.TRUNK.lerp(Palette.SOOT, 0.35) # legs and muzzle
	var dust := Palette.SAND.lerp(Palette.HAZE, 0.5)
	_body = _layer("Bodies", _capsule(), hide, count, 0.35)
	_head = _layer("Heads", _head_mesh(), hide.lerp(dark, 0.3), count, 0.2)
	_legs = _layer("Legs", _leg_mesh(), dark, count * 4, 0.3)
	_dust = _layer("Dust", _clod(), dust, DUST_POOL, 0.25)
	for i in SNORT_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.stream = Sfx.snort()
		p.unit_size = 6.0
		p.max_distance = 70.0
		p.volume_db = -2.0
		add_child(p)
		_voices.append(p)
	_hide_all()


func _layer(layer_name: String, mesh: Mesh, color: Color, instances: int, ao: float) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Emberlight.paint(mesh, color, ao)
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


static func _capsule() -> Mesh:
	var m := CapsuleMesh.new()
	m.radius = BODY_RADIUS
	m.height = BODY_LENGTH
	m.radial_segments = 6
	m.rings = 1
	return m


static func _head_mesh() -> Mesh:
	var m := CylinderMesh.new() # a tapered snout: wide at the neck, narrow at the nose
	m.top_radius = 0.08
	m.bottom_radius = 0.15
	m.height = HEAD_LENGTH
	m.radial_segments = 5
	m.rings = 1
	return m


static func _leg_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.065
	m.bottom_radius = 0.045
	m.height = LEG_LENGTH
	m.radial_segments = 5
	m.rings = 1
	return m


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


## Every part's world transform for one grazer: {body, head, legs: [4]}. `gait_phase` in
## radians, `gait` 0 (standing) to 1 (full trot).
static func part_xforms(pos: Vector3, yaw: float, state_name: String, gait_phase: float, gait: float, size: float = 1.0) -> Dictionary:
	var p := HerdView.pose(state_name)
	var drop: float = p.drop
	var root := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), pos)
	var lie := Basis(Vector3.RIGHT, PI * 0.5) # the capsule and cylinders are built along +y
	var body := root * Transform3D(lie, Vector3(0.0, BODY_HEIGHT - drop, 0.0))
	var pitch := Basis(Vector3.RIGHT, -float(p.head))
	var head := root * Transform3D(Basis(), NECK - Vector3(0.0, drop, 0.0)) \
		* Transform3D(pitch, Vector3.ZERO) * Transform3D(lie, Vector3(0.0, 0.0, HEAD_LENGTH * 0.5))
	var legs: Array = []
	var corners := [[-1.0, 1.0, 0.0], [1.0, 1.0, PI], [-1.0, -1.0, PI], [1.0, -1.0, 0.0]] # diagonal pairs step together
	for c in corners:
		var swing: float = sin(gait_phase + float(c[2])) * LEG_SWING * clampf(gait, 0.0, 1.0)
		if drop > 0.0:
			swing = PI * 0.5 * float(c[1]) # lying down: legs folded under, front ones forward
		var hip := Vector3(HIP_X * float(c[0]), HIP_Y - drop, HIP_Z * float(c[1]))
		legs.append(root * Transform3D(Basis(Vector3.RIGHT, swing), hip) * Transform3D(Basis(), Vector3(0.0, -LEG_LENGTH * 0.5, 0.0)))
	return {"body": body, "head": head, "legs": legs}


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
		var g: Dictionary = _gait.get(id, {})
		if g.is_empty():
			g = {"last": pos, "phase": float(id), "speed": 0.0}
			_gait[id] = g
		var moved := Vector2(pos.x - g.last.x, pos.z - g.last.z).length()
		if moved > HerdView.SNAP_DIST:
			moved = 0.0
		var measured := moved / delta if delta > 0.0 else 0.0
		g.speed = lerpf(float(g.speed), measured, 1.0 - exp(-10.0 * delta))
		g.phase = fmod(float(g.phase) + moved / STRIDE * TAU, TAU)
		g.last = pos
		var x := part_xforms(pos, herd.facing(id, now), herd.state(id), g.phase, float(g.speed) / TROT_SPEED, size_of(id))
		_body.set_instance_transform(id, x.body)
		bodies[id] = x.body
		_head.set_instance_transform(id, x.head)
		for l in 4:
			_legs.set_instance_transform(id * 4 + l, x.legs[l])
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
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	_body.set_instance_transform(id, gone)
	_head.set_instance_transform(id, gone)
	for l in 4:
		_legs.set_instance_transform(id * 4 + l, gone)


func _hide_all() -> void:
	for id in count:
		_hide(id)
	var gone := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in DUST_POOL:
		_dust.set_instance_transform(i, gone)

class_name NodeFx
extends Node3D
## Gathering feedback on resource nodes: the soft glow on the node in reach, and the little
## reaction each gather gets (an ash or pine shudders and sheds a few leaves or needles, an
## outcrop throws stone chips, a seep's pool bobs and splashes glowing droplets).
##
## NodeProps.build() adds one of these as the "Fx" child of the "ResourceNodes" node. Call it
## through NodeProps.set_highlight() and NodeProps.play_hit(), not directly.
##
## Everything the effects look like is pure maths in static functions (`shell_xform`,
## `shake`, `spawn_bits`, `bit_xform`), so tests and bots check it headless. The node itself
## only copies those transforms into a handful of MultiMesh instances. Idle, it does nothing
## per frame; calling set_highlight() every frame with the same node is a no-op.

const SHELL_GROW := 1.07 ## the glow shell is the node's own parts, a little bigger
const SHELL_SLOTS := 10 ## parts per layer the shell can hold (a node has at most 8)
const HIGHLIGHT := Color(1.0, 0.74, 0.40) ## warm ember gold, the same for every kind
const FADE_IN := 0.15 ## seconds for the glow to come up (and go down)

const SHAKE_TIME := {"ash": 0.6, "pine": 0.6, "stone": 0.35, "ember_sap": 0.5}
## Layers that move when hit. The sap seep's rim stones stay still; only its pool bobs.
const SHAKE_LAYERS := {"ember_sap": ["NodeSapPools"]}

const BIT_POOL := 64 ## flying bits shared by every node; the oldest is reused when full
const BITS := {"ash": 7, "pine": 7, "stone": 6, "ember_sap": 8}
const GRAVITY := 9.8
const LEAF_FALL := 1.4 ## m/s, leaves drift down instead of dropping
const CHIP := Color(0.66, 0.63, 0.58)
const DROPLET := Color(1.0, 0.62, 0.25)

var _root: Node3D
var _hl_id := -1
var _hl_level := 0.0 ## 0..1, eased toward 1 while a node is highlighted
var _hl_target := 0.0
var _hl_material: ShaderMaterial
var _shakes := {} ## id -> seconds since the hit
var _bits: Array = [] ## live bits, each a dict from spawn_bits() plus "slot" and "age"
var _next_slot := 0
var _hits := {} ## id -> how many hits so far (varies the bits from hit to hit)


# --- pure maths (no renderer) ---------------------------------------------------------

## A glow-shell transform for one prop part: the same part, grown about its own centre.
static func shell_xform(xf: Transform3D) -> Transform3D:
	return Transform3D(xf.basis * Basis.from_scale(Vector3.ONE * SHELL_GROW), xf.origin)


## How a node of `kind` is displaced `t` seconds after a hit, as a transform about the
## node's base (its pos on the ground). `axis_angle` turns the sway direction so
## neighbouring trees don't all lean the same way. Identity at t <= 0 and once it is over.
static func shake(kind: String, t: float, axis_angle: float = 0.0) -> Transform3D:
	var dur: float = SHAKE_TIME.get(kind, 0.4)
	if t <= 0.0 or t >= dur:
		return Transform3D.IDENTITY
	var fade := 1.0 - t / dur
	match kind:
		"ash", "pine":
			# A shudder from the base: about 2.5 degrees, ringing down fast.
			var axis := Vector3(cos(axis_angle), 0.0, sin(axis_angle))
			return Transform3D(Basis(axis, 0.045 * sin(t * 30.0) * fade * fade), Vector3.ZERO)
		"stone":
			# A short, stiff jolt: a couple of centimetres sideways and a tiny squash.
			var j := 0.025 * sin(t * 70.0) * fade
			var sq := 1.0 - 0.03 * fade
			return Transform3D(Basis.from_scale(Vector3(1.0 / sq, sq, 1.0 / sq)), Vector3(j * cos(axis_angle), 0.0, j * sin(axis_angle)))
		"ember_sap":
			# The pool swells up and settles, like something stirring underneath.
			var y := 1.0 + 0.35 * sin(t / dur * PI) * fade
			return Transform3D(Basis.from_scale(Vector3(1.0, y, 1.0)), Vector3.ZERO)
	return Transform3D.IDENTITY


## The bits one hit on `node` throws. Pure and deterministic for a given (node, hit_no):
## an Array of {p0: Vector3, v: Vector3, life: float, size: Vector3, color: Color,
## glow: float, ground: float, fall: String ("drift" or "arc"), spin: Vector3, phase: float}.
static func spawn_bits(node: Dictionary, hit_no: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 223 + int(node.id) * 7919 + hit_no * 104729
	var s: float = node.scale
	var base: Vector3 = node.pos
	var out: Array = []
	var old := NodeProps.tier_of(node) >= 2 # tier 2 is bigger: bits start further out
	for i in BITS.get(node.kind, 0):
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var b := {"ground": base.y + 0.03, "spin": Vector3(rng.randf_range(-1, 1), 1.0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(4.0, 9.0), "phase": rng.randf() * TAU, "glow": 0.0}
		match node.kind:
			"ash", "pine":
				# Leaves (ash) or needle tufts (pine) shaken loose from the crown.
				# They start just outside the lower edge of the crown, so they are seen at once.
				var ash: bool = node.kind == "ash"
				var r := rng.randf_range(1.6, 2.1) if ash else rng.randf_range(1.2, 1.7)
				var y := rng.randf_range(2.1, 3.0) if ash else rng.randf_range(1.5, 2.8)
				if old and ash: # under the old ash's bigger crown
					r = r * 1.45
					y = y + 0.6
				b.p0 = base + dir * r * s + Vector3.UP * y * s
				b.v = dir * rng.randf_range(0.2, 0.6)
				b.life = rng.randf_range(1.8, 2.6)
				b.fall = "drift"
				if node.kind == "ash":
					b.size = Vector3(0.28, 0.04, 0.2)
					b.color = (NodeProps.OLD_ASH_LEAF if old else NodeProps.ASH_NODE_LEAF).lightened(rng.randf() * 0.15)
					b.glow = 0.25 # ash leaves are warm
				else:
					b.size = Vector3(0.2, 0.06, 0.2)
					b.color = NodeProps.PINE_NODE.lightened(0.15 + rng.randf() * 0.1)
			"stone":
				b.p0 = base + dir * (1.35 if old else 0.9) * s + Vector3.UP * rng.randf_range(0.5, 1.1) * (1.3 if old else 1.0) * s
				b.v = dir * rng.randf_range(1.2, 2.6) + Vector3.UP * rng.randf_range(2.2, 3.6)
				b.life = rng.randf_range(0.7, 1.0)
				b.fall = "arc"
				var c := rng.randf_range(0.08, 0.14)
				b.size = Vector3(c, c * 0.8, c)
				b.color = NodeProps.STONE_VEIN if i == 0 else CHIP.darkened(rng.randf() * 0.2)
				if old: # gold flecks fly off a rich seam
					b.color = NodeProps.RICH_FLECK if i < 2 else NodeProps.RICH_STONE.lightened(rng.randf() * 0.1)
					b.glow = 0.4 if i < 2 else 0.0
			"ember_sap":
				b.p0 = base + dir * rng.randf_range(0.0, 0.3) * s + Vector3.UP * 0.35 * s
				b.v = dir * rng.randf_range(0.3, 1.0) + Vector3.UP * rng.randf_range(2.0, 3.4)
				b.life = rng.randf_range(0.6, 0.85)
				b.fall = "arc"
				var d := rng.randf_range(0.07, 0.11)
				b.size = Vector3(d, d * 1.3, d)
				b.color = DROPLET.lightened(rng.randf() * 0.2)
				b.glow = 1.6
		out.append(b)
	return out


## Where bit `b` is `age` seconds after the hit. Never below its ground; shrinks to nothing
## over the last quarter second of its life (zero basis = hidden).
static func bit_xform(b: Dictionary, age: float) -> Transform3D:
	if age >= b.life or age < 0.0:
		return Transform3D(NodeProps.HIDDEN, b.p0)
	var p: Vector3
	if b.fall == "drift":
		var sway := Vector3(cos(age * 3.1 + b.phase), 0.0, sin(age * 2.3 + b.phase)) * 0.25 * minf(age, 1.0)
		p = b.p0 + b.v * age + sway + Vector3.DOWN * LEAF_FALL * age
	else:
		p = b.p0 + b.v * age + Vector3.DOWN * 0.5 * GRAVITY * age * age
	var landed: bool = p.y <= b.ground
	p.y = maxf(p.y, b.ground)
	var shrink := clampf((b.life - age) / 0.25, 0.0, 1.0)
	var spin: Vector3 = b.spin
	var basis := Basis.IDENTITY
	if not landed:
		basis = Basis(spin.normalized(), spin.length() * age)
	return Transform3D(basis * Basis.from_scale(b.size * shrink), p)


# --- the node -------------------------------------------------------------------------

## Make the shell and bit MultiMeshes. `root` is the ResourceNodes node, `meshes` its
## layer meshes (from NodeProps._meshes()).
func setup(root: Node3D, meshes: Dictionary) -> void:
	_root = root
	name = "Fx"
	_hl_material = ShaderMaterial.new()
	_hl_material.shader = _rim_shader()
	_hl_material.set_shader_parameter("rim_color", HIGHLIGHT)
	_hl_material.set_shader_parameter("strength", 0.0)
	for l in NodeProps.LAYERS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[l]
		mm.instance_count = SHELL_SLOTS
		for i in SHELL_SLOTS:
			mm.set_instance_transform(i, Transform3D(NodeProps.HIDDEN, Vector3.ZERO))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Glow" + l
		mmi.multimesh = mm
		mmi.material_override = _hl_material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		add_child(mmi)
	var bit := SphereMesh.new()
	bit.radius = 0.5
	bit.height = 1.0
	bit.radial_segments = 5
	bit.rings = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Emberlight.bake(bit, 0.0)
	mm.instance_count = BIT_POOL
	for i in BIT_POOL:
		mm.set_instance_transform(i, Transform3D(NodeProps.HIDDEN, Vector3.ZERO))
	var bits := MultiMeshInstance3D.new()
	bits.name = "HitBits"
	bits.multimesh = mm
	bits.material_override = Emberlight.material("glow") # the veins' material: a glowing bit is a flying vein
	bits.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bits)
	set_process(false)


func highlighted() -> int:
	return _hl_id if _hl_target > 0.0 else -1


func set_highlight(id: int, on: bool) -> bool:
	if not _slots().has(id):
		return false
	if on:
		if id == _hl_id and _hl_target > 0.0:
			return true # already lit: cheap every frame
		if id != _hl_id:
			_hl_level = 0.0
		_hl_id = id
		_hl_target = 1.0
		_write_shell()
		_wake()
	elif id == _hl_id:
		_hl_target = 0.0
		_wake()
	return true


func play_hit(id: int) -> bool:
	var slots := _slots()
	if not slots.has(id):
		return false
	var slot: Dictionary = slots[id]
	_shakes[id] = 0.0
	var n := {"id": id, "kind": slot.kind, "pos": slot.pos, "scale": slot.scale, "tier": slot.get("tier", 1)}
	var hit_no: int = _hits.get(id, 0)
	_hits[id] = hit_no + 1
	if _is_depleted(id) and slot.kind != "stone":
		return true # nothing left to shed, but it still shudders (rubble and stumps too)
	var mm := (get_node("HitBits") as MultiMeshInstance3D).multimesh
	for b in spawn_bits(n, hit_no):
		# Reuse the slot of a bit that is still flying if the pool is full.
		var slot_i := _next_slot
		_next_slot = (_next_slot + 1) % BIT_POOL
		_bits = _bits.filter(func(o): return o.slot != slot_i)
		b.slot = slot_i
		b.age = 0.0
		_bits.append(b)
		mm.set_instance_color(slot_i, bit_color(b))
		mm.set_instance_transform(slot_i, bit_xform(b, 0.0))
	_wake()
	return true


## NodeProps.set_depleted() calls this so a lit or shaking node follows its new look.
func refresh(id: int) -> void:
	if id == _hl_id:
		_write_shell()
	if _shakes.has(id):
		_apply_shake(id, _shakes[id])


func _process(delta: float) -> void:
	advance(delta)


## One frame of the effects. Turns itself off when nothing is moving.
func advance(delta: float) -> void:
	# Glow fade.
	if _hl_level != _hl_target:
		_hl_level = move_toward(_hl_level, _hl_target, delta / FADE_IN)
		_hl_material.set_shader_parameter("strength", _hl_level)
		if _hl_level <= 0.0:
			_hide_shell()
	# Shakes.
	for id in _shakes.keys():
		var t: float = _shakes[id] + delta
		_shakes[id] = t
		_apply_shake(id, t)
		if t >= SHAKE_TIME.get(_slots()[id].kind, 0.4):
			_shakes.erase(id)
	# Bits.
	if not _bits.is_empty():
		var mm := (get_node("HitBits") as MultiMeshInstance3D).multimesh
		var alive: Array = []
		for b in _bits:
			b.age += delta
			mm.set_instance_transform(b.slot, bit_xform(b, b.age))
			if b.age < b.life:
				alive.append(b)
		_bits = alive
	if _hl_level == _hl_target and _shakes.is_empty() and _bits.is_empty():
		set_process(false)


func _wake() -> void:
	set_process(true)


func _slots() -> Dictionary:
	return (_root.get_meta("layout", {}) as Dictionary).get("slots", {})


func _is_depleted(id: int) -> bool:
	return (_root.get_meta("depleted", {}) as Dictionary).has(id)


## The parts node `id` shows right now: [[layer, index], ...].
func _current_parts(id: int) -> Array:
	return _slots()[id]["depleted" if _is_depleted(id) else "live"]


func _base_xform(e: Array) -> Transform3D:
	return (_root.get_meta("layout").layers[e[0]][e[1]][0] as Transform3D)


## The node's own transform right now (shaken if it is shaking), for the shell.
func _part_now(id: int, e: Array) -> Transform3D:
	var xf := _base_xform(e)
	if _shakes.has(id) and _shake_moves(id, e[0]):
		xf = _shaken(id, xf, _shakes[id])
	return xf


func _write_shell() -> void:
	_hide_shell()
	var used := {}
	for e in _current_parts(_hl_id):
		var i: int = used.get(e[0], 0)
		if i >= SHELL_SLOTS:
			continue
		used[e[0]] = i + 1
		var mmi := get_node("Glow" + e[0]) as MultiMeshInstance3D
		mmi.multimesh.set_instance_transform(i, shell_xform(_part_now(_hl_id, e)))
		mmi.visible = true


func _hide_shell() -> void:
	for l in NodeProps.LAYERS:
		var mmi := get_node("Glow" + l) as MultiMeshInstance3D
		if mmi.visible:
			for i in SHELL_SLOTS:
				mmi.multimesh.set_instance_transform(i, Transform3D(NodeProps.HIDDEN, Vector3.ZERO))
			mmi.visible = false


func _shake_moves(id: int, layer: String) -> bool:
	var only: Array = SHAKE_LAYERS.get(_slots()[id].kind, [])
	return only.is_empty() or only.has(layer)


func _shaken(id: int, xf: Transform3D, t: float) -> Transform3D:
	var slot: Dictionary = _slots()[id]
	var base: Vector3 = slot.pos
	var m := shake(slot.kind, t, float(id) * 2.399) # golden angle: neighbours sway apart
	return Transform3D(Basis.IDENTITY, base) * m * Transform3D(Basis.IDENTITY, -base) * xf


func _apply_shake(id: int, t: float) -> void:
	for e in _current_parts(id):
		if not _shake_moves(id, e[0]):
			continue
		NodeProps.put_xform(_root, e[0], e[1], _shaken(id, _base_xform(e), t))
	if id == _hl_id and _hl_target > 0.0:
		_write_shell()


## The soft ember-gold rim glow, shared with the workbench's highlight (strength 0..1).
static func rim_shader() -> Shader:
	return _rim_shader()


static func _rim_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 rim_color : source_color = vec4(1.0, 0.74, 0.4, 1.0);
uniform float strength = 0.0;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	ALBEDO = rim_color.rgb * (0.08 + 0.6 * rim) * strength * pulse;
}
"""
	return sh


## A bit's instance colour on Emberlight's shared "glow" material: its colour (linear), with
## its glow carried in alpha as an ember vein (vein = 1 - alpha). The shader's vein light is
## about 2 x vein^2 at rest, so vein = sqrt(glow / 2) keeps each bit as bright as it was on
## its old private shader, now ember-coloured and beating with the valley's heartbeat.
static func bit_color(b: Dictionary) -> Color:
	var c := (b.color as Color).srgb_to_linear()
	c.a = 1.0 - clampf(sqrt(maxf(float(b.get("glow", 0.0)), 0.0) / 2.0), 0.0, 1.0)
	return c

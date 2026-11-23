class_name LevelUpFx
extends Node3D
## The level-up burst: a short column of warm ember light around an avatar, a ring that
## rolls out across the ground from its feet, and a swirl of sparks rising past its head.
## About two seconds, readable from across the Spawn Meadow by day and by night.
##
##   LevelUpFx.play(avatar)   # your own level-ups and other players' alike
##
## `play` adds (or restarts) one "LevelUpFx" child on the avatar, which frees itself when it
## is over, so calling it twice in a row (two skills levelling on one gather) gives one
## brighter, restarted burst rather than two stacked ones.
##
## Everything the burst looks like is pure maths in static functions (`column_at`,
## `ring_at`, `light_at`, `sparks`, `spark_at`), so tests and bots check it headless. The
## node only copies those values into one cylinder, one ring, one MultiMesh of sparks and
## one light. Nothing has a texture; colours come from the lanterns' and the ash leaves'.

const DURATION := 2.0 ## seconds from the burst to the last spark going out
const COLUMN_HEIGHT := 5.5 ## m; about three avatars tall, so it shows over the meadow grass and crowds
const COLUMN_RADIUS := 0.75 ## m at full width; the avatar's body is 0.32 round
const RING_RADIUS := 3.2 ## m the ground ring rolls out to
const SPARKS := 28
const LIGHT_RANGE := 9.0
const LIGHT_ENERGY := 2.4 ## at the peak; a meadow lantern is 1.1 at full night

const CORE := Color(1.0, 0.86, 0.52) ## the column's hot middle, a touch paler than a lantern
const GLOW := Color(1.0, 0.56, 0.24) ## Lamps.FLAME, the lantern light
const SPARK_HOT := Color(1.0, 0.80, 0.42)
const SPARK_EMBER := Color(1.0, 0.42, 0.14) ## Lamps.EMBER, the ash leaves' warmth

const HIDDEN := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

var age := 0.0
var finished := false
var _sparks: Array = []
var _column_mat: ShaderMaterial
var _ring_mat: ShaderMaterial


# --- pure maths (no renderer) ---------------------------------------------------------

## The column `t` seconds in: {height, radius, strength}. It shoots up in the first fifth of
## a second, holds bright, then thins and fades upward. Zero before 0 and from DURATION on.
static func column_at(t: float) -> Dictionary:
	if t <= 0.0 or t >= DURATION:
		return {"height": 0.0, "radius": 0.0, "strength": 0.0}
	var rise := _ease_out(clampf(t / 0.22, 0.0, 1.0))
	var fade := 1.0 - _smooth(clampf((t - 0.5) / (DURATION - 0.7), 0.0, 1.0))
	var flash := 1.0 + 0.6 * exp(-t * 9.0) # a bright pop at the very start
	return {
		"height": COLUMN_HEIGHT * rise * (1.0 + 0.15 * (1.0 - fade)),
		"radius": COLUMN_RADIUS * (0.35 + 0.65 * rise) * (0.45 + 0.55 * fade),
		"strength": fade * flash,
	}


## The ground ring `t` seconds in: {radius, strength}. Rolls out fast and fades as it goes.
static func ring_at(t: float) -> Dictionary:
	const RING_TIME := 0.9
	if t <= 0.0 or t >= RING_TIME:
		return {"radius": 0.0, "strength": 0.0}
	var k := t / RING_TIME
	return {"radius": RING_RADIUS * _ease_out(k) + 0.2, "strength": (1.0 - k) * (1.0 - k)}


## The light's energy `t` seconds in: a flash, then a slow warm fall.
static func light_at(t: float) -> float:
	if t <= 0.0 or t >= DURATION:
		return 0.0
	var up := clampf(t / 0.08, 0.0, 1.0)
	return LIGHT_ENERGY * up * (1.0 - _smooth(t / DURATION))


## The sparks of one burst, deterministic for `seed_value`: an Array of {angle, r0, r1,
## swirl, rise, delay, life, size, color, glow}. They start in a ring at the feet, swirl up
## round the avatar and drift outward a little as they climb.
static func sparks(seed_value: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 6143 + seed_value * 92821
	var out: Array = []
	for i in SPARKS:
		var hot := i % 3 == 0
		out.append({
			"angle": TAU * float(i) / SPARKS + rng.randf_range(-0.1, 0.1),
			"r0": rng.randf_range(0.35, 0.7),
			"r1": rng.randf_range(0.8, 1.5),
			"swirl": rng.randf_range(2.2, 3.6) * (1.0 if i % 2 == 0 else 0.8),
			"rise": rng.randf_range(2.6, 4.2),
			"delay": rng.randf_range(0.0, 0.45),
			"life": rng.randf_range(1.0, 1.5),
			"size": rng.randf_range(0.07, 0.12) * (1.3 if hot else 1.0),
			"color": SPARK_HOT if hot else SPARK_EMBER.lerp(SPARK_HOT, rng.randf() * 0.4),
			"glow": 4.0 if hot else 2.6,
		})
	return out


## Where spark `s` is `t` seconds after the burst, relative to the avatar's feet.
## Zero basis (hidden) before it starts and once it has burnt out; it shrinks over the last
## third of its life, so it winks out rather than popping.
static func spark_at(s: Dictionary, t: float) -> Transform3D:
	var a: float = t - s.delay
	if a <= 0.0 or a >= s.life:
		return Transform3D(HIDDEN, Vector3.ZERO)
	var k: float = a / s.life
	var ang: float = s.angle + s.swirl * a
	var r: float = lerpf(s.r0, s.r1, _ease_out(k))
	var y: float = 0.15 + s.rise * _ease_out(k) * 1.1
	var shrink := clampf((1.0 - k) * 3.0, 0.0, 1.0)
	var p := Vector3(cos(ang) * r, y, sin(ang) * r)
	# Stretched a little along the way it is going, so a spark reads as a streak.
	var b := Basis.from_scale(Vector3(1.0, 2.2, 1.0) * s.size * shrink)
	return Transform3D(b, p)


static func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)


static func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# --- the node -------------------------------------------------------------------------

## Burst on `avatar` (anything whose origin is at the feet, like AvatarBuilder.build()).
## Restarts the burst if one is already playing there. Returns the effect node.
static func play(avatar: Node3D, seed_value: int = 0) -> LevelUpFx:
	var fx := avatar.get_node_or_null("LevelUpFx") as LevelUpFx
	if fx == null or fx.is_queued_for_deletion():
		fx = LevelUpFx.new()
		fx.name = "LevelUpFx"
		fx._build()
		avatar.add_child(fx)
	fx.restart(seed_value)
	return fx


func restart(seed_value: int = 0) -> void:
	age = 0.0
	finished = false
	visible = true
	_sparks = sparks(seed_value)
	_apply()
	set_process(true)


func _process(delta: float) -> void:
	if advance(delta) and is_inside_tree():
		queue_free()


## One frame. Returns true once the burst is over (everything hidden, light out).
func advance(delta: float) -> bool:
	if finished:
		return true
	age += delta
	_apply()
	if age >= DURATION:
		finished = true
		visible = false
		set_process(false)
	return finished


func _apply() -> void:
	var c := column_at(age)
	var col := get_node("Column") as MultiMeshInstance3D
	col.visible = c.strength > 0.0
	col.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(maxf(c.radius, 0.001), maxf(c.height, 0.001), maxf(c.radius, 0.001))), Vector3(0, c.height * 0.5, 0)))
	_column_mat.set_shader_parameter("strength", c.strength)
	var r := ring_at(age)
	var ring := get_node("Ring") as MultiMeshInstance3D
	ring.visible = r.strength > 0.0
	ring.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(maxf(r.radius, 0.001), 1.0, maxf(r.radius, 0.001))), Vector3(0, 0.06, 0)))
	_ring_mat.set_shader_parameter("strength", r.strength)
	var mm := (get_node("Sparks") as MultiMeshInstance3D).multimesh
	for i in _sparks.size():
		mm.set_instance_transform(i, spark_at(_sparks[i], age))
		if age == 0.0:
			mm.set_instance_color(i, (_sparks[i].color as Color).srgb_to_linear())
			mm.set_instance_custom_data(i, Color(_sparks[i].glow, 0, 0, 0))
	var light := get_node("Light") as OmniLight3D
	light.light_energy = light_at(age)
	light.visible = light.light_energy > 0.0


func _build() -> void:
	# The column: an open cylinder, unit size, scaled each frame. Additive and unshaded, so
	# it reads in broad day; brightest in the middle and fading to nothing at the top.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_column_mat = ShaderMaterial.new()
	_column_mat.shader = _column_shader()
	_column_mat.set_shader_parameter("core", CORE)
	_column_mat.set_shader_parameter("glow", GLOW)
	_column_mat.set_shader_parameter("strength", 0.0)
	var col := _single("Column", cyl)
	col.material_override = _column_mat
	add_child(col)

	# The ground ring: a flat disc whose shader draws only a soft band near its edge.
	var disc := PlaneMesh.new()
	disc.size = Vector2(2.0, 2.0)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = _ring_shader()
	_ring_mat.set_shader_parameter("glow", GLOW)
	_ring_mat.set_shader_parameter("strength", 0.0)
	var ring := _single("Ring", disc)
	ring.material_override = _ring_mat
	add_child(ring)

	# Sparks: little low-poly beads, emissive in their own colour.
	var bead := SphereMesh.new()
	bead.radius = 0.5
	bead.height = 1.0
	bead.radial_segments = 5
	bead.rings = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = bead
	mm.instance_count = SPARKS
	for i in SPARKS:
		mm.set_instance_transform(i, Transform3D(HIDDEN, Vector3.ZERO))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sparks"
	mmi.multimesh = mm
	var smat := ShaderMaterial.new()
	smat.shader = _spark_shader()
	mmi.material_override = smat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	var omni := OmniLight3D.new()
	omni.name = "Light"
	omni.light_color = GLOW
	omni.omni_range = LIGHT_RANGE
	omni.light_energy = 0.0
	omni.shadow_enabled = false
	omni.position = Vector3(0, 1.4, 0)
	omni.visible = false
	add_child(omni)
	set_process(false)


## One mesh drawn through a one-instance MultiMesh (sized by its instance transform), so it
## builds cleanly on a headless machine too, where a plain MeshInstance3D logs engine errors.
static func _single(node_name: String, mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(HIDDEN, Vector3.ZERO))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	return mmi


static func _column_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 core : source_color = vec4(1.0, 0.86, 0.52, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.56, 0.24, 1.0);
uniform float strength = 0.0;
varying float h;
void vertex() {
	h = VERTEX.y + 0.5; // 0 at the feet, 1 at the top
}
void fragment() {
	// Edge-on faces are the column's outline; face-on is its thin middle. Inverted rim, so
	// the middle glows and the sides fall off softly instead of showing a hard tube.
	float facing = abs(dot(NORMAL, VIEW));
	float body = pow(facing, 1.6);
	float top = 1.0 - smoothstep(0.35, 1.0, h);
	float foot = smoothstep(0.0, 0.06, h);
	float shimmer = 0.85 + 0.15 * sin(TIME * 14.0 + h * 18.0);
	// Alpha-blended, not additive: over a bright day sky an additive column burns out to a
	// flat white tube, while a warm translucent one reads as gold by day and glows by night.
	// Mostly lantern orange, so it stands out against a blue sky; the pale core only at the
	// very middle.
	ALBEDO = mix(glow.rgb, core.rgb, body * body * 0.6) * 1.2;
	ALPHA = clamp((0.45 + 1.0 * body) * top * foot * shimmer * strength, 0.0, 0.92);
}
"""
	return sh


static func _ring_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 glow : source_color = vec4(1.0, 0.56, 0.24, 1.0);
uniform float strength = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0; // 0 centre, 1 edge of the disc
	float band = smoothstep(0.72, 0.92, d) * (1.0 - smoothstep(0.92, 1.0, d));
	float fill = 0.12 * (1.0 - smoothstep(0.0, 0.92, d));
	ALBEDO = glow.rgb * (band * 1.6 + fill) * strength;
}
"""
	return sh


static func _spark_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
varying float glow;
void vertex() {
	glow = INSTANCE_CUSTOM.r;
}
void fragment() {
	ALBEDO = COLOR.rgb * (0.6 + 0.25 * glow);
}
"""
	return sh

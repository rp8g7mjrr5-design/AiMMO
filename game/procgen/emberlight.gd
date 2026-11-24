class_name Emberlight
## The one shader family for Ashgrove's world art (docs/art_bible.md, "Emberlight: painted
## low-poly"). Three variants share one shader source:
##   "solid"   ground, bark, stone, wood
##   "foliage" the same, plus a gentle wind sway that grows with height up the mesh
##   "glow"    the same as solid, plus ember veins that beat with the valley's heartbeat
##
## What the shader does, all in maths with no texture lookups:
## - Ramp lighting: two soft bands instead of a smooth Lambert falloff, so faces read as
##   painted planes of light and shade.
## - Warm light, cool shadow: the lit side leans gold, the side turned away leans `SHADE`.
## - A soft rim on silhouettes when you look towards the light.
## - "Brush noise": a slow, world-position value noise that varies the paint a few percent,
##   so big flat faces never look like bare untextured blocks.
## - Colour from vertex colours (MultiMesh instance colours multiply in), including the
##   baked ambient occlusion from `bake()` and the terrain builder.
## - Ember veins (glow variant): vertex alpha below 1 marks a vein, vein strength = 1 - alpha.
## - The heartbeat: one global shader parameter, `ember_pulse` (0..1, one beat every
##   `BEAT_SECONDS` of world time), drives every glow. DayNight sets it each frame from the
##   shared clock, so the whole valley breathes together on every screen.
##
## Materials are built once and shared: `material(variant)` always returns the same instance
## for the same variant, and `material(variant, name)` the same instance for the same name
## (used where one layer needs its own uniforms, e.g. the ash leaves' night glow). Per-object
## variety comes from vertex and instance colours, never from a new material. `count()` says
## how many exist, for the art bible's 24-material budget.

const VARIANTS := ["solid", "foliage", "glow"]
const BEAT_SECONDS := 4.0 ## the heartbeat: one slow beat every 4 s of world time
const PULSE_PARAM := "ember_pulse"
const NIGHT_PARAM := "ember_night" ## 0 by day, 1 at full night (SkyClock.night_amount)

static var _shaders: Dictionary = {} # variant -> Shader
static var _materials: Dictionary = {} # "variant" or "variant/name" -> ShaderMaterial
static var _globals_ready := false


## The shared material for `variant` (and optional `name`). Same arguments, same instance.
static func material(variant: String = "solid", name: String = "") -> ShaderMaterial:
	assert(variant in VARIANTS, "unknown Emberlight variant " + variant)
	var key := variant if name == "" else variant + "/" + name
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader(variant)
		m.resource_name = "Emberlight " + key
		_materials[key] = m
	return _materials[key]


## Distinct Emberlight materials made so far this session.
static func count() -> int:
	return _materials.size()


## True if `mat` is one of ours.
static func is_emberlight(mat: Material) -> bool:
	return mat is ShaderMaterial and _materials.values().has(mat)


## The heartbeat at a world time, 0..1. A soft swell and a slower fall, like a breath; the
## same on every machine because world time is.
static func pulse(world_seconds: float) -> float:
	var t := fposmod(world_seconds, BEAT_SECONDS) / BEAT_SECONDS
	var s := 0.5 - 0.5 * cos(TAU * t)
	return s * s * (3.0 - 2.0 * s) # smoothstep: lingers at rest and at the peak


## Set the heartbeat for every Emberlight glow at once (one RenderingServer call).
static func set_pulse(value: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(PULSE_PARAM, clampf(value, 0.0, 1.0))


## How far the world leans to its night paint, 0..1 (one RenderingServer call; DayNight sets
## it on every repaint from `SkyClock.night_amount`).
static func set_night(value: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(NIGHT_PARAM, clampf(value, 0.0, 1.0))


## Register the global shader parameters our shaders read. Must run before any of our
## shaders compiles; `shader()` calls it.
static func ensure_globals() -> void:
	if _globals_ready:
		return
	_globals_ready = true
	# (global_shader_parameter_get_list is editor-only and logs an error in a game, so we
	# rely on the flag above: nothing else registers this name.)
	RenderingServer.global_shader_parameter_add(PULSE_PARAM, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add(NIGHT_PARAM, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


## A copy of `mesh` (first surface) with baked vertex colours: grey `1 - ao` at the bottom
## of the mesh rising to white at the top (things sit dark in the ground and lighten up
## their height, "lit from within"). Vertex positions, normals and order are unchanged, so
## anything that reads the mesh's vertices (camera solids) sees exactly the same shape.
static func bake(mesh: Mesh, ao: float, curve: float = 1.0) -> ArrayMesh:
	return _shaded(mesh, ao, curve, Vector3.ONE, 1.0)


## Like `bake()`, but the vertex colours also carry `color` (sRGB, like the palette; stored
## linear, as the shader expects). For things drawn as single meshes rather than MultiMesh
## instances (avatars), so each part keeps its own colour on the one shared material.
## `color.a` below 1 marks the whole part as an ember vein on the "glow" variant.
static func paint(mesh: Mesh, color: Color, ao: float = 0.0, curve: float = 1.0) -> ArrayMesh:
	var lin := color.srgb_to_linear()
	return _shaded(mesh, ao, curve, Vector3(lin.r, lin.g, lin.b), color.a)


static func _shaded(mesh: Mesh, ao: float, curve: float, tint: Vector3, alpha: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	for v in verts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var span := maxf(hi - lo, 0.0001)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in verts.size():
		var g := 1.0 - ao * pow(1.0 - (verts[i].y - lo) / span, curve)
		colors[i] = Color(g * tint.x, g * tint.y, g * tint.z, alpha)
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## The shader for a variant, built once.
static func shader(variant: String) -> Shader:
	if not _shaders.has(variant):
		ensure_globals()
		var sh := Shader.new()
		sh.code = source(variant)
		_shaders[variant] = sh
	return _shaders[variant]


## The shader source for a variant (pure text, tested headless).
static func source(variant: String) -> String:
	var defines := ""
	if variant == "foliage":
		defines += "#define FOLIAGE\n"
	if variant == "glow":
		defines += "#define GLOW\n"
	var shade := Palette.SHADE.srgb_to_linear()
	var ember := Palette.EMBER.srgb_to_linear()
	var core := Palette.EMBER_CORE.srgb_to_linear()
	return (defines + SHADER_BODY
		.replace("$SHADE", "vec3(%.4f, %.4f, %.4f)" % [shade.r, shade.g, shade.b])
		.replace("$EMBER_CORE", "vec3(%.4f, %.4f, %.4f)" % [core.r, core.g, core.b])
		.replace("$EMBER", "vec3(%.4f, %.4f, %.4f)" % [ember.r, ember.g, ember.b]))


const SHADER_BODY := """
shader_type spatial;
render_mode cull_back, specular_disabled;

global uniform float ember_pulse;
global uniform float ember_night; // 0 by day, 1 at full night: the paint drains and shadows go blue

uniform float shade_strength = 0.30; // how far the turned-away side leans towards SHADE
uniform float warmth = 0.10; // how far the lit side leans gold
uniform float rim_strength = 0.35; // soft rim on silhouettes when looking towards the light
uniform float brush = 0.07; // world-position paint variation, +- this fraction
uniform float night_desat = 0.55; // at full night the paint keeps only this much less of its colour
uniform float night_shade = 0.35; // extra SHADE blue in the shadows at full night
uniform vec3 emission_color : source_color = vec3(1.0, 0.42, 0.14);
uniform float emission_energy = 0.0; // a whole-surface glow (the ash leaves at night)
uniform float pulse_depth = 0.25; // how much emission_energy swells with the heartbeat
uniform float night_rim = 1.5; // extra moonlit rim at full night (x rim_strength), so figures, trunks and crowns keep a readable edge against the dark
#ifdef FOLIAGE
uniform float sway = 0.06; // metres of sway per metre of height up the mesh
uniform float sway_base = -1.3; // local height where the sway starts
#endif
#ifdef GLOW
uniform float vein_energy = 2.0;
#endif

varying vec3 world_pos;
#ifdef GLOW
varying float vein;
#endif

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
#ifdef FOLIAGE
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(VERTEX.y - sway_base, 0.0);
	float phase = TIME * 1.1 + origin.x * 0.21 + origin.z * 0.17;
	VERTEX.x += sin(phase) * sway * h;
	VERTEX.z += sin(phase * 0.73 + 1.7) * sway * 0.6 * h;
#endif
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#ifdef GLOW
	vein = 1.0 - COLOR.a;
#endif
}

void fragment() {
	float n = value_noise(world_pos.xz * 0.35) * 0.65 + value_noise(world_pos.xz * 1.7 + world_pos.y) * 0.35;
	ALBEDO = COLOR.rgb * (1.0 + (n - 0.5) * 2.0 * brush);
	// Night is blue and ember (art bible section 2): the moon drains the greens, so the
	// ground reads moonlit instead of green-black and every glow stands out against it.
	// Only the greens drain: warm paint (ash crowns, bark, the lanterns) keeps its colour.
	float green = smoothstep(-0.02, 0.10, ALBEDO.g - ALBEDO.r);
	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.299, 0.587, 0.114))), ember_night * night_desat * green);
	ROUGHNESS = 1.0;
	float beat = ember_pulse;
	vec3 glow = emission_color * emission_energy * (1.0 - pulse_depth + pulse_depth * 2.0 * beat);
#ifdef GLOW
	glow += mix($EMBER, $EMBER_CORE, beat * vein) * vein * vein_energy * (0.55 + 0.45 * beat);
#endif
	EMISSION = glow;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Two soft bands: shadow, half light, full light.
	float ramp = smoothstep(0.0, 0.15, ndl) * 0.5 + smoothstep(0.35, 0.55, ndl) * 0.5;
	float lit = ramp * ATTENUATION;
	vec3 key = LIGHT_COLOR * mix(vec3(1.0), vec3(1.0, 0.86, 0.66), warmth);
	DIFFUSE_LIGHT += key * lit / PI;
	// Cool shadow: what the sun or moon doesn't reach leans blue-violet, never grey. Only the
	// directional key paints it. A lantern's light() also runs on every pixel of every Forward+
	// light cluster its range touches (screen tiles x depth slices), including pixels far past
	// its range where ATTENUATION is 0, so a lantern adding SHADE here tinted whole cluster
	// cells pale blue: the blocky, stair-stepped pool round Spawn Meadow at night. A local
	// light only ever adds its own warm light, fading smoothly with ATTENUATION.
	if (LIGHT_IS_DIRECTIONAL) {
		float strength = dot(LIGHT_COLOR, vec3(0.299, 0.587, 0.114));
		DIFFUSE_LIGHT += $SHADE * (1.0 - lit) * (shade_strength + night_shade * ember_night) * strength / PI;
	}
	// Rim: silhouettes catch the light from behind.
	// At night the moon's rim is stronger: the moonlit edge is what makes a silhouette read
	// (art bible, night). Lanterns keep the plain rim, faded by their own falloff.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * clamp(dot(LIGHT, -VIEW) * 0.5 + 0.5, 0.0, 1.0);
	float rim_gain = LIGHT_IS_DIRECTIONAL ? 1.0 + night_rim * ember_night : 1.0;
	DIFFUSE_LIGHT += LIGHT_COLOR * rim * rim_strength * rim_gain * ATTENUATION / PI;
}
"""

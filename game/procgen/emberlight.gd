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
## - "Brush noise": a slow, broad world-position value noise that varies the paint a few
##   percent, so big faces get a soft mottling instead of one dead flat colour.
## - "Low-res paint": an optional grain of small square texels from the mesh's own position
##   (hashed, no texture). Off by default since 2026-11-26: the world is clean flat colour
##   like the carved characters that live in it (art bible section 1).
## - "Carved facets": each triangle is lit as one flat plane (its normal from screen-space
##   derivatives, so no mesh is rebuilt and no vertex is added): clean carved low poly.
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


## The shared "solid" material painted with SurfaceTex `kind` detail (bark, stone, wood): one
## material per kind, so every tree trunk shares one and every rock another.
## The detail is OFF (mix 0) since the world was matched to the clean carved characters
## (owner, 2026-11-26: "make sure the map now fits with our new characters", then "B clean
## carved real proportions"): the characters are crisp flat-coloured planes, and grain or
## texture noise on the world beside them read as two games. The kinds stay, so bark and stone keep their own shared materials (and a later look
## can turn a kind back on here, in one place).
const PAINT := {
	"bark": {"tpm": 1.2, "mix": 0.0},
	"stone": {"tpm": 0.9, "mix": 0.0},
	"wood": {"tpm": 1.6, "mix": 0.0},
	"ground": {"tpm": 0.6, "mix": 0.0},
}


static func painted(kind: String, variant: String = "solid") -> ShaderMaterial:
	var m := material(variant, kind)
	if not m.has_meta("painted"):
		m.set_meta("painted", true)
		paint_material(m, kind)
	return m


## Lay SurfaceTex `kind` over material `m` at the art bible's strength for that kind.
static func paint_material(m: ShaderMaterial, kind: String) -> void:
	m.set_shader_parameter("paint_tex", SurfaceTex.get_texture(kind))
	m.set_shader_parameter("paint_tpm", float(PAINT[kind].tpm))
	m.set_shader_parameter("paint_mix", float(PAINT[kind].mix))


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


## True when this process draws with Godot's Compatibility renderer (opengl3: CI's smoke test,
## and any player whose GPU has no Vulkan). Godot 4.3's Compatibility renderer reads a spatial
## shader's ALBEDO and EMISSION as sRGB and linearises them itself (drivers/gles3/shaders/
## scene.glsl, "Convert colors to linear"), and hands `source_color` uniforms over still in
## sRGB; Forward+ and Mobile take ALBEDO and EMISSION as linear, which is what all our shaders
## write (vertex colours from `paint()`, palette constants baked with `srgb_to_linear()`). So on
## Compatibility every colour was linearised twice: a mid tone came out at about a fifth of its
## brightness, and at night, where everything sits low in the tonemapper's toe, pines and
## figures went near black (luma 0.06 against 0.26 on Forward+ for the same night shot).
## Forward+ and Mobile have a RenderingDevice; Compatibility and the headless server don't.
static func srgb_output() -> bool:
	if force_srgb_output >= 0:
		return force_srgb_output == 1
	return RenderingServer.get_rendering_device() == null and DisplayServer.get_name() != "headless"

static var force_srgb_output := -1 ## tests: 1 or 0 pins `srgb_output()`, -1 detects

## On Compatibility, lit surfaces still come out brighter than on Forward+ for the same paint
## (its sky ambient and light paths differ; measured 2026-11-24 on the same night shot, both
## renderers, same lavapipe/llvmpipe machine). Scaling the paint by this before the encode
## brings the night spawn shot to Forward+'s brightness (centre luma 0.23 vs 0.26) and noon
## close to it (0.71 vs 0.64; noon's remaining gap is the sky and fog, which this doesn't
## touch). Only ALBEDO: glows and unlit effects already match exactly after the encode.
const COMPAT_ALBEDO := 0.5


## The line that switches `COMPAT_GLSL`'s fix on, for any of our shaders' sources (Motes and
## other shaders put it first too). Empty on Forward+ and Mobile, so their shaders are unchanged.
static func compat_define(on: bool = srgb_output()) -> String:
	return "#define COMPAT_SRGB\n" if on else ""


## Mirror of the shader's `compat_encode` for one channel (tests): the sRGB value Godot 4.3's
## Compatibility renderer turns back into exactly `lin` with its own `srgb_to_linear` cubic.
static func compat_encode(lin: float) -> float:
	lin = maxf(lin, 0.0)
	# First guess: solve the cubic without its x^3 term (a quadratic), which lands at or just
	# above the answer everywhere; Newton then walks down onto it (the cubic is convex).
	var x := (sqrt(0.012522878 * 0.012522878 + 4.0 * 0.682171111 * lin) - 0.012522878) / (2.0 * 0.682171111)
	for i in 3:
		var f := compat_decode(x) - lin
		var d := x * (x * 0.915918033 + 1.364342222) + 0.012522878
		x -= f / d
	return x


## Godot 4.3 Compatibility's own sRGB to linear (gles3 tonemap_inc.glsl), one channel.
static func compat_decode(c: float) -> float:
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878)


## GLSL for both directions, shared by every shader of ours that writes ALBEDO or EMISSION.
## `compat_encode` inverts Godot 4.3 Compatibility's own sRGB to linear cubic (the cubic
## solved without its x^3 term as a first guess, then three Newton steps; the usual pow
## approximation of linear to sRGB left darks up to 60% too dark,
## which is exactly where night lives), so the renderer's conversion hands back the linear
## colour we meant. Only compiled in under COMPAT_SRGB.
const COMPAT_GLSL := """
#ifdef COMPAT_SRGB
vec3 compat_decode(vec3 c) {
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
}
vec3 compat_encode(vec3 lin) {
	lin = max(lin, vec3(0.0));
	vec3 x = (sqrt(vec3(0.000156822) + 2.728684444 * lin) - vec3(0.012522878)) / 1.364342222;
	x -= (compat_decode(x) - lin) / (x * (x * 0.915918033 + 1.364342222) + 0.012522878);
	x -= (compat_decode(x) - lin) / (x * (x * 0.915918033 + 1.364342222) + 0.012522878);
	x -= (compat_decode(x) - lin) / (x * (x * 0.915918033 + 1.364342222) + 0.012522878);
	return x;
}
#endif
"""


## The shader for a variant, built once.
static func shader(variant: String) -> Shader:
	if not _shaders.has(variant):
		ensure_globals()
		var sh := Shader.new()
		sh.code = source(variant)
		_shaders[variant] = sh
	return _shaders[variant]


## The shader source for a variant (pure text, tested headless).
static func source(variant: String, srgb_out: bool = srgb_output()) -> String:
	var defines := compat_define(srgb_out)
	if variant == "foliage":
		defines += "#define FOLIAGE\n"
	if variant == "glow":
		defines += "#define GLOW\n"
	var shade := Palette.SHADE.srgb_to_linear()
	var ember := Palette.EMBER.srgb_to_linear()
	var core := Palette.EMBER_CORE.srgb_to_linear()
	return (defines + SHADER_BODY.replace("$COMPAT_GLSL", COMPAT_GLSL)
		.replace("$SHADE", "vec3(%.4f, %.4f, %.4f)" % [shade.r, shade.g, shade.b])
		.replace("$EMBER_CORE", "vec3(%.4f, %.4f, %.4f)" % [core.r, core.g, core.b])
		.replace("$EMBER", "vec3(%.4f, %.4f, %.4f)" % [ember.r, ember.g, ember.b])
		.replace("$COMPAT_ALBEDO", "%.3f" % COMPAT_ALBEDO))


const SHADER_BODY := """
shader_type spatial;
render_mode cull_back, specular_disabled;

global uniform float ember_pulse;
global uniform float ember_night; // 0 by day, 1 at full night: the paint drains and shadows go blue

uniform float shade_strength = 0.30; // how far the turned-away side leans towards SHADE
uniform float warmth = 0.10; // how far the lit side leans gold
uniform float rim_strength = 0.35; // soft rim on silhouettes when looking towards the light
uniform float brush = 0.035; // world-position paint variation, +- this fraction: a soft, broad mottling, never noise
uniform float texel_size = 0.055; // metres per "texel" of the low-res paint grain, in the mesh's own space
uniform float texel_grain = 0.0; // how far each texel's paint varies, +- this fraction (0 = off: the world matches the clean carved characters, 2026-11-26)
uniform float facets = 1.0; // 1: every triangle lit as one flat carved plane (clean carved low poly, 2026-11-26); 0: smooth normals
uniform float night_desat = 0.55; // at full night the paint keeps only this much less of its colour
uniform float night_shade = 1.4; // extra SHADE blue in the shadows at full night: the moonlit side of a figure turned away from the moon (never a black hole)
uniform vec3 emission_color : source_color = vec3(1.0, 0.42, 0.14);
uniform float emission_energy = 0.0; // a whole-surface glow (the ash leaves at night)
uniform float pulse_depth = 0.25; // how much emission_energy swells with the heartbeat
uniform sampler2D paint_tex : filter_nearest_mipmap, repeat_enable, hint_default_white; // SurfaceTex detail, brightness around 0.5
uniform float paint_mix = 0.0; // how much the painted surface detail shows (0 = off, the default)
uniform float paint_tpm = 1.0; // how many times the detail texture repeats per metre of world
uniform float night_rim = 1.5; // extra moonlit rim at full night (x rim_strength), so figures, trunks and crowns keep a readable edge against the dark
#ifdef FOLIAGE
uniform float sway = 0.06; // metres of sway per metre of height up the mesh
uniform float sway_base = -1.3; // local height where the sway starts
#endif
#ifdef GLOW
uniform float vein_energy = 2.0;
#endif

$COMPAT_GLSL
varying vec3 world_pos;
varying vec3 world_nrm;
varying vec3 local_pos;
#ifdef GLOW
varying float vein;
#endif

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
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
	world_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	local_pos = VERTEX;
#ifdef GLOW
	vein = 1.0 - COLOR.a;
#endif
}

void fragment() {
	if (facets > 0.5) {
		// Carved: the face's own normal (view space), so every triangle is one clean plane.
		// Screen y runs opposite ways on Vulkan and OpenGL, so the cross product's sign isn't
		// fixed: turn it to the side the mesh's own normal faces.
		vec3 face = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		NORMAL = dot(face, NORMAL) < 0.0 ? -face : face;
	}
	float n = value_noise(world_pos.xz * 0.12) * 0.75 + value_noise(world_pos.xz * 0.45 + world_pos.y * 0.3) * 0.25;
	ALBEDO = COLOR.rgb * (1.0 + (n - 0.5) * 2.0 * brush);
	// Low-res paint (art bible section 1): the colour breaks into small square texels, like a
	// hand-painted texture shown with nearest-neighbour filtering, but computed from the mesh's
	// own position, so there is no texture to load and it sticks to the thing as it moves.
	vec3 texel = floor(local_pos / texel_size);
	float g = hash13(texel + 17.0) - 0.5;
	ALBEDO *= 1.0 + g * 2.0 * texel_grain;
	// Painted surface detail (SurfaceTex): a small tiling texture of grass and earth, bark,
	// stone or wood grain, projected along the face's main axis in world space (no UVs needed,
	// and it lines up across every tree and rock of a layer). Brightness only: the colour stays
	// the vertex colour's.
	if (paint_mix > 0.0) {
		vec3 an = abs(world_nrm);
		vec2 uv = an.y > an.x && an.y > an.z ? world_pos.xz : (an.x > an.z ? vec2(world_pos.z, -world_pos.y) : vec2(world_pos.x, -world_pos.y));
		float detail = texture(paint_tex, uv * paint_tpm).r;
		ALBEDO *= mix(1.0, detail * 2.0, paint_mix);
	}
	// Night is blue and ember (art bible section 2): the moon drains the greens, so the
	// ground reads moonlit instead of green-black and every glow stands out against it.
	// Only the greens drain: warm paint (ash crowns, bark, the lanterns) keeps its colour.
	float green = smoothstep(-0.02, 0.10, ALBEDO.g - ALBEDO.r);
	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.299, 0.587, 0.114))), ember_night * night_desat * green);
	ROUGHNESS = 1.0;
	float beat = ember_pulse;
	vec3 emission_lin = emission_color;
#ifdef COMPAT_SRGB
	emission_lin = compat_decode(emission_lin); // Compatibility leaves source_color uniforms in sRGB
#endif
	vec3 glow = emission_lin * emission_energy * (1.0 - pulse_depth + pulse_depth * 2.0 * beat);
#ifdef GLOW
	glow += mix($EMBER, $EMBER_CORE, beat * vein) * vein * vein_energy * (0.55 + 0.45 * beat);
#endif
	EMISSION = glow;
#ifdef COMPAT_SRGB
	// Compatibility linearises ALBEDO and EMISSION itself: hand it the sRGB of our linear paint,
	// so it comes out as painted instead of linearised twice (see Emberlight.srgb_output()).
	ALBEDO = compat_encode(ALBEDO * $COMPAT_ALBEDO);
	EMISSION = compat_encode(EMISSION);
#endif
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Two wide, soft bands: shadow, half light, full light. Wide enough that a smooth,
	// rounded surface (a body, a limb, a boulder) shades smoothly around its curve instead of
	// breaking into hard planes, while flat-faceted props still read as painted planes.
	float ramp = smoothstep(-0.08, 0.3, ndl) * 0.5 + smoothstep(0.25, 0.75, ndl) * 0.5;
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

class_name Sea
## The sea round an island (the starting-beach pass, owner 2026-11-26: "polish out the
## ocean"). One shader on the one water plane, no textures (art bible section 7):
## - **Depth-tinted water**: green-grey over the sand a hand deep (Palette.SEA_SHALLOW), the old
##   cold WATER further out, clearer near the shore so the wet sand shows through.
## - **Surf**: an off-white line where the water meets the sand, washing up and back every few
##   seconds, with a second, fainter band of broken water just beyond it, broken up by
##   world-position noise so it never reads as a stripe.
## - **A slow swell**: two long, crossing ripples in the normal only (the plane stays flat, so it
##   costs nothing in triangles), so the low sun and the moon draw a glitter path on it.
## Reads the scene's depth (hint_depth_texture), so foam forms on every shore, rock and post
## that stands in the water, with no shoreline data. Islands only: Ashgrove's and version 1's
## lakes keep their plain water, so their look and the smoke test's shots are unchanged.

const FOAM_DEPTH := 0.45 ## metres of water under which the surf line forms
const SHALLOW_DEPTH := 3.5 ## metres over which shallow green-grey turns to deep water
const SWASH_SECONDS := 6.5 ## one wash up the sand and back

static var _material: ShaderMaterial


## The shared sea material (one per session, like Emberlight's).
static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = source()
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("compat_ndc", 1.0 if Emberlight.srgb_output() else 0.0)
	return _material


## The shader source: Emberlight's sRGB fix on Compatibility first, then the sea.
static func source(srgb_out: bool = Emberlight.srgb_output()) -> String:
	var deep := Palette.WATER.srgb_to_linear()
	var shallow := Palette.SEA_SHALLOW.srgb_to_linear()
	var foam := Palette.FOAM.srgb_to_linear()
	return (Emberlight.compat_define(srgb_out) + SHADER.replace("$COMPAT_GLSL", Emberlight.COMPAT_GLSL)
		.replace("$SURF_DEPTH", "%.3f" % FOAM_DEPTH)
		.replace("$TINT_DEPTH", "%.3f" % SHALLOW_DEPTH)
		.replace("$DEEP", "vec3(%.4f, %.4f, %.4f)" % [deep.r, deep.g, deep.b])
		.replace("$SHALLOW", "vec3(%.4f, %.4f, %.4f)" % [shallow.r, shallow.g, shallow.b])
		.replace("$FOAM", "vec3(%.4f, %.4f, %.4f)" % [foam.r, foam.g, foam.b])
		.replace("$SWASH", "%.3f" % (TAU / SWASH_SECONDS))
		.replace("$COMPAT_ALBEDO", "%.3f" % Emberlight.COMPAT_ALBEDO))


const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform sampler2D scene_depth : hint_depth_texture, filter_linear_mipmap;
uniform float compat_ndc = 0.0; // Compatibility's depth runs -1..1; Forward+'s 0..1
uniform float deep_alpha = 0.86;

varying vec3 world_pos;

$COMPAT_GLSL

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// How deep the water is here: the ground under this pixel from the depth buffer.
	float d = texture(scene_depth, SCREEN_UV).r;
	vec3 ndc = compat_ndc > 0.5 ? vec3(SCREEN_UV, d) * 2.0 - 1.0 : vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 floor_pos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	float depth = max(world_pos.y - floor_pos.y, 0.0);

	vec2 xz = world_pos.xz;
	float t = TIME;
	// The swash: the surf line slides up the sand and back.
	float swash = 0.5 + 0.5 * sin(t * $SWASH + vnoise(xz * 0.03) * 6.2831);
	float n1 = vnoise(xz * 0.55 + vec2(t * 0.12, -t * 0.07));
	float n2 = vnoise(xz * 1.7 - vec2(t * 0.2, t * 0.15));
	float edge = $SURF_DEPTH * (0.45 + 0.75 * swash);
	float surf = 1.0 - smoothstep(edge * 0.55, edge, depth + (n1 - 0.5) * 0.18);
	surf *= smoothstep(0.25, 0.55, n2 * 0.6 + n1 * 0.6); // broken up, never a clean stripe
	surf = max(surf, 1.0 - smoothstep(0.0, 0.06, depth)); // a thin wet line right at the sand
	// A second band of broken water rolling in just beyond.
	float roll = fract(depth / ($SURF_DEPTH * 3.0) - t * 0.11);
	float band = smoothstep(0.0, 0.12, roll) * (1.0 - smoothstep(0.12, 0.3, roll));
	band *= (1.0 - smoothstep($SURF_DEPTH, $SURF_DEPTH * 3.2, depth)) * smoothstep(0.45, 0.7, n2) * 0.6;
	float foam = clamp(max(surf, band), 0.0, 1.0) * COLOR.a; // a tide pool's instance alpha calms it

	float shallow = 1.0 - smoothstep(0.0, $TINT_DEPTH, depth);
	vec3 water = mix($DEEP, $SHALLOW, shallow);
	ALBEDO = mix(water, $FOAM, foam);
	ALPHA = mix(mix(deep_alpha, 0.42, shallow * shallow), 0.92, foam);
	ROUGHNESS = mix(0.14, 0.9, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.6, 0.2, foam);

	// The swell: two long crossing ripples and a fine chop, in the normal only.
	vec2 g = vec2(0.0);
	g += vec2(0.8, 0.6) * cos(dot(xz, vec2(0.8, 0.6)) * 0.21 + t * 0.9) * 0.05;
	g += vec2(-0.5, 0.86) * cos(dot(xz, vec2(-0.5, 0.86)) * 0.33 + t * 1.25) * 0.035;
	g += (vec2(vnoise(xz * 0.9 + t * 0.3), vnoise(xz.yx * 0.9 - t * 0.27)) - 0.5) * 0.06;
	g *= 1.0 - foam;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
#ifdef COMPAT_SRGB
	ALBEDO = compat_encode(ALBEDO * $COMPAT_ALBEDO);
#endif
}
"""

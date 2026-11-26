class_name Grass
## Grass tufts near the camera (owner direction 2026-11-24, the test-camp look in the game:
## "whole world first", after the painted surfaces). Crossed cards of alpha-cut blades,
## coloured from the ground under them, swaying a little in the wind.
##
## Only near the camera: the frame budget (art bible section 7) has no room for a whole world
## of grass, and from far away the painted ground texture already reads as turf. The ground
## is cut into CELL x CELL metre cells; each cell's tufts come from a pure, deterministic
## `cell()` (same world, same tufts, on every machine and every visit), and all the cells in
## range share one MultiMesh, so grass is one draw call. Tufts shrink into the ground over the
## last FADE metres of the range, so the edge grows in softly instead of popping.
##
## Client only: WorldBuilder adds it; the server and the bots never build art. Nothing about
## grass is saved, so changing it never touches player data. The Graphics setting thins it
## (the client's `Quality.flora_density()`, read by path like Flora, because the server export
## leaves `client/` out).

const SEED_OFFSET := 509
const CELL := 8.0 ## metres per cell side
const GRID := 1.0 ## metres between ground samples inside a cell (height, colour, where grass grows)
const RANGE := 24.0 ## metres from the grass centre where the last tufts stand
const FADE := 7.0 ## metres over which tufts shrink into the ground at the edge of the range
const AHEAD := 9.0 ## metres the grass centre sits ahead of the camera, so the range covers what you see
const DENSITY := 5.0 ## tufts per square metre on open meadow at full Graphics
const BUILD_PER_FRAME := 2 ## cells generated per frame once the first fill is done
const WATER_CLEAR := 1.0 ## metres above the water before grass grows (shores stay silt)
const MAX_SLOPE := 0.45 ## 1 - normal.y: steeper ground is rock and earth
const ROAD_CLEAR := 1.0 ## metres beyond a kingdom road's edge
const TUFT_W := 0.55
const TUFT_H := 0.5
const FLOATS := 16 ## per instance in the MultiMesh buffer: 12 transform + 4 colour

const QUALITY_SCRIPT := "res://client/quality.gd"
const QUALITY_POLL := 0.5

## How much grass each ground kind grows, 0..1 (ground under a kingdom's biomes; Ashgrove uses heights).
const BIOME_DENSITY := {"farmland": 1.0, "moor": 0.8, "forest": 0.45, "stone_hills": 0.35}

static var _mesh: ArrayMesh
static var _material: ShaderMaterial
static var _patch: FastNoiseLite


## The tufts of one cell, as a MultiMesh buffer (FLOATS per tuft: a 3x4 transform, then a
## linear colour). Pure: depends only on the world, the cell and `density` (0..1, Graphics).
static func cell(cx: int, cz: int, density: float = 1.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if density <= 0.0:
		return out
	var n := int(ceil(CELL / GRID)) + 1
	var x0 := cx * CELL
	var z0 := cz * CELL
	# Sample the ground once per GRID metres (heights, how much grass grows, its colour), then
	# place tufts between the samples. Terrain.height and the palette are too slow to call for
	# every tuft.
	var hs := PackedFloat32Array()
	hs.resize((n + 2) * (n + 2))
	for j in n + 2:
		for i in n + 2:
			hs[j * (n + 2) + i] = Terrain.height(x0 + (i - 1) * GRID, z0 + (j - 1) * GRID)
	var grow := PackedFloat32Array()
	grow.resize(n * n)
	var cols: Array[Color] = []
	cols.resize(n * n)
	var any := false
	for j in n:
		for i in n:
			var k := (j + 1) * (n + 2) + (i + 1)
			var h := hs[k]
			var nrm := Vector3(hs[k - 1] - hs[k + 1], 2.0 * GRID, hs[k - (n + 2)] - hs[k + (n + 2)]).normalized()
			var x := x0 + i * GRID
			var z := z0 + j * GRID
			var w := growth(x, z, h, 1.0 - nrm.y)
			var c := Color()
			if w > 0.0:
				c = Palette.ground_at(x, z, h, 1.0 - nrm.y, 0.0)
				if c.r > c.g * 1.12: # worn earth and sand: no turf
					w = 0.0
			grow[j * n + i] = w
			cols[j * n + i] = c
			any = any or w > 0.0
	if not any:
		return out
	_ensure_patch()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cx, cz, int(WorldGen.config().seed) + SEED_OFFSET))
	var tries := int(DENSITY * CELL * CELL * density)
	for t in tries:
		var fx := rng.randf() * CELL
		var fz := rng.randf() * CELL
		var rot := rng.randf() * TAU
		var keep := rng.randf()
		var s := rng.randf_range(0.75, 1.15)
		var tone := rng.randf()
		var gx := fx / GRID
		var gz := fz / GRID
		var i0 := mini(int(gx), n - 2)
		var j0 := mini(int(gz), n - 2)
		var u := gx - i0
		var v := gz - j0
		var w := lerpf(lerpf(grow[j0 * n + i0], grow[j0 * n + i0 + 1], u), lerpf(grow[(j0 + 1) * n + i0], grow[(j0 + 1) * n + i0 + 1], u), v)
		var x := x0 + fx
		var z := z0 + fz
		var p := _patch.get_noise_2d(x, z) # meadows in clumps: thick patches, thin gaps
		w *= clampf(0.55 + p * 0.9, 0.0, 1.0)
		if keep >= w:
			continue
		var r := (j0 + 1) * (n + 2) + (i0 + 1)
		var y := lerpf(lerpf(hs[r], hs[r + 1], u), lerpf(hs[r + n + 2], hs[r + n + 3], u), v)
		var c: Color = cols[(j0 + int(v + 0.5)) * n + i0 + int(u + 0.5)]
		if c == Color():
			c = cols[j0 * n + i0]
		# Blades read a little lighter and yellower than the ground they grow from, or the turf
		# disappears into it; some tufts are straw.
		c = c.lightened(0.04 + 0.06 * tone).lerp(Palette.DRY_GRASS, 0.15 + 0.3 * tone * tone)
		var lin := c.srgb_to_linear()
		var tall := s * lerpf(0.8, 1.35, clampf(0.5 + p, 0.0, 1.0))
		var b := Basis(Vector3.UP, rot).scaled(Vector3(s, tall, s))
		out.append_array([b.x.x, b.y.x, b.z.x, x, b.x.y, b.y.y, b.z.y, y - 0.03, b.x.z, b.y.z, b.z.z, z,
			lin.r, lin.g, lin.b, 1.0])
	return out


## How much grass grows at a ground point, 0..1 (before the patch noise and the colour test).
static func growth(x: float, z: float, h: float, slope: float) -> float:
	if h < Terrain.water_level() + WATER_CLEAR or slope > MAX_SLOPE:
		return 0.0
	var steep := 1.0 - smoothstep(MAX_SLOPE * 0.5, MAX_SLOPE, slope)
	if WorldGen.is_kingdom():
		var b := WorldGen.biome_for(x, z, h)
		if not BIOME_DENSITY.has(b):
			return 0.0
		if WorldGen.road_distance(x, z) < WorldGen.ROAD_HALF_WIDTH + ROAD_CLEAR:
			return 0.0
		return float(BIOME_DENSITY[b]) * steep
	if h > Flora.FOREST_MAX:
		return 0.0
	var forest := smoothstep(Flora.FOREST_MIN - 1.0, Flora.FOREST_MIN + 1.0, h)
	return lerpf(1.0, 0.45, forest) * steep


## The cells within RANGE (plus a cell's reach) of a point, nearest first.
static func cells_near(center: Vector3) -> Array[Vector2i]:
	var reach := RANGE + CELL * 0.75
	var c0 := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
	var r := int(ceil(reach / CELL))
	var found: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := c0 + Vector2i(dx, dz)
			var mid := Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)
			var d := mid.distance_to(Vector2(center.x, center.z))
			if d <= reach:
				found.append([d, c])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array[Vector2i] = []
	for f in found:
		out.append(f[1])
	return out


## The client's `Quality.flora_density()`, or 1.0 without the client code.
static func quality_density() -> float:
	return Flora.quality_density()


## The Grass node WorldBuilder adds.
static func build() -> Node3D:
	var g := _Field.new()
	g.name = "Grass"
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tufts"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh()
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.ignore_occlusion_culling = true
	# The MultiMesh moves with the camera; a big fixed box keeps Godot from culling it.
	mmi.custom_aabb = AABB(Vector3(-1.0e5, -1.0e3, -1.0e5), Vector3(2.0e5, 2.0e3, 2.0e5))
	g.add_child(mmi)
	g.tufts = mmi
	return g


## One tuft: two crossed cards, UV v = 1 at the root, 0 at the tips. Normals point up, so a
## tuft is lit like the ground it stands on (no dark backfaces when the sun is behind it).
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in 2:
		var a := PI * 0.5 * k + 0.4
		var d := Vector3(cos(a), 0.0, sin(a)) * TUFT_W * 0.5
		var lo0 := -d
		var lo1 := d
		var hi0 := -d + Vector3(0, TUFT_H, 0)
		var hi1 := d + Vector3(0, TUFT_H, 0)
		var u := 0.5 * k # each card shows half of the blade sheet, so the two cards differ
		for q in [[lo0, Vector2(u, 1)], [hi0, Vector2(u, 0)], [hi1, Vector2(u + 0.5, 0)],
				[lo0, Vector2(u, 1)], [hi1, Vector2(u + 0.5, 0)], [lo1, Vector2(u + 0.5, 1)]]:
			st.set_uv(q[1])
			st.add_vertex(q[0])
	_mesh = st.commit()
	return _mesh


## The blade sheet: RGBA, alpha cut. Brightness only (the colour comes from the ground): dark
## roots, lighter tips. Clean carved blades (2026-11-26, the world matched to the clean carved
## characters): about 16 straight-edged tapering blades across 128 x 64, read with linear
## filtering, so a tuft is a few crisp low-poly leaves instead of a spray of pixel-thin lines.
static func blade_image() -> Image:
	var w := 128
	var h := 64
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	# Image.create starts all zero: fully transparent.
	var rng := RandomNumberGenerator.new()
	rng.seed = 14
	for b in 16:
		var x0 := rng.randf_range(8.0, w - 9.0)
		var lean := rng.randf_range(-0.45, 0.45) # straight blades: a constant lean, no curl
		var top := rng.randi_range(h / 3, h - 2)
		var half_w := rng.randf_range(2.6, 4.2)
		var tip := rng.randf_range(0.78, 0.9)
		for k in top:
			var t := float(k) / top
			var v := lerpf(0.5, tip, t) # dark at the root, lighter to the tip, like the ground it grows from
			var cx := x0 + lean * k
			var hw := half_w * (1.0 - t) + 0.5 # a straight taper to the point: a long thin triangle
			var y := h - 1 - k
			for x in range(int(floor(cx - hw)), int(ceil(cx + hw)) + 1):
				if x < 0 or x >= w or absf(x - cx) > hw:
					continue
				var shade := v * (0.9 if x < cx else 1.0) # two planes per blade, like a folded leaf
				im.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	im.generate_mipmaps()
	return im


## Grass's own material (one more in the frame, art bible section 7): Emberlight's banded light
## and night drain, plus wind sway, alpha-cut blades and the edge fade.
static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	Emberlight.ensure_globals()
	var sh := Shader.new()
	sh.code = source()
	_material = ShaderMaterial.new()
	_material.shader = sh
	_material.set_shader_parameter("blades", ImageTexture.create_from_image(blade_image()))
	_material.set_shader_parameter("range_end", RANGE)
	_material.set_shader_parameter("fade", FADE)
	return _material


static func source(srgb_out: bool = Emberlight.srgb_output()) -> String:
	var shade := Palette.SHADE.srgb_to_linear()
	return (Emberlight.compat_define(srgb_out) + SHADER.replace("$COMPAT_GLSL", Emberlight.COMPAT_GLSL)
		.replace("$SHADE", "vec3(%.4f, %.4f, %.4f)" % [shade.r, shade.g, shade.b])
		.replace("$COMPAT_ALBEDO", "%.3f" % Emberlight.COMPAT_ALBEDO))


const SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;

global uniform float ember_night;

uniform sampler2D blades : filter_linear_mipmap, hint_default_white;
uniform vec3 center = vec3(0.0); // the grass centre (Grass sets it every frame)
uniform float range_end = 24.0;
uniform float fade = 7.0;
uniform float sway = 0.07; // metres the tips move in the wind
uniform float shade_strength = 0.30;
uniform float warmth = 0.10;
uniform float night_desat = 0.55;
uniform float night_shade = 1.4;

$COMPAT_GLSL
varying float tip;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(origin.xz - center.xz);
	float grow = 1.0 - smoothstep(range_end - fade, range_end, d);
	VERTEX *= vec3(mix(0.4, 1.0, grow), grow, mix(0.4, 1.0, grow));
	tip = 1.0 - UV.y;
	float phase = TIME * 1.3 + origin.x * 0.37 + origin.z * 0.23;
	float gust = 0.6 + 0.4 * sin(TIME * 0.31 + origin.x * 0.05);
	vec3 w = vec3(sin(phase), 0.0, sin(phase * 0.8 + 1.3) * 0.6) * sway * gust * tip * tip;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * w);
	NORMAL = (inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0));
}

void fragment() {
	vec4 b = texture(blades, UV);
	if (b.a < 0.4) {
		discard;
	}
	ALBEDO = COLOR.rgb * b.r * 1.15;
	float green = smoothstep(-0.02, 0.10, ALBEDO.g - ALBEDO.r);
	ALBEDO = mix(ALBEDO, vec3(dot(ALBEDO, vec3(0.299, 0.587, 0.114))), ember_night * night_desat * green);
	ROUGHNESS = 1.0;
#ifdef COMPAT_SRGB
	ALBEDO = compat_encode(ALBEDO * $COMPAT_ALBEDO);
#endif
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ramp = smoothstep(-0.08, 0.3, ndl) * 0.5 + smoothstep(0.25, 0.75, ndl) * 0.5;
	float lit = ramp * ATTENUATION;
	vec3 key = LIGHT_COLOR * mix(vec3(1.0), vec3(1.0, 0.86, 0.66), warmth);
	DIFFUSE_LIGHT += key * lit / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		float strength = dot(LIGHT_COLOR, vec3(0.299, 0.587, 0.114));
		DIFFUSE_LIGHT += $SHADE * (1.0 - lit) * (shade_strength + night_shade * ember_night) * strength / PI;
	}
}
"""


static func _ensure_patch() -> void:
	if _patch != null and _patch.seed == int(WorldGen.config().seed) + SEED_OFFSET:
		return
	_patch = FastNoiseLite.new()
	_patch.seed = int(WorldGen.config().seed) + SEED_OFFSET
	_patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_patch.frequency = 0.07


## The node that follows the camera: keeps the cells in range generated (a couple a frame),
## joins them into the one MultiMesh, and moves the fade centre.
class _Field:
	extends Node3D
	var tufts: MultiMeshInstance3D
	var cache := {} ## Vector2i -> PackedFloat32Array
	var shown: Array[Vector2i] = []
	var density := -1.0
	var poll := 0.0
	var filled := false

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam == null:
			return
		poll -= delta
		if poll <= 0.0 or density < 0.0:
			poll = Grass.QUALITY_POLL
			var d := Grass.quality_density()
			if not is_equal_approx(d, density):
				density = d
				cache.clear()
				shown.clear()
				filled = false
		var fwd := -cam.global_transform.basis.z
		var flat := Vector3(fwd.x, 0.0, fwd.z)
		flat = flat.normalized() if flat.length() > 0.01 else Vector3.ZERO
		var center := cam.global_position + flat * Grass.AHEAD
		(tufts.material_override as ShaderMaterial).set_shader_parameter("center", center)
		var want := Grass.cells_near(center)
		var built := 0
		for c in want:
			if cache.has(c):
				continue
			if filled and built >= Grass.BUILD_PER_FRAME:
				break
			cache[c] = Grass.cell(c.x, c.y, density)
			built += 1
		filled = true
		var ready: Array[Vector2i] = []
		for c in want:
			if cache.has(c):
				ready.append(c)
		ready.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		if ready == shown:
			return
		shown = ready
		var buf := PackedFloat32Array()
		for c in ready:
			buf.append_array(cache[c])
		# Forget cells well out of range (turning around brings the near ones straight back).
		var forget := Grass.RANGE + Grass.CELL * 2.5
		for c in cache.keys():
			var mid := Vector2((c.x + 0.5) * Grass.CELL, (c.y + 0.5) * Grass.CELL)
			if mid.distance_to(Vector2(center.x, center.z)) > forget:
				cache.erase(c)
		var mm := tufts.multimesh
		mm.instance_count = 0
		mm.instance_count = buf.size() / Grass.FLOATS
		if mm.instance_count > 0:
			mm.buffer = buf

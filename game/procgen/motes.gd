class_name Motes
## Rising ember motes (art bible section 4, "Rising motes"; Emberlight part 4).
##
## From dusk until dawn a few sparks of ember drift slowly up out of the ember ash crowns and
## the sap seeps, so at night you can find the things worth gathering by the sparks rising
## over them, and the whole valley looks warm and alive. Few, slow, and capped by the
## client's Graphics quality.
##
## Cost: one MultiMesh of small camera-facing quads, one draw call, no shadows, and nothing
## per frame on the CPU: the rise, drift, twinkle and fade are all in the vertex shader from
## TIME and per-instance data. By day the node is hidden (no draw call at all).
##
## The pool is built once at its High size and ordered so that the first N instances cover
## every anchor evenly (mote k of anchor a sits at index k * anchors + a). The quality setting
## then only changes `visible_instance_count`, live, with nothing rebuilt.
##
## Pure data (`anchors`, `per_anchor`, `layout`, `amount`, `visible_count`, `slots`) is tested
## headless; `build()` makes the node and `apply()` is called by DayNight on every repaint.
##
## A felled ash or a dry seep breathes no sparks: `NodeProps.set_depleted()` calls `set_dark()`,
## which shrinks that anchor's motes to nothing (size 0 in their custom data, still one draw
## call, nothing rebuilt) and gives them back when the node grows again. So at night the
## sparks over the valley point only at things you can gather right now.

const NODE_NAME := "Motes"
const PER_ANCHOR := 6 ## motes per ash crown or seep on Medium (Quality.motes_scale() = 1)
const TIER2_EXTRA := 2.0 ## old ember ashes: a plume twice as tall (see layout())
const MAX_SCALE := 1.5 ## High's motes_scale: the pool is built this big
const KINDS := {
	# kind: [inner radius, outer radius, lowest spawn height, highest, rise] in metres, x node scale.
	# Ash motes start in a ring just outside the crown (radius ~1.9 m, 2.5 to 5.5 m up), so the
	# leaves never hide them, and drift up past its top.
	"ash": [2.0, 2.8, 0.8, 3.0, 4.5],
	"ember_sap": [0.0, 0.7, 0.1, 0.4, 2.6], # off the glowing pool
}
const TIER2_SPREAD := 1.5 ## the old ember ash's crown is about this much wider
const SIZE := Vector2(0.24, 0.38) ## quad size range in metres (the soft dot inside is about half that): a spark, not a firefly
const LIFE := Vector2(6.0, 10.0) ## seconds for one rise, slow
const FADE_NEAR := 45.0 ## metres: motes start to fade out beyond this
const FADE_FAR := 70.0 ## and are gone here (the haze has them anyway)
const CULL_MARGIN := 6.0 ## the shader lifts quads up to `rise` metres; keep them from being culled early
const ENERGY := 1.4 ## colour strength at full night (higher and the tonemapper washes the ember out to white)


## Where motes rise from: every gatherable ember ash and ember-sap seep (if it glows ember,
## you can use it). Array of {pos, kind, scale, weight}. Deterministic.
static func anchors(nodes: Array = []) -> Array:
	if nodes.is_empty():
		nodes = ResourceNodes.all()
	var out: Array = []
	for n in nodes:
		if not KINDS.has(n.kind):
			continue
		var weight := TIER2_EXTRA if int(n.get("tier", 1)) >= 2 else 1.0
		out.append({"pos": n.pos, "kind": n.kind, "scale": float(n.get("scale", 1.0)), "weight": weight, "id": int(n.get("id", -1))})
	return out


## Motes per anchor for a quality's motes_scale (Low 0.5 -> 3, Medium 1 -> 6, High 1.5 -> 9).
static func per_anchor(motes_scale: float) -> int:
	return clampi(roundi(PER_ANCHOR * motes_scale), 0, roundi(PER_ANCHOR * MAX_SCALE))


## How many pool instances to draw for a quality's motes_scale.
static func visible_count(anchor_count: int, motes_scale: float) -> int:
	return anchor_count * per_anchor(motes_scale)


## 0 by day, 1 at night: the motes come up with the lanterns and leave with them.
static func amount(frac: float) -> float:
	return Lamps.night_glow(frac)


## The whole pool: Array of {origin: Vector3, custom: Color (phase, rate, rise, size)},
## interleaved so any prefix covers every anchor. Tier-2 anchors keep the same number of
## slots (so the prefix rule holds) but their sparks rise `weight` times higher and burn bigger,
## a taller plume you can spot from the meadow.
static func layout(anchor_list: Array, motes_scale: float = MAX_SCALE) -> Array:
	var per := per_anchor(motes_scale)
	var out: Array = []
	out.resize(anchor_list.size() * per)
	for a in anchor_list.size():
		var an: Dictionary = anchor_list[a]
		var k: Array = KINDS[an.kind]
		var s: float = an.scale
		var spread: float = s * (TIER2_SPREAD if an.weight > 1.0 else 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = GameConfig.WORLD_SEED + 409 + an.id * 31 + a
		for m in per:
			var ang := rng.randf() * TAU
			var r: float = sqrt(rng.randf_range(k[0] * k[0], k[1] * k[1])) * spread
			var h: float = rng.randf_range(k[2], k[3]) * spread
			var origin: Vector3 = an.pos + Vector3(cos(ang) * r, h, sin(ang) * r)
			var life := rng.randf_range(LIFE.x, LIFE.y)
			var size := rng.randf_range(SIZE.x, SIZE.y) * (1.25 if an.weight > 1.0 else 1.0)
			# Phases spread evenly per anchor (plus jitter) so the sparks never rise in a clump.
			var phase := fposmod((float(m) + rng.randf() * 0.6) / per, 1.0)
			out[m * anchor_list.size() + a] = {"origin": origin,
				"custom": Color(phase, 1.0 / life, float(k[4]) * s * float(an.weight), size)}
	return out


## Where one mote is `t` seconds in (the same maths as the shader, for tests): rising from
## its origin with a lazy sideways drift. `alpha` is its fade (0 at birth and at the top).
static func mote_at(mote: Dictionary, t: float) -> Dictionary:
	var c: Color = mote.custom
	var life := fposmod(t * c.g + c.r, 1.0)
	var o: Vector3 = mote.origin
	var drift := Vector3(sin(life * 5.0 + o.x), 0.0, cos(life * 4.0 + o.z)) * 0.35 * life
	return {"pos": o + drift + Vector3(0.0, life * c.b, 0.0), "alpha": sin(life * PI), "life": life}


## The Motes node WorldBuilder adds (hidden until DayNight says it is dusk).
static func build(anchor_list: Array = []) -> MultiMeshInstance3D:
	if anchor_list.is_empty():
		anchor_list = anchors()
	var pool := layout(anchor_list, MAX_SCALE)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = pool.size()
	for i in pool.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pool[i].origin))
		mm.set_instance_custom_data(i, pool[i].custom)
	mm.visible_instance_count = visible_count(anchor_list.size(), _scale())
	var mmi := MultiMeshInstance3D.new()
	mmi.name = NODE_NAME
	mmi.multimesh = mm
	mmi.material_override = material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = CULL_MARGIN
	mmi.set_meta("anchors", anchor_list.size())
	var ids := {}
	for a in anchor_list.size():
		ids[int(anchor_list[a].id)] = a
	mmi.set_meta("ids", ids) # node id -> anchor index, for set_dark()
	var customs := PackedColorArray()
	customs.resize(pool.size())
	for i in pool.size():
		customs[i] = pool[i].custom
	mmi.set_meta("customs", customs) # the live look, to give a regrown node its sparks back
	mmi.set_meta("dark", {})
	mmi.visible = false
	return mmi


## The pool indices of anchor `a`'s motes (all of them, at High's size), given `count` anchors.
static func slots(a: int, count: int) -> Array:
	var out: Array = []
	for m in per_anchor(MAX_SCALE):
		out.append(m * count + a)
	return out


## Put out (dark = true) or relight the motes over resource node `id` in `world`. Returns false
## when the world has no motes or the node breathes none (a pine, an outcrop). Cheap: it touches
## only that anchor's few instances, and the same state again is a no-op.
static func set_dark(world: Node, id: int, dark: bool) -> bool:
	if world == null:
		return false
	var mmi := world.get_node_or_null(NODE_NAME) as MultiMeshInstance3D
	if mmi == null:
		return false
	var ids: Dictionary = mmi.get_meta("ids", {})
	if not ids.has(id):
		return false
	var off: Dictionary = mmi.get_meta("dark", {})
	if off.has(id) == dark:
		return true
	var customs: PackedColorArray = mmi.get_meta("customs")
	for i in slots(int(ids[id]), int(mmi.get_meta("anchors", 0))):
		var c: Color = customs[i]
		if dark:
			c.a = 0.0 # a zero-size quad: no pixels, same draw call
		mmi.multimesh.set_instance_custom_data(i, c)
	if dark:
		off[id] = true
	else:
		off.erase(id)
	mmi.set_meta("dark", off)
	return true


## Is node `id`'s plume out? (For tests and callers; the dummy renderer drops custom data.)
static func is_dark(world: Node, id: int) -> bool:
	if world == null:
		return false
	var mmi := world.get_node_or_null(NODE_NAME) as MultiMeshInstance3D
	return mmi != null and (mmi.get_meta("dark", {}) as Dictionary).has(id)


## Show the motes at `value` (0..1; DayNight passes `amount(frac)`), and follow the quality
## setting live. Safe on a world without motes.
static func apply(world: Node, value: float) -> void:
	if world == null:
		return
	var mmi := world.get_node_or_null(NODE_NAME) as MultiMeshInstance3D
	if mmi == null:
		return
	var v := clampf(value, 0.0, 1.0)
	var on := v > 0.01
	if mmi.visible != on:
		mmi.visible = on
	if not on:
		return
	material().set_shader_parameter("amount", v)
	var want := visible_count(int(mmi.get_meta("anchors", 0)), _scale())
	if mmi.multimesh.visible_instance_count != want:
		mmi.multimesh.visible_instance_count = want


static func _scale() -> float:
	return Quality.motes_scale()


static var _material: ShaderMaterial

## The one mote material (shared, built once).
static func material() -> ShaderMaterial:
	if _material == null:
		Emberlight.ensure_globals() # the heartbeat swells the sparks with everything else
		var sh := Shader.new()
		var c := Palette.MOTE.srgb_to_linear()
		var core := Palette.EMBER_CORE.srgb_to_linear()
		sh.code = SHADER.replace("$MOTE", "vec3(%.4f, %.4f, %.4f)" % [c.r, c.g, c.b]) \
			.replace("$CORE", "vec3(%.4f, %.4f, %.4f)" % [core.r, core.g, core.b]) \
			.replace("$FADE_NEAR", "%.1f" % FADE_NEAR).replace("$FADE_FAR", "%.1f" % FADE_FAR) \
			.replace("$ENERGY", "%.2f" % ENERGY)
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.resource_name = "Motes"
	return _material


const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

global uniform float ember_pulse;
uniform float amount = 1.0; // 0 by day, 1 at night (DayNight)

varying float fade;

void vertex() {
	// INSTANCE_CUSTOM: phase, 1 / lifetime, rise (m), size (m). Same maths as Motes.mote_at().
	vec3 o = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float life = fract(TIME * INSTANCE_CUSTOM.g + INSTANCE_CUSTOM.r);
	vec3 drift = vec3(sin(life * 5.0 + o.x), 0.0, cos(life * 4.0 + o.z)) * 0.35 * life;
	vec3 p = o + drift + vec3(0.0, life * INSTANCE_CUSTOM.b, 0.0);
	vec3 view = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	// Each spark shrinks a little as it cools near the top.
	VERTEX = view + vec3(VERTEX.xy * INSTANCE_CUSTOM.a * (1.0 - 0.4 * life), 0.0);
	float twinkle = 0.75 + 0.25 * sin(TIME * 7.0 + INSTANCE_CUSTOM.r * 40.0);
	fade = sin(life * 3.14159) * twinkle * amount * (1.0 - smoothstep($FADE_NEAR, $FADE_FAR, -view.z));
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	// A hot core with a soft halo: reads as a spark at 30 m, never as a square.
	float spot = smoothstep(1.0, 0.0, d);
	ALBEDO = mix($MOTE, $CORE, spot * spot) * $ENERGY * (0.8 + 0.4 * ember_pulse);
	ALPHA = spot * fade;
}
"""

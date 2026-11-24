class_name SurfaceTex
extends RefCounted
## Painted surface detail (docs/art_bible.md, "Model direction" and section 1, "low-res paint"):
## small tiling textures generated in code, read with nearest filtering so their pixels stay
## crisp, and laid over the world by Emberlight's triplanar `paint_tex`. They hold detail only
## (grass strokes and earth on the ground, furrows on bark, cracks in stone, grain and seams in
## wood), stored as brightness around 0.5, so the colour still comes from the vertex and
## instance colours (biomes, seeded tints, baked shade) and one texture serves every tint.
##
## Each texture is built once (64 x 64, a few ms) and shared. Kinds: KINDS.

const SIZE := 64
const KINDS := ["ground", "bark", "stone", "wood"]

static var _cache: Dictionary = {} # kind -> ImageTexture


## The shared detail texture for `kind` (one of KINDS). Same kind, same instance.
static func get_texture(kind: String) -> ImageTexture:
	assert(kind in KINDS, "unknown surface kind " + kind)
	if not _cache.has(kind):
		var im := image(kind)
		im.generate_mipmaps() # far ground fades to its average instead of shimmering
		_cache[kind] = ImageTexture.create_from_image(im)
	return _cache[kind]


## The detail image for `kind`: luminance only, normalised so its mean is 0.5 (so laying it
## over a colour keeps that colour's brightness on average). Pure and deterministic.
static func image(kind: String, size: int = SIZE) -> Image:
	var lum := PackedFloat32Array()
	lum.resize(size * size)
	var f: Callable
	match kind:
		"ground": f = _ground(size)
		"bark": f = _bark(size)
		"stone": f = _stone(size)
		_: f = _wood(size)
	var total := 0.0
	for y in size:
		for x in size:
			var v: float = f.call(x, y)
			lum[x + y * size] = v
			total += v
	var mean := maxf(total / lum.size(), 0.0001)
	var im := Image.create(size, size, false, Image.FORMAT_L8)
	for y in size:
		for x in size:
			var v := clampf(lum[x + y * size] / mean * 0.5, 0.0, 1.0)
			im.set_pixel(x, y, Color(v, v, v))
	return im


static func _noise(seed: int, freq: float, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.noise_type = type
	return n


## Noise in 0..1 that tiles over `size` (four shifted copies blended across the tile).
static func _tile(n: FastNoiseLite, x: float, y: float, size: float) -> float:
	var fx := x / size
	var fy := y / size
	var a := n.get_noise_2d(x, y)
	var b := n.get_noise_2d(x - size, y)
	var c := n.get_noise_2d(x, y - size)
	var d := n.get_noise_2d(x - size, y - size)
	return 0.5 + 0.5 * lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## Ground: soft clumps of grass with short light strokes, darker earth showing between them,
## and a scatter of pebbles.
static func _ground(size: int) -> Callable:
	var clumps := _noise(1, 0.09)
	var fine := _noise(2, 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var marks := {}
	for i in 220: # grass strokes: a few pixels tall, light at the tip
		var x := rng.randi() % size
		var y := rng.randi() % size
		var l := rng.randi_range(2, 4)
		for k in l:
			marks[Vector2i(x, posmod(y - k, size))] = 0.12 + 0.1 * float(k) / l
	for i in 30: # pebbles
		marks[Vector2i(rng.randi() % size, rng.randi() % size)] = -0.25 if rng.randf() < 0.5 else 0.2
	return func(x: int, y: int) -> float:
		var t := _tile(clumps, x, y, size) * 0.7 + _tile(fine, x, y, size) * 0.3
		var v := 0.35 + 0.55 * t
		return v + float(marks.get(Vector2i(x, y), 0.0))


## Bark: furrows running up the trunk, with lighter ridges between them.
static func _bark(size: int) -> Callable:
	var n1 := _noise(6, 0.06)
	var n2 := _noise(7, 0.3)
	return func(x: int, y: int) -> float:
		var t := _tile(n1, x * 4.0, y * 0.5, size * 4.0) * 0.55 + _tile(n2, x * 3.0, y * 0.6, size * 3.0) * 0.45
		var furrow := 1.0 - smoothstep(0.0, 0.12, absf(sin(x * TAU * 5.0 / size + t * 3.0)))
		return (0.4 + 0.6 * t) * (1.0 - 0.5 * furrow)


## Stone: broken into plates by dark cracks, mottled inside.
static func _stone(size: int) -> Callable:
	var cell := _noise(11, 0.12, FastNoiseLite.TYPE_CELLULAR)
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var n2 := _noise(12, 0.3)
	return func(x: int, y: int) -> float:
		var v := 0.35 + 0.65 * _tile(n2, x, y, size)
		if cell.get_noise_2d(x, y) < -0.86: # near a border between two plates: a crack
			v *= 0.5
		return v


## Wood: long grain with four boards and dark seams between them.
static func _wood(size: int) -> Callable:
	var n1 := _noise(8, 0.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var tints := []
	for i in 4:
		tints.append(rng.randf_range(-0.08, 0.08))
	var board_h := size / 4
	return func(x: int, y: int) -> float:
		var v := float(y % board_h) / float(board_h)
		var grain := _tile(n1, x * 0.4, y * 3.0, size * 0.4)
		var c := 0.5 + 0.5 * grain + float(tints[y / board_h])
		if v < 0.08:
			c *= 0.45
		elif v > 0.92:
			c *= 1.08
		return c

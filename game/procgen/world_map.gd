class_name WorldMap
## Paints a generated world (WorldGen, gen_version 1 or the island, 2) as a small top-down map: relief from
## the height field lit from the north-west, ground by biome, water, the river, the king's
## roads, ruin sites marked by grade, and the spawn plot or the island's beach landings. Pure Image maths, no textures; the
## client's map window (client backlog, Phase 1 part 3) can show it as it is, and world uses
## it to look at seeds before they get a 3D view.

const LIGHT := Vector2(-0.7, -0.7) ## light from the north-west (-x, -z), like an old map
const RELIEF := 0.9 ## how hard the hills shade


## The map of the configured world, `px` pixels square. Ashgrove gets its relief and water.
## `marks` false leaves the ruin and landing discs off: the client's map window (MapWindow, M)
## draws its own marks on top so they stay crisp at any zoom. Safe to call off the main thread
## once WorldGen's layout is built (it only reads).
static func paint(px: int = 256, marks: bool = true) -> Image:
	var half := WorldGen.half_size()
	var mpp := WorldGen.size_m() / px ## metres per pixel
	var hg := PackedFloat32Array()
	hg.resize((px + 1) * (px + 1))
	for j in px + 1:
		for i in px + 1:
			hg[j * (px + 1) + i] = Terrain.height(-half + i * mpp, -half + j * mpp)
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	var wl := Terrain.water_level()
	var kingdom := WorldGen.is_kingdom()
	for j in px:
		for i in px:
			var x := -half + (i + 0.5) * mpp
			var z := -half + (j + 0.5) * mpp
			var a := hg[j * (px + 1) + i]
			var b := hg[j * (px + 1) + i + 1]
			var c := hg[(j + 1) * (px + 1) + i]
			var d := hg[(j + 1) * (px + 1) + i + 1]
			var h := (a + b + c + d) * 0.25
			var grad := Vector2((b + d - a - c) * 0.5, (c + d - a - b) * 0.5) / mpp
			var col := ground(x, z, h, wl, kingdom)
			if h >= wl:
				var lit := clampf(1.0 - grad.dot(LIGHT) * RELIEF, 0.55, 1.3)
				col = Color(col.r * lit, col.g * lit, col.b * lit)
			else:
				var deep := clampf((wl - h) / 6.0, 0.0, 1.0)
				col = col.darkened(deep * 0.35)
			if kingdom and h >= wl - 0.3 and WorldGen.road_distance(x, z) < WorldGen.ROAD_HALF_WIDTH + mpp * 0.35:
				col = Palette.MAP_ROAD
			img.set_pixel(i, j, col)
	if kingdom and marks:
		for s in WorldGen.ruin_sites():
			_mark(img, s.pos, half, mpp, maxf(3.0, s.radius / mpp), Palette.MAP_GRADE[int(s.grade) - 1])
		for q in WorldGen.landings():
			_mark(img, Vector3(q.x, 0.0, q.y), half, mpp, 3.5, Palette.EMBER_CORE)
		_mark(img, WorldGen.spawn_point(), half, mpp, 4.0, Palette.EMBER_CORE)
	return img


## The map colour of the ground at (x, z).
static func ground(x: float, z: float, h: float, wl: float, kingdom: bool) -> Color:
	if h < wl:
		return Palette.WATER.lerp(Palette.LAKEBED, 0.25)
	if not kingdom:
		return Palette.ground(h, 0.0, 0.0)
	match WorldGen.biome_for(x, z, h):
		"shore":
			return Palette.SAND
		"snow":
			return Palette.SNOW
		"stone_hills":
			return Palette.ROCK
		"forest":
			return Palette.FOREST
		"moor":
			return Palette.MAP_HEATH
		_:
			return Palette.MEADOW.lerp(Palette.DRY_GRASS, 0.35)


## A filled disc in `fill` with an ink rim.
static func _mark(img: Image, pos: Vector3, half: float, mpp: float, r: float, fill: Color) -> void:
	var cx := (pos.x + half) / mpp
	var cz := (pos.z + half) / mpp
	var reach := int(ceil(r + 1.5))
	for j in range(int(cz) - reach, int(cz) + reach + 1):
		for i in range(int(cx) - reach, int(cx) + reach + 1):
			if i < 0 or j < 0 or i >= img.get_width() or j >= img.get_height():
				continue
			var d := Vector2(i + 0.5 - cx, j + 0.5 - cz).length()
			if d <= r:
				img.set_pixel(i, j, fill)
			elif d <= r + 1.2:
				img.set_pixel(i, j, Palette.MAP_INK)

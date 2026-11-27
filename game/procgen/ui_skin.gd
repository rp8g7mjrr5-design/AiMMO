class_name UiSkin
extends RefCounted
## The windows' leather (art bible section 9, "UI tone": the satchel look, owner pick
## 2026-11-27). One generated nine-patch texture, no files: oiled dark leather, a saddle-stitch
## run inside the rim and an iron stud in each corner. Every window shares it, so a window
## still draws as one textured rect. Built once, on first use.

const SIZE := 384
const MARGIN := 40

static var _texture: Texture2D


## The window leather texture, built once.
static func panel_texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(leather())
	return _texture


## A nine-patch stylebox over the leather, with `pad` px of content margin.
static func panel_box(pad: float) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = panel_texture()
	s.texture_margin_left = MARGIN
	s.texture_margin_right = MARGIN
	s.texture_margin_top = MARGIN
	s.texture_margin_bottom = MARGIN
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


static func _noise(seed: int, freq: float, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.noise_type = type
	n.fractal_octaves = 3
	return n


## Oiled dark leather: pebbled grain, a burnished edge, a saddle-stitch run inside the rim
## and an iron stud in each corner.
static func leather() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var grain := _noise(21, 0.11, FastNoiseLite.TYPE_CELLULAR)
	var mottle := _noise(22, 0.015)
	var base := Palette.UI_LEATHER
	var thread := Palette.LEATHER_THREAD
	var corner := 9.0
	var stitch := 13.0
	for y in SIZE:
		for x in SIZE:
			var fx := float(x)
			var fy := float(y)
			# rounded-rect distance to the edge
			var qx := maxf(corner - fx, fx - (SIZE - 1 - corner))
			var qy := maxf(corner - fy, fy - (SIZE - 1 - corner))
			var d: float
			if qx > 0.0 and qy > 0.0:
				d = corner - Vector2(qx, qy).length()
			else:
				d = minf(minf(fx, fy), minf(SIZE - 1 - fx, SIZE - 1 - fy))
			if d < 0.0:
				continue
			var c := base.lightened(mottle.get_noise_2d(x, y) * 0.12)
			c = c.darkened(clampf(grain.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0) * 0.18)
			# burnished rim: darker at the very edge, a pale worn crest just inside it
			if d < 3.0:
				c = c.darkened(0.45 * (1.0 - d / 3.0))
			elif d < 5.0:
				c = c.lightened(0.10)
			# a pressed groove just inside the stitching
			if absf(d - (stitch + 5.0)) < 0.8:
				c = c.darkened(0.30)
			# saddle stitches along the run
			if absf(d - stitch) < 1.3:
				var along := fx if absf(fy - stitch) < 1.5 or absf(fy - (SIZE - 1 - stitch)) < 1.5 else fy
				var t := fmod(along, 9.0)
				if t < 5.5:
					c = thread.darkened(0.15 * absf(d - stitch))
				elif t > 6.5 and t < 8.0:
					c = c.darkened(0.5) # the awl hole
			c.a = clampf(d / 1.2, 0.0, 1.0) * 0.96
			img.set_pixel(x, y, c)
	# iron studs in the corners
	for cx in [24.0, SIZE - 25.0]:
		for cy in [24.0, SIZE - 25.0]:
			for y in range(int(cy) - 6, int(cy) + 7):
				for x in range(int(cx) - 6, int(cx) + 7):
					var r := Vector2(x - cx, y - cy).length()
					if r <= 4.6:
						var lit := clampf(1.0 - Vector2(x - cx + 1.6, y - cy + 1.6).length() / 4.6, 0.0, 1.0)
						img.set_pixel(x, y, Palette.IRON_SHADE.lerp(Palette.IRON_LIT, lit))
					elif r <= 5.8:
						img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.45))
	return img

extends TestCase
## World stream: ground cover (art bible section 11, "Uniform flat terrain facets"). The grass,
## meadow and forest floor carry gentle seeded patches of moss, dry straw grass and bare earth,
## so the valley reads as real ground instead of one flat olive. Rock, shore and snow are bare.


## Samples the valley on a 6 m grid inside +-300 m: [{x, z, h, slope, w}] for ground-cover land.
func _samples() -> Array:
	var out: Array = []
	for gz in range(-50, 51):
		for gx in range(-50, 51):
			var x := gx * 6.0
			var z := gz * 6.0
			var h := Terrain.height(x, z)
			var dx := Terrain.height(x + 1.0, z) - Terrain.height(x - 1.0, z)
			var dz := Terrain.height(x, z + 1.0) - Terrain.height(x, z - 1.0)
			var n := Vector3(-dx, 2.0, -dz).normalized()
			var slope := 1.0 - absf(n.y)
			out.append({"x": x, "z": z, "h": h, "slope": slope, "w": Palette.cover_weights(x, z, h, slope)})
	return out


func test_cover_tokens_are_muted_naturals() -> void:
	for c in [Palette.MOSS, Palette.DRY_GRASS, Palette.BARE_EARTH]:
		check(c.s <= 0.45, "under 0.45 saturation (%s: %.2f)" % [c, c.s])
		check(c.v > 0.2 and c.v < 0.6, "a mid-dark ground value (%s: %.2f)" % [c, c.v])
		check(c.r > c.b and c.g > c.b, "an earthy colour, never blue (%s)" % c)
	check(Palette.MOSS.g > Palette.MOSS.r, "moss is green")
	check(Palette.BARE_EARTH.r > Palette.BARE_EARTH.g, "bare earth is brown")
	check(Palette.DRY_GRASS.v > Palette.GRASS.v, "dry grass is paler than living grass")


func test_meadow_is_not_one_flat_olive() -> void:
	var s := _samples()
	var land := 0
	var moss := 0
	var dry := 0
	var earth := 0
	var plain := 0
	for p in s:
		var w: Dictionary = p.w
		if w.is_empty():
			continue
		land += 1
		if w.moss > 0.25:
			moss += 1
		if w.dry > 0.25:
			dry += 1
		if w.earth > 0.25:
			earth += 1
		if w.moss < 0.05 and w.dry < 0.05 and w.earth < 0.05:
			plain += 1
	check(land > 2000, "the sample has plenty of grassland (%d)" % land)
	var f := func(k: int) -> float: return float(k) / maxf(1.0, land)
	print("  ground cover: moss %.2f dry %.2f earth %.2f plain %.2f of %d" % [f.call(moss), f.call(dry), f.call(earth), f.call(plain), land])
	check(f.call(moss) > 0.08 and f.call(moss) < 0.5, "moss patches somewhere, not everywhere (%.2f)" % f.call(moss))
	check(f.call(dry) > 0.08 and f.call(dry) < 0.5, "dry grass patches somewhere, not everywhere (%.2f)" % f.call(dry))
	check(f.call(earth) > 0.01 and f.call(earth) < 0.2, "bare earth is a rare scuff (%.2f)" % f.call(earth))
	check(f.call(plain) > 0.2, "plenty of the base grass still shows (%.2f)" % f.call(plain))


func test_patches_are_gentle_and_smooth() -> void:
	# No hard edges: one metre never changes a weight by much, and no patch replaces the ground.
	var worst := 0.0
	for i in 400:
		var x := -300.0 + fmod(i * 37.1, 600.0)
		var z := -300.0 + fmod(i * 53.7, 600.0)
		var h := Terrain.height(x, z)
		var a := Palette.cover_weights(x, z, h, 0.1)
		var b := Palette.cover_weights(x + 1.0, z, Terrain.height(x + 1.0, z), 0.1)
		if a.is_empty() or b.is_empty():
			continue
		for k in ["moss", "dry", "earth"]:
			check(a[k] <= maxf(Palette.COVER_MAX, Palette.EARTH_MAX) + 0.0001, "never covers the ground completely")
			worst = maxf(worst, absf(a[k] - b[k]))
	check(worst < 0.2, "a metre's walk changes the cover by under 0.2 (%.3f)" % worst)


func test_forest_is_mossier_and_the_meadow_drier() -> void:
	var forest := [0.0, 0.0, 0]
	var open := [0.0, 0.0, 0]
	for p in _samples():
		var w: Dictionary = p.w
		if w.is_empty():
			continue
		var bucket: Array = forest if p.h > 7.0 else (open if p.h < 5.0 and p.h > Terrain.water_level() + 4.0 else [])
		if bucket.is_empty():
			continue
		bucket[0] += w.moss
		bucket[1] += w.dry
		bucket[2] += 1
	check(forest[2] > 50 and open[2] > 50, "both kinds of ground are sampled (%d, %d)" % [forest[2], open[2]])
	check(forest[0] / forest[2] > open[0] / open[2], "the forest floor is mossier than the open valley")
	check(open[1] / open[2] > forest[1] / forest[2], "the open valley is drier than the forest floor")


func test_rock_shore_and_snow_stay_bare() -> void:
	var wl := Terrain.water_level()
	check(Palette.cover_weights(10.0, 10.0, wl + 0.5, 0.1).is_empty(), "no cover on the shore silt")
	check(Palette.cover_weights(10.0, 10.0, 15.0, 0.1).is_empty(), "no cover on high rock")
	check(Palette.cover_weights(10.0, 10.0, 20.0, 0.1).is_empty(), "no cover on snow")
	check(Palette.cover_weights(10.0, 10.0, 4.0, 0.7).is_empty(), "no cover on cliffs")
	check(Palette.ground_at(10.0, 10.0, 15.0, 0.1, 0.0) == Palette.ground(15.0, 0.1, 0.0), "rock colour is untouched")


func test_cover_is_deterministic_and_reaches_the_terrain() -> void:
	var a := Palette.ground_at(123.0, -45.0, 3.0, 0.1, 0.02)
	var b := Palette.ground_at(123.0, -45.0, 3.0, 0.1, 0.02)
	check(a == b, "same point, same colour")
	# Built chunks carry the patches: a chunk's grass faces are not all one colour family.
	var m := TerrainMesh.build_chunk(0.0, 0.0)
	var cols: PackedColorArray = m.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var hues := {}
	for c in cols:
		hues[snappedf(c.r / maxf(0.001, c.g), 0.05)] = true
	check(hues.size() >= 4, "a 64 m chunk shows several ground tones (%d)" % hues.size())
	check(TerrainMesh.material() == TerrainMesh.material(), "still one shared terrain material")

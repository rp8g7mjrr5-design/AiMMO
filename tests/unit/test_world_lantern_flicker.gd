extends TestCase
## World stream: lantern flames flicker. Each lit lantern's light (the meadow ring and the
## bench) swings gently around its steady night level, every lantern on its own rhythm,
## never like a strobe, and nothing flickers by day.


func test_flicker_stays_gentle_and_averages_steady() -> void:
	var lo := 9.0
	var hi := -9.0
	var sum := 0.0
	var n := 0
	for i in Lamps.COUNT + 1:
		for f in 6000:
			var v := Lamps.flicker(1.7e6 + f / 60.0, i)
			lo = minf(lo, v)
			hi = maxf(hi, v)
			sum += v
			n += 1
	check(lo >= 1.0 - Lamps.FLICKER_DEPTH * 0.5 - 0.0001, "never dips more than half the depth (%.3f)" % lo)
	check(hi <= 1.0 + Lamps.FLICKER_DEPTH * 0.5 + 0.0001, "never flares more than half the depth (%.3f)" % hi)
	check(hi - lo > Lamps.FLICKER_DEPTH * 0.6, "it really moves (%.3f to %.3f)" % [lo, hi])
	check_near(sum / n, 1.0, 0.01, "averages the steady light, so nights are as bright as before")


func test_flicker_is_not_a_strobe() -> void:
	var worst := 0.0
	for i in Lamps.COUNT + 1:
		var prev := Lamps.flicker(5000.0, i)
		for f in range(1, 3000):
			var v := Lamps.flicker(5000.0 + f / 60.0, i)
			worst = maxf(worst, absf(v - prev))
			prev = v
	check(worst < 0.02, "a 60 fps frame changes the light by under 2%% (%.4f)" % worst)


func test_lanterns_breathe_on_their_own() -> void:
	# Correlation between neighbouring lanterns over a minute: they must not pulse together.
	for i in Lamps.COUNT:
		var a: Array = []
		var b: Array = []
		for f in 3600:
			a.append(Lamps.flicker(100.0 + f / 60.0, i) - 1.0)
			b.append(Lamps.flicker(100.0 + f / 60.0, i + 1) - 1.0)
		var ab := 0.0
		var aa := 0.0
		var bb := 0.0
		for k in a.size():
			ab += a[k] * b[k]
			aa += a[k] * a[k]
			bb += b[k] * b[k]
		var corr := ab / sqrt(aa * bb)
		check(corr < 0.8, "lantern %d and %d are not in step (corr %.2f)" % [i, i + 1, corr])


func _world() -> Node3D:
	var world := Node3D.new()
	world.add_child(Lamps.build())
	world.add_child(Workbench.build())
	return world


func _omnis(world: Node) -> Array:
	var out: Array = world.get_node("Lamps/Lights").get_children()
	out.append(world.get_node("Workbench/Light"))
	return out


func test_lit_lights_flicker_around_their_steady_level() -> void:
	var world := _world()
	Lamps.apply_glow(world, 1.0)
	var omnis := _omnis(world)
	check_eq(omnis.size(), Lamps.COUNT + 1, "eight meadow lanterns and the bench")
	var t := 12345.6
	Lamps.flicker_lights(world, t)
	var differ := false
	for i in omnis.size():
		var o := omnis[i] as OmniLight3D
		var steady := Lamps.LIGHT_ENERGY if i < Lamps.COUNT else Workbench.LIGHT_ENERGY
		check_near(o.light_energy, steady * Lamps.flicker(t, i), 0.0001, "%s follows its own flame" % o.name)
		if absf(o.light_energy - (omnis[0] as OmniLight3D).light_energy) > 0.001:
			differ = true
	check(differ, "the lanterns are not all at the same brightness at once")
	# A repaint (apply_glow) resets the steady level; flicker keeps swinging around the new one.
	Lamps.apply_glow(world, 0.5)
	Lamps.flicker_lights(world, t)
	check_near((omnis[0] as OmniLight3D).light_energy, Lamps.LIGHT_ENERGY * 0.5 * Lamps.flicker(t, 0), 0.0001, "dusk level flickers too")
	world.free()


func test_nothing_flickers_by_day_and_it_is_safe() -> void:
	var world := _world()
	Lamps.flicker_lights(world, 10.0) # before any apply_glow: leave lights alone
	for o in _omnis(world):
		check(not (o as OmniLight3D).visible and (o as OmniLight3D).light_energy == 0.0, "%s untouched before the first repaint" % o.name)
	Lamps.apply_glow(world, 0.0)
	Lamps.flicker_lights(world, 10.0)
	for o in _omnis(world):
		check(not (o as OmniLight3D).visible and (o as OmniLight3D).light_energy == 0.0, "%s stays out by day" % o.name)
	var before := world.get_child_count()
	Lamps.apply_glow(world, 1.0)
	for f in 120:
		Lamps.flicker_lights(world, 10.0 + f / 60.0)
	check_eq(world.get_child_count(), before, "flicker creates nothing")
	Lamps.flicker_lights(null, 1.0)
	var bare := Node3D.new()
	Lamps.flicker_lights(bare, 1.0) # a partial world without lamps or bench
	bare.free()
	world.free()

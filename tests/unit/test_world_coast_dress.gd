extends TestCase
## The whole coast dressed (owner, 2026-11-27: "our beaches still look empty"): kelp on the
## tide mark, shells, pebbles, drift logs, rocks and boards between the landing beaches, and
## dune grass over the back of the sand. Pure data (CoastDress.parts, Grass.growth, the palette).
## Every test puts the world back to Ashgrove, because the config is global.

const SEED := 1126 ## the live world's seed


func _island() -> void:
	WorldGen.configure(SEED, 3000.0, WorldGen.ISLAND)
	ResourceNodes.reset()


func _done() -> void:
	WorldGen.reset()
	ResourceNodes.reset()


func test_the_coast_is_dressed() -> void:
	_island()
	var parts := CoastDress.parts()
	var by := {}
	for p in parts:
		by[p.layer] = by.get(p.layer, 0) + 1
	check(parts.size() > 5000, "thousands of things along the coast (%d)" % parts.size())
	check(int(by.get("BeachPoles", 0)) > 150, "drift logs (%d)" % int(by.get("BeachPoles", 0)))
	check(int(by.get("BeachRocks", 0)) > 400, "rock clusters (%d)" % int(by.get("BeachRocks", 0)))
	check(int(by.get("BeachPlanks", 0)) > 50, "washed-up boards (%d)" % int(by.get("BeachPlanks", 0)))
	for p in parts:
		check(BeachProps.LAYERS.has(p.layer), "on BeachProps' own layers, so no new material")
	_done()


func test_dressing_lies_on_the_sand_and_keeps_clear() -> void:
	_island()
	var wl := Terrain.water_level()
	var lands := WorldGen.landings()
	var marks := BeachGen.landmarks()
	var wet := 0
	var crowded := 0
	for p in CoastDress.parts():
		var o: Vector3 = p.xform.origin
		var g := Terrain.height(o.x, o.z)
		if g < wl:
			wet += 1
		check(o.y > g - 0.01 and o.y < g + 0.6, "sits on the ground, not floating or buried")
		var q := Vector2(o.x, o.z)
		for l in lands:
			if q.distance_to(l) < BeachGen.CLEAR:
				crowded += 1
		for m in marks:
			if m.kind != "old_pier" and q.distance_to(Vector2(m.pos.x, m.pos.z)) < float(BeachGen.LANDMARKS[m.kind].r):
				crowded += 1
	check_eq(wet, 0, "nothing in the water")
	check_eq(crowded, 0, "nothing on a landing's lantern ring or inside a landmark")
	_done()


func test_drift_logs_lie_down() -> void:
	_island()
	var logs := CoastDress.parts().filter(func(p): return p.layer == "BeachPoles")
	var upright := 0
	for p in logs:
		var axis: Vector3 = (p.xform as Transform3D).basis.y.normalized() # the pole mesh's long axis
		if absf(axis.y) > 0.8:
			upright += 1
	check_eq(upright, 0, "no drift log stands on end")
	_done()


func test_dune_grass_on_the_back_of_the_beach() -> void:
	_island()
	var c: Dictionary = WorldGen.coast_at(1.3)
	var cut := CoastDress.cross_section(c.pos, c.sea)
	check(not cut.is_empty(), "a beach to look at")
	var water: Vector2 = cut.water
	var sea: Vector2 = c.sea
	var front := water - sea * 2.0
	var hf := Terrain.height(front.x, front.y)
	check_eq(Palette.dune_weight(front.x, front.y, hf), 0.0, "the sea side of the beach is open sand")
	check_eq(Grass.growth(front.x, front.y, hf, 0.0), 0.0, "no grass at the tide line")
	var grassy := false
	for k in 40:
		var q := water - sea * (4.0 + k * 3.0)
		var h := Terrain.height(q.x, q.y)
		if WorldGen.biome_for(q.x, q.y, h) == "shore" and Grass.growth(q.x, q.y, h, 0.0) > 0.0:
			grassy = true
	check(grassy, "marram grows on the back of the beach")
	_done()


func test_nothing_off_the_island() -> void:
	WorldGen.reset()
	check(CoastDress.parts().is_empty(), "Ashgrove has no sea coast to dress")
	check_eq(WorldGen.beach_depth(0.0, 0.0), 0.0, "and no beach depth")

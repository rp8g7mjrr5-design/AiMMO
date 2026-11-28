extends TestCase
## Basics 2: walkers rise at ruins. A player coming near a ruin wakes its guards on the pad,
## more for a higher grade and at night, out of sight of everyone; they stay with their ruin
## after a chase; a cleared ruin refills only slowly and never next to you; open ground near a
## guarded ruin stays quiet. Pure Gloam over the live island's config; every test puts the
## world back to Ashgrove.

const DT := 0.05


func _island() -> void:
	WorldGen.configure(1126, 3000.0, WorldGen.ISLAND)


func _done() -> void:
	WorldGen.reset()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ruin(grade: int) -> Dictionary:
	for r in Ruins.all():
		if int(r.grade) == grade:
			return r
	return {}


## A player on dry ground `out` metres outside ruin `r`'s pad.
func _outside(r: Dictionary, out: float) -> Vector3:
	for a in 24:
		var ang := TAU * a / 24.0
		var d: float = float(r.radius) + out
		var x: float = r.pos.x + cos(ang) * d
		var z: float = r.pos.z + sin(ang) * d
		if Gloam.good_ground(x, z):
			return Vector3(x, Terrain.height(x, z), z)
	return Vector3(r.pos.x + float(r.radius) + out, 0, r.pos.z)


func _guards(g: Dictionary, r: Dictionary) -> Array:
	return g.walkers.filter(func(w): return int(w.ruin) == int(r.id))


func test_coming_near_a_ruin_wakes_its_guards_on_the_pad() -> void:
	_island()
	for grade in [1, 2, 4]:
		var r := _ruin(grade)
		check(not r.is_empty(), "the island has a grade %d ruin" % grade)
		if r.is_empty():
			continue
		var g := Gloam.new_state()
		var me := _outside(r, 35.0)
		var risen := Gloam.rise_at_ruins(g, [{"id": 1, "pos": me}], 100.0, false, Ruins.all())
		var mine := _guards(g, r)
		check_eq(mine.size(), Gloam.guard_cap(grade, false), "grade %d is guarded by day" % grade)
		check(risen.size() >= mine.size(), "the new guards are reported")
		for w in mine:
			check(_flat(w.pos, r.pos) <= float(r.radius), "a guard rises on its ruin's pad")
			check(_flat(w.pos, me) >= Gloam.GUARD_MIN, "and out of sight of the player")
			check(Gloam.good_ground(w.pos.x, w.pos.z), "on dry ground")
	_done()


func test_higher_grades_and_nights_are_guarded_harder() -> void:
	for grade in [1, 2, 3]:
		check(Gloam.guard_cap(grade + 1, false) > Gloam.guard_cap(grade, false), "grade %d has more guards than %d" % [grade + 1, grade])
	for grade in [1, 2, 3, 4]:
		check(Gloam.guard_cap(grade, true) > Gloam.guard_cap(grade, false), "a grade %d ruin is busier at night" % grade)
	check_eq(Gloam.guard_cap(1, false), 1, "a Quiet ruin by day is one walker: a fair first fight")
	_island()
	var r := _ruin(2)
	var g := Gloam.new_state()
	Gloam.rise_at_ruins(g, [{"id": 1, "pos": _outside(r, 35.0)}], 100.0, true, Ruins.all())
	check_eq(_guards(g, r).size(), Gloam.guard_cap(2, true), "the night cap fills on waking")
	_done()


func test_far_from_every_ruin_nothing_guards() -> void:
	_island()
	var g := Gloam.new_state()
	var sp := WorldGen.spawn_point()
	var risen := Gloam.rise_at_ruins(g, [{"id": 1, "pos": sp}], 100.0, true, Ruins.all())
	var near_ruin := false
	for r in Ruins.all():
		if _flat(sp, r.pos) <= float(r.radius) + Gloam.GUARD_WAKE:
			near_ruin = true
	if not near_ruin:
		check_eq(risen.size(), 0, "no ruin near the spawn beach, no guards")
		check(g.guard_at.is_empty(), "and no ruin is awake")
	# Ashgrove has no ruins at all.
	WorldGen.reset()
	var a := Gloam.new_state()
	check_eq(Gloam.rise_at_ruins(a, [{"id": 1, "pos": Vector3(90, 0, 0)}], 1.0, true, Ruins.all()).size(), 0, "Ashgrove has no guards")
	_done()


func test_a_cleared_ruin_refills_slowly_and_never_beside_you() -> void:
	_island()
	var r := _ruin(1)
	var g := Gloam.new_state()
	var outside := _outside(r, 35.0)
	Gloam.rise_at_ruins(g, [{"id": 1, "pos": outside}], 100.0, false, Ruins.all())
	# Put them all down.
	for w in _guards(g, r):
		Gloam.strike(g, int(w.id), 1, outside, 100.0, 999.0, true)
	check_eq(_guards(g, r).size(), 0, "the ruin is cleared")
	# Straight after: nothing (the refill waits GUARD_EVERY).
	check_eq(Gloam.rise_at_ruins(g, [{"id": 1, "pos": outside}], 101.0, false, Ruins.all()).size(), 0, "no instant refill")
	# Standing in the heart of a small ruin, nothing can rise GUARD_MIN away on its pad.
	var heart := Vector3(r.pos.x, Terrain.height(r.pos.x, r.pos.z), r.pos.z)
	if float(r.radius) * Gloam.GUARD_PAD < Gloam.GUARD_MIN:
		var t := 101.0
		var n := 0
		while t < 101.0 + Gloam.GUARD_EVERY_DAY * 3.0:
			t += 1.0
			n += Gloam.rise_at_ruins(g, [{"id": 1, "pos": heart}], t, false, Ruins.all()).size()
		check_eq(n, 0, "a small ruin you cleared stays clear while you search it")
	# Back outside, it gets one guard per refill, never a whole pack at once.
	var g2 := Gloam.new_state()
	var big := _ruin(4)
	var near_big := _outside(big, 40.0)
	Gloam.rise_at_ruins(g2, [{"id": 1, "pos": near_big}], 100.0, true, Ruins.all())
	for w in _guards(g2, big):
		Gloam.strike(g2, int(w.id), 1, near_big, 100.0, 999.0, true)
	var got := Gloam.rise_at_ruins(g2, [{"id": 1, "pos": near_big}], 100.0 + Gloam.GUARD_EVERY_NIGHT + 0.1, true, Ruins.all())
	check_eq(_guards(g2, big).size(), 1, "one guard back per refill")
	check(got.size() >= 1, "reported")
	_done()


func test_leaving_forgets_the_ruin_and_coming_back_finds_it_guarded() -> void:
	_island()
	var r := _ruin(2)
	var g := Gloam.new_state()
	var near := _outside(r, 35.0)
	Gloam.rise_at_ruins(g, [{"id": 1, "pos": near}], 100.0, false, Ruins.all())
	check(g.guard_at.has(int(r.id)), "the ruin is awake")
	var far := _outside(r, Gloam.GUARD_WAKE + 400.0)
	Gloam.rise_at_ruins(g, [{"id": 1, "pos": far}], 110.0, false, Ruins.all())
	check(not g.guard_at.has(int(r.id)), "forgotten once nobody is near")
	# The old guards crumble while nobody is near.
	Gloam.step(g, [{"id": 1, "pos": far}], [], 111.0, DT, false)
	Gloam.step(g, [{"id": 1, "pos": far}], [], 111.0 + Gloam.CRUMBLE_SECONDS + 1.0, DT, false)
	check_eq(_guards(g, r).size(), 0, "the guards crumbled")
	Gloam.rise_at_ruins(g, [{"id": 1, "pos": near}], 200.0, false, Ruins.all())
	check_eq(_guards(g, r).size(), Gloam.guard_cap(2, false), "coming back, the ruin is guarded again")
	_done()


func test_a_guard_goes_back_to_its_ruin_after_a_noise() -> void:
	_island()
	var r := _ruin(1)
	var g := Gloam.new_state()
	var near := _outside(r, 35.0)
	Gloam.rise_at_ruins(g, [{"id": 1, "pos": near}], 100.0, false, Ruins.all())
	var w: Dictionary = _guards(g, r)[0]
	var home: Vector3 = w.home
	check(_flat(home, r.pos) <= float(r.radius), "its home is in the ruin")
	# A noise just outside the pad draws it; nobody in sight, so it lingers there and then
	# wanders home again rather than making the noise its new home.
	var lure := _outside(r, 4.0)
	Gloam.noise(g, lure, 100.0)
	var t := 100.0
	var far := _outside(r, Gloam.GUARD_WAKE + 30.0) # awake but well out of sight
	while t < 160.0:
		t += DT
		Gloam.step(g, [{"id": 1, "pos": far}], [], t, DT, false)
	check_eq(w.home, home, "a guard keeps its ruin as home")
	check(_flat(w.pos, r.pos) <= float(r.radius) + Gloam.WANDER_RADIUS + 2.0, "and is back about its ruin")
	_done()


func test_open_ground_by_a_guarded_ruin_stays_quiet() -> void:
	_island()
	var r := _ruin(4)
	var g := Gloam.new_state()
	var me := _outside(r, 30.0)
	var players := [{"id": 1, "pos": me}]
	Gloam.rise_near_players(g, players, 100.0, false) # wakes the ruin and books the first open rise
	var guards := _guards(g, r).size()
	check_eq(guards, Gloam.guard_cap(4, false), "rise_near_players wakes the ruin's guards")
	var t := 100.0
	while t < 100.0 + Gloam.RISE_EVERY_DAY * 3.0:
		t += 1.0
		Gloam.rise_near_players(g, players, t, false)
	var open: int = g.walkers.filter(func(w): return int(w.ruin) < 0).size()
	check_eq(open, 0, "by day, nothing else rises beside a guarded ruin")
	check(Gloam.count(g) <= Gloam.MAX_WALKERS, "under the world cap")
	_done()


func test_guards_on_a_big_pad_stay_while_you_are_near_it() -> void:
	_island()
	var r := _ruin(4)
	var g := Gloam.new_state()
	var me := _outside(r, Gloam.GUARD_WAKE - 5.0) # at the edge of the castle's wake ring
	Gloam.rise_at_ruins(g, [{"id": 1, "pos": me}], 100.0, false, Ruins.all())
	var n := _guards(g, r).size()
	check(n > 0, "the castle is guarded")
	_run_near(g, me, 100.0, Gloam.CRUMBLE_SECONDS + 5.0)
	check_eq(_guards(g, r).size(), n, "guards far across the pad don't crumble while you are near their ruin")
	_done()


func _run_near(g: Dictionary, me: Vector3, from: float, seconds: float) -> void:
	var t := from
	while t < from + seconds:
		t += 0.25
		Gloam.step(g, [{"id": 1, "pos": me}], [], t, 0.25, false)

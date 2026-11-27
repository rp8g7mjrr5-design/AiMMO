extends TestCase
## World stream, Basics 4: loot in the beach landmarks. The shipwreck holds a sea chest and a
## body under sailcloth, the fishing shack the shape under the sail and a sack. The spots are
## shared data (BeachGen.loot_spots, appended to RuinLayout.all_loot_spots, so the server and
## the client both read them), pay from Loot's grade 1 table, and are drawn exactly on their
## points (BeachProps). Every test puts the world back to Ashgrove.

const ServerScript := preload("res://server/server.gd")
const SEEDS := [1126, 7, 3, 42]


func _island(seed: int) -> void:
	WorldGen.configure(seed, 3000.0, WorldGen.ISLAND)
	ResourceNodes.reset()
	BeachGen.reset()


func _done() -> void:
	WorldGen.reset()
	ResourceNodes.reset()
	BeachGen.reset()


func _landmark_of(spot: Dictionary) -> Dictionary:
	var id := int(spot.ruin_id) - BeachGen.LOOT_ID_BASE
	var b := BeachGen.beach(id / 10)
	return {"beach": b, "lm": b.landmarks[id % 10]}


func test_every_wreck_and_shack_has_its_spots_on_dry_ground() -> void:
	var wrecks := 0
	var shacks := 0
	var wl := Terrain.water_level()
	for s in SEEDS:
		_island(s)
		var spots := BeachGen.loot_spots()
		var per := {}
		for sp in spots:
			var at := _landmark_of(sp)
			var lm: Dictionary = at.lm
			check_eq(str(lm.kind), str(sp.landmark), "a spot knows its landmark")
			var k := str(sp.ruin_id)
			if not per.has(k):
				per[k] = []
			per[k].append(sp.kind)
			check(absf(sp.pos.y - Terrain.height(sp.pos.x, sp.pos.z)) < 0.001, "%s sits on the ground" % sp.kind)
			check(sp.pos.y >= wl + BeachGen.LOOT_DRY - 0.01, "seed %d: the %s's %s is out of the sea (%.2f)" % [s, lm.kind, sp.kind, sp.pos.y - wl])
			var flat := Vector2(sp.pos.x - lm.pos.x, sp.pos.z - lm.pos.z).length()
			check(flat < float(BeachGen.LANDMARKS[lm.kind].r) + 12.0, "the %s is by its %s (%.1f m)" % [sp.kind, lm.kind, flat])
			check_eq(Loot.grade_of(sp, Ruins.all()), 1, "beach loot is grade 1, the quietest rung")
		for b in BeachGen.all():
			for lm in b.landmarks:
				if lm.kind == "shipwreck":
					wrecks += 1
				elif lm.kind == "fishing_shack":
					shacks += 1
		for k in per:
			var kinds: Array = per[k]
			kinds.sort()
			check(kinds == ["body", "chest"] or kinds == ["body", "sack"], "a wreck has a chest and a body, a shack a body and a sack: %s" % str(kinds))
		for i in spots.size():
			for j in range(i + 1, spots.size()):
				check(spots[i].pos.distance_to(spots[j].pos) > 1.5, "beach loot spots are apart")
	check(wrecks >= 2 and shacks >= 1, "the seeds cover wrecks (%d) and shacks (%d)" % [wrecks, shacks])
	_done()


func test_keys_never_meet_a_ruin_and_the_world_reads_them() -> void:
	for s in SEEDS:
		_island(s)
		var all := RuinLayout.all_loot_spots()
		var beach := BeachGen.loot_spots()
		check(beach.size() >= 2, "seed %d has beach loot (%d)" % [s, beach.size()])
		check(all.size() >= beach.size() + 4, "all_loot_spots holds the farmstead and the beaches")
		var keys := {}
		for sp in all:
			var k := Loot.key(sp)
			check(not keys.has(k), "seed %d: key %s is unique" % [s, k])
			keys[k] = true
		for r in Ruins.all():
			check(int(r.id) < BeachGen.LOOT_ID_BASE, "ruin ids stay below the beach ids")
	_done()
	check_eq(BeachGen.loot_spots(), [], "Ashgrove has no beaches and no beach loot")


func test_the_beaches_did_not_move() -> void:
	# loot_spots draws nothing from the beaches' rng: building them, reading the spots and
	# building again gives the same landmarks and pickings.
	_island(1126)
	var before := str(BeachGen.all())
	BeachGen.loot_spots()
	BeachGen.reset()
	check_eq(str(BeachGen.all()), before, "same beaches")
	_done()


func test_spots_clear_of_the_beach_pickings() -> void:
	for s in SEEDS:
		_island(s)
		for sp in BeachGen.loot_spots():
			for n in BeachGen.nodes():
				var d := Vector2(sp.pos.x - n.pos.x, sp.pos.z - n.pos.z).length()
				check(d > 1.2, "seed %d: the %s's %s is clear of a %s (%.2f m)" % [s, sp.landmark, sp.kind, n.kind, d])
	_done()


func test_drawn_exactly_on_the_spots() -> void:
	for s in SEEDS:
		_island(s)
		var all_parts := BeachProps.parts()
		for sp in BeachGen.loot_spots():
			if bool(sp.drawn):
				# The shack's shape under the sail is the landmark's own part: one sits on the spot.
				var at := _landmark_of(sp)
				var near := false
				for p in BeachProps.landmark_parts(at.lm, at.beach):
					var o: Vector3 = p.xform.origin
					if p.layer == "BeachRocks" and Vector2(o.x - sp.pos.x, o.z - sp.pos.z).length() < 0.2:
						near = true
				check(near, "the shack draws its body on the spot")
				continue
			var parts := BeachProps.loot_parts(sp)
			check(parts.size() >= 2, "a %s is drawn" % sp.kind)
			for p in parts:
				var o: Vector3 = p.xform.origin
				check(Vector2(o.x - sp.pos.x, o.z - sp.pos.z).length() < 1.0, "%s parts sit on the spot" % sp.kind)
				check(o.y - sp.pos.y < 0.8, "%s is low on the sand" % sp.kind)
				check(BeachProps.LAYERS.has(p.layer), "on a shared beach layer")
				var c: Color = p.color
				check(c.s < 0.45, "%s colours are muted naturals (s %.2f)" % [sp.kind, c.s])
			# and they are in the beaches' build data
			var found := false
			for p in all_parts:
				if p.xform.origin.distance_to(parts[0].xform.origin) < 0.001:
					found = true
					break
			check(found, "the %s is in BeachProps.parts()" % sp.kind)
	_done()


func test_the_server_searches_a_wreck() -> void:
	var srv: Node = ServerScript.new()
	srv.use_world(WorldGen.parse("1126:2:3000"))
	var beach: Array = srv.loot_spots.filter(func(sp): return int(sp.ruin_id) >= BeachGen.LOOT_ID_BASE)
	check(beach.size() >= 2, "the server knows the beach spots (%d)" % beach.size())
	if beach.is_empty():
		srv.free()
		_done()
		return
	var spot: Dictionary = beach[0]
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "Beachcomber"})
	ch.x = spot.pos.x + 0.6
	ch.z = spot.pos.z
	srv.sessions[1] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
		"channel": {}, "login_attempts": 0, "inv_dirty": false}
	srv.loot_rng.seed = 11
	srv._on_place(1, "search")
	check(not srv.sessions[1].get("search", {}).is_empty(), "the search runs at the %s" % spot.landmark)
	for i in int(round((Loot.SEARCH_SECONDS + 0.2) / GameConfig.TICK_DT)):
		srv.test_now += GameConfig.TICK_DT
		srv._tick()
	var res: Array = []
	for m in srv.test_outbox:
		if m[0] == 1 and m[1] == "s2c_place_result":
			res.append(m[2])
	check_eq(res.size(), 1, "one answer")
	if res.size() == 1:
		check_eq(res[0][0], "search")
		check(str(res[0][3]).begins_with("You search the %s" % Loot.kind_name(str(spot.kind))), str(res[0][3]))
	check(Loot.is_empty(srv.loot, Loot.key(spot), srv.test_now), "searched until tomorrow")
	srv.free()
	_done()

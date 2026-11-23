extends TestCase
## Resource node placement (game/shared/resource_nodes.gd).

## Pinned fingerprints of the node list. Node ids are permanent (gathering has shipped), so
## the first 397 (passes 1 and 2) must never change; new passes only append. FINGERPRINT is
## the whole list today: when a pass is appended, pin the old whole list as another prefix
## here and update FINGERPRINT, and say why in docs/devlog/gameplay.md.
const FINGERPRINT_397 := "397-661be157d592b82ad460e8b5154aa417" ## starter ring + wild
const FINGERPRINT := "405-413500cecfbb07c82c21389af3f8a317" ## + the tier-2 ring (2026-11-23)


func test_list_is_pinned() -> void:
	check_eq(ResourceNodes.fingerprint(397), FINGERPRINT_397, "the first 397 nodes never change (ids are permanent)")
	check_eq(ResourceNodes.fingerprint(), FINGERPRINT, "node list unchanged")


func test_deterministic() -> void:
	var a := ResourceNodes.generate()
	var b := ResourceNodes.generate()
	check_eq(a.size(), b.size(), "same count every time")
	var same := true
	for i in a.size():
		if a[i].kind != b[i].kind or not a[i].pos.is_equal_approx(b[i].pos):
			same = false
			break
	check(same, "same nodes in the same order every time")
	check_eq(a.size(), ResourceNodes.count(), "cached list matches a fresh build")


func test_ids_are_indices() -> void:
	var ok := true
	for i in ResourceNodes.count():
		if ResourceNodes.all()[i].id != i:
			ok = false
	check(ok, "every node's id is its index")
	check(ResourceNodes.get_by_id(-1).is_empty(), "negative id is unknown")
	check(ResourceNodes.get_by_id(ResourceNodes.count()).is_empty(), "id past the end is unknown")
	check_eq(ResourceNodes.get_by_id(3).id, 3, "lookup by id")


func test_every_kind_reaches_its_target() -> void:
	var by_kind := {}
	for n in ResourceNodes.all():
		check(ResourceNodes.KINDS.has(n.kind), "known kind %s" % n.kind)
		by_kind[n.kind] = by_kind.get(n.kind, 0) + 1
	for k in ResourceNodes.KIND_ORDER:
		check(by_kind.get(k, 0) >= ResourceNodes.TARGETS[k], "%s: %d placed, target %d" % [k, by_kind.get(k, 0), ResourceNodes.TARGETS[k]])
	check(by_kind.ember_sap < by_kind.ash / 3, "ember sap is rare")
	for k in ResourceNodes.KINDS:
		var info := ResourceNodes.kind_info(k)
		check(info.item != "" and info.amount > 0 and info.respawn > 0.0, "%s has an item, amount and respawn" % k)
	check(ResourceNodes.kind_info("ember_sap").night_only, "ember sap seeps only at night")
	check(ResourceNodes.kind_info("nope").is_empty(), "unknown kind gives empty info")


func test_nodes_sit_on_dry_ground_inside_the_world() -> void:
	var h := GameConfig.WORLD_HALF_SIZE
	var bad := 0
	for n in ResourceNodes.all():
		var p: Vector3 = n.pos
		if absf(p.x) > h - 1.0 or absf(p.z) > h - 1.0:
			bad += 1
		elif absf(p.y - Terrain.height(p.x, p.z)) > 0.001:
			bad += 1
		elif p.y < Terrain.water_level() + 0.5:
			bad += 1
		elif Vector2(p.x, p.z).length() < ResourceNodes.SPAWN_CLEAR_RADIUS:
			bad += 1
	check_eq(bad, 0, "nodes are on the ground, out of the water, inside the border, off the spawn point")


func test_minimum_spacing() -> void:
	var list := ResourceNodes.all()
	var closest := INF
	for i in list.size():
		for j in range(i + 1, list.size()):
			var d := Vector2(list[i].pos.x - list[j].pos.x, list[i].pos.z - list[j].pos.z).length()
			closest = minf(closest, d)
	check(closest >= ResourceNodes.MIN_SPACING, "closest pair %.2f m apart" % closest)


func test_starter_ring_has_every_kind_near_spawn() -> void:
	var found := {}
	for n in ResourceNodes.near(GameConfig.SPAWN_POINT, ResourceNodes.STARTER_MAX_RADIUS + 0.01):
		found[n.kind] = found.get(n.kind, 0) + 1
	for k in ResourceNodes.KIND_ORDER:
		check(found.has(k), "a %s within %d m of spawn" % [k, ResourceNodes.STARTER_MAX_RADIUS])
	check(found.get("ash", 0) >= 2 and found.get("pine", 0) >= 2 and found.get("stone", 0) >= 2, "two of each common kind at spawn")


func test_near_matches_brute_force() -> void:
	var probes := [Vector3.ZERO, Vector3(120, 0, -80), Vector3(-200, 0, 190), Vector3(255, 0, 255)]
	for p in probes:
		for r in [5.0, 25.0, 70.0]:
			var want := 0
			for n in ResourceNodes.all():
				if Vector2(n.pos.x - p.x, n.pos.z - p.z).length() <= r:
					want += 1
			var got := ResourceNodes.near(p, r)
			check_eq(got.size(), want, "near(%s, %d)" % [p, r])
			var sorted := true
			for i in range(1, got.size()):
				if Vector2(got[i].pos.x - p.x, got[i].pos.z - p.z).length() < Vector2(got[i - 1].pos.x - p.x, got[i - 1].pos.z - p.z).length():
					sorted = false
			check(sorted, "near() is nearest first")
	for n in ResourceNodes.near(Vector3(60, 0, 60), 80.0, "pine"):
		check_eq(n.kind, "pine", "kind filter")


func test_nearest_and_range() -> void:
	var n := ResourceNodes.nearest(GameConfig.SPAWN_POINT, "ember_sap")
	check(not n.is_empty(), "an ember-sap seep near spawn")
	check(Vector2(n.pos.x, n.pos.z).length() <= ResourceNodes.STARTER_MAX_RADIUS, "and it is the starter one")
	check(ResourceNodes.in_range(n.id, n.pos + Vector3(2.0, 5.0, 0.0)), "2 m away is in range (height ignored)")
	check(not ResourceNodes.in_range(n.id, n.pos + Vector3(3.5, 0.0, 0.0)), "3.5 m away is out of range")
	check(not ResourceNodes.in_range(99999, n.pos), "unknown id is never in range")
	check(ResourceNodes.nearest(Vector3(10000, 0, 10000), "", 16.0).is_empty(), "nothing far outside the world")

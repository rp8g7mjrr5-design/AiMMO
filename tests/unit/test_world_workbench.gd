extends TestCase
## World stream: the Spawn Meadow workbench stands exactly where gameplay's crafting rule
## says (Crafting.workbench_pos), on the ground, facing spawn, clear of everything else.
## Uses the pure halves of Workbench (no renderer).


func test_bench_stands_where_crafting_works() -> void:
	var s := Workbench.spot()
	var bench := Crafting.workbench_pos()
	check(s.pos.is_equal_approx(bench), "bench is at Crafting.workbench_pos()")
	check_near(s.pos.y, Terrain.height(s.pos.x, s.pos.z), 0.01, "bench stands on the ground")
	check(Crafting.near_bench(s.pos), "standing at the bench counts as near it")
	# Local +Z faces spawn, so the long side and the tools greet a new player.
	var facing := Basis(Vector3.UP, s.rot) * Vector3.BACK
	var to_spawn: Vector3 = GameConfig.SPAWN_POINT - s.pos
	to_spawn.y = 0.0
	check(facing.dot(to_spawn.normalized()) > 0.99, "bench faces spawn")


func test_parts_hold_together() -> void:
	var s := Workbench.spot()
	var ps := Workbench.parts(s)
	var by := {}
	for p in ps:
		check(Workbench.LAYERS.has(p.layer), "part %s is on a known layer" % p.name)
		by[p.name] = by.get(p.name, 0) + 1
		var o: Vector3 = p.xform.origin
		var g := Terrain.height(o.x, o.z)
		check(o.y > g - 0.05, "%s is not under the ground" % p.name)
		check(o.y < s.pos.y + Workbench.TOP_HEIGHT + 0.6, "%s is not floating above the bench" % p.name)
		check(Vector2(o.x - s.pos.x, o.z - s.pos.z).length() <= Workbench.FOOTPRINT, "%s stays within the footprint" % p.name)
		check(absf(p.xform.basis.determinant()) > 0.00001, "%s has a real size" % p.name)
	check_eq(by.get("leg", 0), 4, "four stone legs")
	check_eq(by.get("plank", 0), 3, "three planks on top")
	check_eq(by.get("hammer_head", 0), 1, "a hammer on the bench")
	check_eq(by.get("block", 0), 1, "a chopping block")
	# The planks' top is at standing height above the bench's ground.
	for p in ps:
		if p.name == "plank":
			var top: float = p.xform.origin.y + p.xform.basis.get_scale().y * 0.5
			check_near(top - s.pos.y, Workbench.TOP_HEIGHT, 0.02, "plank top is at TOP_HEIGHT")
	var lay := Workbench.layout(s)
	var total := 0
	for l in Workbench.LAYERS:
		total += lay[l].size()
	check_eq(total, ps.size(), "layout has every part")


func test_bench_is_clear_of_everything() -> void:
	var s := Workbench.spot()
	var flat := Vector2(s.pos.x, s.pos.z) as Vector2
	check(ResourceNodes.near(s.pos, Workbench.CLEARANCE).is_empty(), "no resource node at the bench")
	for l in Lamps.positions():
		check(Vector2(l.pos.x, l.pos.z).distance_to(flat) > Workbench.CLEARANCE, "no lantern at the bench")
	for it in Props.scatter():
		check(Vector2(it.pos.x, it.pos.z).distance_to(flat) > Workbench.CLEARANCE, "no decorative tree or rock at the bench")
	for f in Flora.spots():
		check(Vector2(f.pos.x, f.pos.z).distance_to(flat) > Workbench.CLEARANCE, "no flora at the bench")
	# Out of the way of arrivals: spawn itself is not inside the bench.
	var sp := Vector2(GameConfig.SPAWN_POINT.x, GameConfig.SPAWN_POINT.z)
	check(sp.distance_to(flat) > Workbench.FOOTPRINT + 0.5, "spawn point is not inside the bench")


func test_deterministic() -> void:
	var a := Workbench.parts()
	var b := Workbench.parts()
	check_eq(a.size(), b.size(), "same number of parts")
	for i in a.size():
		check(a[i].xform.is_equal_approx(b[i].xform) and a[i].color.is_equal_approx(b[i].color), "part %d same every time" % i)

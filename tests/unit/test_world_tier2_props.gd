extends TestCase
## World stream: tier-2 resource-node props (Milestone 1 part 2). Gameplay's level-gated
## nodes carry `tier` 2; an ash draws as an old ember ash and a stone as a rich stone seam.
## They must read as landmarks (taller and wider than tier 1, glowing), keep every vertex
## inside their own solid columns (so the action camera never sees inside), fit NodeFx's
## highlight shell, and leave every tier-1 node exactly as it was. Renderer-free.


func _first_of(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _tier2(kind: String, count: int = 1) -> Array:
	var out: Array = []
	for n in ResourceNodes.all():
		if n.kind == kind:
			var t: Dictionary = n.duplicate()
			t["tier"] = 2
			out.append(t)
			if out.size() >= count:
				break
	return out


func _verts() -> Dictionary:
	var meshes := NodeProps._meshes()
	var verts := {}
	for l in NodeProps.LAYERS:
		verts[l] = (meshes[l] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return verts


## [max height above ground, max distance from the axis] over every vertex, at scale 1.
func _extent(node: Dictionary, verts: Dictionary) -> Vector2:
	var top := 0.0
	var wide := 0.0
	for p in NodeProps.parts(node):
		for v in verts[p.layer]:
			var w: Vector3 = p.xform * v
			top = maxf(top, (w.y - node.pos.y) / node.scale)
			wide = maxf(wide, Vector2(w.x - node.pos.x, w.z - node.pos.z).length() / node.scale)
	return Vector2(top, wide)


func _count(parts: Array, layer: String) -> int:
	return parts.filter(func(p): return p.layer == layer).size()


func test_tier_two_is_a_bigger_landmark() -> void:
	var verts := _verts()
	var ash1 := _extent(_first_of("ash"), verts)
	var ash2 := _extent(_tier2("ash")[0], verts)
	check(ash2.x > ash1.x + 1.2, "old ember ash stands taller (%.1f m vs %.1f m)" % [ash2.x, ash1.x])
	check(ash2.y > ash1.y + 0.8, "old ember ash spreads wider (%.1f m vs %.1f m)" % [ash2.y, ash1.y])
	var st1 := _extent(_first_of("stone"), verts)
	var st2 := _extent(_tier2("stone")[0], verts)
	check(st2.x > st1.x + 0.5, "rich seam stands taller (%.1f m vs %.1f m)" % [st2.x, st1.x])
	check(st2.y > st1.y + 0.4, "rich seam spreads wider (%.1f m vs %.1f m)" % [st2.y, st1.y])


func test_tier_two_glows_and_has_its_own_colours() -> void:
	var ash := NodeProps.parts(_tier2("ash")[0])
	check(_count(ash, NodeProps.GLOW_LAYER) >= 4, "old ember ash hangs glowing ember pods")
	check(ash.any(func(p): return p.layer == "NodeAshCrowns" and p.color.is_equal_approx(NodeProps.OLD_ASH_LEAF)), "brighter gold crown")
	check(_count(ash, "NodeTrunks") == 3, "trunk and two gnarled boughs")
	check(_count(ash, NodeProps.VEIN_LAYER) > _count(NodeProps.parts(_first_of("ash")), NodeProps.VEIN_LAYER), "more ember cracks than a tier-1 ash")
	var stone := NodeProps.parts(_tier2("stone")[0])
	check(_count(stone, NodeProps.GLOW_LAYER) == 3, "rich seam has three ember crystals")
	check(stone.any(func(p): return p.layer == "NodeStones" and p.color.is_equal_approx(NodeProps.RICH_STONE)), "deeper stone colour")
	var flecks := stone.filter(func(p): return p.layer == NodeProps.DETAIL_LAYER)
	check(flecks.size() >= 8 and flecks.all(func(p): return p.color.r > 0.85 and p.color.g > 0.75), "bright gold flecks")
	var dead := NodeProps.parts(_tier2("ash")[0], true)
	check(_count(dead, NodeProps.GLOW_LAYER) == 0 and _count(dead, NodeProps.VEIN_LAYER) == 0, "a felled old ash goes dark")
	check(_count(dead, "NodeStumps") == 2, "and leaves a wide stump")
	check(_count(NodeProps.parts(_tier2("stone")[0], true), NodeProps.GLOW_LAYER) == 0, "worked-out seam goes dark")


func test_every_tier_two_vertex_is_inside_its_solid_columns() -> void:
	var verts := _verts()
	var checked := 0
	var worst := 0.0
	var worst_at := ""
	for n in _tier2("ash", 30) + _tier2("stone", 30):
		var cols := NodeProps.solid_columns(n.kind, n.scale, 2)
		for depleted in [false, true]:
			for p in NodeProps.parts(n, depleted):
				for v in verts[p.layer]:
					var w: Vector3 = p.xform * v
					var h: float = w.y - n.pos.y
					if h < 0.0:
						continue
					checked += 1
					var d := Vector2(w.x - n.pos.x, w.z - n.pos.z).length()
					var miss := INF
					for c in cols:
						if h >= c[1] - 0.01 and h <= c[2] + 0.01:
							miss = minf(miss, d - c[0])
					if miss > worst:
						worst = miss
						worst_at = "%s node %d %s (h %.2f)" % [n.kind, n.id, p.layer, h / n.scale]
	check(checked > 20000, "checked %d vertices" % checked)
	check(worst <= 0.01, "a vertex sticks %.3f m out of the tier-2 columns at %s" % [worst, worst_at])


func test_columns_are_snug() -> void:
	# The camera shouldn't be pushed off by empty air: each column is touched by some vertex
	# within 0.35 m of its radius.
	var verts := _verts()
	for kind in ["ash", "stone"]:
		var n: Dictionary = _tier2(kind)[0]
		n["scale"] = 1.0
		var cols := NodeProps.solid_columns(kind, 1.0, 2)
		var reach: Array = []
		reach.resize(cols.size())
		reach.fill(0.0)
		for depleted in [false, true]:
			for p in NodeProps.parts(n, depleted):
				for v in verts[p.layer]:
					var w: Vector3 = p.xform * v
					var h: float = w.y - n.pos.y
					var d := Vector2(w.x - n.pos.x, w.z - n.pos.z).length()
					for i in cols.size():
						if h >= cols[i][1] and h <= cols[i][2]:
							reach[i] = maxf(reach[i], d)
		for i in cols.size():
			check(cols[i][0] - reach[i] < 0.35, "%s:2 column %d is snug (radius %.2f, reached %.2f)" % [kind, i, cols[i][0], reach[i]])


func test_inside_solid_reads_the_tier() -> void:
	var ash1 := _first_of("ash")
	var ash2: Dictionary = _tier2("ash")[0]
	var p: Vector3 = ash1.pos + Vector3(2.7, 4.0, 0) * float(ash1.scale)
	check(NodeProps.inside_solid(p, ash2), "inside the old ash's wide crown")
	check(not NodeProps.inside_solid(p, ash1), "the same spot is clear of a tier-1 ash")
	var st2: Dictionary = _tier2("stone")[0]
	check(NodeProps.inside_solid(st2.pos + Vector3(0, 2.2, 0) * float(st2.scale), st2), "inside the crystals on top")
	check(not NodeProps.inside_solid(st2.pos + Vector3(0, 3.2, 0) * float(st2.scale), st2), "clear above them")


func test_fits_the_highlight_shell_and_vein_budget() -> void:
	for n in _tier2("ash", 10) + _tier2("stone", 10):
		for depleted in [false, true]:
			var per := {}
			for p in NodeProps.parts(n, depleted):
				per[p.layer] = per.get(p.layer, 0) + 1
			for l in per:
				check(per[l] <= NodeFx.SHELL_SLOTS, "%s:2 %s has %d parts, shell holds %d" % [n.kind, l, per[l], NodeFx.SHELL_SLOTS])
			check(per.get(NodeProps.VEIN_LAYER, 0) <= NodeProps.MAX_VEIN_PARTS, "veins fit")


func test_veins_and_flecks_sit_on_the_surface() -> void:
	for n in _tier2("ash", 20):
		var s: float = n.scale
		for v in NodeProps.parts(n).filter(func(p): return p.layer == NodeProps.VEIN_LAYER):
			var o: Vector3 = (v.xform as Transform3D).origin - (n.pos as Vector3)
			var y := o.y / s
			var d := Vector2(o.x, o.z).length() / s
			var r := NodeProps.trunk_radius(y, 2)
			check(absf(d - r) < 0.05, "node %d: vein on the old trunk (%.3f m vs radius %.3f)" % [n.id, d, r])
	for n in _tier2("stone", 20):
		var s: float = n.scale
		var half: Vector3 = NodeProps.STONE_HALF[2]
		var cy: float = NodeProps.STONE_CENTRE_Y[2]
		for v in NodeProps.parts(n).filter(func(p): return p.layer == NodeProps.VEIN_LAYER or p.layer == NodeProps.DETAIL_LAYER):
			var o: Vector3 = (v.xform as Transform3D).origin - (n.pos as Vector3)
			var e := Vector3(o.x / s / half.x, (o.y / s - cy) / half.y, o.z / s / half.z).length()
			check(e > 0.9 and e < 1.04, "node %d: %s on the big stone (%.3f)" % [n.id, v.layer, e])


func test_tier_one_is_untouched() -> void:
	for kind in ResourceNodes.KIND_ORDER:
		var n := _first_of(kind)
		var t1: Dictionary = n.duplicate()
		t1["tier"] = 1
		for depleted in [false, true]:
			var a := NodeProps.parts(n, depleted)
			var b := NodeProps.parts(t1, depleted)
			check_eq(a.size(), b.size(), "%s: tier 1 same part count" % kind)
			for i in mini(a.size(), b.size()):
				check(a[i].xform.is_equal_approx(b[i].xform) and a[i].layer == b[i].layer, "%s part %d unchanged" % [kind, i])
	# Kinds without a tier-2 look keep theirs, with the extra veins.
	for kind in ["pine", "ember_sap"]:
		var n: Dictionary = _first_of(kind).duplicate()
		n["tier"] = 2
		check_eq(NodeProps.tier_of(n), 1, "%s has no tier-2 look yet" % kind)
		check_eq(NodeProps.solid_columns(kind, 1.0, 2), NodeProps.solid_columns(kind), "%s keeps its columns" % kind)


func test_layout_and_hit_bits_know_the_tier() -> void:
	var nodes := _tier2("ash", 2) + _tier2("stone", 2) + [_first_of("pine")]
	var lay := NodeProps.layout(nodes)
	for n in nodes:
		check_eq(lay.slots[n.id].tier, NodeProps.tier_of(n), "slot %d keeps its tier" % n.id)
	var ash: Dictionary = nodes[0]
	for b in NodeFx.spawn_bits(ash):
		# Outside the main crown (centre 4.6 m up, radius 2.47 m, half height 1.95 m at scale 1).
		var o: Vector3 = (b.p0 - (ash.pos as Vector3)) / float(ash.scale)
		var e := Vector2(o.x, o.z).length_squared() / (2.47 * 2.47) + pow((o.y - 4.6) / 1.95, 2.0)
		check(e > 1.0, "old ash leaves start outside the main crown (%.2f)" % e)
		check(b.color.r > 0.95, "old ash sheds its bright gold leaves")
	var stone: Dictionary = nodes[2]
	var bits := NodeFx.spawn_bits(stone)
	check(bits[0].color.is_equal_approx(NodeProps.RICH_FLECK), "a rich seam throws gold flecks")
	check(NodeProps.parts(ash) == NodeProps.parts(ash), "deterministic")

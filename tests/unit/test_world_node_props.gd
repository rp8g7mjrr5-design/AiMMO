extends TestCase
## World stream: every resource node has a prop players can recognise, plus a depleted look,
## and decorative trees and rocks keep clear of them. Uses NodeProps.parts()/layout(), which
## never touch the renderer, so it runs headless.


func _parts_by_layer(node: Dictionary, depleted: bool) -> Dictionary:
	var by := {}
	for p in NodeProps.parts(node, depleted):
		by[p.layer] = by.get(p.layer, 0) + 1
	return by


func _first_of(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func test_every_kind_has_its_own_live_and_depleted_look() -> void:
	var ash := _parts_by_layer(_first_of("ash"), false)
	check(ash.get("NodeAshCrowns", 0) >= 1 and ash.get("NodeTrunks", 0) == 1, "ash: trunk and ember crown")
	var pine := _parts_by_layer(_first_of("pine"), false)
	check(pine.get("NodePineTiers", 0) >= 3 and pine.get("NodeTrunks", 0) == 1, "pine: trunk and tiers")
	var stone := NodeProps.parts(_first_of("stone"), false)
	check(stone.any(func(p): return p.color == NodeProps.STONE_VEIN), "stone outcrop shows its pale seam")
	var sap := _parts_by_layer(_first_of("ember_sap"), false)
	check(sap.get(NodeProps.GLOW_LAYER, 0) >= 1, "live sap seep glows")
	for kind in ResourceNodes.KIND_ORDER:
		var dead := _parts_by_layer(_first_of(kind), true)
		check(not dead.is_empty(), "%s has a depleted look" % kind)
		for l in ["NodeAshCrowns", "NodePineTiers", "NodeTrunks", NodeProps.GLOW_LAYER]:
			check(dead.get(l, 0) == 0, "depleted %s has no %s" % [kind, l])


func test_props_stand_on_their_node() -> void:
	for n in ResourceNodes.all():
		for depleted in [false, true]:
			for p in NodeProps.parts(n, depleted):
				var o: Vector3 = p.xform.origin
				var flat := Vector2(o.x - n.pos.x, o.z - n.pos.z).length()
				if flat > 1.6 * n.scale:
					check(false, "node %d part strays %.2f m from its spot" % [n.id, flat])
					return
				if o.y < n.pos.y - 0.05 or o.y > n.pos.y + 7.5:
					check(false, "node %d part floats or sinks (y %.2f vs ground %.2f)" % [n.id, o.y, n.pos.y])
					return


func test_parts_are_deterministic() -> void:
	var n := ResourceNodes.get_by_id(5)
	var a := NodeProps.parts(n)
	var b := NodeProps.parts(n)
	check_eq(a.size(), b.size(), "same part count")
	for i in a.size():
		check(a[i].xform.is_equal_approx(b[i].xform) and a[i].color == b[i].color, "part %d identical" % i)


func test_layout_indexes_every_part_once() -> void:
	var nodes := ResourceNodes.all()
	var lay := NodeProps.layout(nodes)
	check_eq(lay.slots.size(), nodes.size(), "one slot per node")
	var seen := {}
	var total := 0
	for id in lay.slots:
		for look in ["live", "depleted"]:
			check(not lay.slots[id][look].is_empty(), "node %d has %s parts" % [id, look])
			for e in lay.slots[id][look]:
				var key := "%s/%d" % [e[0], e[1]]
				check(not seen.has(key), "instance %s used once" % key)
				seen[key] = true
				check(e[1] < lay.layers[e[0]].size(), "index in range")
	for l in lay.layers:
		total += lay.layers[l].size()
	check_eq(seen.size(), total, "every instance belongs to a node")


func test_decoration_keeps_clear_of_nodes() -> void:
	var crowded := 0
	for it in Props.scatter():
		if not ResourceNodes.near(it.pos, Props.NODE_CLEARANCE).is_empty():
			crowded += 1
	check_eq(crowded, 0, "no scattered tree or rock within %.0f m of a node" % Props.NODE_CLEARANCE)
	check(Props.scatter().size() > 1500, "the forest is still dense")

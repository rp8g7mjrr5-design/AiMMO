extends TestCase
## World stream: a felled ash breathes no sparks. At night the motes over the
## valley point only at things you can gather right now (art bible section 4, "if it glows
## ember, you can use it"). NodeProps.set_depleted() puts a node's motes out and a regrown
## node gets them back.


func _world() -> Node3D:
	var world := Node3D.new()
	world.add_child(NodeProps.build())
	world.add_child(Motes.build())
	return world


func _first(kind: String, tier: int = 1) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind and int(n.get("tier", 1)) == tier:
			return n
	return {}


func test_slots_cover_each_anchor_once() -> void:
	var count := Motes.anchors().size()
	var seen := {}
	for a in count:
		var s := Motes.slots(a, count)
		check_eq(s.size(), Motes.per_anchor(Motes.MAX_SCALE), "every High slot of anchor %d" % a)
		for i in s:
			check(not seen.has(i), "slot %d belongs to one anchor" % i)
			seen[i] = true
	check_eq(seen.size(), Motes.layout(Motes.anchors()).size(), "together they are the whole pool")
	# The slots really are that anchor's motes: each one rises from beside its node.
	var anchors := Motes.anchors()
	var pool := Motes.layout(anchors)
	for a in [0, count / 2, count - 1]:
		for i in Motes.slots(a, count):
			var o: Vector3 = pool[i].origin
			var p: Vector3 = anchors[a].pos
			check(Vector2(o.x - p.x, o.z - p.z).length() < 8.0, "slot %d sits by anchor %d" % [i, a])


func test_depleting_puts_the_sparks_out_and_regrowth_brings_them_back() -> void:
	var world := _world()
	var nodes := world.get_node("ResourceNodes") as Node3D
	var ash := _first("ash")
	var old := _first("ash", 2)
	for n in [ash, old]:
		check(not n.is_empty(), "the world has this kind of node")
		check(not Motes.is_dark(world, n.id), "node %d starts lit" % n.id)
		check(NodeProps.set_depleted(nodes, n.id, true), "deplete %d" % n.id)
		check(Motes.is_dark(world, n.id), "felled or dry: node %d breathes no sparks" % n.id)
	NodeProps.set_depleted(nodes, old.id, false)
	check(not Motes.is_dark(world, old.id), "a regrown ash sparks again")
	check(Motes.is_dark(world, ash.id), "the others stay out")
	check(Motes.set_dark(world, ash.id, true), "the same state again is fine")
	check(Motes.is_dark(world, ash.id), "and changes nothing")
	world.free()


func test_only_ember_things_have_plumes() -> void:
	var world := _world()
	var pine := _first("pine")
	var stone := _first("stone")
	check(not Motes.set_dark(world, pine.id, true), "a pine has no motes to put out")
	check(not Motes.set_dark(world, stone.id, true), "nor an outcrop")
	check(not Motes.set_dark(world, -5, true), "nor an unknown id")
	check(not Motes.set_dark(null, ash_id(), true), "safe without a world")
	check(not Motes.is_dark(null, ash_id()), "and reads safely")
	# A world without motes (the server, old tests) still depletes fine.
	var bare := Node3D.new()
	var nodes := NodeProps.build()
	bare.add_child(nodes)
	check(NodeProps.set_depleted(nodes, ash_id(), true), "deplete works without motes")
	var lone := NodeProps.build()
	check(NodeProps.set_depleted(lone, ash_id(), true), "and without a parent")
	lone.free()
	bare.free()
	world.free()


func ash_id() -> int:
	return int(_first("ash").id)


func test_dark_keeps_the_pool_and_draw_call() -> void:
	var world := _world()
	var mmi := world.get_node(Motes.NODE_NAME) as MultiMeshInstance3D
	var nodes := world.get_node("ResourceNodes") as Node3D
	var before := mmi.multimesh.instance_count
	var was := Quality.level
	Quality.level = Quality.MEDIUM
	Motes.apply(world, 1.0)
	var shown := mmi.multimesh.visible_instance_count
	for n in ResourceNodes.all():
		if n.kind == "ash":
			NodeProps.set_depleted(nodes, n.id, true)
	Motes.apply(world, 1.0)
	check_eq(mmi.multimesh.instance_count, before, "nothing rebuilt")
	check_eq(mmi.multimesh.visible_instance_count, shown, "quality count untouched")
	check(mmi.visible, "the motes node stays on at night (regrowth needs no rebuild)")
	# The live look is kept so regrowth restores exactly what was there.
	var customs: PackedColorArray = mmi.get_meta("customs")
	var pool := Motes.layout(Motes.anchors())
	for i in [0, pool.size() / 3, pool.size() - 1]:
		check_eq(customs[i], pool[i].custom, "kept live look %d" % i)
	Quality.level = was
	world.free()

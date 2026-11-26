extends TestCase
## World stream: resource-node props are chunked like the forest (art bible section 7, "Draw
## less"), so the camera and the sun's shadow cascades skip what they can't see, the close-up
## layers fade out where nobody can see them, and stump chunks cost nothing until something
## is felled. Nothing moves: every part is still drawn once, in its node's chunk.


func _all_parts(root: Node3D) -> Array:
	var lay: Dictionary = root.get_meta("layout")
	var out: Array = []
	for id in lay.slots:
		for look in ["live", "depleted"]:
			for e in lay.slots[id][look]:
				out.append([id, look, e])
	return out


func test_every_part_is_drawn_once_in_its_nodes_chunk() -> void:
	var root := NodeProps.build()
	var lay: Dictionary = root.get_meta("layout")
	var seen := {}
	for p in _all_parts(root):
		var e: Array = p[2]
		var chunk := NodeProps.part_chunk(root, e[0], e[1])
		var w: Array = root.get_meta("where")[e[0]][e[1]]
		var slot_key := "%d/%d" % [chunk.get_instance_id(), w[1]]
		check(not seen.has(slot_key), "one MultiMesh slot per part")
		seen[slot_key] = true
		check(w[1] < chunk.multimesh.instance_count, "slot in range")
		check(chunk.get_parent().name == e[0], "drawn on its own layer")
		var k := NodeProps.chunk_key(e[0], lay.slots[p[0]].pos)
		check_eq(String(chunk.name), "c%d_%d" % [k.x, k.y], "in its node's chunk")
		check_eq(chunk.position, NodeProps.chunk_centre(e[0], k), "chunk sits at its centre")
	var total := 0
	for l in NodeProps.LAYERS:
		total += (lay.layers[l] as Array).size()
		var drawn := 0
		for c in root.get_node(l).get_children():
			drawn += (c as MultiMeshInstance3D).multimesh.instance_count
		check_eq(drawn, (lay.layers[l] as Array).size(), "%s: every part drawn" % l)
	check_eq(seen.size(), total, "nothing dropped or added")
	root.free()


func test_spawn_meadow_is_the_middle_of_a_chunk() -> void:
	for l in NodeProps.LAYERS:
		var size := NodeProps.chunk_size(l)
		check_eq(NodeProps.chunk_key(l, Vector3.ZERO), Vector2i.ZERO, "%s: spawn in chunk 0,0" % l)
		check_eq(NodeProps.chunk_centre(l, Vector2i.ZERO), Vector3.ZERO, "%s: chunk 0,0 is centred on spawn" % l)
		if size <= 0.0:
			check_eq(NodeProps.chunk_key(l, Vector3(300, 0, -300)), Vector2i.ZERO, "%s: a whole layer is one chunk" % l)
			continue
		check_eq(NodeProps.chunk_key(l, Vector3(size * 0.49, 0, -size * 0.49)), Vector2i.ZERO, "%s: half a chunk out is still 0,0" % l)
		check_eq(NodeProps.chunk_key(l, Vector3(size * 0.51, 0, 0)), Vector2i(1, 0), "%s: past half a chunk is the next one" % l)


func test_layers_are_split_and_cut_at_their_range() -> void:
	var root := NodeProps.build()
	for l in NodeProps.LAYERS:
		var chunks := root.get_node(l).get_children()
		if l == NodeProps.BOX_LAYER and chunks.is_empty():
			continue # only an island's beaches have crates (BeachGen); Ashgrove draws none
		var whole := NodeProps.chunk_size(l) <= 0.0
		if whole:
			check_eq(chunks.size(), 1, "%s stays whole" % l)
		else:
			check(chunks.size() >= 4, "%s is split into chunks (%d)" % [l, chunks.size()])
		for c in chunks:
			var mmi := c as MultiMeshInstance3D
			check(mmi.material_override == NodeProps.layer_material(l), "%s chunks share the layer's material" % l)
			if whole:
				check_eq(mmi.visibility_range_end, 0.0, "%s: a whole layer is never cut" % l)
			else:
				var r: float = NodeProps.RANGES[l]
				check(mmi.visibility_range_end >= r + NodeProps.chunk_size(l) * 0.7071, "%s: nothing closer than %d m is cut" % [l, r])
	check(NodeProps.RANGES[NodeProps.DETAIL_LAYER] < NodeProps.RANGES[NodeProps.VEIN_LAYER], "studs and flecks fade before the glowing cracks")
	check(NodeProps.RANGES["NodeStones"] >= Chunks.range_of("Rocks"), "node stones are seen at least as far as the scatter rocks")
	for l in ["NodeTrunks", "NodeAshCrowns", "NodePineTiers", NodeProps.GLOW_LAYER]:
		check(NodeProps.cut_of(l) == 0.0, "%s: trees and glows are landmarks, seen as far as the haze allows" % l)
	root.free()


func test_stump_chunks_cost_nothing_until_something_is_felled() -> void:
	var nodes: Array = ResourceNodes.all()
	var root := NodeProps.build(nodes)
	for c in root.get_node("NodeStumps").get_children():
		check(not (c as Node3D).visible, "no stumps yet, so stump chunk %s is hidden" % c.name)
	for l in ["NodeTrunks", "NodeAshCrowns", "NodeStones", NodeProps.DETAIL_LAYER]:
		for c in root.get_node(l).get_children():
			check((c as Node3D).visible, "%s chunk %s is shown" % [l, c.name])
	var ash: Dictionary = nodes.filter(func(n): return n.kind == "ash" and int(n.get("tier", 1)) == 1)[0]
	var lay: Dictionary = root.get_meta("layout")
	var slot: Dictionary = lay.slots[ash.id]
	var stump_chunk := NodeProps.part_chunk(root, "NodeStumps", slot.depleted.filter(func(e): return e[0] == "NodeStumps")[0][1])
	var trunk_e: Array = slot.live.filter(func(e): return e[0] == "NodeTrunks")[0]
	NodeProps.set_depleted(root, ash.id, true)
	check(stump_chunk.visible, "felling an ash shows its stump chunk")
	check(not NodeProps.part_shown(root, trunk_e[0], trunk_e[1]), "its trunk is hidden")
	check(NodeProps.part_shown(root, "NodeStumps", slot.depleted[0][1]), "its stump is shown")
	NodeProps.set_depleted(root, ash.id, true) # twice is the same as once
	check_eq(int(stump_chunk.get_meta("shown")), 2, "one stump and its cut face shown, counted once")
	NodeProps.set_depleted(root, ash.id, false)
	check(not stump_chunk.visible, "regrown: the stump chunk is hidden again")
	check(NodeProps.part_shown(root, trunk_e[0], trunk_e[1]), "its trunk is back")
	check(NodeProps.part_chunk(root, trunk_e[0], trunk_e[1]).visible, "and its chunk shown")
	root.free()


func test_gather_feedback_still_works_on_chunks() -> void:
	var nodes: Array = ResourceNodes.all()
	var root := NodeProps.build(nodes)
	var id: int = nodes.filter(func(n): return n.kind == "pine")[0].id
	check(NodeProps.set_highlight(root, id, true), "highlight a chunked node")
	check_eq(NodeProps.highlighted(root), id, "it is lit")
	check(NodeProps.play_hit(root, id), "hit a chunked node")
	var fx := root.get_node("Fx") as NodeFx
	for i in 60:
		fx.advance(1.0 / 30.0) # shake writes go through put_xform into the node's chunk
	check(NodeProps.set_depleted(root, id, true), "deplete while lit")
	check(NodeProps.play_hit(root, id), "hit the stump")
	for i in 60:
		fx.advance(1.0 / 30.0)
	root.free()

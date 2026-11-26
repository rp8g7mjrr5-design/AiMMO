extends TestCase
## World stream: gathering feedback on resource nodes (NodeFx through NodeProps). The glow
## shell, the hit shake and the flying bits are pure maths, so this runs headless; the
## renderer side is checked by the client smoke test and close-up renders.


func _first_of(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func test_glow_shell_wraps_the_part() -> void:
	for p in NodeProps.parts(_first_of("ash")):
		var shell := NodeFx.shell_xform(p.xform)
		check(shell.origin.is_equal_approx(p.xform.origin), "shell centred on its part")
		check_near(shell.basis.get_scale().y / p.xform.basis.get_scale().y, NodeFx.SHELL_GROW, 0.001, "shell a little bigger")
	var most := 0
	for kind in ResourceNodes.KIND_ORDER:
		for depleted in [false, true]:
			var per := {}
			for p in NodeProps.parts(_first_of(kind), depleted):
				per[p.layer] = per.get(p.layer, 0) + 1
			for l in per:
				most = maxi(most, per[l])
	check(most <= NodeFx.SHELL_SLOTS, "every node fits the glow shell (%d parts in one layer)" % most)


func test_shake_rings_down_and_returns_to_rest() -> void:
	for kind in ResourceNodes.KIND_ORDER:
		var dur: float = NodeFx.SHAKE_TIME[kind]
		check(NodeFx.shake(kind, 0.0).is_equal_approx(Transform3D.IDENTITY), "%s still before the hit" % kind)
		check(NodeFx.shake(kind, dur).is_equal_approx(Transform3D.IDENTITY), "%s at rest after %.2f s" % [kind, dur])
		var moved := false
		var t := 0.01
		while t < dur:
			var m := NodeFx.shake(kind, t, 1.0)
			# Keep it subtle: the top of a 6 m tree moves at most ~30 cm, nothing lifts off.
			var top := m * Vector3(0, 6, 0)
			check(top.distance_to(Vector3(0, 6, 0)) < 0.35 or kind == "scrub", "%s shake is gentle at %.2f" % [kind, t])
			check((m * Vector3.ZERO).y >= -0.001, "%s base stays on the ground" % kind)
			if not m.is_equal_approx(Transform3D.IDENTITY):
				moved = true
			t += 0.03
		check(moved, "%s visibly reacts" % kind)


func test_each_kind_throws_its_own_bits() -> void:
	var colors := {}
	for kind in ResourceNodes.KIND_ORDER:
		var n := _first_of(kind)
		var bits := NodeFx.spawn_bits(n, 0)
		check_eq(bits.size(), NodeFx.BITS[kind], "%s bit count" % kind)
		colors[kind] = bits[1].color
		for b in bits:
			check(b.p0.y >= b.ground, "%s bit starts above ground" % kind)
			check(Vector2(b.p0.x - n.pos.x, b.p0.z - n.pos.z).length() < 2.5 * n.scale, "%s bit starts at its node" % kind)
	check(colors.ash != colors.pine and colors.pine != colors.stone and colors.stone != colors.scrub, "leaves, needles, chips and stalks look different")
	var stalks: Array = NodeFx.spawn_bits(_first_of("scrub"), 0)
	check(stalks.all(func(b): return b.glow == 0.0), "scrub stalks never glow (no magic)")


func test_bits_fly_land_and_vanish() -> void:
	for kind in ResourceNodes.KIND_ORDER:
		for b in NodeFx.spawn_bits(_first_of(kind), 3):
			var t := 0.0
			while t < b.life:
				var xf := NodeFx.bit_xform(b, t)
				check(xf.origin.y >= b.ground - 0.001, "%s bit never sinks" % kind)
				t += 0.05
			check(NodeFx.bit_xform(b, b.life).basis.get_scale().is_zero_approx(), "%s bit gone after its life" % kind)
			check(b.life <= 3.0, "%s bit is short-lived" % kind)
	var leaf: Dictionary = NodeFx.spawn_bits(_first_of("ash"), 0)[0]
	check(NodeFx.bit_xform(leaf, 0.8).origin.y < leaf.p0.y, "leaves fall")
	var chip: Dictionary = NodeFx.spawn_bits(_first_of("stone"), 0)[0]
	check(NodeFx.bit_xform(chip, 0.1).origin.y > chip.p0.y, "chips fly up first")


func test_hits_are_deterministic_but_vary() -> void:
	var n := _first_of("stone")
	var a := NodeFx.spawn_bits(n, 2)
	var b := NodeFx.spawn_bits(n, 2)
	var c := NodeFx.spawn_bits(n, 3)
	check(a[0].p0.is_equal_approx(b[0].p0) and a[0].v.is_equal_approx(b[0].v), "same hit, same bits")
	check(not a[0].v.is_equal_approx(c[0].v), "the next hit throws differently")


func test_layout_slots_know_their_node() -> void:
	var nodes := ResourceNodes.all()
	var lay := NodeProps.layout(nodes)
	for n in nodes:
		var slot: Dictionary = lay.slots[n.id]
		if slot.kind != n.kind or not (slot.pos as Vector3).is_equal_approx(n.pos) or slot.scale != n.scale:
			check(false, "slot %d carries its node's kind, pos and scale" % n.id)
			return

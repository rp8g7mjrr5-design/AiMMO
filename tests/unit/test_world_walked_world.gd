extends TestCase
## World stream: the art checks that eight bots used to repeat as they walked, run once here
## over the whole world instead (art bible section 7: bots cost only what players cost).
##
## The old `world_*` bot behaviours each built art (node props, gather bits, lanterns, the
## bench, avatars, flora, camera arms against the props) at whatever spots the bots happened
## to walk past. These tests cover every node, every flora spot, a full day of the clock, a
## few hundred avatar seeds and a grid of camera looks round the meadow, so they are
## stronger than the bots were and cost nothing in the 8-bot loop. What stays in the bot
## test is only what the network can get wrong (`world_ground_truth.gd`).
## Renderer-free: primitive meshes build their arrays headless.

const Cam := preload("res://client/action_camera.gd")
const ICON_SIZE := 24


# --- resource nodes (was world_resource_nodes, world_closeup, world_gather_fx) -----------

func test_every_node_has_a_live_and_a_depleted_look_on_its_spot() -> void:
	var lay := NodeProps.layout(ResourceNodes.all())
	check_eq(lay.slots.size(), ResourceNodes.count(), "one layout slot per node")
	for n in ResourceNodes.all():
		var live := NodeProps.parts(n, false)
		var dead := NodeProps.parts(n, true)
		if live.is_empty() or dead.is_empty():
			check(false, "node %d (%s) has no prop" % [n.id, n.kind])
			return
		if live.size() == dead.size() and live[0].layer == dead[0].layer and live[0].color == dead[0].color:
			check(false, "node %d (%s) looks the same depleted" % [n.id, n.kind])
			return
		var spread := 2.0 if NodeProps.tier_of(n) == 1 else 3.2 * float(n.scale) # the old ash is 3 m wide
		for p in live:
			var o: Vector3 = p.xform.origin
			if Vector2(o.x - n.pos.x, o.z - n.pos.z).length() > spread or o.y < n.pos.y - 0.05:
				check(false, "node %d (%s) prop is not standing on its spot" % [n.id, n.kind])
				return


func test_every_node_has_its_close_up_detail_inside_its_columns() -> void:
	var want := {"ash": 7, "pine": 7, "stone": 6, "scrub": 6}
	var checked := 0
	for n in ResourceNodes.all():
		var detail := NodeProps.parts(n).filter(func(p): return p.layer == NodeProps.DETAIL_LAYER)
		# A tier-2 node (the level-gated ring) has richer detail: at least tier 1's.
		var got := detail.size()
		if got != want[n.kind] and not (NodeProps.tier_of(n) >= 2 and got >= want[n.kind]):
			check(false, "%s node %d has %d detail parts, want %d" % [n.kind, n.id, got, want[n.kind]])
			return
		for p in detail:
			checked += 1
			if not NodeProps.inside_solid(p.xform.origin, n, 0.01):
				check(false, "node %d detail at %s is outside its solid columns" % [n.id, p.xform.origin])
				return
	check(checked > 1000, "checked %d detail parts" % checked)


func test_a_hit_on_every_node_plays_out_and_comes_to_rest() -> void:
	var bits := 0
	for n in ResourceNodes.all():
		for p in NodeProps.parts(n, false):
			if not NodeFx.shell_xform(p.xform).origin.is_equal_approx(p.xform.origin):
				check(false, "node %d glow shell is off its part" % n.id)
				return
		if not NodeFx.shake(n.kind, NodeFx.SHAKE_TIME[n.kind]).is_equal_approx(Transform3D.IDENTITY):
			check(false, "node %d (%s) does not come back to rest" % [n.id, n.kind])
			return
		var thrown := NodeFx.spawn_bits(n, int(n.id) + 1)
		if thrown.is_empty():
			check(false, "a hit on node %d (%s) throws nothing" % [n.id, n.kind])
			return
		for b in thrown:
			bits += 1
			var t := 0.0
			while t < b.life:
				var o := NodeFx.bit_xform(b, t).origin
				if o.y < b.ground - 0.001 or Vector2(o.x - n.pos.x, o.z - n.pos.z).length() > 6.0 * n.scale:
					check(false, "node %d (%s) bit strays to %s at %.2f s" % [n.id, n.kind, o, t])
					return
				t += 0.1
			if not NodeFx.bit_xform(b, b.life).basis.get_scale().is_zero_approx():
				check(false, "node %d (%s) bit outlives its life" % [n.id, n.kind])
				return
	check(bits > ResourceNodes.count(), "played %d bits" % bits)


# --- the camera (was world_closeup, world_deco_solids) ------------------------------------

## Where players stand: a 6 m grid over the meadow and its edge (bots wander within 60 m of
## spawn), plus a step off every node's four sides, where gatherers stop.
func _feet() -> Array:
	var out: Array = []
	var c := GameConfig.SPAWN_POINT
	for i in range(-10, 11):
		for j in range(-10, 11):
			var p := Vector3(c.x + i * 6.0, 0.0, c.z + j * 6.0)
			if Vector2(p.x - c.x, p.z - c.z).length() <= 60.0:
				out.append(p)
	for n in ResourceNodes.all():
		if Vector2(n.pos.x - c.x, n.pos.z - c.z).length() > 70.0:
			continue
		for d in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
			out.append(n.pos + d)
	for i in out.size():
		out[i] = Terrain.clamp_to_world(out[i])
	return out


func test_camera_never_ends_inside_a_prop_round_the_meadow() -> void:
	var looks := 0
	var height := Callable(Terrain, "height")
	for feet in _feet():
		var nodes := ResourceNodes.near(feet, Cam.DIST_MAX + 3.0)
		var both: Array = nodes + WorldSolids.near(feet, Cam.DIST_MAX + 3.0)
		for i in 8:
			var yaw := TAU * i / 8.0
			var shoulder := Cam.shoulder_point(feet, yaw, 1.0)
			var nodes_arm := Cam.clear_arm(shoulder, yaw, Cam.PITCH_DEFAULT, Cam.DIST_DEFAULT, height, nodes)
			var arm := Cam.clear_arm(shoulder, yaw, Cam.PITCH_DEFAULT, Cam.DIST_DEFAULT, height, both)
			if arm > nodes_arm + 0.0001:
				check(false, "adding decoration made the arm longer at %s (%.2f > %.2f)" % [feet, arm, nodes_arm])
				return
			# At ARM_MIN the player stands inside a footprint and no arm could clear it.
			if arm <= Cam.ARM_MIN:
				continue
			looks += 1
			var cam := Cam.camera_point(shoulder, yaw, Cam.PITCH_DEFAULT, arm)
			for s in both:
				if NodeProps.inside_solid(cam, s):
					check(false, "camera at %s is inside %s at %s" % [cam, s.get("source", s.kind), s.pos])
					return
	check(looks > 3000, "checked %d camera looks" % looks)


# --- lights by the clock (was world_lamps, world_bench_lantern) ---------------------------

func test_lamps_and_bench_lantern_follow_a_whole_day_of_the_server_clock() -> void:
	var world := Node3D.new()
	var bench := Workbench.build()
	world.add_child(bench)
	var omni := bench.get_node("Light") as OmniLight3D
	var lit := 0
	var step := WorldClock.DAY_SECONDS / 240.0 # every 10 real seconds of a 40 minute day
	for k in 241:
		var secs := 1000.0 + k * step
		var g := Lamps.night_glow(WorldClock.day_fraction(secs))
		if not is_finite(g) or g < 0.0 or g > 1.0:
			check(false, "lamp glow %s out of range at %s" % [g, WorldClock.describe(secs)])
			break
		var phase := WorldClock.phase(secs)
		var broad_day := phase == "day" and WorldClock.sun_elevation(secs) > 0.2
		if phase == "night" and g < 0.9:
			check(false, "lamps only %.2f lit at night (%s)" % [g, WorldClock.describe(secs)])
			break
		if broad_day and g > 0.5:
			check(false, "lamps %.2f lit in broad day (%s)" % [g, WorldClock.describe(secs)])
			break
		Lamps.apply_glow(world, g)
		if phase == "night" and not (omni.visible and omni.light_energy > 0.9 * Workbench.LIGHT_ENERGY):
			check(false, "bench lantern dark at night (%s)" % WorldClock.describe(secs))
			break
		if broad_day and omni.visible:
			check(false, "bench lantern lit in broad day (%s)" % WorldClock.describe(secs))
			break
		if omni.visible:
			lit += 1
	check(lit > 30 and lit < 200, "bench lantern lit for %d of 241 samples" % lit)
	world.free()


func test_bench_highlight_follows_whoever_stands_at_it() -> void:
	var bench := Workbench.build()
	var shell := bench.get_node("Highlight") as Node3D
	var at := Crafting.workbench_pos()
	for p in [at + Vector3(1.5, 0, 0), at + Vector3(40, 0, 0), at + Vector3(0, 0, -2), at + Vector3(0, 0, 30)]:
		var near := Crafting.near_bench(p)
		Workbench.set_highlight(bench, near)
		check_eq(shell.visible, near, "highlight %s at %s" % ["on" if near else "off", p])
		check_eq(Workbench.highlighted(bench), near, "bench knows its highlight")
	bench.free()


# --- avatars, flora, sky, icons (was world_avatar_limbs, world_flora, world_day_night,
# world_item_icons) ------------------------------------------------------------------------

func test_hundreds_of_avatars_have_limbs_a_pack_and_real_colours() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seeds: Array = []
	for i in 150:
		seeds.append(i)
		seeds.append(rng.randi())
	for s in seeds:
		var per_limb := {}
		var back := 0
		for p in AvatarBuilder.parts(s):
			var c: Color = p.color
			if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b)):
				check(false, "seed %d avatar has a broken colour" % s)
				return
			if p.limb != "":
				per_limb[p.limb] = per_limb.get(p.limb, 0) + 1
			elif p.pos.z < -0.2:
				back += 1
		for limb in AvatarBuilder.LIMBS:
			if per_limb.get(limb, 0) == 0:
				check(false, "seed %d avatar has no %s" % [s, limb])
				return
		if back != 2:
			check(false, "seed %d avatar has %d parts on its back, want pack and bedroll" % [s, back])
			return


func test_every_flora_spot_stands_on_open_ground_and_has_parts() -> void:
	for k in ["birch", "boulder", "flowers"]:
		check(Flora.count(k) > 0, "some %s in the world" % k)
	for s in Flora.spots():
		var p: Vector3 = s.pos
		if absf(p.y - Terrain.height(p.x, p.z)) > 0.05:
			check(false, "%s at %s floats or sinks" % [s.kind, p])
			return
		if not ResourceNodes.near(p, Flora.NODE_CLEARANCE).is_empty():
			check(false, "%s at %s stands on a resource node" % [s.kind, p])
			return
		if Flora.parts(s).is_empty():
			check(false, "%s at %s has no parts" % [s.kind, p])
			return


func test_sky_colours_are_sane_all_day() -> void:
	for k in 1001:
		var f := k / 1000.0
		var s := SkyClock.sample(f)
		for key in ["sky_top", "sky_horizon", "fog", "light_color"]:
			var c: Color = s[key]
			if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b)):
				check(false, "sky colour %s is broken at fraction %.3f" % [key, f])
				return
		if not is_finite(s.light_energy) or s.light_energy < 0.0:
			check(false, "light energy broken at fraction %.3f" % f)
			return


func test_pack_sized_icons_for_every_item_and_unknown_ids() -> void:
	var ids: Array = Inventory.ITEMS.keys()
	ids.append("not_an_item_yet")
	for item in ids:
		var tex := ItemIcons.texture(item, ICON_SIZE)
		if tex == null or tex.get_width() != ICON_SIZE:
			check(false, "no %d px icon for %s" % [ICON_SIZE, item])
			continue
		var img := ItemIcons.image(item, ICON_SIZE)
		var solid := 0
		var edge := 0.0
		for y in ICON_SIZE:
			for x in ICON_SIZE:
				var a := img.get_pixel(x, y).a
				if a > 0.5:
					solid += 1
				if x == 0 or y == 0 or x == ICON_SIZE - 1 or y == ICON_SIZE - 1:
					edge = maxf(edge, a)
		check(solid >= ICON_SIZE * ICON_SIZE / 10, "icon for %s is nearly empty (%d px)" % [item, solid])
		check(edge <= 0.2, "icon for %s is clipped at the edge" % item)
		if Inventory.is_item(item):
			check(ItemIcons.has_icon(item), "known item %s has its own icon, not the bundle" % item)

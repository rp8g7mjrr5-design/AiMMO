extends SceneTree
## Island biomes, photographed (not a test: it never fails, it only draws). Picks views on the
## version 3 island (pine hills seen from the lowland, into a marsh, across a meadow, and the
## view from a hilltop), then shoots those same spots on the generator `--gen` names, so a v2
## and a v3 run make before/after pairs:
##
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path game \
##     -s tests/client_smoke/biome_shots.gd -- --out=/abs/dir --gen=3 [--seed=1126] [--tag=after]

const W := 1600
const H := 900
const TIMES := {"noon": 0.5, "golden": 0.74, "night": 0.0}

var out := ""
var seed_v := 1126
var gen := 3
var tag := "shot"
var only_time := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--seed="):
			seed_v = a.substr(7).to_int()
		elif a.begins_with("--gen="):
			gen = a.substr(6).to_int()
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--time="):
			only_time = a.substr(7)
	DisplayServer.window_set_size(Vector2i(W, H))
	root.size = Vector2i(W, H)
	_run.call_deferred()


## Spots on a grid (every 30 m) where `want` is true, mid-island first.
func _find(want: Callable, skip: int = 0) -> Vector2:
	var half := WorldGen.half_size() - 60.0
	var found := 0
	var best := Vector2.INF
	var step := 30.0
	var n := int(half * 2.0 / step)
	var order: Array = []
	for j in n:
		for i in n:
			order.append(Vector2(-half + i * step, -half + j * step))
	# Middle of the island first (inland about 0.35): away from the heart's crags and the beach.
	var key := {}
	for p in order:
		key[p] = absf(WorldGen.inland(p.x, p.y) - 0.35)
	order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return key[a] < key[b])
	for p in order:
		if WorldGen.road_distance(p.x, p.y) < 10.0:
			continue
		if want.call(p, Terrain.height(p.x, p.y)):
			if found == skip:
				return p
			found += 1
	return best


func _biome(p: Vector2) -> String:
	return WorldGen.biome_at(p.x, p.y)


func _views() -> Dictionary:
	var v := {}
	# Pine hills from the lowland: a hill crest, seen from 140 m off on open ground.
	for skip in 12:
		var crest := _find(func(p: Vector2, h: float) -> bool: return _biome(p) == "pine_hills" and h > 22.0, skip * 3)
		if crest == Vector2.INF or v.has("hills"):
			break
		for k in 16:
			var from := crest + Vector2.from_angle(TAU * k / 16.0) * 130.0
			var b := _biome(from)
			if b != "pine_hills" and b != "shore" and b != "water" and Terrain.height(from.x, from.y) > 1.0 and Terrain.height(from.x, from.y) < Terrain.height(crest.x, crest.y) - 10.0:
				v["hills"] = [from, 2.2, crest, -6.0]
				break
	# Into a marsh, from its edge.
	var fen := _find(func(p: Vector2, h: float) -> bool:
		if _biome(p) != "marsh" or h > 1.0:
			return false
		var c := 0
		for k in 8:
			var q := p + Vector2.from_angle(TAU * k / 8.0) * 40.0
			if _biome(q) == "marsh":
				c += 1
		return c >= 7)
	if fen != Vector2.INF:
		for k in 16:
			var from := fen + Vector2.from_angle(TAU * k / 16.0) * 55.0
			if Terrain.height(from.x, from.y) > 0.6:
				v["marsh"] = [from, 2.2, fen, 0.5]
				break
	# Across a meadow toward whatever rises beyond it.
	var mead := _find(func(p: Vector2, h: float) -> bool:
		if _biome(p) != "farmland":
			return false
		for k in 8:
			if _biome(p + Vector2.from_angle(TAU * k / 8.0) * 50.0) != "farmland":
				return false
		return true, 2)
	if mead != Vector2.INF:
		var heart := Vector2.ZERO
		v["meadow"] = [mead, 2.2, mead + (heart - mead).normalized() * 200.0, 4.0]
	# Down in a valley between the pine hills, looking at the nearest tall crest.
	var low := _find(func(p: Vector2, h: float) -> bool:
		if _biome(p) != "pine_hills" or h > 16.0:
			return false
		for k in 8:
			var q := p + Vector2.from_angle(TAU * k / 8.0) * 90.0
			if Terrain.height(q.x, q.y) > h + 14.0:
				return true
		return false, 1)
	if low != Vector2.INF:
		var best := low
		for k in 24:
			var q := low + Vector2.from_angle(TAU * k / 24.0) * 90.0
			if Terrain.height(q.x, q.y) > Terrain.height(best.x, best.y):
				best = q
		v["valley"] = [low, 2.2, best, -4.0]
	# From a hilltop, looking in toward the heart's crags.
	var top := _find(func(p: Vector2, h: float) -> bool: return _biome(p) == "pine_hills" and h > 30.0, 0)
	if top != Vector2.INF:
		var heart: Vector2 = WorldGen._L.heart
		v["hilltop"] = [top, 3.0, top + (heart - top).normalized() * 300.0, 0.0]
	return v


func _run() -> void:
	WorldGen.configure(seed_v, 3000.0, WorldGen.ISLAND_HILLS)
	var views := _views()
	print("[biome_shots] views: ", views)
	WorldGen.configure(seed_v, 3000.0, gen)
	ResourceNodes.reset()
	DayNight.pinned_fraction = 0.5
	var world := WorldBuilder.build()
	root.add_child(world)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 1200.0
	root.add_child(cam)
	cam.make_current()
	var dn: DayNight = world.get_node("DayNight")
	for name in views:
		var spec: Array = views[name]
		var f2: Vector2 = spec[0]
		var t2: Vector2 = spec[2]
		var from := Vector3(f2.x, maxf(Terrain.height(f2.x, f2.y), 0.0) + float(spec[1]), f2.y)
		var to := Vector3(t2.x, maxf(Terrain.height(t2.x, t2.y), 0.0) + float(spec[3]), t2.y)
		cam.look_at_from_position(from, to, Vector3.UP)
		# Let the streamed ground catch up with the camera before any shot of this view.
		for node in world.find_children("*", "", true, false):
			if not node is TerrainStream:
				continue
			var ts: TerrainStream = node
			ts.rethink(from)
			# The ground within 300 m, built here and now (the thread streams on beyond it).
			for c in ts.cells_within(from, 300.0):
				if not ts.is_built(c):
					ts._add(c, TerrainMesh.build_chunk(ts.corner(c).x, ts.corner(c).y))
		for t in TIMES:
			if only_time != "" and t != only_time:
				continue
			DayNight.pinned_fraction = TIMES[t]
			dn.apply(TIMES[t])
			for i in 90:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(out)
			img.save_png(out.path_join("%s-%s-%s.png" % [tag, name, t]))
			print("[biome_shots] saved ", tag, "-", name, "-", t)
	quit(0)

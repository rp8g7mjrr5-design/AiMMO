class_name CampfireProps
## The look of a placed campfire (gameplay's `Campfires`, Phase 2 build-ahead; `docs/vision.md`:
## "torches keep the Gloam wary"). The first warm place in a dark world: a ring of
## fire-blackened field stones round a pale ash bed, split logs leaned into a low cone, a
## bed of coals and three tongues of flame that flicker, and one short warm light pool.
##
## A fire has three looks, all from the time it has left (`state()`):
## - "lit": tall flames, logs leaned in, coals glowing, a warm pool of light;
## - "low" (the last LOW_FRACTION of its burn): the logs have slumped, the flames are half as
##   tall and the light dims, so you can see from across the clearing that it is going out;
## - "ash": burned out. Three charred stubs on a wide grey ash bed in the stone ring, the coals
##   barely warm, no flame and no light. The server drops a fire when it goes out; `sync()`
##   keeps a fire that went out on its own as ash for ASH_SECONDS, so the place you camped stays
##   marked for a while.
##
## Pooled like NodeFx (art bible section 7): `build()` makes one hidden "Campfires" node with
## three MultiMesh layers sized for `Campfires.MAX_FIRES` and LIGHT_POOL lights, on the shared
## Emberlight materials (stones on `solid`; logs, coals and flames on the veins' `glow`, with
## the glow carried in instance alpha), so no material is new and nothing is created or freed
## while playing. With no fire anywhere the node is hidden and draws nothing.
##
## Client use: WorldBuilder adds the node. On every `s2c_campfires` the client calls
## `CampfireProps.sync(world.get_node("Campfires"), CampfireProps.from_wire(data), player_pos)`,
## and now and then `follow(node, player_pos)` so the few lights sit on the nearest fires.
## DayNight drives the rest from the shared clock: `Lamps.apply_glow` brightens the light pools
## at night and `Lamps.flicker_lights` calls `animate()` every frame (flames and light flicker,
## lit -> low -> ash on the local clock between server updates).
##
## `parts()`, `state()`, `light_energy()`, `flame_xform()` and `from_wire()` are pure data
## (safe headless, unit tested).

const NODE_NAME := "Campfires"
const LAYERS := ["FireStones", "FireLogs", "FireFlames"]
## Instances one fire uses at most in each layer (pool size = this x Campfires.MAX_FIRES).
const PER_FIRE := {"FireStones": 9, "FireLogs": 4, "FireFlames": 8}

const RING_STONES := 8
const RING_RADIUS := 0.55 ## metres from the fire's centre to the middle of a ring stone
const LOG_COUNT := 4
const LOG_LENGTH := 0.62
const LOG_RADIUS := 0.065
const LOG_FOOT := 0.34 ## metres from the centre where a log's foot rests
const LOG_LEAN := 0.95 ## radians from upright: logs lean well in, a low cone, not a tall teepee
const COALS := 5

## The flame tongues: [height m, width m, offset from centre (local x, z)]. The tallest is
## about knee height: a cooking fire, not a bonfire.
const TONGUES := [[0.58, 0.30, Vector2(0.0, 0.0)], [0.42, 0.24, Vector2(0.1, 0.06)], [0.36, 0.22, Vector2(-0.09, -0.07)]]
const LOW_FLAME := 0.45 ## a low fire's flames are this much of a lit fire's
const LOW_FRACTION := 0.15 ## the last 15% of a burn (36 world minutes of its 4 hours) is "low"
const ASH_SECONDS := 120.0 ## real seconds a burned-out fire stays as ash

## How much each kind glows (instance alpha below 1 is the Emberlight vein; 1 - alpha = glow).
const GLOW_FLAME := 0.0 ## a flame is all glow
const GLOW_COAL := {"lit": 0.35, "low": 0.5, "ash": 0.93}
const GLOW_LOG := {"lit": 0.96, "low": 0.93, "ash": 1.0} ## only a hint of warmth: the logs are wood, not glow

## The light pool. A fire lights the ground round it like a lantern does, a little warmer and
## lower; by day the light is faint (the flame still glows).
const LIGHT_POOL := 3 ## fires that carry a light at once (the nearest lit ones); the rest only glow
const LIGHT_HEIGHT := 0.55
const LIGHT_DAY := 0.5
const LIGHT_NIGHT := 2.3
const LIGHT_LOW := 0.5 ## a low fire's light is this much of a lit fire's
const LIGHT_RANGE := 7.5
const LIGHT_ATTENUATION := 2.0
const LIGHT_FLICKER := 2.0 ## a fire breathes twice as deep as a lantern flame (Lamps.flicker)
const LIGHT_INDEX := 64 ## Lamps.flicker offsets: clear of the lanterns, bench and seeps
## Flames: height swings +- this much, three waves a tongue, never in step.
const FLAME_FLICKER := 0.16
const FLAME_SWAY := 0.10 ## radians a tongue leans in the draught
const REFRESH := 0.5 ## seconds between checks for a fire turning low or going out


## The look a fire has with `left` real seconds still to burn.
static func state(left: float) -> String:
	if left <= 0.0:
		return "ash"
	if left < Campfires.burn_seconds() * LOW_FRACTION:
		return "low"
	return "lit"


## A fire's light energy for a state and night-glow level (Lamps.night_glow: 0 day, 1 night).
static func light_energy(st: String, glow: float) -> float:
	if st == "ash":
		return 0.0
	var e := lerpf(LIGHT_DAY, LIGHT_NIGHT, clampf(glow, 0.0, 1.0))
	return e * (LIGHT_LOW if st == "low" else 1.0)


## `s2c_campfires`' payload ([id, x, y, z, seconds_left] per fire, `Campfires.to_wire`) as
## an Array of {id, pos, left}. A short or ragged array gives the whole fires it holds.
static func from_wire(data: PackedFloat32Array) -> Array:
	var out: Array = []
	var i := 0
	while i + 5 <= data.size():
		out.append({"id": int(data[i]), "pos": Vector3(data[i + 1], data[i + 2], data[i + 3]), "left": float(data[i + 4])})
		i += 5
	return out


## A flame tongue's transform: a cone `w` wide and `h` tall standing on `base`, leaning `lean`
## radians towards local yaw `dir`. The cone grows from its foot, so a flicker never lifts it
## off the coals.
static func flame_xform(base: Vector3, h: float, w: float, dir: float, lean: float) -> Transform3D:
	var tilt := Basis(Vector3.UP, dir) * Basis(Vector3.RIGHT, lean) * Basis(Vector3.UP, -dir)
	var b := tilt * Basis.from_scale(Vector3(w, h, w))
	return Transform3D(b, base + tilt * Vector3(0.0, h * 0.5, 0.0))


## A flame tongue `f` ({base, h, w, dir, phase}, as `parts()` gives it) at world time
## `seconds`: three waves on its height (never in step with another tongue's) and a slow lean,
## thinner as it stretches, its foot always on the coals.
static func flicker_xform(f: Dictionary, seconds: float) -> Transform3D:
	var ph: float = f.phase
	var k := 1.0 + FLAME_FLICKER * (0.55 * sin(seconds * 9.1 + ph) + 0.3 * sin(seconds * 15.7 + ph * 2.0) + 0.15 * sin(seconds * 4.3 + ph * 3.0))
	var lean := FLAME_SWAY * sin(seconds * 3.3 + ph)
	return flame_xform(f.base, float(f.h) * k, float(f.w) * (1.0 - 0.4 * (k - 1.0)), float(f.dir), lean)


## Every part of one fire in world space: Array of {layer, kind, xform, color}, where `fire`
## is {id, pos} and `st` its state. `kind` is stone, bed, log, stub, coal or flame; colour
## alpha below 1 glows (the Emberlight vein). Flames carry `base`, `h`, `w`, `dir` and `phase`
## so animate() can flicker them. Deterministic per fire id.
static func parts(fire: Dictionary, st: String = "lit") -> Array:
	var out: Array = []
	var origin: Vector3 = fire.pos
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(fire.id) * 7919 + 17)
	var turn := rng.randf() * TAU
	var spin := Basis(Vector3.UP, turn)
	var ground := func(local: Vector3) -> float:
		var w := origin + spin * local
		return Terrain.height(w.x, w.z)
	var add := func(layer: String, kind: String, xform: Transform3D, color: Color) -> void:
		out.append({"layer": layer, "kind": kind, "xform": xform, "color": color})
	# The ring: eight field stones, each its own size and lean, sunk a little into the ground.
	for i in RING_STONES:
		var a := TAU * i / RING_STONES + rng.randf_range(-0.12, 0.12)
		var r := RING_RADIUS + rng.randf_range(-0.04, 0.05)
		var local := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var size := Vector3(rng.randf_range(0.24, 0.32), rng.randf_range(0.11, 0.16), rng.randf_range(0.18, 0.25))
		var g: float = ground.call(local)
		var b := spin * Basis(Vector3.UP, -a + rng.randf_range(-0.3, 0.3)) * Basis(Vector3.FORWARD, rng.randf_range(-0.25, 0.25))
		var col := Palette.FIRE_STONE_SOOT if (i + int(fire.id)) % 3 == 0 else Palette.FIRE_STONE.darkened(rng.randf_range(0.0, 0.1))
		add.call("FireStones", "stone", Transform3D(b * Basis.from_scale(size), Vector3(origin.x, g, origin.z) + spin * local + Vector3(0, size.y * 0.5 - 0.04, 0)), col)
	# The ash bed inside the ring: wider and paler once the fire is out.
	var bed_r := 0.82 if st == "ash" else 0.7
	var bed_col := Palette.FIRE_ASH if st == "ash" else Palette.FIRE_ASH.darkened(0.25)
	add.call("FireStones", "bed", Transform3D(spin * Basis.from_scale(Vector3(bed_r, 0.05, bed_r)), origin), bed_col)
	# Logs: leaned into a low cone while it burns, slumped when low, charred stubs when out.
	if st == "ash":
		for i in 3:
			var a := TAU * i / 3.0 + rng.randf_range(-0.4, 0.4)
			var stub := rng.randf_range(0.22, 0.32)
			var b := spin * Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(LOG_RADIUS * 1.7, stub, LOG_RADIUS * 1.7))
			add.call("FireLogs", "stub", Transform3D(b, origin + spin * Vector3(cos(a) * 0.12, 0.05, sin(a) * 0.12)), Color(Palette.FIRE_CHAR, GLOW_LOG.ash))
	else:
		var low := st == "low"
		var lean := LOG_LEAN + (0.35 if low else 0.0)
		var length := LOG_LENGTH * (0.7 if low else 1.0)
		for i in LOG_COUNT:
			var a := TAU * (i + 0.5) / LOG_COUNT + rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0.0, sin(a))
			# Lean the log's top in towards the centre: rotate about the horizontal axis
			# across its direction (up x dir), by `lean` from upright.
			var axis := Vector3.UP.cross(dir).normalized()
			var b := spin * Basis(axis, -lean) * Basis.from_scale(Vector3(LOG_RADIUS * 2.0, length, LOG_RADIUS * 2.0))
			var up := spin * (Basis(axis, -lean) * Vector3.UP)
			var foot := origin + spin * (dir * LOG_FOOT * (0.85 if low else 1.0)) + Vector3(0, 0.04, 0)
			add.call("FireLogs", "log", Transform3D(b, foot + up * length * 0.5), Color(Palette.FIRE_LOG.darkened(0.08 * (i % 2)), GLOW_LOG[st]))
	# Coals: a few squat glowing lumps in the middle.
	for i in COALS:
		var a := TAU * i / COALS + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(0.05, 0.2)
		var w := rng.randf_range(0.09, 0.14)
		add.call("FireFlames", "coal", Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(w, w * 0.55, w * 0.8)),
			origin + spin * Vector3(cos(a) * r, 0.03, sin(a) * r)), Color(Palette.SMOULDER, GLOW_COAL[st]))
	# Flames: three tongues from the coals, none while it is out.
	if st != "ash":
		var k := LOW_FLAME if st == "low" else 1.0
		for t in TONGUES:
			var off: Vector2 = t[2]
			var base := origin + spin * Vector3(off.x, 0.04, off.y)
			var h: float = float(t[0]) * k
			var w: float = float(t[1]) * lerpf(1.0, k, 0.5)
			var dir := turn + rng.randf() * TAU
			var p := {"layer": "FireFlames", "kind": "flame", "xform": flame_xform(base, h, w, dir, 0.0),
				"color": Color(Palette.EMBER, GLOW_FLAME), "base": base, "h": h, "w": w, "dir": dir, "phase": rng.randf() * TAU}
			out.append(p)
	return out


## The hidden, empty "Campfires" node WorldBuilder adds.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	root.visible = false
	var meshes := _meshes()
	for l in LAYERS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[l]
		mm.instance_count = int(PER_FIRE[l]) * Campfires.MAX_FIRES
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = l
		mmi.multimesh = mm
		mmi.material_override = Emberlight.material("solid") if l == "FireStones" else Emberlight.material("glow")
		# Low to the ground: a shadow would cost a draw per pass and show nothing worth it.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	var lights := Node3D.new()
	lights.name = "Lights"
	root.add_child(lights)
	for i in LIGHT_POOL:
		var omni := OmniLight3D.new()
		omni.name = "Fire%d" % i
		omni.light_color = Lamps.FLAME
		omni.light_energy = 0.0
		omni.omni_range = LIGHT_RANGE
		omni.omni_attenuation = LIGHT_ATTENUATION
		omni.shadow_enabled = false
		omni.visible = false
		lights.add_child(omni)
	root.set_meta("fires", {})
	root.set_meta("glow", 0.0)
	root.set_meta("near", Vector3.INF)
	return root


## Show the fires the server says are burning: `fires` is Array of {id, pos, left} (see
## `from_wire`). A fire that drops out of the list after it had turned low stays as ash for
## ASH_SECONDS; one that vanishes while still burning (a restart) just goes. `near` is where
## the player stands (the nearest fires get the lights). `now` is real seconds (default: the
## engine clock). Safe on null.
static func sync(node: Node, fires: Array, near: Vector3 = Vector3.INF, now: float = -1.0) -> void:
	if node == null:
		return
	if now < 0.0:
		now = _clock()
	var known: Dictionary = node.get_meta("fires", {})
	var next := {}
	for f in fires:
		var id := int(f.id)
		next[id] = {"id": id, "pos": f.pos, "out_at": now + float(f.left), "ash_until": -1.0}
	for id in known:
		if next.has(id):
			continue
		var old: Dictionary = known[id]
		if float(old.ash_until) >= 0.0:
			next[id] = old # already ash: keeps its time
		elif _state_at(old, now) != "lit":
			var ash := old.duplicate()
			ash.ash_until = now + ASH_SECONDS
			next[id] = ash
	node.set_meta("fires", next)
	if near != Vector3.INF:
		node.set_meta("near", near)
	_redraw(node, now)


## Move the lights to the fires nearest `near` (call now and then as the player walks). Only
## redraws when there are more burning fires than lights. Safe on null.
static func follow(node: Node, near: Vector3) -> void:
	if node == null:
		return
	node.set_meta("near", near)
	if int(node.get_meta("burning", 0)) > LIGHT_POOL:
		_redraw(node, _clock())


## The night-glow level from the shared clock (Lamps.apply_glow passes it on). Safe on null.
static func apply_glow(node: Node, glow: float) -> void:
	if node == null:
		return
	node.set_meta("glow", clampf(glow, 0.0, 1.0))
	_light(node)


## Every frame (Lamps.flicker_lights): the flames and their light flicker, and every REFRESH
## seconds a fire that turned low or went out on the local clock is redrawn. Does nothing while
## no fire is shown. `seconds` is world time (only the flicker uses it).
static func animate(node: Node, seconds: float) -> void:
	if node == null or not (node as Node3D).visible:
		return
	var now := _clock()
	if now >= float(node.get_meta("next_check", 0.0)):
		node.set_meta("next_check", now + REFRESH)
		if _changed(node, now):
			_redraw(node, now)
	var flames := node.get_node_or_null("FireFlames") as MultiMeshInstance3D
	if flames:
		var mm := flames.multimesh
		for f in node.get_meta("flames", []):
			mm.set_instance_transform(int(f.index), flicker_xform(f, seconds))
	var lights := node.get_node_or_null("Lights")
	if lights:
		var i := 0
		for omni in lights.get_children():
			var o := omni as OmniLight3D
			if o.visible and o.has_meta("steady_energy"):
				o.light_energy = float(o.get_meta("steady_energy")) * (1.0 + LIGHT_FLICKER * (Lamps.flicker(seconds, LIGHT_INDEX + i) - 1.0))
			i += 1


## How many fires (burning or ash) the node shows now.
static func shown(node: Node) -> int:
	return 0 if node == null else int(node.get_meta("shown", 0))


static func _clock() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _state_at(entry: Dictionary, now: float) -> String:
	if float(entry.ash_until) >= 0.0:
		return "ash"
	return state(float(entry.out_at) - now)


## True if any fire's look changed since it was drawn, or an ash ran out.
static func _changed(node: Node, now: float) -> bool:
	var drawn: Dictionary = node.get_meta("drawn", {})
	var fires: Dictionary = node.get_meta("fires", {})
	for id in fires:
		var e: Dictionary = fires[id]
		if float(e.ash_until) >= 0.0 and now > float(e.ash_until):
			return true
		if drawn.get(id, "") != _state_at(e, now):
			return true
	return false


## The fires to draw, in order: burning ones by id, then ashes, newest first; at most the pool.
static func _order(fires: Dictionary, now: float) -> Array:
	var burning: Array = []
	var ashes: Array = []
	for id in fires:
		var e: Dictionary = fires[id]
		if _state_at(e, now) == "ash":
			ashes.append(e)
		else:
			burning.append(e)
	burning.sort_custom(func(a, b): return int(a.id) < int(b.id))
	ashes.sort_custom(func(a, b): return float(a.get("ash_until", 0.0)) > float(b.get("ash_until", 0.0)))
	return (burning + ashes).slice(0, Campfires.MAX_FIRES)


static func _redraw(node: Node, now: float) -> void:
	var fires: Dictionary = node.get_meta("fires", {})
	# Ashes that have had their time go; a fire that went out on the local clock turns to ash.
	for id in fires.keys():
		var e: Dictionary = fires[id]
		if float(e.ash_until) >= 0.0 and now > float(e.ash_until):
			fires.erase(id)
		elif float(e.ash_until) < 0.0 and now >= float(e.out_at):
			e.ash_until = now + ASH_SECONDS
	var order := _order(fires, now)
	var lay := {}
	for l in LAYERS:
		lay[l] = []
	var flames: Array = []
	var drawn := {}
	var burning: Array = []
	for e in order:
		var st := _state_at(e, now)
		drawn[e.id] = st
		if st != "ash":
			burning.append({"pos": e.pos, "state": st})
		for p in parts(e, st):
			if p.kind == "flame":
				flames.append({"index": lay[p.layer].size(), "base": p.base, "h": p.h, "w": p.w, "dir": p.dir, "phase": p.phase})
			lay[p.layer].append([p.xform, p.color])
	for l in LAYERS:
		var mmi := node.get_node_or_null(l) as MultiMeshInstance3D
		if mmi == null:
			continue
		var mm := mmi.multimesh
		var items: Array = lay[l]
		var n := mini(items.size(), mm.instance_count)
		for i in n:
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, Color((items[i][1] as Color).srgb_to_linear(), (items[i][1] as Color).a))
		mm.visible_instance_count = n
	node.set_meta("flames", flames)
	node.set_meta("drawn", drawn)
	node.set_meta("shown", order.size())
	node.set_meta("burning", burning.size())
	# Lights on the burning fires nearest the player (by id order when we don't know where they are).
	var near: Vector3 = node.get_meta("near", Vector3.INF)
	if near != Vector3.INF:
		burning.sort_custom(func(a, b): return (a.pos as Vector3).distance_squared_to(near) < (b.pos as Vector3).distance_squared_to(near))
	node.set_meta("lit_fires", burning.slice(0, LIGHT_POOL))
	(node as Node3D).visible = not order.is_empty()
	_light(node)


## Put the light pool on the lit fires for the current glow level.
static func _light(node: Node) -> void:
	var lights := node.get_node_or_null("Lights")
	if lights == null:
		return
	var lit: Array = node.get_meta("lit_fires", [])
	var glow := float(node.get_meta("glow", 0.0))
	var i := 0
	for omni in lights.get_children():
		var o := omni as OmniLight3D
		if i < lit.size():
			var e := light_energy(lit[i].state, glow)
			o.position = (lit[i].pos as Vector3) + Vector3(0, LIGHT_HEIGHT, 0)
			o.set_meta("steady_energy", e)
			o.light_energy = e
			o.visible = e > 0.01
		else:
			o.visible = false
			o.set_meta("steady_energy", 0.0)
		i += 1


static func _meshes() -> Dictionary:
	var stone := CylinderMesh.new() # a squat, faceted field stone, narrower on top
	stone.top_radius = 0.34
	stone.bottom_radius = 0.5
	stone.height = 1.0
	stone.radial_segments = 6
	stone.rings = 1
	var wood := CylinderMesh.new()
	wood.top_radius = 0.5
	wood.bottom_radius = 0.5
	wood.height = 1.0
	wood.radial_segments = 6
	wood.rings = 1
	var cone := CylinderMesh.new() # a flame tongue, and squashed flat, a coal
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 1
	return {"FireStones": Emberlight.bake(stone, 0.35, 1.4), "FireLogs": Emberlight.bake(wood, 0.25), "FireFlames": Emberlight.bake(cone, 0.0)}

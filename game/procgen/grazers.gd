class_name Grazers
## The grazers' look (Milestone 2 build-ahead, gameplay's `Wildlife`): small, deer-like herd
## animals on Emberlight's shared `solid` material. A warm fawn coat with a cream belly and a
## pale rump, dark hooves and muzzle, tall ears. They graze head down, look up at you with
## their ears forward, amble and trot on a diagonal gait, bound when they bolt and lie folded
## at night.
##
## The fun it is for: the land past the meadow is alive, and you can read a herd at a glance.
## Heads down means creep closer; a head snapping up means freeze; a bounding white rump
## going over the hill means you rushed it.
##
## How it draws: every grazer is three MultiMesh layers (body, head-and-neck, legs; four leg
## instances per grazer), so the whole valley's herds cost three draw calls no matter how
## many are in view, and nothing is built or freed as grazers come and go. Poses are
## per-instance transforms computed on the CPU each frame (about 20 grazers, six transforms
## each); the material is the one every prop uses, so the material count does not move.
##
## Client use (three calls, all static):
##   var herds := Grazers.build()        # once; add it under the world
##   Grazers.feed(herds, entries)        # on every net.wildlife_changed(entries)
##   Grazers.tick(herds, delta)          # every frame
## `feed` takes the wire list as it arrives ([id, x, z, yaw, state_index] per grazer, see
## `Wildlife.WIRE_STRIDE`) and smooths between the ~5 updates a second itself: positions and
## facing glide, the legs move at the speed the body really travels, and a pose change (head
## down to head up) blends instead of snapping. A grazer missing from a non-empty list, or an
## empty list, takes it away.
##
## Everything the grazer looks like is pure maths in static functions (`pieces`, `pose_for`,
## `xforms`), so unit tests check the shape headless without a renderer.

const CAPACITY := 48 ## grazers drawn at once; today's world has 21 (Wildlife.describe())
const LEGS := 4
## Leg hips in the body's space (left is +X, front is +Z), legs hang LEG_LENGTH below them.
const HIPS := [Vector3(0.15, 0.86, 0.40), Vector3(-0.15, 0.86, 0.40),
	Vector3(0.14, 0.88, -0.42), Vector3(-0.14, 0.88, -0.42)]
const LEG_LENGTH := 0.86
const NECK_PIVOT := Vector3(0.0, 1.08, 0.50) ## where the head-and-neck layer turns (pitch)
const SHOULDER := 1.2 ## standing height at the withers, roughly (a small deer)

## Smoothing between server updates (they come ~5 a second).
const FOLLOW_RATE := 7.0 ## how fast the drawn position closes on the latest one, per second
const TURN_RATE := 6.0
const SNAP_DISTANCE := 12.0 ## further than this from where it was drawn: jump, don't glide
const POSE_RATE := 5.0 ## pose blending per second
const ALERT_RATE := 14.0 ## the head snaps up fast: that's the "freeze now" cue
const STRIDE := 1.5 ## metres per full gait cycle when walking; legs never slide on the ground
const BOUND := 3.6 ## metres per bound when fleeing


## Every piece of the three layers as {layer, shape, size, color, pos, rot, ao}. `size` is
## the shape's scale: sphere radii and box half-extents; cone radius, -, length; cylinder
## ("cyl") top radius, bottom radius, length.
## Positions are in the layer's own space: the body around the creature's origin (feet at
## y 0, facing +Z), the head around `NECK_PIVOT`, the leg around its hip (hanging down -Y).
static func pieces() -> Array:
	var coat := Palette.GRAZER_COAT
	var belly := Palette.GRAZER_BELLY
	var dark := Palette.GRAZER_DARK
	var out: Array = []
	# Body: a long barrel, a cream belly under it, the pale rump patch and a short tail.
	out.append(_pc("body", "sphere", Vector3(0.27, 0.27, 0.62), coat, Vector3(0, 1.0, -0.02), Vector3.ZERO, 0.30))
	out.append(_pc("body", "sphere", Vector3(0.21, 0.13, 0.50), belly, Vector3(0, 0.86, 0.0), Vector3.ZERO, 0.0))
	out.append(_pc("body", "sphere", Vector3(0.22, 0.22, 0.14), belly, Vector3(0, 1.05, -0.56), Vector3.ZERO, 0.0))
	out.append(_pc("body", "sphere", Vector3(0.22, 0.24, 0.26), coat, Vector3(0, 1.06, 0.40), Vector3.ZERO, 0.25))
	out.append(_pc("body", "cone", Vector3(0.07, 0.0, 0.20), belly, Vector3(0, 1.15, -0.66), Vector3(-2.2, 0, 0), 0.0))
	# Head and neck, around the neck pivot: the neck rises forward, the head points ahead and
	# a little down, ears up and out, a dark muzzle and eyes.
	out.append(_pc("head", "cyl", Vector3(0.09, 0.15, 0.56), coat, Vector3(0, 0.22, 0.12), Vector3(0.55, 0, 0), 0.15))
	out.append(_pc("head", "sphere", Vector3(0.12, 0.13, 0.17), coat, Vector3(0, 0.47, 0.30), Vector3(0.35, 0, 0), 0.0))
	out.append(_pc("head", "sphere", Vector3(0.08, 0.08, 0.13), coat, Vector3(0, 0.42, 0.44), Vector3(0.35, 0, 0), 0.0))
	out.append(_pc("head", "box", Vector3(0.05, 0.045, 0.045), dark, Vector3(0, 0.38, 0.55), Vector3.ZERO, 0.0))
	for side in [1.0, -1.0]:
		out.append(_pc("head", "cone", Vector3(0.05, 0.0, 0.20), coat, Vector3(0.10 * side, 0.60, 0.25), Vector3(-0.25, 0, -0.75 * side), 0.0))
		out.append(_pc("head", "box", Vector3(0.035, 0.035, 0.03), dark, Vector3(0.095 * side, 0.50, 0.38), Vector3.ZERO, 0.0))
	# A leg: a slim thigh, a thinner shank and a dark hoof at the ground.
	out.append(_pc("leg", "cyl", Vector3(0.07, 0.045, 0.40), coat, Vector3(0, -0.20, 0), Vector3.ZERO, 0.0))
	out.append(_pc("leg", "cyl", Vector3(0.04, 0.032, 0.42), coat, Vector3(0, -0.60, 0), Vector3.ZERO, 0.15))
	out.append(_pc("leg", "cyl", Vector3(0.04, 0.045, 0.08), dark, Vector3(0, -0.82, 0.01), Vector3.ZERO, 0.0))
	return out


static func _pc(layer: String, shape: String, size: Vector3, color: Color, pos: Vector3, rot: Vector3, ao: float) -> Dictionary:
	return {"layer": layer, "shape": shape, "size": size, "color": color, "pos": pos, "rot": rot, "ao": ao}


static var _mesh_cache: Dictionary = {}


## The three baked meshes {body, head, leg}, built once: every piece painted into vertex
## colours (`Emberlight.paint`) and merged, so each layer is one mesh on the shared material.
static func meshes() -> Dictionary:
	if _mesh_cache.is_empty():
		var by_layer := {"body": [], "head": [], "leg": []}
		for p in pieces():
			by_layer[p.layer].append(p)
		for l in by_layer:
			_mesh_cache[l] = _merge(by_layer[l])
	return _mesh_cache


static func _primitive(p: Dictionary) -> Mesh:
	var s: Vector3 = p.size
	match str(p.shape):
		"sphere":
			var m := SphereMesh.new()
			m.radius = 1.0
			m.height = 2.0
			m.radial_segments = 6
			m.rings = 3
			return m
		"box":
			var b := BoxMesh.new()
			b.size = Vector3(2, 2, 2)
			return b
		"cone":
			var c := CylinderMesh.new() # a pointed cone along +Y: radius s.x, length s.z
			c.top_radius = 0.0
			c.bottom_radius = 1.0
			c.height = 1.0
			c.radial_segments = 4
			c.rings = 0
			return c
		_:
			var y := CylinderMesh.new()
			y.top_radius = 1.0
			y.bottom_radius = s.y / maxf(s.x, 0.001)
			y.height = 1.0
			y.radial_segments = 5
			y.rings = 0
			return y


static func _scale_of(p: Dictionary) -> Vector3:
	var s: Vector3 = p.size
	match str(p.shape):
		"sphere", "box":
			return s
		"cone":
			return Vector3(s.x, s.z, s.x * 0.6) # flattened front to back: ears and tail read as blades
		_:
			return Vector3(s.x, s.z, s.x)


static func _merge(list: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	for p in list:
		var painted := Emberlight.paint(_primitive(p), p.color, p.ao)
		var a := painted.surface_get_arrays(0)
		var xf := Transform3D(Basis.from_euler(p.rot) * Basis.from_scale(_scale_of(p)), p.pos)
		var nb := xf.basis.inverse().transposed()
		var base := verts.size()
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var pc: PackedColorArray = a[Mesh.ARRAY_COLOR]
		for i in pv.size():
			verts.append(xf * pv[i])
			normals.append((nb * pn[i]).normalized())
			colors.append(pc[i])
		var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in pi:
			index.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Triangles one grazer draws (body + head + four legs).
static func triangles() -> int:
	var m := meshes()
	var t := 0
	for l in ["body", "head", "leg", "leg", "leg", "leg"]:
		t += (m[l] as ArrayMesh).surface_get_array_index_len(0) / 3
	return t


# --- Poses ---------------------------------------------------------------------------------

## The pose for a server state at time `t` (seconds), gait phase `phase` (0..1 per cycle)
## and real ground speed `speed` (m/s), as {head (pitch, + is down), lift (body height
## offset), pitch (body, + is nose down), roll, legs: [4 hip angles, + swings the foot back],
## knee (0..1 fold, used lying down)}. Pure: same inputs, same pose.
static func pose_for(state: String, t: float, phase: float, speed: float) -> Dictionary:
	var w := TAU * phase
	var p := {"head": 0.15, "lift": 0.0, "pitch": 0.0, "roll": 0.0, "legs": [0.0, 0.0, 0.0, 0.0], "fold": 0.0}
	var moving := clampf(speed / 1.0, 0.0, 1.0) # legs come to rest when it stops
	match state:
		"graze":
			# Head down in the grass, with a slow nibble; the front dips a touch.
			p.head = 1.35 + 0.06 * sin(t * 2.3)
			p.pitch = 0.07
			p.legs = [0.12, 0.12, -0.05, -0.05]
		"alert":
			# Head high, still: the look that says "freeze now".
			p.head = -0.45
			p.pitch = -0.04
		"rest":
			# Lying folded: body down on the ground, legs tucked under, head up but low.
			p.head = -0.05 + 0.03 * sin(t * 0.6)
			p.lift = -0.58
			p.legs = [1.45, 1.45, -1.45, -1.45]
			p.fold = 1.0
			p.roll = 0.06
		"flee":
			# A bound: front legs together, back legs together, half a cycle apart; the body
			# rises and pitches with each leap and the head stays up and forward.
			var a := 0.75 * moving
			p.legs = [a * sin(w), a * sin(w + 0.25), -a * sin(w), -a * sin(w + 0.25)]
			p.lift = 0.14 * moving * maxf(sin(w + 1.2), 0.0)
			p.pitch = -0.12 * moving * sin(w)
			p.head = -0.10 + 0.08 * sin(w)
		_:
			# amble and return: a diagonal walk (left front with right back). Return trots,
			# so its swing is bigger and there is a little bob.
			var a2 := (0.32 if state == "amble" else 0.45) * moving
			p.legs = [a2 * sin(w), a2 * sin(w + PI), a2 * sin(w + PI), a2 * sin(w)]
			p.lift = 0.025 * moving * absf(sin(w))
			p.head = 0.20 + 0.05 * sin(2.0 * w)
	return p


## `a` moved toward `b` by `k` (0..1).
static func blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var legs: Array = []
	for i in LEGS:
		legs.append(lerpf(a.legs[i], b.legs[i], k))
	return {"head": lerpf(a.head, b.head, k), "lift": lerpf(a.lift, b.lift, k),
		"pitch": lerpf(a.pitch, b.pitch, k), "roll": lerpf(a.roll, b.roll, k),
		"legs": legs, "fold": lerpf(a.fold, b.fold, k)}


## Gait cycles per metre travelled for a state (the legs follow the ground, so they never slide).
static func cycles_per_metre(state: String) -> float:
	return 1.0 / (BOUND if state == "flee" else STRIDE)


## The world transforms of one grazer standing at `base` (origin on the ground, basis
## facing +Z) in `pose`: {body, head, legs: [4]}.
static func xforms(base: Transform3D, pose: Dictionary) -> Dictionary:
	var body_local := Transform3D(Basis.from_euler(Vector3(pose.pitch, 0.0, pose.roll)), Vector3(0, pose.lift, 0))
	# Pitch turns about the middle of the body, not the feet.
	var mid := Vector3(0, 0.95, 0)
	body_local.origin += mid - body_local.basis * mid
	var body := base * body_local
	var head := body * Transform3D(Basis(Vector3.RIGHT, pose.head), NECK_PIVOT)
	var legs: Array = []
	for i in LEGS:
		# Lying down the legs fold: shorter (a knee bend), tucked under the body.
		var fold: float = pose.fold
		var sc := Basis.from_scale(Vector3(1.0, 1.0 - 0.45 * fold, 1.0))
		legs.append(body * Transform3D(Basis(Vector3.RIGHT, pose.legs[i]) * sc, HIPS[i]))
	return {"body": body, "head": head, "legs": legs}


## Client's drawing hook (#161 `GrazerFigures.part_xforms`, same signature and result): every
## part's world transform for one grazer standing at `pos` facing `yaw` in server state
## `state_name`. `gait_phase` is in radians, `gait` 0 (standing) to 1 (full trot), `size`
## scales the whole animal. No smoothing or pose blending here: the caller owns that (the
## client's `HerdView`), so a state change snaps. Uses the slope-following ground basis.
static func part_xforms(pos: Vector3, yaw: float, state_name: String, gait_phase: float, gait: float, size: float = 1.0) -> Dictionary:
	var phase := fposmod(gait_phase / TAU, 1.0)
	var speed := clampf(gait, 0.0, 1.0) # pose_for's legs reach full swing at 1 m/s and up
	var pose := pose_for(state_name, phase * STRIDE, phase, speed)
	var basis := ground_basis(pos.x, pos.z, yaw).scaled(Vector3.ONE * size)
	return xforms(Transform3D(basis, pos), pose)


## The ground under a grazer as a basis: facing `yaw` (forward = (sin yaw, 0, cos yaw)) and
## tilted to follow the slope front to back, so a grazer on a hill doesn't float its hooves.
static func ground_basis(x: float, z: float, yaw: float) -> Basis:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var front := Terrain.height(x + fwd.x * 0.45, z + fwd.z * 0.45)
	var back := Terrain.height(x - fwd.x * 0.45, z - fwd.z * 0.45)
	var tilt := clampf(atan2(front - back, 0.9), -0.4, 0.4)
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt)


# --- Live layers -----------------------------------------------------------------------------

## The node the client adds under the world: three MultiMesh layers, all empty until `feed`.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Grazers"
	var m := meshes()
	root.add_child(_layer("GrazerBodies", m.body, CAPACITY))
	root.add_child(_layer("GrazerHeads", m.head, CAPACITY))
	root.add_child(_layer("GrazerLegs", m.leg, CAPACITY * LEGS))
	root.set_meta("herd", {})
	return root


static func _layer(node_name: String, mesh: Mesh, capacity: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = Emberlight.material("solid")
	mmi.visible = false
	return mmi


## Take one wildlife update off the wire (`[id, x, z, yaw, state_index]` per grazer). New
## grazers appear where they are; known ones get a new target to glide to; a grazer missing
## from the list is gone. An empty list clears the herd.
static func feed(root: Node3D, entries) -> void:
	var herd: Dictionary = root.get_meta("herd", {})
	var seen := {}
	var n: int = entries.size() / Wildlife.WIRE_STRIDE
	for k in n:
		var o := k * Wildlife.WIRE_STRIDE
		var id := int(entries[o])
		var x := float(entries[o + 1])
		var z := float(entries[o + 2])
		var yaw := float(entries[o + 3])
		var si := int(entries[o + 4])
		var state: String = Wildlife.STATES[si] if si >= 0 and si < Wildlife.STATES.size() else "graze"
		seen[id] = true
		if not herd.has(id):
			if herd.size() >= CAPACITY:
				continue
			herd[id] = {"pos": Vector2(x, z), "yaw": yaw, "target": Vector2(x, z), "target_yaw": yaw,
				"state": state, "phase": fposmod(id * 0.37, 1.0), "speed": 0.0, "t": id * 1.7,
				"pose": pose_for(state, id * 1.7, 0.0, 0.0)}
		var g: Dictionary = herd[id]
		g.target = Vector2(x, z)
		g.target_yaw = yaw
		g.state = state
		if (g.pos as Vector2).distance_to(g.target) > SNAP_DISTANCE:
			g.pos = g.target
			g.yaw = yaw
	for id in herd.keys():
		if not seen.has(id):
			herd.erase(id)
	root.set_meta("herd", herd)
	_draw(root)


## Advance every grazer by `delta` seconds: glide toward its latest position and facing, move
## its legs by the distance really travelled, blend its pose, and redraw.
static func tick(root: Node3D, delta: float) -> void:
	var herd: Dictionary = root.get_meta("herd", {})
	if herd.is_empty():
		return
	delta = clampf(delta, 0.0, 0.25)
	for id in herd:
		var g: Dictionary = herd[id]
		var before: Vector2 = g.pos
		g.pos = before.lerp(g.target, 1.0 - exp(-FOLLOW_RATE * delta))
		g.yaw = lerp_angle(g.yaw, g.target_yaw, 1.0 - exp(-TURN_RATE * delta))
		var moved := (g.pos as Vector2).distance_to(before)
		var speed := moved / delta if delta > 0.0 else 0.0
		g.speed = lerpf(g.speed, speed, 1.0 - exp(-8.0 * delta))
		g.phase = fposmod(g.phase + moved * cycles_per_metre(g.state), 1.0)
		g.t += delta
		var rate := ALERT_RATE if g.state == "alert" else POSE_RATE
		g.pose = blend(g.pose, pose_for(g.state, g.t, g.phase, g.speed), 1.0 - exp(-rate * delta))
	_draw(root)


## How many grazers are drawn now, and where (for tests and the client): {id: Vector3}.
static func shown(root: Node3D) -> Dictionary:
	var out := {}
	var herd: Dictionary = root.get_meta("herd", {})
	for id in herd:
		var p: Vector2 = herd[id].pos
		out[id] = Vector3(p.x, Terrain.height(p.x, p.y), p.y)
	return out


## The world transforms of grazer `id` as drawn now ({body, head, legs}), or {} if not shown.
static func xforms_of(root: Node3D, id: int) -> Dictionary:
	var herd: Dictionary = root.get_meta("herd", {})
	if not herd.has(id):
		return {}
	var g: Dictionary = herd[id]
	var p: Vector2 = g.pos
	var base := Transform3D(ground_basis(p.x, p.y, g.yaw), Vector3(p.x, Terrain.height(p.x, p.y), p.y))
	return xforms(base, g.pose)


## A gentle per-grazer coat variation (lighter, darker, a touch redder) from its id, as an
## instance colour multiplier around white.
static func coat_tint(id: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 13
	var v := rng.randf_range(0.86, 1.08)
	var warm := rng.randf_range(-0.04, 0.05)
	return Color(v * (1.0 + warm), v, v * (1.0 - warm), 1.0)


static func _draw(root: Node3D) -> void:
	var bodies := (root.get_node("GrazerBodies") as MultiMeshInstance3D)
	var heads := (root.get_node("GrazerHeads") as MultiMeshInstance3D)
	var legs := (root.get_node("GrazerLegs") as MultiMeshInstance3D)
	var herd: Dictionary = root.get_meta("herd", {})
	var i := 0
	for id in herd:
		var x := xforms_of(root, id)
		var tint := coat_tint(id)
		bodies.multimesh.set_instance_transform(i, x.body)
		bodies.multimesh.set_instance_color(i, tint)
		heads.multimesh.set_instance_transform(i, x.head)
		heads.multimesh.set_instance_color(i, tint)
		for l in LEGS:
			legs.multimesh.set_instance_transform(i * LEGS + l, x.legs[l])
			legs.multimesh.set_instance_color(i * LEGS + l, tint)
		i += 1
	bodies.multimesh.visible_instance_count = i
	heads.multimesh.visible_instance_count = i
	legs.multimesh.visible_instance_count = i * LEGS
	for mmi in [bodies, heads, legs]:
		mmi.visible = i > 0

class_name NodeProps
## The props players gather from: an ember ash, a pine, a stone outcrop and an ember-sap
## seep at every position in ResourceNodes.all(), each with a "depleted" look (a stump,
## rubble, a dried-out seep) for when gathering empties it.
##
## Resource nodes are drawn bigger and brighter than the decorative trees and rocks from
## Props.scatter, so players can tell at a glance what can be gathered.
##
## Split like AvatarBuilder: `parts()` and `layout()` are pure data (no renderer, safe in
## headless tests and bots); `build()` turns the layout into a few MultiMeshes, and
## `set_depleted()` swaps one node between its live and depleted look by showing and hiding
## its MultiMesh instances, so no meshes are created or freed while playing.
##
## Chunked (art bible section 7, "Draw less"): each layer is a Node3D holding one
## MultiMeshInstance3D per chunk of the world ("c<x>_<z>", like `Chunks.build`), so the camera
## and the sun's shadow cascades skip chunks they can't see and far chunks fade out at their
## layer's `RANGES`. Every part of a node goes in the chunk of the node's own position, so a
## tree is never split across chunks. The grid is shifted half a chunk so Spawn Meadow sits in
## the middle of one chunk, not on the corner of four. `layout()` still indexes parts by
## (layer, index) in world space; `build()` records where each one went (`part_xform` /
## `put_xform`), and a chunk whose parts are all hidden (a stump chunk while nothing is felled)
## is hidden as a whole, so it costs no draw call and no triangles.

const LAYERS := ["NodeTrunks", "NodeAshCrowns", "NodePineTiers", "NodeStones", "NodeSapPools", "NodeStumps", "NodeDetail", "NodeVeins"]
const GLOW_LAYER := "NodeSapPools" ## drawn with a warm emissive material
## Small boxes that only matter up close, behind the action camera's shoulder: root flares
## and bark ridges on trees and stumps, quartz studs along the outcrop's seam. Shadowless.
const DETAIL_LAYER := "NodeDetail"
## Ember veins (docs/art_bible.md, "Signature motifs"): thin glowing cracks through the bark,
## along the outcrop's seam and across the seep's rim stones, the art bible's "if it glows
## ember, you can use it". Live look only, so an emptied node goes dark. Each crack is a few
## thin boxes on the Emberlight glow material, marked as vein by instance alpha 0, so they
## beat with the valley's heartbeat. Richer tiers (node "tier", default 1) get more cracks.
const VEIN_LAYER := "NodeVeins"
const VEIN := Color(0.95, 0.65, 0.26, 0.0) ## alpha 0: all vein (Emberlight glow reads 1 - alpha)
const VEIN_CRACKS := {"ash": 3, "pine": 2, "stone": 2, "ember_sap": 3} ## at tier 1
const MAX_VEIN_PARTS := 10 ## NodeFx's glow shell holds 10 parts per layer

## Seep light: each live ember-sap seep throws a small warm pool on its rim stones and the
## ground round it at night, like a banked fire, so it reads as a light in the dark and not
## only a glowing sticker. One shadowless OmniLight per seep (no draw call in Forward+);
## `Lamps.apply_glow` sets its energy from the night glow and `Lamps.flicker_lights` swells it
## with the heartbeat. Far seeps fade out (distance fade) so they cost nothing off in the hills.
const SEEP_LIGHTS := "SeepLights"
const SEEP_LIGHT_HEIGHT := 0.7 ## m above the seep's ground: just over the shards
const SEEP_LIGHT_RANGE := 6.0
const SEEP_LIGHT_ENERGY := 1.6 ## at full night
const SEEP_LIGHT_FADE := 45.0 ## m from the camera where a seep's light starts fading out
const SEEP_LIGHT_COLOR := SAP_GLOW ## the sap's own hot orange: redder than a lantern flame

## Colours. Live nodes are lifted above the decoration palette so they stand out.
const ASH_NODE_LEAF := Color(0.70, 0.36, 0.18) ## a touch hotter than the scatter ash, so a gatherable reads
const PINE_NODE := Color(0.17, 0.31, 0.23)
const STONE_NODE := Color(0.54, 0.52, 0.49)
const STONE_VEIN := Color(0.80, 0.76, 0.66) ## a pale quartz seam: "this rock is worth hitting"
const SAP_GLOW := Color(1.0, 0.55, 0.18)
const SAP_RIM := Color(0.30, 0.24, 0.20)
const SAP_DRY := Color(0.22, 0.19, 0.17)
const STUMP_CUT := Color(0.74, 0.60, 0.42) ## the pale cut face on top of a stump
const SEAM_STUD := Color(0.84, 0.80, 0.70) ## quartz studs along the outcrop's seam

## Tier 2 (node "tier" 2, gameplay's level-gated nodes: Felling 5 and Quarrying 5). Each is
## built to be a landmark seen from the meadow: an old ember ash is taller and wider than any
## tree around it, gnarled boughs, a brighter gold crown and glowing ember pods hanging under
## it (the sap glow, so it shines at night and beats with the heartbeat); a rich stone seam is
## a wide, deep plum-grey outcrop flecked with bright gold, with ember crystals breaking out
## of its top. Both keep the tier-1 layers and materials (no new material, art bible 7).
const OLD_ASH_LEAF := Palette.OLD_ASH_LEAF
const OLD_ASH_BARK := Palette.OLD_ASH_BARK
const RICH_STONE := Palette.RICH_STONE
const RICH_FLECK := Palette.RICH_FLECK
const OLD_ASH_TRUNK := Vector2(1.5, 1.25) ## trunk mesh scale (width, height) against tier 1
## The big stone of each outcrop: world-axis ellipsoid half sizes and centre height. Veins
## and seam studs sit on its surface.
const STONE_HALF := {1: Vector3(1.1, 0.9, 0.9), 2: Vector3(1.5, 1.15, 1.2)}
const STONE_CENTRE_Y := {1: 0.6, 2: 0.8}

## The solid shape of each kind of prop, as vertical columns [radius, bottom, top] in metres
## at scale 1, relative to the node's ground position (multiply by the node's scale; see
## solid_columns()). Every part of both looks (live and depleted) fits inside them, which a
## unit test checks vertex by vertex, so a camera kept outside them never sees inside a mesh.
const SOLID_COLUMNS := {
	"ash": [[0.8, 0.0, 0.4], [0.42, 0.0, 2.0], [1.45, 2.0, 2.5], [1.92, 2.5, 5.0], [1.6, 5.0, 5.55]],
	"pine": [[0.8, 0.0, 0.4], [0.42, 0.0, 1.15], [1.62, 1.15, 2.2], [1.3, 2.2, 3.25], [0.98, 3.25, 4.3], [0.66, 4.3, 6.8]],
	"stone": [[1.95, 0.0, 0.85], [1.15, 0.85, 1.56]],
	"ember_sap": [[1.3, 0.0, 0.45], [0.42, 0.45, 1.32]],
	"ash:2": [[1.15, 0.0, 0.25], [0.62, 0.0, 2.65], [3.05, 2.65, 5.1], [1.8, 5.1, 6.2], [1.25, 6.2, 7.1]],
	"stone:2": [[2.4, 0.0, 0.9], [1.65, 0.9, 1.75], [0.8, 1.75, 2.9]],
}

## A collapsed basis hides a MultiMesh instance without resizing the MultiMesh.
const HIDDEN := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

## Chunk side per layer, metres; 0 = the whole layer is one chunk (centred on spawn).
## Measured on the client smoke test's spawn shot (2026-11-23, night; before: one MultiMesh
## per layer, 277 draw calls, 625k primitives): 128 m chunks everywhere gave 345k primitives
## but 335 draw calls, 256 m 388k / 302. Chunks pay where a layer is heavy and short-ranged,
## and cost a draw call per chunk per pass everywhere else, so: the close-up layers (detail,
## veins: 64k triangles of 4-12 cm boxes) get 128 m chunks and a short range; stones and
## stumps (54k, big) get 256 m chunks; the tree parts and glows (50k, seen from far off as
## landmarks) stay whole. That gives 461k / 286.
const CHUNK_SIZES := {
	"NodeTrunks": 0.0, "NodeAshCrowns": 0.0, "NodePineTiers": 0.0, GLOW_LAYER: 0.0,
	"NodeStones": 256.0, "NodeStumps": 256.0, VEIN_LAYER: 128.0, DETAIL_LAYER: 128.0,
}
## Draw distance per chunked layer, metres (a whole layer has none). Stones and stumps go as
## far as the big boulders and a bit more; the close-up layers (root flares, bark ridges,
## studs, flecks, 4-6 cm ember cracks) only as far as anyone can make them out.
const RANGES := {"NodeStones": 220.0, "NodeStumps": 220.0, VEIN_LAYER: 110.0, DETAIL_LAYER: 60.0}


## Every part of one node's prop, in world space, as an Array of
## {layer: String, xform: Transform3D, color: Color}. Pure and deterministic: the same node
## always gives the same parts (small variations are seeded from the node id).
static func parts(node: Dictionary, depleted: bool = false) -> Array:
	var out: Array = []
	var s: float = node.scale
	var origin: Vector3 = node.pos
	var turn := Basis(Vector3.UP, node.rot)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 211 + int(node.id) * 7919
	var put := func(layer: String, local_pos: Vector3, size: Vector3, color: Color, spin: float = 0.0) -> void:
		var b := (turn * Basis(Vector3.UP, spin)).scaled(size * s)
		out.append({"layer": layer, "xform": Transform3D(b, origin + turn * (local_pos * s)), "color": color})
	# Close-up detail. Added after every older part (and with its own rng) so the older parts,
	# their order and their colours are exactly as before.
	var put_detail := func(local_basis: Basis, local_pos: Vector3, size: Vector3, color: Color) -> void:
		var b := turn * local_basis * Basis.from_scale(size * s)
		out.append({"layer": DETAIL_LAYER, "xform": Transform3D(b, origin + turn * (local_pos * s)), "color": color})
	var drng := RandomNumberGenerator.new()
	drng.seed = GameConfig.WORLD_SEED + 227 + int(node.id) * 7919
	var rim_angles: Array = []
	var look_tier := tier_of(node)
	if look_tier >= 2:
		# Tier 2 has its own looks; tier 1 below is untouched, part for part.
		var put_b := func(layer: String, local_basis: Basis, local_pos: Vector3, size: Vector3, color: Color) -> void:
			var b := turn * local_basis * Basis.from_scale(size * s)
			out.append({"layer": layer, "xform": Transform3D(b, origin + turn * (local_pos * s)), "color": color})
		match node.kind:
			"ash":
				_old_ash(put, put_b, put_detail, rng, drng, depleted)
			"stone":
				_rich_seam(put, put_b, put_detail, rng, drng, node.rot, depleted)
	match "" if look_tier >= 2 else node.kind:
		"ash":
			if depleted:
				_stump(put, Palette.TRUNK)
			else:
				put.call("NodeTrunks", Vector3(0, 1.4, 0), Vector3.ONE, Palette.TRUNK)
				put.call("NodeAshCrowns", Vector3(0, 3.5, 0), Vector3.ONE, ASH_NODE_LEAF)
				put.call("NodeAshCrowns", Vector3(0.35, 4.6, -0.2), Vector3.ONE * 0.62, ASH_NODE_LEAF.lightened(0.10 + rng.randf() * 0.08))
		"pine":
			if depleted:
				_stump(put, Palette.TRUNK.darkened(0.2))
			else:
				put.call("NodeTrunks", Vector3(0, 1.4, 0), Vector3.ONE, Palette.TRUNK.darkened(0.2))
				for tier in 4:
					var w := 1.0 - tier * 0.2
					put.call("NodePineTiers", Vector3(0, 2.4 + tier * 1.05, 0), Vector3(w, 1.0, w), PINE_NODE.lightened(tier * 0.05))
		"stone":
			if depleted:
				for i in 3: # low scattered rubble where the outcrop was
					var a := TAU * i / 3.0 + rng.randf() * 0.6
					put.call("NodeStones", Vector3(cos(a) * 0.9, 0.08, sin(a) * 0.9), Vector3(0.85, 0.32, 0.7), STONE_NODE.darkened(0.25), a)
			else:
				put.call("NodeStones", Vector3(0, 0.6, 0), Vector3(2.2, 1.8, 1.8), STONE_NODE)
				put.call("NodeStones", Vector3(1.2, 0.3, 0.5), Vector3(1.2, 1.0, 1.0), STONE_NODE.darkened(0.08), 0.9)
				put.call("NodeStones", Vector3(-1.0, 0.25, 0.7), Vector3(0.95, 0.8, 0.9), STONE_NODE.darkened(0.04 + rng.randf() * 0.06), 2.1)
				put.call("NodeStones", Vector3(0.2, 1.35, -0.3), Vector3(1.0, 0.35, 0.6), STONE_VEIN, 0.4)
		"ember_sap":
			# A ring of dark stones around a shallow pool. Live, the pool glows ember orange and
			# a few glowing shards poke up so the seep reads from a distance (and at night).
			for i in 5:
				var a := TAU * i / 5.0 + rng.randf() * 0.4
				rim_angles.append(a)
				put.call("NodeStones", Vector3(cos(a) * 0.95, 0.15, sin(a) * 0.95), Vector3(0.6, 0.5, 0.55), SAP_RIM, a)
			if depleted:
				put.call("NodeStumps", Vector3(0, 0.05, 0), Vector3(2.0, 0.1, 2.0), SAP_DRY)
			else:
				put.call("NodeSapPools", Vector3(0, 0.2, 0), Vector3(1.4, 0.3, 1.4), SAP_GLOW)
				for i in 3:
					var a := TAU * i / 3.0 + rng.randf() * 0.8
					var tall := 0.8 + rng.randf() * 0.5
					put.call("NodeSapPools", Vector3(cos(a) * 0.3, tall * 0.5, sin(a) * 0.3), Vector3(0.18, tall, 0.18), SAP_GLOW.lightened(0.15), a)
	match "" if look_tier >= 2 else node.kind:
		"ash", "pine":
			var bark: Color = Palette.TRUNK if node.kind == "ash" else Palette.TRUNK.darkened(0.2)
			_roots(put_detail, drng, bark)
			if not depleted:
				_bark_ridges(put_detail, drng, bark, node.kind == "ash")
		"stone":
			if not depleted:
				_seam_studs(put_detail, drng, node.rot)
	if not depleted:
		# Veins last, with their own rng, so every older part is exactly as before.
		var vrng := RandomNumberGenerator.new()
		vrng.seed = GameConfig.WORLD_SEED + 239 + int(node.id) * 7919
		var put_vein := func(local_basis: Basis, local_pos: Vector3, size: Vector3) -> void:
			var b := turn * local_basis * Basis.from_scale(size * s)
			out.append({"layer": VEIN_LAYER, "xform": Transform3D(b, origin + turn * (local_pos * s)), "color": VEIN})
		_veins(put_vein, vrng, str(node.kind), node.rot, vein_cracks(str(node.kind), int(node.get("tier", 1))), rim_angles, look_tier)
	return out


## A node's tier: 1 unless its data says more. Only ash and stone have a tier-2 look so far
## (gameplay's tier-2 nodes); any other kind draws its tier-1 look with the extra veins.
static func tier_of(node: Dictionary) -> int:
	var t := int(node.get("tier", 1))
	if t >= 2 and not SOLID_COLUMNS.has("%s:2" % node.get("kind", "")):
		return 1
	return clampi(t, 1, 2)


## The old ember ash: a thick grey trunk, two gnarled boughs, a big bright crown with two
## side crowns and a top knot, ember pods hanging under the crown. Depleted: a wide stump.
static func _old_ash(put: Callable, put_b: Callable, put_detail: Callable, rng: RandomNumberGenerator, drng: RandomNumberGenerator, depleted: bool) -> void:
	var tw := OLD_ASH_TRUNK.x
	var th := OLD_ASH_TRUNK.y
	if depleted:
		put.call("NodeStumps", Vector3(0, 0.3, 0), Vector3(1.6, 1.2, 1.6), OLD_ASH_BARK)
		put.call("NodeStumps", Vector3(0, 0.61, 0), Vector3(1.36, 0.04, 1.36), STUMP_CUT.lightened(0.05))
	else:
		put.call("NodeTrunks", Vector3(0, 1.4 * th, 0), Vector3(tw, th, tw), OLD_ASH_BARK)
		put.call("NodeAshCrowns", Vector3(0, 4.6, 0), Vector3.ONE * 1.3, OLD_ASH_LEAF)
		var bough_a := rng.randf() * TAU
		for i in 2:
			# A bough leaning out of the trunk at about 40 degrees, a side crown at its end.
			var a := bough_a + PI * i + rng.randf_range(-0.4, 0.4)
			var out_dir := Vector3(cos(a), 0.0, -sin(a))
			var lean := Basis(Vector3.UP, a) * Basis(Vector3.BACK, -0.7)
			put_b.call("NodeTrunks", lean, Vector3(0, 2.9, 0) + out_dir * 0.5, Vector3(0.7, 0.55, 0.7), OLD_ASH_BARK.darkened(0.05))
			put.call("NodeAshCrowns", out_dir * 1.55 + Vector3(0, 3.9, 0), Vector3.ONE * 0.75, OLD_ASH_LEAF.lightened(0.06 + rng.randf() * 0.06))
		put.call("NodeAshCrowns", Vector3(0.35, 6.15, -0.25), Vector3.ONE * 0.6, OLD_ASH_LEAF.lightened(0.14))
		var pod_a := rng.randf() * TAU
		for i in 5:
			# Ember pods: glowing seed husks hanging just under the crown's rim.
			var a := pod_a + TAU * i / 5.0 + rng.randf_range(-0.25, 0.25)
			var r := rng.randf_range(1.75, 2.1)
			put.call("NodeSapPools", Vector3(cos(a) * r, rng.randf_range(3.05, 3.35), -sin(a) * r), Vector3(0.24, 0.42, 0.24), SAP_GLOW.lightened(0.1))
	# Close up: five long root flares (stump too) and five bark fissures.
	var start := drng.randf() * TAU
	for i in 5:
		var a := start + TAU * i / 5.0 + drng.randf_range(-0.3, 0.3)
		var out_dir := Vector3(cos(a), 0.0, sin(a))
		var b := Basis(Vector3.UP, atan2(out_dir.x, out_dir.z)) * Basis(Vector3.RIGHT, deg_to_rad(22.0))
		put_detail.call(b, out_dir * 0.62 + Vector3(0, 0.12, 0), Vector3(0.3, 0.28, drng.randf_range(0.75, 0.9)), OLD_ASH_BARK.darkened(0.1))
	if not depleted:
		var ridge_start := drng.randf() * TAU
		for i in 5:
			var a := ridge_start + TAU * i / 5.0 + drng.randf_range(-0.25, 0.25)
			var y := 0.7 + (i % 3) * 0.8 + drng.randf_range(-0.15, 0.15)
			var r := trunk_radius(y, 2)
			put_detail.call(Basis(Vector3.UP, a + PI * 0.5), Vector3(cos(a), 0.0, -sin(a)) * (r - 0.005) + Vector3(0, y, 0), Vector3(0.08, drng.randf_range(0.8, 1.1), 0.12), OLD_ASH_BARK.darkened(0.32))


## The rich stone seam: a wide plum-grey outcrop of four stones, gold flecks over the big one,
## three ember crystals breaking out of its top. Depleted: a wide ring of dark rubble.
static func _rich_seam(put: Callable, put_b: Callable, put_detail: Callable, rng: RandomNumberGenerator, drng: RandomNumberGenerator, rot: float, depleted: bool) -> void:
	var half: Vector3 = STONE_HALF[2]
	var cy: float = STONE_CENTRE_Y[2]
	if depleted:
		for i in 5:
			var a := TAU * i / 5.0 + rng.randf() * 0.5
			put.call("NodeStones", Vector3(cos(a) * 1.3, 0.1, sin(a) * 1.3), Vector3(1.0, 0.38, 0.85), RICH_STONE.darkened(0.3), a)
		return
	put.call("NodeStones", Vector3(0, cy, 0), half * 2.0, RICH_STONE)
	put.call("NodeStones", Vector3(1.5, 0.45, 0.6), Vector3(1.7, 1.4, 1.4), RICH_STONE.darkened(0.08), 0.9)
	put.call("NodeStones", Vector3(-1.4, 0.38, 0.75), Vector3(1.4, 1.1, 1.2), RICH_STONE.darkened(0.04 + rng.randf() * 0.06), 2.1)
	put.call("NodeStones", Vector3(0.2, 0.3, -1.3), Vector3(1.1, 0.8, 1.0), RICH_STONE.darkened(0.12), 3.7)
	# Ember crystals: long thin glowing shards leaning out of the top of the big stone.
	var unturn := Basis(Vector3.UP, -rot)
	var ca := rng.randf() * TAU
	for i in 3:
		var a := ca + TAU * i / 3.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(sin(a) * 0.35, 0.94, cos(a) * 0.35).normalized()
		var surf := Vector3(half.x * d.x, half.y * d.y, half.z * d.z)
		var tall := 0.9 + rng.randf() * 0.4
		var tilt := Basis(Vector3(cos(a), 0.0, -sin(a)), rng.randf_range(0.2, 0.4))
		put_b.call(GLOW_LAYER, unturn * tilt, unturn * surf + Vector3(0, cy + tall * 0.25, 0), Vector3(0.2, tall, 0.2), SAP_GLOW.lightened(0.2))
	# Close up: ten gold flecks scattered over the big stone's upper faces.
	for k in 10:
		var phi := drng.randf() * TAU
		var theta := drng.randf_range(0.0, 0.75)
		var d := Vector3(sin(phi) * cos(theta), sin(theta), cos(phi) * cos(theta))
		var surf := Vector3(half.x * d.x, half.y * d.y, half.z * d.z)
		var normal := Vector3(d.x / half.x, d.y / half.y, d.z / half.z).normalized()
		var tangent := Vector3.UP.cross(normal)
		tangent = Vector3.RIGHT if tangent.length() < 0.01 else tangent.normalized()
		var b := unturn * Basis(tangent, normal, tangent.cross(normal)) * Basis(Vector3.UP, drng.randf() * TAU)
		var c := drng.randf_range(0.1, 0.16)
		put_detail.call(b, unturn * (surf - normal * 0.012) + Vector3(0, cy, 0), Vector3(c, 0.045, c * 0.7), RICH_FLECK.darkened(drng.randf() * 0.1))


## The radius of a node tree's trunk `y` metres up (at scale 1): tier 1's trunk, or the old
## ember ash's wider, taller one.
static func trunk_radius(y: float, tier: int = 1) -> float:
	if tier >= 2:
		return OLD_ASH_TRUNK.x * (0.36 - 0.12 * y / (2.8 * OLD_ASH_TRUNK.y))
	return 0.36 - 0.12 * y / 2.8


## How many ember cracks a live node of `kind` and `tier` shows: richer tiers glow more.
static func vein_cracks(kind: String, tier: int = 1) -> int:
	return VEIN_CRACKS.get(kind, 0) + maxi(tier - 1, 0)


static func _veins(put_vein: Callable, rng: RandomNumberGenerator, kind: String, rot: float, cracks: int, rim_angles: Array, tier: int = 1) -> void:
	var budget := MAX_VEIN_PARTS
	match kind:
		"ash", "pine":
			# Zig-zag cracks running up the trunk between the root flares and the crown.
			var top := 1.8 if kind == "ash" else 1.05
			if tier >= 2:
				top = 2.5 # the old ash's taller trunk, below its boughs
			var start := rng.randf() * TAU
			for c in cracks:
				if budget < 2:
					break
				var a := start + TAU * c / float(cracks) + rng.randf_range(-0.3, 0.3)
				var y0 := rng.randf_range(0.25, 0.45)
				var y2 := rng.randf_range(top - 0.35, top)
				var y1 := lerpf(y0, y2, rng.randf_range(0.4, 0.6))
				var pts: Array = []
				for k in 3:
					var y: float = [y0, y1, y2][k]
					var ak: float = a + [0.0, rng.randf_range(0.12, 0.22) * (1 if c % 2 == 0 else -1), rng.randf_range(-0.05, 0.05)][k]
					var r := trunk_radius(y, tier)
					var out_dir := Vector3(cos(ak), 0.0, -sin(ak))
					pts.append([out_dir * r + Vector3(0, y, 0), (out_dir + Vector3(0, 0.043, 0)).normalized()])
				budget -= _crack(put_vein, pts, 0.045, 0.03)
		"stone":
			# Ember lines along the big stone (world-axis ellipsoid, half sizes (1.1, 0.9, 0.9)
			# round local (0, 0.6, 0)), on the faces the quartz seam leaves free.
			var half: Vector3 = STONE_HALF[tier]
			var cy: float = STONE_CENTRE_Y[tier]
			var unturn := Basis(Vector3.UP, -rot)
			var start := rng.randf() * TAU
			for c in cracks:
				if budget < 2:
					break
				var phi := start + TAU * c / float(cracks) + rng.randf_range(-0.3, 0.3)
				var pts: Array = []
				for k in 3:
					var ph := phi + lerpf(-0.35, 0.35, k / 2.0) + rng.randf_range(-0.08, 0.08)
					var th := lerpf(0.75, 0.1, k / 2.0) + rng.randf_range(-0.06, 0.06)
					var d := Vector3(sin(ph) * cos(th), sin(th), cos(ph) * cos(th))
					var surf := Vector3(half.x * d.x, half.y * d.y, half.z * d.z)
					var normal := Vector3(d.x / half.x, d.y / half.y, d.z / half.z).normalized()
					pts.append([unturn * surf + Vector3(0, cy, 0), unturn * normal])
				budget -= _crack(put_vein, pts, 0.06, 0.035)
		"ember_sap":
			# A crack over the top of some rim stones, running in towards the glowing pool.
			# Each rim stone is a world-axis ellipsoid, half sizes (0.3, 0.25, 0.275).
			var half := Vector3(0.3, 0.25, 0.275)
			var unturn := Basis(Vector3.UP, -rot)
			for c in mini(cracks, rim_angles.size()):
				if budget < 2:
					break
				var a: float = rim_angles[(c * 2) % rim_angles.size()]
				var centre := Vector3(cos(a) * 0.95, 0.15, sin(a) * 0.95)
				var inward := -(Basis(Vector3.UP, rot) * Vector3(cos(a), 0.0, sin(a))) # towards the pool, world axes
				var base_phi := atan2(inward.x, inward.z)
				var pts: Array = []
				for k in 3:
					var ph := base_phi + PI + lerpf(-0.6, 0.6, k / 2.0) * 0.5 + rng.randf_range(-0.1, 0.1)
					var th: float = [0.55, 1.2, 0.55][k] + rng.randf_range(-0.05, 0.05)
					if k == 2:
						ph = base_phi + rng.randf_range(-0.2, 0.2) # down the pool side
					var d := Vector3(sin(ph) * cos(th), sin(th), cos(ph) * cos(th))
					var surf := Vector3(half.x * d.x, half.y * d.y, half.z * d.z)
					var normal := Vector3(d.x / half.x, d.y / half.y, d.z / half.z).normalized()
					pts.append([unturn * surf + centre, unturn * normal])
				budget -= _crack(put_vein, pts, 0.04, 0.025)


## One crack: a thin box between each pair of neighbouring surface points ([point, normal],
## node-local at scale 1), its flat face along the surface. Returns how many boxes it drew.
static func _crack(put_vein: Callable, pts: Array, width: float, depth: float) -> int:
	for k in pts.size() - 1:
		var p0: Vector3 = pts[k][0]
		var p1: Vector3 = pts[k + 1][0]
		var n: Vector3 = ((pts[k][1] as Vector3) + (pts[k + 1][1] as Vector3)).normalized()
		var along := p1 - p0
		var length := along.length() + width # overlap at the joints so the crack is unbroken
		var y := along.normalized()
		var z := (n - y * n.dot(y)).normalized()
		var x := y.cross(z)
		put_vein.call(Basis(x, y, z), (p0 + p1) * 0.5 + z * (depth * 0.15), Vector3(width, length, depth))
	return pts.size() - 1


## Three root flares where the trunk meets the ground, so a tree (or its stump) grows out of
## the slope instead of standing on it like a post.
static func _roots(put_detail: Callable, rng: RandomNumberGenerator, bark: Color) -> void:
	var start := rng.randf() * TAU
	for i in 3:
		var a := start + TAU * i / 3.0 + rng.randf_range(-0.35, 0.35)
		var out_dir := Vector3(cos(a), 0.0, sin(a))
		var b := Basis(Vector3.UP, atan2(out_dir.x, out_dir.z)) * Basis(Vector3.RIGHT, deg_to_rad(24.0))
		var length := rng.randf_range(0.5, 0.62)
		put_detail.call(b, out_dir * 0.42 + Vector3(0, 0.1, 0), Vector3(0.2, 0.2, length), bark.darkened(0.08))


## Bark ridges on the trunk: dark fissures on the pale-barked ash, lighter reddish plates on
## the pine. They break up the flat six-sided trunk the camera sees from 3 m.
static func _bark_ridges(put_detail: Callable, rng: RandomNumberGenerator, bark: Color, ash: bool) -> void:
	var color := bark.darkened(0.3) if ash else bark.lightened(0.12).lerp(Color(0.55, 0.30, 0.20), 0.25)
	var start := rng.randf() * TAU
	for i in 4:
		var a := start + TAU * i / 4.0 + rng.randf_range(-0.3, 0.3)
		var y := 0.65 + (i % 2) * 0.85 + rng.randf_range(-0.15, 0.15)
		var r := 0.36 - 0.12 * y / 2.8 # the trunk's radius at this height
		var b := Basis(Vector3.UP, a + PI * 0.5)
		put_detail.call(b, Vector3(cos(a), 0.0, -sin(a)) * (r - 0.005) + Vector3(0, y, 0), Vector3(0.06, rng.randf_range(0.7, 1.0), 0.1), color)


## Pale quartz studs set along a rising seam across the outcrop's big stone, the close-up
## version of "this rock is worth hitting". The big stone is an ellipsoid with world-axis
## half sizes (1.1, 0.9, 0.9) round local (0, 0.6, 0) (see parts()), so each stud sits on
## its surface with its flat face along the surface normal.
static func _seam_studs(put_detail: Callable, rng: RandomNumberGenerator, rot: float) -> void:
	var half := Vector3(1.1, 0.9, 0.9)
	var unturn := Basis(Vector3.UP, -rot) # the stone is drawn in world axes; studs go in node axes
	var face := rng.randf() * TAU
	for k in 6:
		var phi := face + lerpf(-0.75, 0.75, k / 5.0)
		var theta := lerpf(0.05, 0.55, k / 5.0) + rng.randf_range(-0.05, 0.05)
		var d := Vector3(sin(phi) * cos(theta), sin(theta), cos(phi) * cos(theta))
		var surf := Vector3(half.x * d.x, half.y * d.y, half.z * d.z)
		var normal := Vector3(d.x / half.x, d.y / half.y, d.z / half.z).normalized()
		var tangent := Vector3.UP.cross(normal).normalized()
		var b := unturn * Basis(tangent, normal, tangent.cross(normal))
		var size := Vector3(rng.randf_range(0.26, 0.32), 0.045, rng.randf_range(0.07, 0.09)) # long along the seam
		put_detail.call(b, unturn * (surf - normal * 0.012) + Vector3(0, 0.6, 0), size, SEAM_STUD.darkened(rng.randf() * 0.08))


## The solid columns of `kind` at `scale`: [[radius, bottom, top], ...] relative to the
## node's ground position. Covers the live and the depleted look.
static func solid_columns(kind: String, scale: float = 1.0, tier: int = 1) -> Array:
	var out: Array = []
	var key := "%s:%d" % [kind, tier] if tier >= 2 else kind
	for c in SOLID_COLUMNS.get(key, SOLID_COLUMNS.get(kind, [])):
		out.append([c[0] * scale, c[1] * scale, c[2] * scale])
	return out


## True if `p` is inside node's prop, or within `margin` of it (by its solid columns). For
## the action camera: keep it outside every nearby node with a margin and it never sees
## inside a trunk, crown, pine tier or stone.
## Decorative solids from `WorldSolids` (kind "deco") work here too, so the camera can be
## handed nodes and decoration in one list.
static func inside_solid(p: Vector3, node: Dictionary, margin: float = 0.0) -> bool:
	if node.has("columns"):
		return WorldSolids.inside(p, node, margin)
	var base: Vector3 = node.pos
	var dx := p.x - base.x
	var dz := p.z - base.z
	var h := p.y - base.y
	for c in solid_columns(str(node.kind), float(node.get("scale", 1.0)), tier_of(node)):
		var r: float = c[0] + margin
		if h >= c[1] - margin and h <= c[2] + margin and dx * dx + dz * dz <= r * r:
			return true
	return false


static func _stump(put: Callable, bark: Color) -> void:
	put.call("NodeStumps", Vector3(0, 0.25, 0), Vector3.ONE, bark)
	put.call("NodeStumps", Vector3(0, 0.51, 0), Vector3(0.85, 0.04, 0.85), STUMP_CUT)


## Both looks of every node, ready for MultiMeshes:
## {layers: {layer: Array of [Transform3D, Color]}, slots: {id: {live: [[layer, index]...],
## depleted: [[layer, index]...], kind, pos, scale, tier}}}. Every node starts live, so its depleted parts begin
## hidden (their transforms are kept in `layers`; build() hides them).
static func layout(nodes: Array) -> Dictionary:
	var layers := {}
	for l in LAYERS:
		layers[l] = []
	var slots := {}
	for n in nodes:
		var slot := {"live": [], "depleted": [], "kind": n.kind, "pos": n.pos, "scale": n.scale, "tier": tier_of(n)}
		for look in ["live", "depleted"]:
			for p in parts(n, look == "depleted"):
				slot[look].append([p.layer, layers[p.layer].size()])
				layers[p.layer].append([p.xform, p.color])
		slots[n.id] = slot
	return {"layers": layers, "slots": slots}


## The node that draws every resource node. Call set_depleted() on it to change a look.
static func build(nodes: Array = []) -> Node3D:
	if nodes.is_empty():
		nodes = ResourceNodes.all()
	var lay := layout(nodes)
	var root := Node3D.new()
	root.name = "ResourceNodes"
	root.set_meta("layout", lay)
	var meshes := _meshes()
	# Where each part lives: layer -> Array (by layout index) of [chunk, index in its MultiMesh].
	var where := {}
	for l in LAYERS:
		where[l] = []
		(where[l] as Array).resize((lay.layers[l] as Array).size())
		root.add_child(_chunked(l, meshes[l], lay, where[l]))
	root.set_meta("where", where)
	for id in lay.slots:
		_show(root, lay.slots[id].depleted, false)
	root.set_meta("depleted", {})
	var fx := NodeFx.new()
	root.add_child(fx)
	fx.setup(root, meshes)
	root.add_child(_seep_lights(nodes))
	return root


## One unlit OmniLight per ember-sap seep, named "Seep<id>", for `Lamps.apply_glow` to light.
static func _seep_lights(nodes: Array) -> Node3D:
	var lights := Node3D.new()
	lights.name = SEEP_LIGHTS
	for n in nodes:
		if n.kind != "ember_sap":
			continue
		var omni := OmniLight3D.new()
		omni.name = "Seep%d" % n.id
		omni.position = (n.pos as Vector3) + Vector3.UP * SEEP_LIGHT_HEIGHT
		omni.light_color = SEEP_LIGHT_COLOR
		omni.light_energy = 0.0
		omni.omni_range = SEEP_LIGHT_RANGE
		omni.omni_attenuation = 1.8
		omni.shadow_enabled = false
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = SEEP_LIGHT_FADE
		omni.distance_fade_length = 15.0
		omni.visible = false
		lights.add_child(omni)
	return lights


## The light over seep `id`, or null (not a seep, or a world built without lights).
static func seep_light(root: Node, id: int) -> OmniLight3D:
	return root.get_node_or_null("%s/Seep%d" % [SEEP_LIGHTS, id]) as OmniLight3D if root else null


## The chunk key of a world position for `layer`: Chunks' grid shifted by half a chunk, so
## the world origin (Spawn Meadow) is the middle of chunk (0, 0). A whole layer is all (0, 0).
static func chunk_key(layer: String, p: Vector3) -> Vector2i:
	var size := chunk_size(layer)
	if size <= 0.0:
		return Vector2i.ZERO
	return Chunks.key(p + Vector3(size, 0.0, size) * 0.5, size)


## The centre of `layer`'s chunk `k` on the ground plane (the origin for a whole layer).
static func chunk_centre(layer: String, k: Vector2i) -> Vector3:
	var size := chunk_size(layer)
	if size <= 0.0:
		return Vector3.ZERO
	return Chunks.centre(k, size) - Vector3(size, 0.0, size) * 0.5


static func chunk_size(layer: String) -> float:
	return CHUNK_SIZES.get(layer, 0.0)


## A layer's chunks' visibility_range_end: its range plus half a chunk diagonal, so a part at
## a chunk's corner is still drawn out to the layer's range (as `Chunks.cut_of`). 0 = no limit.
## `scale` is the Graphics range scale (`Chunks.range_scale`: 0.5 on Low).
static func cut_of(layer: String, scale: float = 1.0) -> float:
	return Chunks.cut_for(RANGES.get(layer, 0.0), chunk_size(layer), scale)


## Layer `l` as a Node3D of chunk MultiMeshes. Parts go in the chunk of their node's position,
## in layout order inside each chunk; `where` (one entry per layout index) is filled in.
static func _chunked(l: String, mesh: Mesh, lay: Dictionary, where: Array) -> Node3D:
	var node_at: Array = []
	node_at.resize(where.size())
	for id in lay.slots:
		var slot: Dictionary = lay.slots[id]
		for look in ["live", "depleted"]:
			for e in slot[look]:
				if e[0] == l:
					node_at[e[1]] = slot.pos
	var by_chunk := {}
	var all: Array = lay.layers[l]
	for i in all.size():
		var k := chunk_key(l, node_at[i])
		if not by_chunk.has(k):
			by_chunk[k] = []
		(by_chunk[k] as Array).append(i)
	var keys := by_chunk.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var layer_node := Node3D.new()
	layer_node.name = l
	var r: float = RANGES.get(l, 0.0)
	var scale := Chunks.quality_range_scale()
	for k in keys:
		var at := chunk_centre(l, k)
		var idx: Array = by_chunk[k]
		var inst: Array = []
		for i in idx:
			var t: Transform3D = all[i][0]
			inst.append([Transform3D(t.basis, t.origin - at), all[i][1]])
		var mmi := _multimesh("c%d_%d" % [k.x, k.y], mesh, inst, l)
		mmi.position = at
		Chunks.set_range(mmi, r, chunk_size(l), scale)
		mmi.set_meta("shown", idx.size())
		layer_node.add_child(mmi)
		for j in idx.size():
			where[idx[j]] = [mmi, j]
	return layer_node


## Draw part (`layer`, `index`) of the layout at world transform `xf` (NodeFx's shakes).
static func put_xform(root: Node3D, layer: String, index: int, xf: Transform3D) -> void:
	var w: Array = root.get_meta("where")[layer][index]
	var mmi := w[0] as MultiMeshInstance3D
	mmi.multimesh.set_instance_transform(w[1], Transform3D(xf.basis, xf.origin - mmi.position))


## The world transform part (`layer`, `index`) is drawn at right now (hidden parts collapsed).
static func part_xform(root: Node3D, layer: String, index: int) -> Transform3D:
	var w: Array = root.get_meta("where")[layer][index]
	var mmi := w[0] as MultiMeshInstance3D
	return mmi.transform * mmi.multimesh.get_instance_transform(w[1])


## Whether part (`layer`, `index`) is shown (its chunk tracks how many of its parts are).
static func part_shown(root: Node3D, layer: String, index: int) -> bool:
	var hidden: Dictionary = root.get_meta("hidden", {})
	return not hidden.has(_part_key(layer, index))


## The MultiMeshInstance3D chunk that draws part (`layer`, `index`).
static func part_chunk(root: Node3D, layer: String, index: int) -> MultiMeshInstance3D:
	return root.get_meta("where")[layer][index][0] as MultiMeshInstance3D


## Switch node `id` between its live and depleted look. Returns false for an unknown id.
static func set_depleted(root: Node3D, id: int, depleted: bool) -> bool:
	var lay: Dictionary = root.get_meta("layout", {})
	if not lay.get("slots", {}).has(id):
		return false
	var slot: Dictionary = lay.slots[id]
	_show(root, slot.live, not depleted)
	_show(root, slot.depleted, depleted)
	var dead: Dictionary = root.get_meta("depleted", {})
	if depleted:
		dead[id] = true
	else:
		dead.erase(id)
	root.set_meta("depleted", dead)
	var fx := root.get_node_or_null("Fx") as NodeFx
	if fx:
		fx.refresh(id)
	# A felled ash or dry seep stops breathing sparks (if it glows ember, you can use it).
	Motes.set_dark(root.get_parent(), id, depleted)
	# ...and a dried-out seep goes dark: no light without the glow.
	var omni := seep_light(root, id)
	if omni:
		omni.set_meta("dry", depleted)
		omni.visible = not depleted and float(omni.get_meta("steady_energy", 0.0)) > 0.0
	return true


## Softly light node `id` (the one in reach / under the reticle) with a warm rim glow, or
## turn it off. One node is lit at a time: lighting another moves the glow. Cheap to call
## every frame (the same node again is a no-op). Returns false for an unknown id.
static func set_highlight(root: Node3D, id: int, on: bool) -> bool:
	var fx := root.get_node_or_null("Fx") as NodeFx
	return fx != null and fx.set_highlight(id, on)


## The id lit by set_highlight, or -1.
static func highlighted(root: Node3D) -> int:
	var fx := root.get_node_or_null("Fx") as NodeFx
	return fx.highlighted() if fx else -1


## One gather's reaction on node `id`: an ash or pine shudders and sheds a few leaves or
## needles, an outcrop jolts and throws stone chips, a seep's pool swells and splashes
## glowing droplets. Call it once per gather result (for anyone's gather nearby). Returns
## false for an unknown id.
static func play_hit(root: Node3D, id: int) -> bool:
	var fx := root.get_node_or_null("Fx") as NodeFx
	return fx != null and fx.play_hit(id)


static func _show(root: Node3D, entries: Array, visible: bool) -> void:
	var lay: Dictionary = root.get_meta("layout")
	var hidden: Dictionary = root.get_meta("hidden", {})
	for e in entries:
		var xf: Transform3D = lay.layers[e[0]][e[1]][0]
		put_xform(root, e[0], e[1], xf if visible else Transform3D(HIDDEN, xf.origin))
		var key := _part_key(e[0], e[1])
		if hidden.has(key) != visible:
			continue # already in that state
		var mmi := part_chunk(root, e[0], e[1])
		var shown: int = mmi.get_meta("shown") + (1 if visible else -1)
		mmi.set_meta("shown", shown)
		mmi.visible = shown > 0 # a chunk with nothing to show costs nothing
		if visible:
			hidden.erase(key)
		else:
			hidden[key] = true
	root.set_meta("hidden", hidden)


static func _part_key(layer: String, index: int) -> String:
	return "%s:%d" % [layer, index]


static func _meshes() -> Dictionary:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.24
	trunk.bottom_radius = 0.36
	trunk.height = 2.8
	trunk.radial_segments = 6
	trunk.rings = 1
	var crown := SphereMesh.new()
	crown.radius = 1.9
	crown.height = 3.0
	crown.radial_segments = 7
	crown.rings = 3
	var tier := CylinderMesh.new()
	tier.top_radius = 0.0
	tier.bottom_radius = 1.6
	tier.height = 2.5
	tier.radial_segments = 7
	tier.rings = 1
	var stone := SphereMesh.new()
	stone.radius = 0.5
	stone.height = 1.0
	stone.radial_segments = 5
	stone.rings = 2
	var pool := SphereMesh.new()
	pool.radius = 0.5
	pool.height = 1.0
	pool.radial_segments = 8
	pool.rings = 2
	var stump := CylinderMesh.new()
	stump.top_radius = 0.34
	stump.bottom_radius = 0.42
	stump.height = 0.5
	stump.radial_segments = 6
	stump.rings = 1
	var detail := BoxMesh.new()
	var vein := BoxMesh.new()
	# Baked vertex colours (Emberlight): dark where the part meets the ground, lighter up its
	# height. Same vertices, so the solid columns and NodeFx's shells are unchanged.
	return {
		"NodeTrunks": Emberlight.bake(trunk, 0.45, 1.6),
		"NodeAshCrowns": Emberlight.bake(crown, 0.35),
		"NodePineTiers": Emberlight.bake(tier, 0.40),
		"NodeStones": Emberlight.bake(stone, 0.40, 1.5),
		"NodeSapPools": pool,
		"NodeStumps": Emberlight.bake(stump, 0.35),
		DETAIL_LAYER: Emberlight.bake(detail, 0.25),
		VEIN_LAYER: vein,
	}


## Which shared Emberlight material each node layer uses (docs/art_bible.md, section 7):
## bark, stone and stumps share `solid` with the scatter forest; pine tiers share its
## `foliage`; node ash leaves have their own named foliage material (they glow brighter at
## night than the decorative ones, from one number in Lamps.apply_glow); the sap pools a
## named glow material (a whole-surface glow, swelling with the heartbeat); veins the plain
## `glow` material, where instance alpha marks the vein.
static func layer_material(layer: String) -> ShaderMaterial:
	match layer:
		"NodeAshCrowns":
			var leaf := Emberlight.material("foliage", "node_ash_leaf")
			if not leaf.has_meta("configured"): # once: apply_glow changes the energy later
				leaf.set_meta("configured", true)
				leaf.set_shader_parameter("emission_color", Lamps.EMBER)
				leaf.set_shader_parameter("sway", 0.03) # gentler, so NodeFx's still glow shell keeps up
			return leaf
		"NodePineTiers":
			return Emberlight.material("foliage")
		GLOW_LAYER:
			var sap := Emberlight.material("glow", "sap")
			if not sap.has_meta("configured"):
				sap.set_meta("configured", true)
				sap.set_shader_parameter("emission_color", SAP_GLOW)
				sap.set_shader_parameter("emission_energy", Lamps.SAP_DAY)
				sap.set_shader_parameter("pulse_depth", 0.35)
			return sap
		VEIN_LAYER:
			var vein := Emberlight.material("glow")
			# A touch under the shader's default, so a vein reads ember orange with a hot core on
			# the beat rather than clipping to white in the noon sun.
			vein.set_shader_parameter("vein_energy", 1.4)
			return vein
		_:
			return Emberlight.material("solid")


static func _multimesh(node_name: String, mesh: Mesh, instances: Array, layer: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = instances.size()
	for i in instances.size():
		mm.set_instance_transform(i, instances[i][0])
		mm.set_instance_color(i, (instances[i][1] as Color).srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = layer_material(layer)
	if layer == GLOW_LAYER or layer == DETAIL_LAYER or layer == VEIN_LAYER:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

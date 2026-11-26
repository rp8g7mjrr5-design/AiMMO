class_name PlaceGhost
extends Node3D
## The campfire you are about to set down (B with a campfire in your pack): a see-through
## ring of field stones and leaned logs, the same shapes CampfireProps draws for a lit fire,
## standing exactly where the server will put it (`Campfires.spot_in_front`). Pale and quiet
## when the spot is good; `SMOULDER` red when it isn't (on another fire, a node, the bench,
## wet ground, the edge), so you see why before you press, and nothing is said in a fight.
##
## Client use: `setup()` once, add it to the world, then `show_at(spot, reason)` every frame
## while placing and `hide()` when done. `reason_at()` is the client's own copy of the
## server's spot rules (Campfires.check_spot) over the fires it was last sent; the server
## still decides, and the few rules the client can't see (your own fire count) come back as
## a refusal that turns the ghost red (`refuse()`).
##
## One small node, two layers on two materials, built once and moved; nothing is created or
## freed while playing (art bible section 7).

const NODE_NAME := "PlaceGhost"
const KINDS := ["stone", "log"] ## what the ghost shows of a fire: no flame, coal or ash
const GOOD_ALPHA := 0.55
const BAD_ALPHA := 0.55
const REFUSED_SECONDS := 1.2 ## a server refusal keeps the ghost red this long
const MOVE_EPS := 0.04 ## metres the spot must move before the parts are laid out again

var _layers := {}
var _good: StandardMaterial3D
var _bad: StandardMaterial3D
var _spot := Vector3.INF
var _refused_left := 0.0
var reason := "" ## why the spot is refused now ("" when good)


## The ghost's tint for a refusal reason: pale ash when good, smoulder red when not.
static func tint(why: String) -> Color:
	if why == "":
		return Color(Palette.FIRE_ASH.lightened(0.55), GOOD_ALPHA)
	return Color(Palette.SMOULDER, BAD_ALPHA)


## s2c_campfires' payload as the client reads it: [{id, pos, left}] (CampfireProps.from_wire).
static func fires_from_wire(data: PackedFloat32Array) -> Array:
	return CampfireProps.from_wire(data)


## A Campfires-shaped state from the fires the client was sent ({id, pos, left}, from
## CampfireProps.from_wire), owned by nobody the client can name.
static func state_from(fires: Array) -> Dictionary:
	var st := Campfires.new_state()
	for f in fires:
		st.fires[int(f.id)] = {"id": int(f.id), "pos": f.pos, "owner": "\n", "lit_at": 0.0, "out_at": 0.0}
	return st


## Why a fire can't go at `at` (a Campfires.REFUSALS key), or "" when it can, by the rules the
## client can check. The server checks again.
static func reason_at(fires: Array, at: Vector3) -> String:
	return Campfires.check_spot(state_from(fires), "", at)


## The ghost's parts at `at`: CampfireProps' stones and logs for a lit fire there.
static func ghost_parts(at: Vector3) -> Array:
	return CampfireProps.parts({"id": 0, "pos": at}, "lit").filter(func(p): return KINDS.has(p.kind))


func setup() -> void:
	name = NODE_NAME
	visible = false
	_good = _material(tint(""))
	_bad = _material(tint("crowded"))
	var meshes := CampfireProps._meshes()
	for layer in ["FireStones", "FireLogs"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[layer]
		mm.instance_count = int(CampfireProps.PER_FIRE[layer])
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = layer
		mmi.multimesh = mm
		mmi.material_override = _good
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_layers[layer] = mmi


## Stand the ghost at `spot`, tinted for `why` (a refusal from the server in the last
## REFUSED_SECONDS keeps it red).
func show_at(spot: Vector3, why: String, delta: float = 0.0) -> void:
	_refused_left = maxf(_refused_left - delta, 0.0)
	reason = why
	visible = true
	if _spot == Vector3.INF or _spot.distance_to(spot) > MOVE_EPS:
		_spot = spot
		_lay_out(spot)
	var mat := _good if why == "" and _refused_left <= 0.0 else _bad
	for layer in _layers:
		(_layers[layer] as MultiMeshInstance3D).material_override = mat


## The server said no: red for a moment, whatever the client thought.
func refuse() -> void:
	_refused_left = REFUSED_SECONDS


func is_red() -> bool:
	return visible and ((_layers.values()[0] as MultiMeshInstance3D).material_override == _bad)


func drop() -> void:
	visible = false
	_refused_left = 0.0
	_spot = Vector3.INF
	reason = ""


func _lay_out(spot: Vector3) -> void:
	var by := {}
	for layer in _layers:
		by[layer] = []
	for p in ghost_parts(spot):
		if by.has(p.layer):
			by[p.layer].append(p.xform)
	for layer in _layers:
		var mm := (_layers[layer] as MultiMeshInstance3D).multimesh
		var xs: Array = by[layer]
		var n := mini(xs.size(), mm.instance_count)
		for i in n:
			mm.set_instance_transform(i, xs[i])
		mm.visible_instance_count = n


static func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.no_depth_test = false
	return m

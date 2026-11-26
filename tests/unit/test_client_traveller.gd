extends TestCase
## Client stream: the sculpted traveller (Traveller, SculptField, TravellerBodies; art bible
## section 3, the model direction). One body is sculpted once for the whole file (it takes a
## couple of seconds) and every check reads it.

const LOOK := {"body": 2, "height": 3, "skin": 4, "face": 1, "hair": 2, "hair_colour": 1,
	"beard": 3, "headwear": 0, "tunic": 2, "trousers": 1}
static var _geo := {}


func _body() -> Dictionary:
	if _geo.is_empty():
		_geo = Traveller.geometry(Traveller.style(LOOK, 77))
	return _geo


func test_within_the_triangle_budget() -> void:
	var tris: int = (_body().verts as PackedVector3Array).size() / 3
	check(tris <= Traveller.MAX_TRIS, "at most %d triangles (%d)" % [Traveller.MAX_TRIS, tris])
	check(tris >= 2000, "still a real body (%d triangles)" % tris)


func test_proportions() -> void:
	var lo := Vector3.ONE * INF
	var hi := -Vector3.ONE * INF
	for v in (_body().verts as PackedVector3Array):
		lo = lo.min(v)
		hi = hi.max(v)
	check(hi.y > 1.72 and hi.y < 1.86, "about 1.78 m tall before height scaling (%.2f)" % hi.y)
	check(lo.y > -0.05 and lo.y < 0.03, "stands on its soles (%.3f)" % lo.y)
	check(hi.x - lo.x < 0.75, "arms hang by the sides (%.2f m across)" % (hi.x - lo.x))


func test_skinned_to_the_avatar_skeleton() -> void:
	var g := _body()
	var bones: PackedInt32Array = g.bones
	var weights: PackedFloat32Array = g.weights
	var n := AvatarSkeleton.names().size()
	var bad := 0
	for i in range(0, weights.size(), 4):
		var sum := weights[i] + weights[i + 1] + weights[i + 2] + weights[i + 3]
		if absf(sum - 1.0) > 0.001:
			bad += 1
		for j in 4:
			if bones[i + j] < 0 or bones[i + j] >= n:
				bad += 1
	check_eq(bad, 0, "every vertex weighted to real bones, weights summing to 1")
	# The head rides the Head bone, the boots the feet.
	var verts: PackedVector3Array = g.verts
	var head := AvatarSkeleton.index_of("Head")
	var feet := [AvatarSkeleton.index_of("LeftFoot"), AvatarSkeleton.index_of("RightFoot")]
	for i in verts.size():
		if verts[i].y > 1.7:
			check_eq(bones[i * 4], head, "the crown rides the head")
			break
	for i in verts.size():
		if verts[i].y < 0.02:
			check(bones[i * 4] in feet, "the soles ride the feet")
			break


func test_painted_regions() -> void:
	var seen := {}
	for r in (_body().regions as PackedByteArray):
		seen[Traveller.KEYS[r]] = true
	for k in ["skin", "eye", "brow", "hair", "beard", "tunic", "jerkin", "belt", "buckle", "trousers", "boot", "boot_cuff", "bracer", "sleeve"]:
		check(seen.has(k), "%s is painted" % k)
	check(not seen.has("hood"), "no hood on a bare head")


func test_shape_key_ignores_colours() -> void:
	var a := Traveller.style(LOOK, 77)
	var recoloured := LOOK.duplicate()
	recoloured.tunic = 5
	recoloured.skin = 0
	recoloured.hair_colour = 4
	recoloured.trousers = 3
	recoloured.height = 0
	check_eq(Traveller.shape_key(Traveller.style(recoloured, 9)), Traveller.shape_key(a), "dyes, skin, hair colour and height reuse the sculpt")
	var hooded := LOOK.duplicate()
	hooded.headwear = 1
	check(Traveller.shape_key(Traveller.style(hooded, 77)) != Traveller.shape_key(a), "a hood is a new shape")
	check_eq(Traveller.style({}, 5).headwear, Appearance.from_seed(5).headwear, "an unchosen look stands in from the seed")
	check(Traveller.shape_key(a).begins_with("v%d-" % Traveller.VERSION), "keys carry the sculpt version")


func test_paint_follows_the_look() -> void:
	var st := Traveller.style(LOOK, 77)
	var cols := Traveller.vertex_colours(_body(), st)
	var regions: PackedByteArray = _body().regions
	var verts: PackedVector3Array = _body().verts
	check_eq(cols.size(), verts.size(), "a colour per vertex")
	var want := (Traveller.colours(st).skin as Color).srgb_to_linear()
	var skin := Traveller.KEYS.find("skin")
	for t in regions.size():
		if regions[t] == skin and verts[t * 3].y > 1.6:
			var c := cols[t * 3]
			var f := 1.0 - Traveller.SHADE_UP * clampf(1.0 - verts[t * 3].y / 1.8, 0.0, 1.0)
			check(absf(c.r - want.r * f) < 0.002 and absf(c.g - want.g * f) < 0.002, "the face is the chosen skin")
			break


func test_disk_cache_round_trip() -> void:
	var geo := _body()
	TravellerBodies.save_geometry(geo)
	var back := TravellerBodies.load_geometry(geo.key)
	check_eq(back.key, geo.key, "reads back")
	check_eq(back.verts, geo.verts, "same vertices")
	check_eq(back.weights, geo.weights, "same weights")
	check(TravellerBodies.load_geometry("v0-not-a-body").is_empty(), "a missing body is just not cached")
	DirAccess.remove_absolute(TravellerBodies.cache_path(geo.key))


func test_dress_now_when_cached() -> void:
	# Headless has no renderer to hold meshes, so this checks the bookkeeping on bare nodes.
	var tb := TravellerBodies.new()
	tb.use_disk = false
	var st := Traveller.style(LOOK, 77)
	var key := Traveller.shape_key(st)
	check(tb.geometry(key).is_empty(), "nothing cached yet")
	tb._geo[key] = _body()
	check_eq(tb.geometry(key), _body(), "a sculpted shape is kept in memory")
	var a := Skeleton3D.new()
	var b := Skeleton3D.new()
	for sk in [a, b]:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		sk.add_child(mi)
	(a.get_node("Mesh") as MeshInstance3D).set_meta("traveller_key", key)
	TravellerBodies.carry(a, b)
	check_eq((b.get_node("Mesh") as MeshInstance3D).get_meta("traveller_key", ""), key, "a restyle carries the sculpted body over")
	check(not tb.busy(), "nothing waiting")
	a.free()
	b.free()
	tb.free()


func test_field_is_a_closed_body() -> void:
	var s := SculptField.new()
	Traveller.sculpt(s, Traveller.style(LOOK, 77))
	s.prepare()
	check(s.field(Vector3(0, 1.2, 0)) < 0.0, "inside the chest")
	check(s.field(Vector3(0, 1.0, 0.6)) > 0.0, "outside in front")
	check(s.field(Vector3(0.6, 1.8, 0)) > 0.0, "nothing far out at the side")
	var hand := AvatarSkeleton.world_rest("LeftHand") + Vector3(-Traveller.ARM_IN, -0.06, 0.0)
	check_eq(s.limb[s.owner(hand)], "ArmL", "a hand by the hip belongs to the arm")

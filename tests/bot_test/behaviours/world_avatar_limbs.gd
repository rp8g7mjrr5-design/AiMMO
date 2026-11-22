extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): every player who joins can be drawn with arms and legs that swing.
##
## For each player_joined, the bot takes that player's real appearance seed, lays out their
## avatar's parts (AvatarBuilder.parts, renderer-free), checks every limb has its meshes and
## sane colours, then walks a limb rig with the client's WalkAnim and checks the limbs swing.

var built := 0
var seeds := {}


func setup(net: Node) -> void:
	net.player_joined.connect(_on_player_joined)


func _on_player_joined(_id: int, player_name: String, appearance_seed: int) -> void:
	built += 1
	seeds[appearance_seed] = true
	var per_limb := {}
	for p in AvatarBuilder.parts(appearance_seed):
		var c: Color = p.color
		if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b)):
			fail("%s's avatar has a broken colour" % player_name)
		if p.limb != "":
			per_limb[p.limb] = per_limb.get(p.limb, 0) + 1
	for limb in AvatarBuilder.LIMBS:
		if per_limb.get(limb, 0) == 0:
			fail("%s's avatar has no %s" % [player_name, limb])
	var rig := AvatarBuilder.rig()
	var anim := WalkAnim.new()
	for i in 10:
		anim.step(Vector3(0, 0, GameConfig.WALK_SPEED * 0.1 * i), 0.1)
	anim.apply(rig)
	var swung := 0
	for limb in AvatarBuilder.LIMBS:
		if absf((rig.get_node(limb) as Node3D).rotation.x) > 0.01:
			swung += 1
	rig.free()
	if swung < AvatarBuilder.LIMBS.size():
		fail("%s's limbs did not all swing while walking (%d of 4)" % [player_name, swung])


func on_finish() -> void:
	stat("avatars_checked", built)
	stat("distinct_looks", seeds.size())
	if built == 0:
		fail("never saw a player join, so no avatar was checked")

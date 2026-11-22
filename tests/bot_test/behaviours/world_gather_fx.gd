extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): gathering feedback is sane wherever players go.
##
## Every few seconds the bot takes the resource node nearest to where the server says it
## is, and plays out (renderer-free, with NodeFx's pure maths) what a gather there would
## show: the glow shell around its prop, the shake, and the hit's flying bits over their
## whole life. Every bit must start at the node, stay above ground, and be gone after its
## life; the shake must come back to rest.

const CHECK_EVERY := 4.0

var hits := 0
var bits := 0
var kinds := {}
var since := 0.0


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_hit_near(bot.my_pos)


func on_play(delta: float) -> void:
	since += delta
	if since >= CHECK_EVERY:
		since = 0.0
		_hit_near(bot.my_pos)


func _hit_near(pos: Vector3) -> void:
	var n := ResourceNodes.nearest(pos, "", 256.0)
	if n.is_empty():
		fail("no resource node within 256 m of %s" % pos)
		return
	hits += 1
	kinds[n.kind] = true
	for p in NodeProps.parts(n, false):
		var shell := NodeFx.shell_xform(p.xform)
		if not shell.origin.is_equal_approx(p.xform.origin):
			fail("node %d glow shell is off its part" % n.id)
			return
	if not NodeFx.shake(n.kind, NodeFx.SHAKE_TIME[n.kind]).is_equal_approx(Transform3D.IDENTITY):
		fail("node %d (%s) does not come back to rest" % [n.id, n.kind])
	var thrown := NodeFx.spawn_bits(n, hits)
	if thrown.is_empty():
		fail("a hit on node %d (%s) throws nothing" % [n.id, n.kind])
	for b in thrown:
		bits += 1
		var t := 0.0
		while t < b.life:
			var o := NodeFx.bit_xform(b, t).origin
			if o.y < b.ground - 0.001 or Vector2(o.x - n.pos.x, o.z - n.pos.z).length() > 6.0 * n.scale:
				fail("node %d (%s) bit strays to %s at %.2f s" % [n.id, n.kind, o, t])
				return
			t += 0.1
		if not NodeFx.bit_xform(b, b.life).basis.get_scale().is_zero_approx():
			fail("node %d (%s) bit outlives its life" % [n.id, n.kind])
			return


func on_finish() -> void:
	stat("hits_played", hits)
	stat("bits_checked", bits)
	stat("kinds_seen", kinds.size())
	if hits == 0:
		fail("never played a gather hit")

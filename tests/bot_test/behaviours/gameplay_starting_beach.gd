extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the starting beaches (BeachGen, 2026-11-26).
##
## On every s2c_world the bot works out the beaches the way a client does. Off an island
## (Ashgrove, CI's default world) there must be none and no beach node in ResourceNodes.
## On an island (AIMMO_WORLD=<seed>:2):
## - every login lands within LANDING_REACH of a landing whose beach is dressed: one or two
##   landmarks and at least MIN_PICKINGS beach nodes, and the beach nodes are the last ids;
## - once per login the bot asks the server for the nearest beach node it is NOT standing at
##   (c2s_gather_start): the server must know the id the client computed and refuse it only
##   for being out of reach ("far"), never "unknown". Out of reach on purpose, so the bot's
##   pack and the other behaviours' gathers are untouched.

const LANDING_REACH := 40.0
const MIN_PICKINGS := 6
const ASK_AFTER := 3.0
const ANSWER_TIMEOUT := 4.0

var _island := false
var _login_at := -1.0
var _asked := -1
var _asked_at := -1.0
var _checked_landing := false
var _woke_at := Vector2.ZERO
var beaches := 0
var asks := 0
var answers := 0


func setup(net: Node) -> void:
	net.world_config.connect(_on_world)
	net.gather_ended.connect(_on_ended)
	net.gather_begun.connect(_on_begun)


func on_login(reconnect: bool, character: Dictionary) -> void:
	_login_at = bot.elapsed
	_asked = -1
	_asked_at = -1.0
	# Only a first login washes up: a reconnect comes back where the bot left.
	_checked_landing = reconnect
	_woke_at = Vector2(float(character.get("x", 0.0)), float(character.get("z", 0.0)))


func _on_world(config: Dictionary) -> void:
	# ResourceNodes and BeachGen rebuild themselves when the config changes, so no reset (a
	# second build of the whole island would stall the bot).
	WorldGen.apply(config)
	_island = WorldGen.is_island()
	beaches = BeachGen.all().size()
	stat("island", _island)
	stat("beaches", beaches)
	if not _island:
		if beaches != 0:
			fail("a world that isn't an island has %d beaches" % beaches)
		for n in ResourceNodes.all():
			if ResourceNodes.BEACH_KINDS.has(n.kind):
				fail("beach node %d (%s) on a world that isn't an island" % [n.id, n.kind])
				return
		return
	var all := ResourceNodes.all()
	var first := all.size() - BeachGen.nodes().size()
	for i in range(first, all.size()):
		if not ResourceNodes.BEACH_KINDS.has(all[i].kind):
			fail("node %d should be a beach node, is %s" % [i, all[i].kind])
			return
	for b in BeachGen.all():
		if b.landmarks.is_empty() or b.landmarks.size() > 2 or b.nodes.size() < MIN_PICKINGS:
			fail("beach %d is not dressed: %d landmarks, %d pickings" % [b.index, b.landmarks.size(), b.nodes.size()])


func on_play(_delta: float) -> void:
	if not _island or _login_at < 0.0:
		return
	var me: Vector3 = bot.my_pos
	if not _checked_landing and not BeachGen.all().is_empty():
		_checked_landing = true
		var best := INF
		for b in BeachGen.all():
			best = minf(best, _woke_at.distance_to(b.landing))
		stat("landing_distance", snappedf(best, 0.1))
		if best > LANDING_REACH:
			fail("washed up %.1f m from the nearest landing" % best)
	if _asked < 0 and bot.elapsed - _login_at > ASK_AFTER:
		var list := ResourceNodes.all()
		var best_id := -1
		var best_d := INF
		for i in range(list.size() - BeachGen.nodes().size(), list.size()):
			var d := Vector2(list[i].pos.x - me.x, list[i].pos.z - me.z).length()
			if d > ResourceNodes.GATHER_RANGE + 3.0 and d < best_d:
				best_d = d
				best_id = i
		if best_id >= 0:
			_asked = best_id
			_asked_at = bot.elapsed
			asks += 1
			bot.send_play("c2s_gather_start", [best_id])
	if _asked >= 0 and _asked_at > 0.0 and bot.elapsed - _asked_at > ANSWER_TIMEOUT:
		fail("no answer for beach node %d within %.0f s" % [_asked, ANSWER_TIMEOUT])
		_asked_at = -1.0


func _on_begun(peer: int, node_id: int, _seconds: float) -> void:
	if peer == int(bot.my_id) and node_id == _asked and _asked_at > 0.0:
		fail("beach node %d started from out of reach" % node_id)
		_asked_at = -1.0


func _on_ended(peer: int, node_id: int, reason: String) -> void:
	if peer != int(bot.my_id) or node_id != _asked or _asked_at < 0.0:
		return
	_asked_at = -1.0
	answers += 1
	if reason == "unknown":
		fail("the server doesn't know beach node %d the client computed" % node_id)
	elif not reason in ["far", "cooldown", "busy", "depleted"]:
		fail("beach node %d refused for %s, expected far" % [node_id, reason])


func on_finish() -> void:
	stat("asks", asks)
	stat("answers", answers)
	if _island and asks > 0 and answers == 0:
		fail("asked about %d beach nodes, never heard back" % asks)

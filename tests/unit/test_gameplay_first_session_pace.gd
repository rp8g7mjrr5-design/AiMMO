extends TestCase
## First-session pace: the short loop that pays off (fun comes first). There are no levels
## (owner direction, 2026-11-26), so the payoff a new player feels is the first tool: a fresh
## character walks out of Spawn Meadow bare-handed and has the 3 ash wood and 2 stone for a
## stone axe within FIRST_AXE_LIMIT seconds of their first gather, and the axe then visibly
## speeds the wood up. This plays a fresh character through the real server's timed gathers
## (no network: fake clock `test_now`, messages in `test_outbox`) the way a new player does it:
## walk to the nearest node of a kind still needed, keep pressing E until it is empty or the
## goal is met, walk to the next. Walking uses GameConfig.WALK_SPEED in a straight line, every
## press costs PRESS_GAP of human reaction, and a gather pays out on the first server tick
## after its bar ends. Nodes respawn on the server's own timers.
##
## If one of these fails after a change to the gather timings, amounts or the nodes near
## spawn, the first minute no longer ends on something you can make: retune those, rather
## than loosening the limits here.

const ServerScript := preload("res://server/server.gd")
const PRESS_GAP := 0.3 ## seconds between a bar ending and the player's next press of E
const START := 100.0
const FIRST_AXE_LIMIT := 90.0 ## the stone axe's materials within 90 s of the first gather
const AXE_GOAL := {"ash_wood": 3, "stone": 2}
const KIND_OF := {"ash_wood": "ash", "pine_wood": "pine", "stone": "stone", "ember_sap": "ember_sap"}


func _server(pos: Vector3, inv: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = START
	var ch := CharacterData.normalize({"name": "Fresh", "inventory": inv})
	ch.x = pos.x
	ch.y = pos.y
	ch.z = pos.z
	srv.sessions[1] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
		"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


## The nearest tier-1 node of one of `kinds` that has a charge left right now, or {}.
func _next_node(srv: Node, pos: Vector3, kinds: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for n in ResourceNodes.all():
		if not kinds.has(str(n.kind)) or int(n.get("tier", 1)) != 1:
			continue
		if Gathering.is_depleted(srv.gathering, int(n.id), srv.test_now):
			continue
		var d := Vector2(n.pos.x - pos.x, n.pos.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


## Kinds of node still worth working for `goal` (item -> qty) with this pack.
func _kinds_left(inv: Dictionary, goal: Dictionary) -> Array:
	var out: Array = []
	for item in goal:
		if Inventory.count(inv, item) < int(goal[item]):
			out.append(KIND_OF[item])
	return out


## Plays from the first gather on until the pack holds `goal` (item -> qty) or `limit`
## seconds pass. Returns {done (seconds since the first gather started, -1 if not reached),
## gathers, walked, pack}.
func _play(inv: Dictionary, goal: Dictionary, limit: float) -> Dictionary:
	var srv := _server(GameConfig.SPAWN_POINT, inv)
	var s: Dictionary = srv.sessions[1]
	var out := {"done": -1.0, "gathers": 0, "walked": 0.0, "pack": {}}
	var first := -1.0
	var stand_off := ResourceNodes.GATHER_RANGE - 0.5
	while first < 0.0 or srv.test_now - first < limit:
		var kinds := _kinds_left(s.character.inventory, goal)
		if kinds.is_empty():
			out.done = srv.test_now - first
			break
		var pos := CharacterData.position(s.character)
		var node := _next_node(srv, pos, kinds)
		if node.is_empty(): # every node of these kinds is empty: wait a second for a respawn
			srv.test_now += 1.0
			srv._respawn_nodes(srv.test_now)
			continue
		var to: Vector3 = node.pos
		var flat := Vector2(to.x - pos.x, to.z - pos.z)
		if flat.length() > stand_off:
			var stop := flat - flat.normalized() * stand_off
			srv.test_now += stop.length() / GameConfig.WALK_SPEED
			out.walked += stop.length()
			s.character.x = pos.x + stop.x
			s.character.z = pos.z + stop.y
			s.character.y = Terrain.height(s.character.x, s.character.z)
		srv.test_now += PRESS_GAP
		var r: Dictionary = srv.gather_start(1, int(node.id))
		check(r.ok, "the fresh character can work node %d (%s)" % [node.id, r.reason])
		if not r.ok:
			break
		if first < 0.0:
			first = srv.test_now
		var ends: float = srv.test_now + float(r.seconds)
		while GatherChannel.is_active(s.channel):
			srv.test_now += GameConfig.TICK_DT
			srv._tick_channels(srv.test_now)
			if srv.test_now > ends + 1.0:
				break
		out.gathers += 1
	out.pack = s.character.inventory.duplicate()
	srv.free()
	return out


func test_the_first_axe_is_a_minute_away() -> void:
	var r := _play({}, AXE_GOAL, FIRST_AXE_LIMIT * 2.0)
	print("  pace first axe: materials at %.1f s, %d gathers, walked %.0f m" % [r.done, r.gathers, r.walked])
	check(r.done >= 0.0 and r.done <= FIRST_AXE_LIMIT,
		"bare-handed: a stone axe's materials within %d s of the first gather (took %.1f s)" % [FIRST_AXE_LIMIT, r.done])
	check(r.gathers >= 2, "it takes a few gathers, not one: it should feel earned")


func test_the_axe_pays_off_at_once() -> void:
	var goal := {"ash_wood": 30}
	var bare := _play({}, goal, 600.0)
	var axe := _play({"stone_axe": 1}, goal, 600.0)
	print("  pace 30 wood: bare-handed %.1f s, stone axe %.1f s" % [bare.done, axe.done])
	check(bare.done > 0.0 and axe.done > 0.0, "both get there")
	check(axe.done < bare.done * 0.75, "the axe is a big, felt step (%.1f s vs %.1f s)" % [axe.done, bare.done])


func test_no_xp_is_ever_earned() -> void:
	var srv := _server(GameConfig.SPAWN_POINT, {})
	var node := _next_node(srv, GameConfig.SPAWN_POINT, ["ash"])
	var s: Dictionary = srv.sessions[1]
	s.character.x = node.pos.x + 1.0
	s.character.z = node.pos.z
	s.character.y = Terrain.height(s.character.x, s.character.z)
	var r: Dictionary = srv.gather_start(1, int(node.id))
	check(r.ok, str(r.reason))
	srv.test_now += float(r.seconds) + 0.2
	srv._tick_channels(srv.test_now)
	check(Inventory.count(s.character.inventory, "ash_wood") > 0, "the gather paid")
	check(s.character.skills.is_empty(), "and taught nothing: there are no skills")
	for m in srv.test_outbox:
		check(not str(m[1]) in ["s2c_xp", "s2c_level_up", "s2c_level_up_seen", "s2c_skills"], "never sends %s" % m[1])
	srv.free()

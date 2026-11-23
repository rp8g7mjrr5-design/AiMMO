extends TestCase
## First-session pace (roadmap Milestone 1, "Done when"): a fresh character levels a skill
## within 90 s of their first gather and reaches level 5 in some skill within about 10
## minutes. This plays a fresh character through the real server's timed gathers (no
## network: fake clock `test_now`, messages in `test_outbox`), Felling only, the way a new
## player does it: walk to the nearest ash or pine, keep pressing E until it is empty,
## walk to the next nearest one. Walking uses GameConfig.WALK_SPEED in a straight line,
## every press costs PRESS_GAP of human reaction, and a gather pays out on the first server
## tick after its bar ends. Nodes respawn on the server's own timers.
##
## If one of these fails after a change to the curve, the gather timings, XP or the nodes
## near spawn, the first ten minutes no longer end on a level you can feel: retune
## Skills.CURVE_A / CURVE_P (one data file) rather than loosening the limits here.

const ServerScript := preload("res://server/server.gd")
const PRESS_GAP := 0.3 ## seconds between a bar ending and the player's next press of E
const START := 100.0
const FIRST_LEVEL_LIMIT := 90.0 ## roadmap: level 2 within 90 s of the first gather
const LEVEL5_LIMIT := 600.0 ## roadmap: level 5 within about 10 minutes
const LEVEL5_SLACK := 60.0 ## "about": bare-handed (no axe ever) may run this much over
const FELLING_KINDS := ["ash", "pine"]


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


## The nearest tier-1 ash or pine that has a charge left right now, or {}.
func _next_tree(srv: Node, pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for n in ResourceNodes.all():
		if not FELLING_KINDS.has(str(n.kind)) or int(n.get("tier", 1)) != 1:
			continue
		if Gathering.is_depleted(srv.gathering, int(n.id), srv.test_now):
			continue
		var d := Vector2(n.pos.x - pos.x, n.pos.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best


## Plays `seconds` of game time from the first gather on. Returns {first_level, level5,
## gathers, walked, full (a wood stack hit Inventory.MAX_STACK on the way)} (times in seconds since the first gather started, -1 if not reached).
func _play(inv: Dictionary, seconds: float) -> Dictionary:
	var srv := _server(GameConfig.SPAWN_POINT, inv)
	var s: Dictionary = srv.sessions[1]
	var out := {"first_level": -1.0, "level5": -1.0, "gathers": 0, "walked": 0.0, "full": false}
	var first := -1.0
	var stand_off := ResourceNodes.GATHER_RANGE - 0.5
	while first < 0.0 or srv.test_now - first < seconds:
		var pos := CharacterData.position(s.character)
		var tree := _next_tree(srv, pos)
		if tree.is_empty(): # every tree in the valley is empty: wait a second for a respawn
			srv.test_now += 1.0
			srv._respawn_nodes(srv.test_now)
			continue
		var to: Vector3 = tree.pos
		var flat := Vector2(to.x - pos.x, to.z - pos.z)
		if flat.length() > stand_off:
			var stop := flat - flat.normalized() * stand_off
			srv.test_now += stop.length() / GameConfig.WALK_SPEED
			out.walked += stop.length()
			s.character.x = pos.x + stop.x
			s.character.z = pos.z + stop.y
			s.character.y = Terrain.height(s.character.x, s.character.z)
		srv.test_now += PRESS_GAP
		var r: Dictionary = srv.gather_start(1, int(tree.id))
		check(r.ok, "the fresh character can work tree %d (%s)" % [tree.id, r.reason])
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
		for item in ["ash_wood", "pine_wood"]:
			if Inventory.count(s.character.inventory, item) >= Inventory.MAX_STACK:
				out.full = true
		var level := Skills.level_of(s.character.skills, "felling")
		if level >= 2 and out.first_level < 0.0:
			out.first_level = srv.test_now - first
		if level >= 5 and out.level5 < 0.0:
			out.level5 = srv.test_now - first
			break
	srv.free()
	return out


func _report(name: String, r: Dictionary) -> void:
	print("  pace %s: level 2 at %.1f s, level 5 at %.1f s, %d gathers, walked %.0f m" % [name, r.first_level, r.level5, r.gathers, r.walked])


func test_bare_handed_first_session() -> void:
	var r := _play({}, LEVEL5_LIMIT + LEVEL5_SLACK)
	_report("bare-handed", r)
	check(r.first_level >= 0.0 and r.first_level <= FIRST_LEVEL_LIMIT,
		"bare-handed: Felling 2 within %d s of the first gather (took %.1f s)" % [FIRST_LEVEL_LIMIT, r.first_level])
	check(r.level5 >= 0.0 and r.level5 <= LEVEL5_LIMIT + LEVEL5_SLACK,
		"bare-handed: Felling 5 within about 10 minutes (took %.1f s)" % r.level5)
	# Felling 5 is ~170 gathers, ~340 wood: more than two stacks hold. A full stack still pays
	# XP (server _finish_channel), which is why this run gets there at all.
	check(r.full, "the run fills a wood stack on the way (so the full-pack rule is covered)")


func test_with_a_stone_axe_first_session() -> void:
	var r := _play({"stone_axe": 1}, LEVEL5_LIMIT)
	_report("stone axe", r)
	check(r.first_level >= 0.0 and r.first_level <= FIRST_LEVEL_LIMIT,
		"with an axe: Felling 2 within %d s of the first gather (took %.1f s)" % [FIRST_LEVEL_LIMIT, r.first_level])
	check(r.level5 >= 0.0 and r.level5 <= LEVEL5_LIMIT,
		"with an axe: Felling 5 within 10 minutes (took %.1f s)" % r.level5)


func test_the_first_level_is_not_instant() -> void:
	# The other side of the pace: level 2 should take a handful of gathers, not one or two,
	# so it feels earned. With an axe and no walking at all it still takes 10+ gathers.
	var need := Skills.xp_for_level(2)
	var per := Skills.gather_xp("ash")
	check(need / per >= 10, "Felling 2 takes at least 10 gathers (%d XP at %d each)" % [need, per])

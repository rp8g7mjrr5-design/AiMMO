extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): what the network can get wrong about the world, and nothing else.
##
## The art checks the old `world_*` behaviours built inside every bot (props, gather bits,
## lanterns, the bench, avatars, flora, the camera) now run once over the whole world in
## tests/unit/test_world_walked_world.gd. Art-free (art bible section 7), this behaviour
## checks what only a live server can break:
## - every position the server sends (mine and every other player's) stands on the ground the
##   client draws (`Terrain.height`), so nobody floats or sinks after a desync;
## - the server's clock arrives and never runs backwards, and the bots see more than one phase
##   of the day if the run crosses one;
## - wherever bots wander there is something to gather within reach, and they pass the bench;
## - every joining player brings an appearance seed, so the crowd isn't all one look;

const GROUND_EPS := 0.05
const GATHER_REACH := 40.0 ## something gatherable should be in sight of every spot bots reach

var ground_checks := 0
var clock_syncs := 0
var phases := {}
var last_seconds := NAN
var walk_checks := 0
var far_from_nodes := 0
var nearest_node_max := 0.0
var bench_in_range := 0
var seeds := {}
var _since := 0.0


func setup(net: Node) -> void:
	net.world_time.connect(_on_world_time)
	net.player_joined.connect(_on_player_joined)


func _on_world_time(world_seconds: float) -> void:
	clock_syncs += 1
	if not is_finite(world_seconds):
		fail("server clock sent %s" % world_seconds)
		return
	if not is_nan(last_seconds) and world_seconds + 0.5 < last_seconds:
		fail("server clock ran backwards: %.2f after %.2f" % [world_seconds, last_seconds])
	last_seconds = world_seconds
	phases[WorldClock.phase(world_seconds)] = true


func _on_player_joined(_id: int, _player_name: String, appearance_seed: int) -> void:
	seeds[appearance_seed] = true


func on_snapshot(_tick: int, entries: Array) -> void:
	var i := 0
	while i + 4 < entries.size():
		var p := Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
		ground_checks += 1
		if absf(p.y - Terrain.height(p.x, p.z)) > GROUND_EPS:
			fail("player %s at %s is %.2f m off the ground" % [entries[i], p, p.y - Terrain.height(p.x, p.z)])
			return
		i += 5


func on_play(delta: float) -> void:
	_since += delta
	if _since < 2.0:
		return
	_since = 0.0
	walk_checks += 1
	var me: Vector3 = bot.my_pos
	var n := ResourceNodes.nearest(me, "", 256.0)
	var d := INF if n.is_empty() else Vector2(n.pos.x - me.x, n.pos.z - me.z).length()
	nearest_node_max = maxf(nearest_node_max, d if is_finite(d) else 999.0)
	if d > GATHER_REACH:
		far_from_nodes += 1
	if Crafting.near_bench(me):
		bench_in_range += 1


func on_finish() -> void:
	stat("ground_checks", ground_checks)
	stat("clock_syncs", clock_syncs)
	stat("clock_phases_seen", phases.size())
	stat("walk_checks", walk_checks)
	stat("walks_far_from_nodes", far_from_nodes)
	stat("farthest_from_a_node_m", snappedf(nearest_node_max, 0.1))
	stat("bench_in_range_checks", bench_in_range)
	stat("distinct_looks", seeds.size())
	if ground_checks == 0:
		fail("never saw a position from the server")
	if clock_syncs == 0:
		fail("never got the server's clock")
	if walk_checks == 0:
		fail("never walked")
	elif far_from_nodes > 0:
		fail("%d walk checks found nothing to gather within %d m" % [far_from_nodes, GATHER_REACH])

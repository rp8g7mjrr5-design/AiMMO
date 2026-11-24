extends TestCase
## Gentle wildlife (game/shared/wildlife.gd), Milestone 2 build-ahead: herds placed from the
## seed outside the meadow, grazing at home, the look-up, creep-and-freeze, the herd bolting
## together, outrunning a walker, settling and coming home, resting at night, never in water,
## and the server stepping them every tick.

const ServerScript := preload("res://server/server.gd")
const DT := GameConfig.TICK_DT


## Runs `seconds` of wildlife with players at `players`. Returns every id that bolted.
func _run(state: Dictionary, players: Array, t0: float, seconds: float, night: bool = false) -> Array:
	var bolted: Array = []
	var t := 0.0
	while t < seconds:
		t += DT
		bolted.append_array(Wildlife.step(state, players, t0 + t, DT, night))
	return bolted


## A player standing `dist` metres from creature `c`, on the side away from its home.
func _beside(c: Dictionary, dist: float) -> Vector3:
	var away := Vector2(c.pos.x - c.home.x, c.pos.z - c.home.z)
	if away.length() < 0.1:
		away = Vector2(1, 0)
	away = away.normalized()
	return Vector3(c.pos.x + away.x * dist, c.pos.y, c.pos.z + away.y * dist)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func test_herds_live_just_outside_the_meadow_on_dry_land() -> void:
	var spawns := Wildlife.spawns()
	check(spawns.size() >= Wildlife.HERD_COUNT * Wildlife.HERD_MIN_SIZE - Wildlife.HERD_MAX_SIZE, "most herds found ground: %d" % spawns.size())
	var herds := {}
	for i in spawns.size():
		var s: Dictionary = spawns[i]
		check_eq(s.id, i, "ids follow the list")
		check_eq(s.kind, "grazer")
		herds[s.herd] = true
		var r := Vector2(s.home.x, s.home.z).length()
		check(r >= Wildlife.HERD_MIN_RADIUS - 0.01 and r <= Wildlife.HERD_MAX_RADIUS + 0.01, "home %.1f m out" % r)
		check(Vector2(s.pos.x, s.pos.z).length() > ResourceNodes.STARTER_MAX_RADIUS, "not in the meadow")
		check(Wildlife.good_ground(s.pos.x, s.pos.z), "stands on good ground")
		check_near(s.pos.y, Terrain.height(s.pos.x, s.pos.z), 0.001, "on the ground")
	check(herds.size() >= Wildlife.HERD_COUNT - 1, "herds: %d" % herds.size())


func test_placement_is_the_same_every_time() -> void:
	var a := Wildlife.generate()
	var b := Wildlife.generate()
	check_eq(a.size(), b.size())
	for i in a.size():
		check_eq(a[i].pos, b[i].pos, "creature %d" % i)


func test_alone_they_graze_and_amble_near_home() -> void:
	var w := Wildlife.new_state()
	var states := {}
	var t := 0.0
	while t < 120.0:
		t += DT
		Wildlife.step(w, [], t, DT, false)
		for c in w.creatures:
			states[c.state] = true
	for c in w.creatures:
		check(_flat_dist(c.pos, c.home) <= Wildlife.HOME_RADIUS + Wildlife.MEMBER_SPREAD + 0.5, "creature %d stayed home" % c.id)
		check(Wildlife.good_ground(c.pos.x, c.pos.z), "never in water")
	check(states.has("graze") and states.has("amble"), "they graze and amble: %s" % [states.keys()])
	check(not states.has("flee"), "nothing to flee from")


func test_coming_close_makes_it_look_up_and_rushing_makes_the_herd_bolt() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = w.creatures[0]
	var start: Vector3 = c.pos
	var p := _beside(c, Wildlife.ALERT_RADIUS - 1.0)
	Wildlife.step(w, [p], 1.0, DT, false)
	check_eq(c.state, "alert", "it looks up")
	check_near(c.yaw, atan2(p.x - c.pos.x, p.z - c.pos.z), 0.001, "and looks at you")
	# Keep walking in during the look-up.
	var toward := Vector3(c.pos.x - p.x, 0, c.pos.z - p.z).normalized()
	var bolted: Array = []
	var t := 1.0
	while t < 1.0 + Wildlife.ALERT_SECONDS + 0.2:
		t += DT
		p += toward * GameConfig.WALK_SPEED * DT * 0.5
		bolted.append_array(Wildlife.step(w, [p], t, DT, false))
	check_eq(c.state, "flee", "you kept coming: it bolts")
	check(bolted.has(c.id), "reported as bolted")
	for other in w.creatures:
		if other.herd == c.herd and _flat_dist(other.pos, c.pos) <= Wildlife.HERD_RADIUS:
			check_eq(other.state, "flee", "herd-mate %d bolts too" % other.id)
	check(_flat_dist(c.pos, p) > _flat_dist(start, p) - 1.0, "running away, not at you")


func test_creep_and_freeze_lets_you_get_close() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = w.creatures[0]
	var p := _beside(c, Wildlife.ALERT_RADIUS + 2.0)
	var toward := Vector3(c.pos.x - p.x, 0, c.pos.z - p.z).normalized()
	var t := 0.0
	var closest := INF
	# Walk in slowly; whenever one of the herd looks up, stand still until it settles.
	while t < 60.0:
		t += DT
		var watched := false
		for o in w.creatures:
			if o.herd == c.herd and o.state == "alert":
				watched = true
		var nearest := INF
		for o in w.creatures:
			if o.herd == c.herd:
				nearest = minf(nearest, _flat_dist(p, o.pos))
		if not watched and nearest > Wildlife.BOLT_RADIUS + 1.5:
			p += toward * 1.0 * DT
		Wildlife.step(w, [p], t, DT, false)
		check(c.state != "flee", "a patient stalker never startles it (%.1f m)" % _flat_dist(p, c.pos))
		if c.state == "flee":
			return
		closest = minf(closest, nearest)
	check(closest < Wildlife.BOLT_RADIUS + 2.0, "got well inside the %.0f m ring: %.1f m" % [Wildlife.ALERT_RADIUS, closest])


func test_too_close_bolts_at_once() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = w.creatures[0]
	Wildlife.step(w, [_beside(c, Wildlife.BOLT_RADIUS - 1.0)], 1.0, DT, false)
	check_eq(c.state, "flee")


func test_a_walker_cannot_run_one_down_and_it_comes_home_after() -> void:
	check(Wildlife.FLEE_SPEED > GameConfig.WALK_SPEED, "faster than a player")
	var w := Wildlife.new_state()
	var c: Dictionary = w.creatures[0]
	var p := _beside(c, Wildlife.BOLT_RADIUS - 1.0)
	var t := 0.0
	var gap0 := _flat_dist(p, c.pos)
	while t < 3.0:
		t += DT
		var chase := Vector3(c.pos.x - p.x, 0, c.pos.z - p.z).normalized()
		p += chase * GameConfig.WALK_SPEED * DT
		Wildlife.step(w, [p], t, DT, false)
	check(_flat_dist(p, c.pos) > gap0 + 1.0 or c.state != "flee", "it pulled away: %.1f m" % _flat_dist(p, c.pos))
	# The chaser gives up and goes back to the meadow.
	var far := Vector3(0, 0, 0)
	_run(w, [far], t, 90.0)
	check(c.state in ["graze", "amble", "return"], "settled: %s" % c.state)
	check(_flat_dist(c.pos, c.home) <= Wildlife.HOME_RADIUS + 1.0, "home again: %.1f m" % _flat_dist(c.pos, c.home))


func test_fleeing_never_leaves_good_ground_or_the_leash_for_long() -> void:
	var w := Wildlife.new_state()
	for c in w.creatures:
		var p := _beside(c, 2.0)
		var t := 0.0
		var furthest := 0.0
		while t < Wildlife.FLEE_MAX + 1.0:
			t += DT
			Wildlife.step(w, [p], t, DT, false)
			check(Wildlife.good_ground(c.pos.x, c.pos.z), "creature %d on good ground" % c.id)
			furthest = maxf(furthest, _flat_dist(c.pos, c.home))
		check(furthest <= Wildlife.LEASH + Wildlife.FLEE_SPEED * Wildlife.FLEE_MAX * 0.5, "creature %d stayed in its hills: %.1f" % [c.id, furthest])
		_run(w, [], t, 60.0)


func test_at_night_they_rest_at_home_and_let_you_closer() -> void:
	var w := Wildlife.new_state()
	_run(w, [], 0.0, 40.0, true)
	var c: Dictionary = w.creatures[0]
	check_eq(c.state, "rest", "lying down at night")
	check(_flat_dist(c.pos, c.home) <= 2.5, "at home")
	var d := Wildlife.ALERT_RADIUS * Wildlife.REST_SCALE + 1.0
	Wildlife.step(w, [_beside(c, d)], 41.0, DT, true)
	check_eq(c.state, "rest", "%.1f m from a resting grazer is fine (by day it would look up)" % d)
	_run(w, [], 41.0, 1.0, false)
	check(c.state != "rest", "up again in the morning")


func test_wire_form() -> void:
	var w := Wildlife.new_state()
	var wire := Wildlife.to_wire(w)
	check_eq(wire.size(), Wildlife.count(w) * 5)
	check_eq(int(wire[0]), 0)
	check_eq(int(wire[4]), Wildlife.STATES.find("graze"))


func test_the_server_steps_them_every_tick() -> void:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	# By day: at night a drowsy herd lets you much closer (Wildlife.bolt_distance), and the
	# server reads the wall clock, so pin it to noon.
	srv.clock_offset = WorldClock.DAY_SECONDS * 0.25 - fposmod(WorldClock.now_seconds(), WorldClock.DAY_SECONDS)
	var c: Dictionary = srv.wildlife.creatures[0]
	var p := _beside(c, Wildlife.BOLT_RADIUS - 1.0)
	var ch := CharacterData.normalize({"name": "Stalker"})
	ch.x = p.x
	ch.y = p.y
	ch.z = p.z
	srv.sessions[2] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_gather": -1000.0, "channel": {}, "login_attempts": 0, "inv_dirty": false}
	var start: Vector3 = c.pos
	srv._tick()
	check_eq(c.state, "flee", "the server's grazer saw the player")
	for i in 10:
		srv._tick()
	check(_flat_dist(c.pos, start) > 1.0, "and ran")
	var sends := 0
	for m in srv.test_outbox:
		if m[1] == "s2c_wildlife":
			sends += 1
			check(m[2][0].has(float(c.id)), "the stalker is sent the grazer it spooked")
	check_eq(sends, 2, "11 ticks, sent on ticks 4 and 8 (protocol v6)")
	srv.free()

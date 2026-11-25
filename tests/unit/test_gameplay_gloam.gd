extends TestCase
## The Gloam walker, server side (Phase 2 build-ahead): it shambles by day and is quicker at
## night, is drawn by noise, grabs with a windup you can step out of or break with a heavy
## blow, goes down to a few blows, keeps away from fire, rises only near players and outside
## the meadow, and crumbles when nobody is near. Off on the live world unless --gloam.

const ServerScript := preload("res://server/server.gd")
const DT := 0.05


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A spot on dry ground well outside the meadow, east of spawn.
func _field() -> Vector3:
	for r in range(60, 200, 5):
		for a in 16:
			var ang := TAU * a / 16.0
			var x := cos(ang) * r
			var z := sin(ang) * r
			if Gloam.good_ground(x, z) and Gloam.good_ground(x + 12, z) and Gloam.good_ground(x - 12, z):
				return Vector3(x, Terrain.height(x, z), z)
	return Vector3(80, 0, 0)


func _p(id: int, pos: Vector3) -> Dictionary:
	return {"id": id, "pos": pos}


func _run(g: Dictionary, players: Array, fires: Array, from: float, seconds: float, night: bool) -> Dictionary:
	var all := {"grabs": [], "missed": [], "crumbled": []}
	var t := from
	while t < from + seconds:
		t += DT
		var r := Gloam.step(g, players, fires, t, DT, night)
		for k in all:
			all[k].append_array(r[k])
	return all


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true
	for id in players:
		var ch := CharacterData.normalize({"name": "p%d" % id})
		var pos: Vector3 = players[id]
		ch.x = pos.x
		ch.y = pos.y
		ch.z = pos.z
		srv.sessions[id] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
			"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
			"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _sent(srv: Node, id: int, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == method:
			out.append(m[2])
	return out


func test_numbers_hold_together() -> void:
	check(Gloam.DAY_SPEED < GameConfig.WALK_SPEED * 0.5, "by day you can always walk away")
	check(Gloam.NIGHT_SPEED > Gloam.DAY_SPEED, "quicker at night")
	check(Gloam.NIGHT_SPEED < GameConfig.WALK_SPEED, "but still slower than you walk")
	check(Gloam.max_hp("walker") > Wildlife.max_hp("grazer"), "tougher than a grazer")
	check(Weapons.damage("ash_spear", "heavy") * 3.0 >= Gloam.max_hp("walker"), "three spear haymakers")
	var fists := Weapons.damage(Weapons.FISTS, "heavy") * 3.0 + Weapons.damage(Weapons.FISTS, "light") * 2.0
	check(fists >= Gloam.max_hp("walker"), "about five bare-handed swings")
	check(Gloam.GRAB_WINDUP >= 0.6, "the grab's windup is a telegraph you can read")
	check(Gloam.GRAB_REACH < Gloam.GRAB_START + GameConfig.WALK_SPEED * Gloam.GRAB_WINDUP, "stepping back during the windup escapes")
	check(Weapons.data(Weapons.FISTS).reach + Gloam.radius("walker") >= Gloam.GRAB_START, "bare hands reach a walker that stops to grab")
	check(Vitals.MAX_HP / Gloam.grab_damage("walker") >= 5.0, "one walker alone takes many grabs to knock you down")
	check(Gloam.SAFE_RADIUS > 34.0, "never in the meadow's starter ring")


func test_shambles_by_day_quicker_at_night() -> void:
	var at := _field()
	for night in [false, true]:
		var g := Gloam.new_state()
		var w := Gloam.rise(g, at, 0.0)
		var prey := at + Vector3(10.0 if night else 7.0, 0, 0) # inside its sight either way
		var start: Vector3 = w.pos
		_run(g, [_p(1, prey)], [], 0.0, 1.0, night)
		var moved := _flat(w.pos, start)
		var want := Gloam.NIGHT_SPEED if night else Gloam.DAY_SPEED
		check(str(w.state) == "hunt", "it hunts the player it sees (night %s): %s" % [night, w.state])
		check(moved <= want + 0.05 and moved >= want * 0.8, "moved about %.1f m in a second (night %s): %.2f" % [want, night, moved])


func test_sees_only_up_close_by_day() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var w := Gloam.rise(g, at, 0.0)
	_run(g, [_p(1, at + Vector3(Gloam.SIGHT_DAY + 3.0, 0, 0))], [], 0.0, 0.2, false)
	check(str(w.state) != "hunt", "doesn't see you past SIGHT_DAY by day")
	_run(g, [_p(1, at + Vector3(Gloam.SIGHT_DAY + 3.0, 0, 0))], [], 1.0, 0.2, true)
	check_eq(str(w.state), "hunt", "but does at night")


func test_noise_draws_walkers_within_range() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var near := Gloam.rise(g, at, 0.0)
	var far := Gloam.rise(g, at + Vector3(0, 0, Gloam.NOISE_RADIUS + 10.0), 0.0)
	var drawn := Gloam.noise(g, at + Vector3(Gloam.NOISE_RADIUS - 5.0, 0, 0), 0.0)
	check_eq(drawn, [int(near.id)], "only the one in earshot")
	check_eq(str(near.state), "drawn")
	var d0 := _flat(near.pos, near.target)
	_run(g, [], [], 0.0, 2.0, false)
	check(_flat(near.pos, near.target) < d0 - 2.0, "it shambles toward the noise")
	check(str(far.state) != "drawn", "the far one never heard it")


func test_a_grab_lands_after_its_windup() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var w := Gloam.rise(g, at, 0.0)
	var prey := at + Vector3(1.0, 0, 0)
	var r := Gloam.step(g, [_p(7, prey)], [], 0.0, DT, false) # sees you
	r = Gloam.step(g, [_p(7, prey)], [], DT, DT, false) # in reach: arms up
	check_eq(str(w.state), "grab", "the windup starts")
	check(r.grabs.is_empty(), "nothing yet")
	var all := _run(g, [_p(7, prey)], [], DT, Gloam.GRAB_WINDUP - 0.15, false)
	check(all.grabs.is_empty(), "nothing during the windup")
	all = _run(g, [_p(7, prey)], [], Gloam.GRAB_WINDUP - 0.1, 0.3, false)
	check_eq(all.grabs.size(), 1, "one grab")
	if all.grabs.size() == 1:
		check_eq(int(all.grabs[0].player), 7)
		check_eq(float(all.grabs[0].damage), Gloam.grab_damage("walker"))
	check_eq(str(w.state), "recover", "then it recovers")


func test_stepping_back_during_the_windup_escapes() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var w := Gloam.rise(g, at, 0.0)
	var prey := at + Vector3(1.0, 0, 0)
	Gloam.step(g, [_p(7, prey)], [], 0.0, DT, false)
	Gloam.step(g, [_p(7, prey)], [], DT, DT, false)
	check_eq(str(w.state), "grab")
	# Half the windup later you have walked 2.7 m away.
	var away := at + Vector3(1.0 + GameConfig.WALK_SPEED * Gloam.GRAB_WINDUP * 0.5, 0, 0)
	var all := _run(g, [_p(7, away)], [], DT, Gloam.GRAB_WINDUP + 0.1, false)
	check(all.grabs.is_empty(), "it closes on air")
	check_eq(all.missed, [int(w.id)])


func test_a_heavy_blow_breaks_the_grab_and_blows_put_it_down() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var w := Gloam.rise(g, at, 0.0)
	var prey := at + Vector3(1.0, 0, 0)
	Gloam.step(g, [_p(7, prey)], [], 0.0, DT, false)
	Gloam.step(g, [_p(7, prey)], [], DT, DT, false)
	var r := Gloam.strike(g, int(w.id), 7, prey, 0.3, 4.0, false)
	check_eq(bool(r.broke_grab), false, "a jab doesn't break it")
	check_eq(str(w.state), "grab")
	r = Gloam.strike(g, int(w.id), 7, prey, 0.4, 9.0, true)
	check_eq(bool(r.broke_grab), true, "a haymaker does")
	check_eq(str(w.state), "stagger")
	var all := _run(g, [_p(7, prey)], [], 0.4, Gloam.GRAB_WINDUP, false)
	check(all.grabs.is_empty(), "no grab from the broken windup")
	var blows := 0
	while Gloam.get_by_id(g, int(w.id)).size() > 0 and blows < 20:
		Gloam.strike(g, int(w.id), 7, prey, 2.0 + blows, Weapons.damage(Weapons.FISTS, "heavy"), true)
		blows += 1
	check(Gloam.get_by_id(g, int(w.id)).is_empty(), "down and gone")
	check_eq(int(g.downs), 1)
	check(blows + 2 <= 6, "a handful of bare-handed blows: %d" % (blows + 2))
	check(Gloam.strike(g, int(w.id), 7, prey, 30.0, 9.0, true).is_empty(), "a downed walker can't be struck")


func test_keeps_away_from_fire() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var w := Gloam.rise(g, at, 0.0)
	var prey := at + Vector3(8.0, 0, 0)
	var fire := prey + Vector3(-1.0, 0, 0) # you stand by your fire
	var all := _run(g, [_p(1, prey)], [fire], 0.0, 8.0, true)
	check(all.grabs.is_empty(), "no grab by the fire")
	check(_flat(w.pos, fire) >= Gloam.FIRE_KEEPAWAY - 0.05, "it stops at the fire's edge: %.2f m" % _flat(w.pos, fire))
	# A fire lit right beside it drives it out of the ring.
	var g2 := Gloam.new_state()
	var w2 := Gloam.rise(g2, at, 0.0)
	_run(g2, [], [at + Vector3(1.0, 0, 0)], 0.0, 6.0, false)
	check(_flat(w2.pos, at + Vector3(1.0, 0, 0)) >= Gloam.FIRE_KEEPAWAY - 0.05, "it walks out of the ring: %.2f m" % _flat(w2.pos, at + Vector3(1.0, 0, 0)))


func test_rises_only_near_players_outside_the_meadow() -> void:
	var g := Gloam.new_state()
	var meadow := WorldGen.spawn_point()
	var field := _field()
	var players := [_p(1, meadow), _p(2, field)]
	var t := 0.0
	while t < 600.0:
		t += 1.0
		Gloam.rise_near_players(g, players, t, true)
	check(Gloam.count(g) > 0, "walkers rose at night")
	for w in g.walkers:
		check(_flat(w.pos, meadow) >= Gloam.SAFE_RADIUS, "never in the meadow: %.1f m" % _flat(w.pos, meadow))
		check(_flat(w.pos, field) >= Gloam.RISE_MIN - 0.01 and _flat(w.pos, field) <= Gloam.RISE_MAX + 0.01, "out of sight but near the player out in the field")
		check(_flat(w.pos, meadow) >= Gloam.RISE_MIN, "never under anyone's feet")
		check(Gloam.good_ground(w.pos.x, w.pos.z), "on dry land")
	check(Gloam.count_near(g, field) <= Gloam.cap_near(players[1], players, true), "capped per player")
	var none := Gloam.new_state()
	Gloam.rise_near_players(none, [], 0.0, true)
	check_eq(Gloam.count(none), 0, "nobody online, nothing rises")


func test_more_at_night_and_for_a_crowd() -> void:
	var field := _field()
	var lone := [_p(1, field)]
	var band := [_p(1, field), _p(2, field + Vector3(3, 0, 0)), _p(3, field + Vector3(0, 0, 3))]
	check(Gloam.cap_near(lone[0], lone, true) > Gloam.cap_near(lone[0], lone, false), "more at night")
	check(Gloam.cap_near(band[0], band, true) > Gloam.cap_near(lone[0], lone, true), "more for a crowd")
	var g := Gloam.new_state()
	var t := 0.0
	while t < 1200.0:
		t += 1.0
		Gloam.rise_near_players(g, band, t, true)
	check(Gloam.count(g) <= Gloam.MAX_WALKERS, "under the world cap")
	check(Gloam.count_near(g, field) <= Gloam.cap_near(band[0], band, true) + 2, "a band's cap is shared, not tripled: %d" % Gloam.count_near(g, field))


func test_crumbles_when_nobody_is_near() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var w := Gloam.rise(g, at, 0.0)
	var far := at + Vector3(Gloam.CRUMBLE_RADIUS + 20.0, 0, 0)
	var all := _run(g, [_p(1, far)], [], 0.0, Gloam.CRUMBLE_SECONDS - 1.0, false)
	check(all.crumbled.is_empty(), "not yet")
	all = _run(g, [_p(1, far)], [], Gloam.CRUMBLE_SECONDS - 1.0, 2.0, false)
	check_eq(all.crumbled, [int(w.id)], "gone after CRUMBLE_SECONDS alone")
	check_eq(Gloam.count(g), 0)


func test_a_bound_walker_hunts_only_its_player() -> void:
	var at := _field()
	var g := Gloam.new_state()
	var w := Gloam.summon(g, 5, at, 0.0, 0.0)
	check_near(_flat(w.pos, at), Gloam.SUMMON_DISTANCE, 0.01, "rises in front of you")
	var bystander: Vector3 = w.pos + Vector3(1.0, 0, 0)
	var all := _run(g, [_p(9, bystander), _p(5, at)], [], 0.0, 6.0, false)
	for gr in all.grabs:
		check_eq(int(gr.player), 5, "only its player is grabbed")
	check(all.grabs.size() >= 1, "and it reaches them by day inside 6 s")
	all = _run(g, [_p(9, bystander)], [], 6.0, DT * 2, false)
	check_eq(all.crumbled, [int(w.id)], "it crumbles when its player leaves")


func test_target_keys_round_trip() -> void:
	check_eq(Gloam.id_of_key(Gloam.target_key(12)), 12)
	check_eq(Gloam.id_of_key(3), -1, "a grazer's int id is not a walker")
	check_eq(Gloam.id_of_key("x3"), -1)


## --- On the server ---

func test_off_by_default_nothing_rises() -> void:
	check_eq(ServerScript.parse_gloam({}, func(_n): return ""), false, "unset is off")
	check_eq(ServerScript.parse_gloam({"gloam": true}, func(_n): return ""), true, "--gloam")
	check_eq(ServerScript.parse_gloam({"gloam": "0"}, func(_n): return "1"), false, "--gloam=0 wins")
	check_eq(ServerScript.parse_gloam({}, func(n): return "on" if n == "AIMMO_GLOAM" else ""), true, "AIMMO_GLOAM=on")
	var srv := _server({1: _field()})
	for i in 2000:
		srv.test_now += DT
		srv._tick_gloam(srv.test_now)
	check_eq(Gloam.count(srv.gloam), 0, "no walker rises on a server without --gloam")
	srv.gloam_on = true
	for i in 3000:
		srv.test_now += 1.0
		srv._tick_gloam(srv.test_now)
	check(srv.gloam.downs >= 0 and srv.gloam.next_id > 0, "with --gloam they rise near the player")
	srv.free()


func test_gloam_command_grab_hurts_and_blows_put_it_down() -> void:
	var at := _field()
	var srv := _server({1: at})
	srv._on_chat(1, "/gloam")
	var lines := _sent(srv, 1, "s2c_system")
	check(lines.size() == 1 and str(lines[0][0]).begins_with("A Gloam walker rises"), "the walker rises: %s" % [lines])
	check_eq(Gloam.count(srv.gloam), 1)
	var w: Dictionary = srv.gloam.walkers[0]
	check_eq(int(w.bound), 1)
	# Stand and wait: it shambles up and grabs.
	var hp0 := float(srv.vitals_of(1).hp)
	var t := 0.0
	while t < 8.0 and float(srv.vitals_of(1).hp) >= hp0:
		t += DT
		srv.test_now += DT
		srv._tick_gloam(srv.test_now)
	check_near(hp0 - float(srv.vitals_of(1).hp), Gloam.grab_damage("walker"), 0.01, "one grab's worth of health")
	check(not _sent(srv, 1, "s2c_vitals").is_empty(), "the health bar hears of it")
	check(Vitals.in_combat(srv.vitals_of(1), srv.test_now), "you're in combat")
	# Swing haymakers at it until it is down; s2c_swing_hits never names it (walkers go out in s2c_gloam_hits, v10).
	var yaw := atan2(w.pos.x - at.x, w.pos.z - at.z)
	var swings := 0
	while Gloam.count(srv.gloam) > 0 and swings < 12:
		srv.sessions[1].swing = {}
		srv.vitals_of(1).stamina = 100.0
		yaw = atan2(w.pos.x - at.x, w.pos.z - at.z)
		check_eq(srv.attack_request(1, "heavy", yaw).ok, true, "swing goes")
		srv.test_now += Weapons.swing_seconds(Weapons.FISTS, "heavy") + 0.01
		srv._tick_swings(srv.test_now)
		srv._tick_gloam(srv.test_now)
		swings += 1
	check_eq(Gloam.count(srv.gloam), 0, "down within a few haymakers (%d)" % swings)
	check(swings <= 5, "four or five haymakers: %d" % swings)
	check_eq(int(srv.sessions[1].get("gloam_downs", 0)), 1)
	for h in _sent(srv, 1, "s2c_swing_hits"):
		for id in h[2]:
			check(typeof(id) == TYPE_INT, "only grazer ids on the wire: %s" % [h])
	srv._on_chat(1, "/gloam status")
	srv.test_now += GameConfig.CHAT_COOLDOWN + 0.1
	srv.sessions[1].last_command = -1000.0
	srv._on_chat(1, "/gloam status")
	lines = _sent(srv, 1, "s2c_system")
	check_eq(str(lines[lines.size() - 1][0]), "Your walker %d is down." % int(w.id))
	srv.free()


func test_a_swing_is_a_noise() -> void:
	var at := _field()
	var srv := _server({1: at})
	var w := Gloam.rise(srv.gloam, at + Vector3(0, 0, 20.0), srv.test_now)
	check(str(w.state) == "wander", "idle")
	srv.attack_request(1, "light", PI) # swinging at nothing, facing away
	srv.test_now += 0.5
	srv._tick_swings(srv.test_now)
	check_eq(str(w.state), "drawn", "it heard the swing 20 m off")
	srv.free()


func test_hurt_by_walkers_knocks_down_fairly() -> void:
	var at := _field()
	var srv := _server({1: at})
	var w := Gloam.rise(srv.gloam, at + Vector3(1.0, 0, 0), srv.test_now)
	var grabs := 0
	var t := 0.0
	while t < 60.0 and int(srv.sessions[1].get("knockdowns", 0)) == 0:
		t += DT
		srv.test_now += DT
		var r: Dictionary = srv._tick_gloam(srv.test_now)
		grabs += r.grabs.size()
	check_eq(int(srv.sessions[1].get("knockdowns", 0)), 1, "an unanswered walker knocks you down in the end")
	check(grabs >= 5, "but only after many grabs: %d" % grabs)
	var pos := CharacterData.position(srv.sessions[1].character)
	check(_flat(pos, WorldGen.spawn_point()) < 5.0, "you come to at spawn")
	check(_flat(w.pos, pos) > Gloam.LOSE_RADIUS, "far from the walker")
	srv.free()

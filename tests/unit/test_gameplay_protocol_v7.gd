extends TestCase
## Protocol v7 (Milestone 2 "First blood"): your own health and stamina reach your game
## (s2c_vitals, once at login and on every change), and the first swing: c2s_attack spends
## stamina, everyone in view sees it start (s2c_swing), the blow lands after the windup
## (s2c_swing_hits) and a grazer it strikes bolts with its herd. Bare hands only until the
## spear and maul can be made. Net's own RPCs are unchanged, so old clients still get
## "please update" (net_v6.gd is frozen for that).

const ServerScript := preload("res://server/server.gd")
const NetScript := preload("res://shared/net.gd")
const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")

const V7_RPCS := ["c2s_attack", "s2c_attack_refused", "s2c_swing", "s2c_swing_hits", "s2c_vitals"]


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
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


## Moves the clock on and lands due swings only (no wildlife step, so the grazer we aim at
## stays put for the check).
func _advance(srv: Node, seconds: float) -> void:
	srv.test_now += seconds
	srv._tick_swings(srv.test_now)


## A spot 1 m south of grazer `cid`, and the yaw that faces it from there.
func _next_to(srv: Node, cid: int) -> Array:
	var c: Dictionary = Wildlife.get_by_id(srv.wildlife, cid)
	var at: Vector3 = c.pos + Vector3(0, 0, -1.0)
	return [at, atan2(c.pos.x - at.x, c.pos.z - at.z)]


func test_v7_adds_vitals_and_the_swing_on_play_and_v6_is_frozen() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 7, "v7 or later")
	var play := ProtocolCompat.rpc_names("res://tests/protocol/net_play_v7.gd") # as v7 shipped
	var expected := Array(ProtocolCompat.rpc_names("res://tests/protocol/net_play_v6.gd")) + V7_RPCS
	expected.sort()
	check_eq(Array(play), expected, "v7 Play = v6 Play + vitals and the swing")
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v6.gd"),
		"Net's own RPCs unchanged since v6")


func test_v7_rpcs_reemit_on_net() -> void:
	var net: Node = NetScript.new()
	net._ready()
	var got := []
	net.vitals_changed.connect(func(a, b, c, d): got.append(["vitals", a, b, c, d]))
	net.swing_begun.connect(func(p, w, k, s): got.append(["swing", p, w, k, s]))
	net.swing_landed.connect(func(p, k, ids): got.append(["hits", p, k, ids]))
	net.attack_refused.connect(func(k, r): got.append(["refused", k, r]))
	net.attack_requested.connect(func(p, k, y): got.append(["attack", p, k, y]))
	net.play.s2c_vitals(90, 100, 80, 100)
	net.play.s2c_swing(3, "fists", "light", 0.44)
	net.play.s2c_swing_hits(3, "light", [5])
	net.play.s2c_attack_refused("heavy", "tired")
	net.play.c2s_attack("heavy", 1.5)
	check_eq(got, [["vitals", 90, 100, 80, 100], ["swing", 3, "fists", "light", 0.44], ["hits", 3, "light", [5]],
		["refused", "heavy", "tired"], ["attack", 0, "heavy", 1.5]])
	net.free()


func test_send_vitals_reports_the_bar() -> void:
	var srv := _server({1: Vector3(40, 0, 40)})
	srv._send_vitals(1)
	check_eq(_sent(srv, 1, "s2c_vitals"), [[100, 100, 100, 100]], "a full bar at login")
	srv.free()


func test_a_swing_spends_stamina_and_everyone_in_view_sees_it() -> void:
	var srv := _server({1: Vector3(40, 0, 40), 2: Vector3(45, 0, 40), 3: Vector3(-400, 0, -400)})
	var r: Dictionary = srv.attack_request(1, "heavy", 0.5)
	check_eq(r, {"ok": true, "reason": ""})
	var cost := Weapons.stamina_cost(Weapons.FISTS, "heavy")
	check_eq(float(srv.vitals_of(1).stamina), 100.0 - cost, "the heavy swing's stamina is spent")
	check_eq(_sent(srv, 1, "s2c_vitals"), [[100, 100, roundi(100.0 - cost), 100]], "and the bar shows it")
	var swing := [1, Weapons.FISTS, "heavy", Weapons.swing_seconds(Weapons.FISTS, "heavy")]
	check_eq(_sent(srv, 1, "s2c_swing"), [swing], "you see your own swing")
	check_eq(_sent(srv, 2, "s2c_swing"), [swing], "a player in view sees it")
	check_eq(_sent(srv, 3, "s2c_swing"), [], "a player far away doesn't")
	check_eq(float(srv.sessions[1].yaw), 0.5, "you turn to face the swing")
	srv.free()


func test_pressing_again_mid_swing_is_busy_then_works_after() -> void:
	var srv := _server({1: Vector3(40, 0, 40)})
	srv.attack_request(1, "light", 0.0)
	_advance(srv, 0.2)
	check_eq(srv.attack_request(1, "light", 0.0).reason, "busy")
	check_eq(_sent(srv, 1, "s2c_attack_refused"), [["light", "busy"]])
	_advance(srv, Weapons.swing_seconds(Weapons.FISTS, "light"))
	check(srv.sessions[1].swing.is_empty(), "the swing is over")
	check_eq(srv.attack_request(1, "light", 0.0).ok, true, "free to swing again")
	srv.free()


func test_bad_kinds_and_yaws_are_refused() -> void:
	var srv := _server({1: Vector3(40, 0, 40)})
	check_eq(srv.attack_request(1, "kick", 0.0).reason, "unknown")
	check_eq(srv.attack_request(1, "light", NAN).reason, "unknown")
	check_eq(_sent(srv, 1, "s2c_attack_refused"), [["", "unknown"], ["light", "unknown"]])
	check_eq(float(srv.vitals_of(1).stamina), 100.0, "nothing spent")
	check_eq(srv.attack_request(99, "light", 0.0), {}, "nobody there")
	srv.free()


func test_out_of_stamina_is_tired_then_winded() -> void:
	var srv := _server({1: Vector3(40, 0, 40)})
	var v: Dictionary = srv.vitals_of(1)
	v.stamina = 3.0
	check_eq(srv.attack_request(1, "heavy", 0.0).reason, "tired", "not enough for a heavy")
	check_eq(srv.attack_request(1, "light", 0.0).reason, "tired", "nor a jab")
	check(Weapons.refusal_text("tired") != "", "tired says why")
	v.stamina = Weapons.stamina_cost(Weapons.FISTS, "light")
	check_eq(srv.attack_request(1, "light", 0.0).ok, true, "exactly enough is enough")
	check(Vitals.is_winded(v, srv.test_now), "and empty leaves you winded")
	_advance(srv, 0.5) # the jab is over, the bar still empty and inside WINDED_SECONDS
	check_eq(srv.attack_request(1, "light", 0.0).reason, "winded")
	srv.free()


func test_a_fist_light_costs_less_than_the_flat_light() -> void:
	# Bare hands' jab is cheaper than Vitals.COSTS.light: 6 stamina still buys one.
	var v := Vitals.full()
	v.stamina = 6.0
	check_eq(Vitals.check(v, "light", 0.0), "tired", "the flat cost wouldn't allow it")
	var r := Vitals.spend_cost(v, "light", Weapons.stamina_cost(Weapons.FISTS, "light"), 0.0)
	check_eq(r.ok, true)
	check(absf(float(v.stamina) - (6.0 - Weapons.stamina_cost(Weapons.FISTS, "light"))) < 0.001, "spent the weapon's cost")
	var w := Vitals.full()
	check_eq(Vitals.spend_cost(w, "dodge", 25.0, 0.0).ok, true, "other moves work too")


func test_the_blow_lands_after_the_windup_and_the_grazer_bolts() -> void:
	var srv := _server({})
	var spot: Array = _next_to(srv, 0)
	srv.free()
	srv = _server({1: spot[0], 2: spot[0] + Vector3(6, 0, 0)})
	srv.attack_request(1, "light", spot[1])
	_advance(srv, Weapons.hit_at(Weapons.FISTS, "light") * 0.5)
	check_eq(_sent(srv, 1, "s2c_swing_hits"), [], "nothing lands during the windup")
	_advance(srv, Weapons.hit_at(Weapons.FISTS, "light"))
	check_eq(_sent(srv, 1, "s2c_swing_hits"), [[1, "light", [0]]], "the jab strikes grazer 0")
	check_eq(_sent(srv, 2, "s2c_swing_hits"), [[1, "light", [0]]], "the onlooker sees the hit")
	var c: Dictionary = Wildlife.get_by_id(srv.wildlife, 0)
	check_eq(str(c.state), "flee", "the struck grazer bolts")
	check_eq(int(c.struck), 1)
	check(Vitals.in_combat(srv.vitals_of(1), srv.test_now), "a hit is a fight")
	check_eq(int(srv.sessions[1].swing_hits), 1)
	srv.free()


func test_a_whiff_tells_only_the_swinger() -> void:
	var srv := _server({})
	var spot: Array = _next_to(srv, 0)
	srv.free()
	srv = _server({1: spot[0], 2: spot[0] + Vector3(6, 0, 0)})
	srv.attack_request(1, "light", spot[1] + PI) # facing away
	_advance(srv, 0.5)
	check_eq(_sent(srv, 1, "s2c_swing_hits"), [[1, "light", []]], "you hear your whiff")
	check_eq(_sent(srv, 2, "s2c_swing_hits"), [], "nobody else is bothered")
	check(not Vitals.in_combat(srv.vitals_of(1), srv.test_now), "swinging at air is no fight")
	srv.free()


func test_a_swing_never_cuts_a_gather_short() -> void:
	var srv := _server({1: Vector3(40, 0, 40)})
	srv.sessions[1].channel = GatherChannel.start(1, Vector3(40, 0, 40), 99.0, 4.0)
	srv.sessions[1].channel.audience = [1]
	check_eq(srv.attack_request(1, "light", 0.0).reason, "gathering")
	check(GatherChannel.is_active(srv.sessions[1].channel), "the gather goes on")
	check_eq(float(srv.vitals_of(1).stamina), 100.0, "nothing spent")
	srv.gather_cancel(1, "stopped") # what the client sends first when the swing should win
	check_eq(srv.attack_request(1, "light", 0.0).ok, true, "then the swing goes")
	srv.free()


func test_striking_one_bolts_its_herd_mates() -> void:
	var w := Wildlife.new_state()
	var c: Dictionary = Wildlife.get_by_id(w, 0)
	var mates := []
	for o in w.creatures:
		if o.id != 0 and o.herd == c.herd and Vector2(o.pos.x - c.pos.x, o.pos.z - c.pos.z).length() <= Wildlife.HERD_RADIUS:
			mates.append(o.id)
	var bolted := Wildlife.strike(w, 0, c.pos + Vector3(0, 0, -1), 10.0)
	check_eq(bolted[0], 0, "the struck one first")
	check_eq(bolted.size(), 1 + mates.size(), "and every herd-mate nearby")
	check_eq(Wildlife.strike(w, 9999, Vector3.ZERO, 10.0), [], "unknown id")
	check_eq(Wildlife.targets(w).size(), Wildlife.count(w))


func test_weapon_of_is_bare_hands_until_a_weapon_is_carried() -> void:
	var srv := _server({1: Vector3(40, 0, 40)})
	check_eq(srv.weapon_of(1), Weapons.FISTS)
	srv.sessions[1].character.inventory["stone_spear"] = 1
	check_eq(srv.weapon_of(1), "stone_spear")
	srv.sessions[1].character.inventory["stone_maul"] = 1
	check_eq(srv.weapon_of(1), "stone_maul", "the best one carried")
	check_eq(srv.weapon_of(99), Weapons.FISTS)
	srv.free()


func test_a_knock_down_ends_the_swing() -> void:
	var srv := _server({1: Vector3(40, 0, 40)})
	srv.attack_request(1, "heavy", 0.0)
	srv.knock_down(1)
	check(srv.sessions[1].swing.is_empty(), "no blow lands after you go down")
	srv.free()

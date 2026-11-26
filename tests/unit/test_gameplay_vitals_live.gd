extends TestCase
## Vitals wired into the server (roadmap Milestone 2 "First blood", build-ahead): every
## logged-in player has health and stamina that tick with the server, a hit can knock them
## down (fair failure: back in Spawn Meadow at once, full, pack untouched), and
## "Return to Spawn Meadow" is refused mid-fight so it is never an escape button. The hidden
## /hurt and /vitals dev commands drive it until creatures fight.

const ServerScript := preload("res://server/server.gd")


func _server(players: Dictionary) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.dev_commands = true
	for id in players:
		var ch := CharacterData.normalize({"name": players[id]})
		ch.x = 40.0
		ch.z = 40.0
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


## Runs `seconds` of server ticks at the real tick rate, moving the test clock along.
func _run(srv: Node, seconds: float) -> void:
	var n := int(round(seconds / GameConfig.TICK_DT))
	for i in n:
		srv.test_now += GameConfig.TICK_DT
		srv._tick()


func test_everyone_starts_full_and_idle_costs_nothing() -> void:
	var srv := _server({1: "Ash"})
	var v: Dictionary = srv.vitals_of(1)
	check_eq(Vitals.shown(v), [100, 100], "full health and stamina")
	_run(srv, 2.0)
	check_eq(_sent(srv, 1, "s2c_vitals"), [], "nothing changed, nothing sent")
	check_eq(srv.vitals_of(99), {}, "nobody there, no vitals")
	srv.free()


func test_a_hit_hurts_then_health_comes_back_out_of_combat() -> void:
	var srv := _server({1: "Ash"})
	var r: Dictionary = srv.hurt(1, 30.0)
	check_eq([r.taken, r.dead, r.knocked_down], [30.0, false, false])
	check_eq(_sent(srv, 1, "s2c_vitals"), [[70, 100, 100, 100]], "the bar drops at once")
	_run(srv, Vitals.COMBAT_SECONDS - 0.5)
	check_eq(int(srv.vitals_of(1).hp), 70, "no health back while in combat")
	_run(srv, 4.0)
	check_eq(Vitals.shown(srv.vitals_of(1)), [100, 100], "full again a few seconds after the fight")
	var last: Array = _sent(srv, 1, "s2c_vitals").back()
	check_eq(last, [100, 100, 100, 100], "the last send says full")
	var sends := _sent(srv, 1, "s2c_vitals").size()
	_run(srv, 2.0)
	check_eq(_sent(srv, 1, "s2c_vitals").size(), sends, "full and idle: quiet again")
	srv.free()


func test_knocked_down_wakes_in_the_meadow_with_everything() -> void:
	var srv := _server({1: "Ash", 2: "Bryn"})
	srv.give_item(1, "ash_wood", 7)
	srv.sessions[1].character.skills = {"felling": 1700}
	srv.sessions[1].move = Vector2(1, 0)
	var r: Dictionary = srv.hurt(1, 250.0)
	check(r.knocked_down, "250 damage knocks a 100-health player down")
	var ch: Dictionary = srv.sessions[1].character
	var home := Vector2(ch.x - GameConfig.SPAWN_POINT.x, ch.z - GameConfig.SPAWN_POINT.z).length()
	check(home < 4.0, "back at spawn (%.1f m)" % home)
	check_eq(srv.sessions[1].move, Vector2.ZERO, "standing still on arrival")
	check_eq(Vitals.shown(srv.vitals_of(1)), [100, 100], "full on waking")
	check(not Vitals.in_combat(srv.vitals_of(1), srv.test_now), "the fight is over")
	check_eq(Inventory.count(ch.inventory, "ash_wood"), 7, "pack untouched")
	check_eq(ch.skills, {"felling": 1700}, "old XP in the save untouched")
	check_eq(_sent(srv, 1, "s2c_system"), [[Vitals.KNOCKED_DOWN_TEXT]], "told what happened")
	check_eq(_sent(srv, 2, "s2c_system"), [], "nobody else is told")
	check_eq(int(srv.sessions[1].knockdowns), 1)
	srv.free()


func test_a_knock_down_stops_a_running_gather() -> void:
	var srv := _server({1: "Ash"})
	var node: Dictionary = ResourceNodes.all()[0]
	var ch: Dictionary = srv.sessions[1].character
	var p: Vector3 = node.pos + Vector3(1.0, 0, 0)
	ch.x = p.x
	ch.y = p.y
	ch.z = p.z
	var started: Dictionary = srv.gather_start(1, int(node.id))
	if not started.ok:
		check(false, "could not start a gather to test with: %s" % started.reason)
		srv.free()
		return
	srv.hurt(1, 500.0)
	check(not GatherChannel.is_active(srv.sessions[1].channel), "the gather stopped")
	check_eq(_sent(srv, 1, "s2c_gather_end").back(), [1, int(node.id), "moved"], "ended like a move")
	srv.free()


func test_no_return_to_spawn_mid_fight() -> void:
	var srv := _server({1: "Ash"})
	srv.hurt(1, 10.0)
	_run(srv, 1.0)
	var r: Dictionary = srv.unstuck_request(1)
	check(not r.ok, "refused while in combat")
	check(str(r.text).begins_with("You can't return to Spawn Meadow mid-fight."), str(r.text))
	check_near(float(r.wait), Vitals.COMBAT_SECONDS - 1.0, 0.11, "wait is the time left in the fight")
	check(not srv.sessions[1].has("unstuck_at"), "a refusal spends no cooldown")
	_run(srv, Vitals.COMBAT_SECONDS)
	check(srv.unstuck_request(1).ok, "fine once the fight is over")
	srv.free()


func test_dev_commands_hurt_and_vitals() -> void:
	var srv := _server({1: "Ash"})
	srv._on_chat(1, "/hurt 30")
	check_eq(_sent(srv, 1, "s2c_system").back(), ["You take 30 damage. Health 70/100, stamina 100/100, in combat."])
	srv.test_now += 1.0
	srv._on_chat(1, "/vitals")
	check_eq(_sent(srv, 1, "s2c_system").back(), ["Health 70/100, stamina 100/100, in combat."])
	srv.test_now += 1.0
	srv._on_chat(1, "/hurt lots")
	check(str(_sent(srv, 1, "s2c_system").back()[0]).begins_with("Hurt how much?"), "a bad number hurts nobody")
	check_eq(int(srv.vitals_of(1).hp), 70)
	srv.test_now += 1.0
	srv._on_chat(1, "/hurt 1000")
	check_eq(_sent(srv, 1, "s2c_system").back(), [Vitals.KNOCKED_DOWN_TEXT], "the knock-down line is the whole answer")
	srv.free()


func test_hurt_and_vitals_are_dev_only() -> void:
	var srv := _server({1: "Ash"})
	srv.dev_commands = false
	srv._on_chat(1, "/hurt 50")
	check_eq(_sent(srv, 1, "s2c_system"), [[ChatCommands.NOT_FOR_CHAT]], "chat is for talking")
	check_eq(int(srv.vitals_of(1).hp), 100, "nothing happened")
	check(not ChatCommands.HELP.contains("/hurt") and not ChatCommands.HELP.contains("/vitals"), "never listed in /help")
	srv.free()


func test_hurt_amount_parsing() -> void:
	check_eq(ChatCommands.hurt_amount("/hurt"), ChatCommands.HURT_DEFAULT)
	check_eq(ChatCommands.hurt_amount("/hurt 25"), 25)
	check_eq(ChatCommands.hurt_amount("/hurt 0"), 0)
	check_eq(ChatCommands.hurt_amount("/hurt -5"), 0)
	check_eq(ChatCommands.hurt_amount("/hurt 1001"), 0)
	check_eq(ChatCommands.hurt_amount("/hurt 2.5"), 0)
	check(ChatCommands.is_hurt("/HURT 3") and ChatCommands.is_vitals("/hp") and not ChatCommands.is_vitals("/help"), "names")


func test_health_is_not_saved() -> void:
	var srv := _server({1: "Ash"})
	srv.hurt(1, 60.0)
	var saved := CharacterData.normalize(srv.sessions[1].character)
	check(not saved.has("hp") and not saved.has("vitals"), "a relog is a fresh, full bar (nothing new in the save)")
	srv.free()


func test_combat_left_and_describe() -> void:
	var v := Vitals.full()
	check_eq(Vitals.combat_left(v, 10.0), 0.0, "never hit: not in combat")
	Vitals.hit(v, 5.0, 10.0)
	check_near(Vitals.combat_left(v, 12.0), Vitals.COMBAT_SECONDS - 2.0, 0.001)
	check_eq(Vitals.describe(v, 12.0), "Health 95/100, stamina 100/100, in combat.")
	check_eq(Vitals.describe(v, 10.0 + Vitals.COMBAT_SECONDS), "Health 95/100, stamina 100/100, out of combat.")

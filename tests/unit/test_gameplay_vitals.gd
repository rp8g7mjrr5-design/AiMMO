extends TestCase
## Health and stamina rules (game/shared/vitals.gd), Milestone 2 build-ahead: costs, the
## last-gasp dodge, winded, regen delay and speed, free sprint out of combat, blocks, death,
## and health regen only out of combat.


func test_full_state() -> void:
	var v := Vitals.full()
	check_eq(v.hp, Vitals.MAX_HP)
	check_eq(v.stamina, Vitals.MAX_STAMINA)
	check(not Vitals.in_combat(v, 0.0), "a fresh state is out of combat")
	check(not Vitals.is_winded(v, 0.0), "not winded")
	check(not Vitals.is_dead(v), "alive")
	check_eq(Vitals.shares(v), {"hp": 1.0, "stamina": 1.0})


func test_spend_costs() -> void:
	var v := Vitals.full()
	var r := Vitals.spend(v, "heavy", 1.0)
	check(r.ok and r.spent == Vitals.COSTS.heavy, "heavy: %s" % [r])
	check_eq(v.stamina, Vitals.MAX_STAMINA - Vitals.COSTS.heavy)
	check_eq(Vitals.spend(v, "fly", 1.0).reason, "unknown")
	check_eq(v.stamina, Vitals.MAX_STAMINA - Vitals.COSTS.heavy, "a refusal costs nothing")


func test_swings_need_their_cost_but_a_dodge_needs_only_some() -> void:
	var v := Vitals.full()
	v.stamina = 5.0
	check_eq(Vitals.check(v, "light", 1.0), "tired", "5 < light's 8")
	check_eq(Vitals.check(v, "heavy", 1.0), "tired")
	var r := Vitals.spend(v, "dodge", 1.0)
	check(r.ok, "the last-gasp dodge always goes out: %s" % [r])
	check_eq(r.spent, 5.0, "it takes what is left")
	check_eq(v.stamina, 0.0)
	check(Vitals.is_winded(v, 1.5), "dry: winded")
	check_eq(Vitals.check(v, "dodge", 1.5), "winded", "no second free roll")
	check(not Vitals.is_winded(v, 1.0 + Vitals.WINDED_SECONDS), "winded is short and fixed")


func test_regen_waits_then_refills_fast() -> void:
	var v := Vitals.full()
	Vitals.spend(v, "dodge", 10.0)
	var after := float(v.stamina)
	Vitals.tick(v, 10.0 + Vitals.REGEN_DELAY * 0.5, 0.05)
	check_eq(v.stamina, after, "nothing during the delay")
	var t := 10.0 + Vitals.REGEN_DELAY
	var steps := 0
	while v.stamina < Vitals.MAX_STAMINA and steps < 1000:
		Vitals.tick(v, t, GameConfig.TICK_DT)
		t += GameConfig.TICK_DT
		steps += 1
	check_eq(v.stamina, Vitals.MAX_STAMINA, "refills and stops at max")
	check(Vitals.MAX_STAMINA / Vitals.REGEN <= 3.0, "empty to full in at most 3 s")


func test_sprint_is_free_out_of_combat() -> void:
	var v := Vitals.full()
	var r := Vitals.spend(v, "sprint", 1.0, 5.0)
	check(r.ok and r.spent == 0.0, "travel costs nothing: %s" % [r])
	check_eq(v.stamina, Vitals.MAX_STAMINA)
	v.stamina = 0.0
	check_eq(Vitals.check(v, "sprint", 1.0), "", "even dry, out of combat")
	v.stamina = Vitals.MAX_STAMINA
	Vitals.dealt(v, 2.0)
	r = Vitals.spend(v, "sprint", 2.5, 2.0)
	check_eq(r.spent, Vitals.COSTS.sprint * 2.0, "in combat it costs per second")


func test_block_takes_most_of_a_hit_for_stamina() -> void:
	var v := Vitals.full()
	var r := Vitals.hit(v, 40.0, 5.0, true)
	check_eq(r.blocked, 40.0 * Vitals.BLOCK_SHARE)
	check_eq(r.taken, 40.0 - 40.0 * Vitals.BLOCK_SHARE)
	check_eq(v.hp, Vitals.MAX_HP - r.taken)
	check_eq(v.stamina, Vitals.MAX_STAMINA - r.blocked * Vitals.BLOCK_COST)
	check(Vitals.in_combat(v, 5.0 + Vitals.COMBAT_SECONDS - 0.1), "a hit starts combat")


func test_a_block_that_runs_dry_still_holds_once() -> void:
	var v := Vitals.full()
	v.stamina = 2.0
	var r := Vitals.hit(v, 40.0, 5.0, true)
	check_eq(r.blocked, 40.0 * Vitals.BLOCK_SHARE, "no surprise guard break mid-swing")
	check_eq(v.stamina, 0.0)
	check(Vitals.is_winded(v, 5.1), "but you are winded")
	r = Vitals.hit(v, 40.0, 5.2, true)
	check_eq(r.blocked, 0.0, "the next one isn't blocked")
	check_eq(r.taken, 40.0)


func test_death_and_no_regen_while_dead() -> void:
	var v := Vitals.full()
	var r := Vitals.hit(v, 250.0, 1.0)
	check(r.dead, "dead")
	check_eq(v.hp, 0.0, "never below 0")
	check_eq(Vitals.check(v, "dodge", 1.0), "dead")
	Vitals.tick(v, 100.0, 1.0)
	check_eq(v.hp, 0.0, "the dead regain nothing")
	check_eq(Vitals.hit(v, 10.0, 2.0).taken, 0.0, "no hits on the dead")
	check(not Vitals.is_dead(Vitals.full()), "respawn is a full state")


func test_health_regen_only_out_of_combat() -> void:
	var v := Vitals.full()
	Vitals.hit(v, 50.0, 1.0)
	Vitals.tick(v, 1.0 + Vitals.COMBAT_SECONDS - 0.5, 1.0)
	check_eq(v.hp, 50.0, "no regen in combat")
	Vitals.dealt(v, 6.0)
	Vitals.tick(v, 6.0 + Vitals.COMBAT_SECONDS - 0.5, 1.0)
	check_eq(v.hp, 50.0, "hitting back keeps you in combat")
	var t := 6.0 + Vitals.COMBAT_SECONDS
	Vitals.tick(v, t, 1.0)
	check_eq(v.hp, 50.0, "at half, nothing comes back by itself: that takes a bandage")
	v.hp = 20.0
	Vitals.tick(v, t + 1.0, 1.0)
	check_near(float(v.hp), 20.0 + Vitals.MAX_HP * Vitals.HP_REGEN_SHARE, 0.0001, "a slow trickle below half")
	Vitals.tick(v, t + 2.0, 1000.0)
	check_eq(v.hp, Vitals.MAX_HP * Vitals.HP_REGEN_CAP, "stops at half")
	check(Vitals.HP_REGEN_CAP < 1.0, "never back to full on its own (owner direction 2026-11-26: bandages)")

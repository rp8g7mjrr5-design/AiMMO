extends TestCase
## The first crafted weapons (game/shared/weapons.gd), Milestone 2 build-ahead: two weapons
## that play differently, neither strictly best, bare hands clearly worse, short windups a
## dodge can cancel, and aimed hit checks (reach, arc, lunge, how many one swing hits).


func test_every_weapon_has_both_attacks_and_sane_numbers() -> void:
	for id in [Weapons.FISTS] + Weapons.ORDER:
		check(Weapons.exists(id), id)
		var w := Weapons.data(id)
		check(float(w.reach) > 0.0 and float(w.arc) > 0.0 and float(w.arc) <= 360.0, "%s reach/arc" % id)
		check(int(w.max_targets) >= 1, "%s hits something" % id)
		for kind in Weapons.ATTACKS:
			var a := Weapons.attack(id, kind)
			check(float(a.damage) > 0.0, "%s %s damage" % [id, kind])
			check(float(a.windup) > 0.0 and float(a.windup) <= Weapons.MAX_WINDUP, "%s %s windup %s" % [id, kind, a.windup])
			check(float(a.active) > 0.0 and float(a.recovery) > 0.0, "%s %s timing" % [id, kind])
			check(Weapons.stamina_cost(id, kind) > 0.0, "%s %s costs stamina" % [id, kind])
		check(Weapons.damage(id, "heavy") > Weapons.damage(id, "light"), "%s: heavy hits harder" % id)
		check(Weapons.swing_seconds(id, "heavy") > Weapons.swing_seconds(id, "light"), "%s: heavy is slower" % id)
	for id in Weapons.ORDER:
		check(not Weapons.data(id).has("mastery"), "%s has no mastery skill: there are no levels" % id)


func test_unknown_ids_fight_bare_handed() -> void:
	check(not Weapons.exists("laser_sword"), "unknown")
	check_eq(Weapons.label("laser_sword"), "Bare hands")
	check_eq(Weapons.damage("laser_sword", "light"), Weapons.damage(Weapons.FISTS, "light"))
	check_eq(Weapons.attack("stone_spear", "kick"), {})
	check_eq(Weapons.damage("stone_spear", "kick"), 0.0)
	check_eq(Weapons.stamina_cost("stone_spear", "kick"), 0.0)
	check(not Weapons.in_swing(Vector3.ZERO, 0.0, Vector3(0, 0, 1), 0.5, "stone_spear", "kick"), "no such attack hits nothing")


func test_the_two_weapons_play_differently() -> void:
	var spear := Weapons.data("stone_spear")
	var maul := Weapons.data("stone_maul")
	check(float(spear.reach) > float(maul.reach) + 0.5, "the spear outreaches the maul")
	check(float(maul.arc) >= 3.0 * float(spear.arc), "the maul sweeps wide, the spear thrusts narrow")
	check_eq(int(spear.max_targets), 1)
	check(int(maul.max_targets) >= 3, "the maul hits a crowd")
	check(Weapons.damage("stone_maul", "heavy") > Weapons.damage("stone_spear", "heavy") * 1.4, "the maul's heavy is the big hit")
	check(Weapons.hit_at("stone_spear", "light") < Weapons.hit_at("stone_maul", "light"), "the spear is quicker")
	check(bool(Weapons.attack("stone_maul", "heavy").stagger), "the maul's heavy staggers")
	check(Weapons.reach("stone_spear", "heavy") > Weapons.reach("stone_spear", "light"), "the spear's heavy lunges")


func test_no_weapon_is_strictly_best() -> void:
	for kind in Weapons.ATTACKS:
		var a := Weapons.damage_per_stamina("stone_spear", kind)
		var b := Weapons.damage_per_stamina("stone_maul", kind)
		check(maxf(a, b) / minf(a, b) <= Weapons.BALANCE_BAND, "%s damage per stamina %.2f vs %.2f" % [kind, a, b])
		var da := Weapons.damage_per_second("stone_spear", kind)
		var db := Weapons.damage_per_second("stone_maul", kind)
		check(maxf(da, db) / minf(da, db) <= Weapons.BALANCE_BAND, "%s damage per second %.1f vs %.1f" % [kind, da, db])


func test_each_tier_has_two_equal_shapes() -> void:
	for pair in Weapons.TIERS:
		for kind in Weapons.ATTACKS:
			var a := Weapons.damage_per_stamina(pair[0], kind)
			var b := Weapons.damage_per_stamina(pair[1], kind)
			check(maxf(a, b) / minf(a, b) <= Weapons.BALANCE_BAND, "%s vs %s %s per stamina %.2f vs %.2f" % [pair[0], pair[1], kind, a, b])
		check(Weapons.data(pair[0]).reach > Weapons.data(pair[1]).reach, "%s outreaches %s" % pair)
		check(int(Weapons.data(pair[1]).max_targets) > 1, "%s sweeps more than one" % pair[1])
	for i in 2:
		var wood: String = Weapons.TIERS[0][i]
		var stone: String = Weapons.TIERS[1][i]
		check(Weapons.damage(stone, "heavy") > Weapons.damage(wood, "heavy"), "%s hits harder than %s" % [stone, wood])
		check_eq(str(Crafting.RECIPES[stone].upgrades), wood, "%s is made from %s" % [stone, wood])


func test_making_a_weapon_is_a_real_step_up() -> void:
	for id in Weapons.ORDER:
		for kind in Weapons.ATTACKS:
			check(Weapons.damage_per_second(id, kind) > 1.4 * Weapons.damage_per_second(Weapons.FISTS, kind), "%s %s vs bare hands" % [id, kind])
		check(Weapons.data(id).reach > Weapons.data(Weapons.FISTS).reach, "%s reaches further than a fist" % id)


func test_stamina_follows_vitals_costs() -> void:
	check_near(Weapons.stamina_cost("stone_spear", "light"), Vitals.COSTS.light * 0.75, 0.001)
	check_near(Weapons.stamina_cost("stone_maul", "heavy"), Vitals.COSTS.heavy * 1.4, 0.001)
	# A full bar buys a real exchange with either weapon, not one swing.
	for id in Weapons.ORDER:
		check(Vitals.MAX_STAMINA / Weapons.stamina_cost(id, "light") >= 8.0, "%s: 8+ light swings on a full bar" % id)
		check(Vitals.MAX_STAMINA / Weapons.stamina_cost(id, "heavy") >= 2.0, "%s: 2+ heavies on a full bar" % id)


func test_a_dodge_cancels_only_the_windup() -> void:
	var w := Weapons.hit_at("stone_maul", "heavy")
	check(Weapons.can_cancel("stone_maul", "heavy", 0.0), "right after the press")
	check(Weapons.can_cancel("stone_maul", "heavy", w - 0.01), "just before it lands")
	check(not Weapons.can_cancel("stone_maul", "heavy", w), "once it lands you're committed")
	check(not Weapons.can_cancel("stone_maul", "heavy", -0.1), "not before the press")
	check(not Weapons.can_cancel("stone_maul", "kick", 0.0), "no such attack")


func test_damage_is_the_weapons_own() -> void:
	# No mastery levels: a spear hits as hard on day one as on day ninety.
	check_eq(Weapons.damage("stone_spear", "light"), float(Weapons.attack("stone_spear", "light").damage))


func test_reach_and_arc() -> void:
	# yaw 0 looks along +z.
	var o := Vector3(10, 5, 10)
	check(Weapons.in_swing(o, 0.0, o + Vector3(0, 0, 2.9), 0.0, "stone_spear", "light"), "straight ahead, in reach")
	check(not Weapons.in_swing(o, 0.0, o + Vector3(0, 0, 3.2), 0.0, "stone_spear", "light"), "just out of reach")
	check(Weapons.in_swing(o, 0.0, o + Vector3(0, 0, 3.2), 0.5, "stone_spear", "light"), "a big target's edge is in reach")
	check(Weapons.in_swing(o, 0.0, o + Vector3(0, 0, 4.3), 0.0, "stone_spear", "heavy"), "the lunge reaches further")
	check(not Weapons.in_swing(o, 0.0, o + Vector3(0, 0, -1.5), 0.0, "stone_maul", "light"), "nothing behind you")
	check(not Weapons.in_swing(o, 0.0, o + Vector3(1.0, 0, 1.0), 0.0, "stone_spear", "light"), "45 degrees off is outside the spear's line")
	check(Weapons.in_swing(o, 0.0, o + Vector3(1.0, 0, 1.0), 0.0, "stone_maul", "light"), "but inside the maul's sweep")
	check(Weapons.in_swing(o, PI * 0.5, o + Vector3(2.0, 0, 0.0), 0.0, "stone_spear", "light"), "yaw 90 degrees looks along +x")
	check(Weapons.in_swing(o, 0.0, o + Vector3(0.1, 0, -0.1), 0.0, "stone_spear", "light"), "a target on top of you is always hit")
	check(Weapons.in_swing(o, 0.0, o + Vector3(0, 20, 2.0), 0.0, "stone_spear", "light"), "height is ignored (flat distance)")


func test_the_spear_hits_one_the_maul_hits_a_crowd() -> void:
	var o := Vector3.ZERO
	var crowd := [
		{"id": "far", "pos": Vector3(0, 0, 1.9), "radius": 0.4},
		{"id": "near", "pos": Vector3(0, 0, 1.0), "radius": 0.4},
		{"id": "left", "pos": Vector3(-1.2, 0, 1.0), "radius": 0.4},
		{"id": "right", "pos": Vector3(1.2, 0, 1.0), "radius": 0.4},
		{"id": "behind", "pos": Vector3(0, 0, -1.0), "radius": 0.4},
	]
	check_eq(Weapons.targets_hit(o, 0.0, "stone_spear", "light", crowd), ["near"], "the spear stops at the first")
	var maul := Weapons.targets_hit(o, 0.0, "stone_maul", "light", crowd)
	check_eq(maul.size(), 3, "the maul hits three: %s" % [maul])
	check_eq(maul[0], "near", "nearest first")
	check(not maul.has("behind"), "never behind")
	check_eq(Weapons.targets_hit(o, PI, "stone_spear", "light", crowd), ["behind"], "turn round and it's the one behind")
	check_eq(Weapons.targets_hit(o, 0.0, "stone_spear", "light", []), [], "swinging at air")


func test_describe() -> void:
	check_eq(Weapons.describe("stone_spear"), "Stone spear: reach 3.0 m, hits 1, light 9 / heavy 21")
	check(Weapons.describe("stone_maul").begins_with("Stone maul: reach 2.1 m, hits 3"), Weapons.describe("stone_maul"))

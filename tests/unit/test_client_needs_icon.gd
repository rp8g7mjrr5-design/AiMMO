extends TestCase
## The hunger mark (NeedsIcon, protocol v12 s2c_needs): nothing on screen while you're fed,
## a quiet straw mark when hungry, a slow SMOULDER pulse when starving, and the eat key on it.


func test_only_shows_when_it_matters() -> void:
	check(not NeedsIcon.visible_for(100), "full: nothing")
	check(not NeedsIcon.visible_for(int(Needs.LOW_AT)), "at the line: still nothing")
	check(NeedsIcon.visible_for(int(Needs.LOW_AT) - 1), "hungry: shown")
	check(NeedsIcon.visible_for(0), "starving: shown")


func test_tints() -> void:
	check_eq(NeedsIcon.tint(40, 0.0), NeedsIcon.LOW_TINT, "low is straw")
	var a := NeedsIcon.tint(5, 0.0)
	var b := NeedsIcon.tint(5, NeedsIcon.PULSE_PERIOD * 0.25)
	check(a != b, "starving pulses")
	check(a.r > a.g and a.r > a.b, "and reads red")
	check(a.s < 0.75, "but stays muted (art bible: restraint)")


func test_the_node_follows_s2c_needs() -> void:
	var n := NeedsIcon.new()
	n.setup(Theme.new())
	n.on_needs({"hunger": 80})
	check(not n.showing(), "fed")
	n.on_needs({"hunger": 30, "thirst": 90})
	check(n.showing(), "hungry, and an unknown key is ignored")
	n.step(1.0)
	check(n.modulate.a > 0.9, "faded in")
	n.on_needs({"thirst": 10})
	check_eq(n.hunger, 30, "a message without hunger changes nothing")
	n.hide_all()
	check(not n.showing(), "logged out")
	n.free()


func test_eat_key_is_bound() -> void:
	check_eq(ControlsOverlay.DEFAULT_BINDS.get("eat", []), [KEY_F], "F eats")

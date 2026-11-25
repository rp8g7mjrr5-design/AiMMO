extends TestCase
## The attack keys (AttackInput): left click swings light whenever it isn't gathering, right
## click always swings heavy (cancelling a gather first), mashing sends one swing per MIN_GAP
## and none while your own swing plays, and the whoosh lands with the blow. Plus the new
## sounds and the controls overlay line.

const ON_NODE := {"id": 3, "aimed": true, "can": true}
const NEAR_NODE := {"id": 3, "aimed": false, "can": true} ## nearest-node fallback, not aimed
const CANT := {"id": 3, "aimed": true, "can": false} ## a spent node, or one you can't fell yet


func test_left_click_swings_when_not_gathering() -> void:
	check_eq(AttackInput.decide(true, false, {}, {}, false, false, false), {"kind": "light", "cancel_gather": false}, "click at open ground: a light swing")
	check_eq(AttackInput.decide(true, false, {}, NEAR_NODE, false, false, false).get("kind", ""), "light", "a node nearby but not aimed: still a swing")
	check_eq(AttackInput.decide(true, false, {}, CANT, false, false, false).get("kind", ""), "light", "a node you can't gather: swing at it")
	check(AttackInput.decide(false, false, {}, {}, false, false, false).is_empty(), "no click, no swing")


func test_left_click_on_a_node_gathers() -> void:
	check(AttackInput.decide(true, false, {"op": "start", "node": 3}, ON_NODE, false, false, false).is_empty(), "the click started a gather: no swing")
	check(AttackInput.decide(true, false, {}, ON_NODE, true, false, false).is_empty(), "clicking the node you chop keeps chopping")
	check(AttackInput.decide(true, false, {}, {}, false, true, false).is_empty(), "a gather start is waiting: the click belongs to it")


func test_swinging_out_of_a_gather() -> void:
	check_eq(AttackInput.decide(true, false, {}, {}, true, false, false), {"kind": "light", "cancel_gather": true}, "mid-gather, aimed off the node: cancel, then swing")
	check_eq(AttackInput.decide(false, true, {}, ON_NODE, true, false, false), {"kind": "heavy", "cancel_gather": true}, "right click mid-gather: cancel, then heavy")
	check_eq(AttackInput.decide(false, true, {}, ON_NODE, false, false, false), {"kind": "heavy", "cancel_gather": false}, "right click at a node: heavy, gathering is the left button")


func test_mashing_sends_one_swing() -> void:
	check(AttackInput.decide(true, true, {}, {}, false, false, true).is_empty(), "your own swing is playing: dropped")
	check(AttackInput.decide(true, false, {}, {}, false, false, false, AttackInput.MIN_GAP * 0.5).is_empty(), "inside the gap: dropped")
	check(not AttackInput.decide(true, false, {}, {}, false, false, false, AttackInput.MIN_GAP).is_empty(), "after the gap: sent")


func test_whoosh_lands_with_the_blow() -> void:
	var a := Weapons.attack(Weapons.FISTS, "heavy")
	var total := float(a.windup) + float(a.active) + float(a.recovery)
	check(absf(AttackInput.blow_delay(Weapons.FISTS, "heavy", total) - float(a.windup)) < 0.0001, "at the weapon's own pace: after the windup")
	check(absf(AttackInput.blow_delay(Weapons.FISTS, "heavy", total * 2.0) - float(a.windup) * 2.0) < 0.0001, "stretched with the server's seconds")
	check(AttackInput.blow_delay(Weapons.FISTS, "light", total) < AttackInput.blow_delay(Weapons.FISTS, "heavy", total), "light comes out faster than heavy")


func test_swing_sounds() -> void:
	var light := Sfx.whoosh(false)
	var heavy := Sfx.whoosh(true)
	var smack := Sfx.thwack()
	check_eq(light.data.size(), int(Sfx.RATE * Sfx.WHOOSH_LIGHT) * 2)
	check(heavy.data.size() > light.data.size(), "the heavy whoosh is longer")
	check_eq(smack.data.size(), int(Sfx.RATE * Sfx.THWACK_LENGTH) * 2)
	for w in [light, heavy, smack]:
		var peak := 0
		var bytes: PackedByteArray = (w as AudioStreamWAV).data
		for i in range(0, bytes.size(), 2):
			var v: int = bytes.decode_s16(i)
			peak = maxi(peak, absi(v))
		check(peak > 1000, "audible")
		check(peak < 32767 * 0.45, "restrained: under 0.45 full scale")


func test_controls_list_the_swing() -> void:
	ControlsOverlay.install_input()
	check(InputMap.has_action("click_heavy"), "click_heavy is in the InputMap")
	check_eq(ControlsOverlay.key_text("click_heavy"), "Right click")
	var found := false
	for r in ControlsOverlay.rows():
		if str(r[1]) == "Swing (light, heavy)":
			found = true
	check(found, "F1 lists the swing")

extends TestCase
## Client left-click gathering (action camera, owner direction 3: "E or left-click"): a
## click starts a gather on the node under the reticle and only that node, holding the
## button chains gathers like holding E, a click never stops a gather, and the button shows
## as "Left click" in the F1 overlay.


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func _a_day() -> float:
	for i in 96:
		var t := i * WorldClock.DAY_SECONDS / 96.0
		if not WorldClock.is_night(t):
			return t
	return 0.0


## A camera eye a little behind and above `n`'s spot, and the look straight at its centre.
func _aim(n: Dictionary) -> Array:
	var eye: Vector3 = n.pos + Vector3(0.0, 2.2, 2.6)
	return [eye, (n.pos + Vector3.UP - eye).normalized()]


func test_decide_click() -> void:
	var aimed := {"id": 7, "can": true, "aimed": true}
	var nearest := {"id": 7, "can": true, "aimed": false}
	var spent := {"id": 7, "can": false, "aimed": true}
	check_eq(GatherPrompt.decide(false, false, false, aimed, false, false, false, true, true), {"op": "start", "node": 7}, "click on the aimed node starts it")
	check_eq(GatherPrompt.decide(false, false, false, nearest, false, false, false, true, true), {}, "a click never takes the nearest-node fallback")
	check_eq(GatherPrompt.decide(false, false, false, spent, false, false, false, true, true), {}, "nor a node you can't work")
	check_eq(GatherPrompt.decide(false, false, false, aimed, false, false, false, true, false), {"op": "start", "node": 7}, "holding the button chains the next gather")
	check_eq(GatherPrompt.decide(false, false, false, aimed, false, false, true, true, false), {}, "after a refusal, holding the button waits")
	check_eq(GatherPrompt.decide(false, false, false, aimed, false, false, true, true, true), {"op": "start", "node": 7}, "a fresh click tries again")
	check_eq(GatherPrompt.decide(false, false, false, aimed, false, true, false, true, true), {}, "never twice while a start is unanswered")
	check_eq(GatherPrompt.decide(false, false, true, aimed, false, false, false, true, true), {}, "not while moving")
	check_eq(GatherPrompt.decide(false, false, false, aimed, true, false, false, true, true), {}, "a click while chopping keeps chopping")
	check_eq(GatherPrompt.decide(true, true, false, nearest, false, false, false), {"op": "start", "node": 7}, "E still takes the nearest")


func test_target_says_when_it_is_aimed() -> void:
	var n := _first("stone")
	var a := _aim(n)
	var t := GatherPrompt.target(n.pos, _a_day(), a[0], a[1])
	check_eq(int(t.id), int(n.id), "the aimed outcrop is the target")
	check(bool(t.aimed), "and it is under the reticle")
	var sky := GatherPrompt.target(n.pos, _a_day(), a[0], Vector3.UP)
	check(not sky.is_empty() and not bool(sky.aimed), "looking at the sky: the nearest, not aimed")
	var no_cam := GatherPrompt.target(n.pos, _a_day())
	check(not no_cam.is_empty() and not bool(no_cam.aimed), "no camera: never aimed")


func test_widget_click_gathers() -> void:
	var n := _first("stone")
	var a := _aim(n)
	var day := _a_day()
	var w := GatherPrompt.new()
	w.setup(Theme.new())
	var now := 50.0
	check_eq(w.update(0.05, n.pos, day, now, false, false, false, a[0], a[1], true, true), {"op": "start", "node": int(n.id)}, "click at the outcrop starts it")
	w.on_begun(n.id, 2.4, now)
	now += 0.5
	check_eq(w.update(0.05, n.pos, day, now, false, false, false, a[0], a[1], true, true), {}, "clicking again doesn't stop it")
	check(w.gathering(), "still mining")
	w.on_ended(n.id, "done")
	now += 0.05
	check_eq(w.update(0.05, n.pos, day, now, false, false, false, a[0], a[1], true, false), {"op": "start", "node": int(n.id)}, "held button chains the next")
	w.on_begun(n.id, 2.4, now)
	now += 0.3
	check_eq(w.update(0.05, n.pos, day, now, true, true, false, a[0], a[1], true, false), {"op": "cancel"}, "E stops it")
	check_eq(w.update(0.05, n.pos, day, now + 0.05, false, false, false, a[0], a[1], true, false), {}, "button still held after E: no restart")
	check_eq(w.update(0.05, n.pos, day, now + 0.1, false, false, false, a[0], a[1], false, false), {}, "let go")
	check_eq(w.update(0.05, n.pos, day, now + 0.15, false, false, false, a[0], Vector3.UP, true, true), {}, "click at the sky: nothing")
	w.free()


func test_left_click_is_bound_and_listed() -> void:
	ControlsOverlay.install_input()
	check(InputMap.has_action("click_use"), "click_use is in the InputMap")
	check_eq(ControlsOverlay.key_text("click_use"), "Left click")
	check_eq(ControlsOverlay.mouse_text(MOUSE_BUTTON_RIGHT), "Right click")
	check_eq(ControlsOverlay.mouse_text(5), "Mouse 5")
	var found := false
	for r in ControlsOverlay.rows():
		if r[1] == "Gather what you look at":
			found = r[2] == ["E", "Left click"]
	check(found, "F1 lists E and Left click for gathering")

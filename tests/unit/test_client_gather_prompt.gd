extends TestCase
## Client gather prompt: shows the nearest node in reach (and only in reach), knows seeps
## only give at night, sends "/gather <kind>" at most once per PRESS_INTERVAL, and turns the
## server's success line into a "+2 Ash wood" toast.


func _a_night_and_a_day() -> Array:
	var night := -1.0
	var day := -1.0
	for i in 96:
		var t := i * WorldClock.DAY_SECONDS / 96.0
		if WorldClock.is_night(t) and night < 0.0:
			night = t
		if not WorldClock.is_night(t) and day < 0.0:
			day = t
	return [night, day]


func _first(kind: String) -> Dictionary:
	for n in ResourceNodes.all():
		if n.kind == kind:
			return n
	return {}


func test_prompt_only_within_reach() -> void:
	var nd := _a_night_and_a_day()
	var n := _first("pine")
	check(not n.is_empty(), "there is a pine")
	var t := GatherPrompt.target(n.pos + Vector3(1.0, 0, 0.5), nd[1])
	check_eq(t.get("id", -1), n.id, "standing at the pine targets it")
	check_eq(t.get("kind", ""), "pine")
	check(bool(t.get("can", false)), "pine can be gathered by day")
	check_eq(t.get("command", ""), "/gather pine")
	check(str(t.get("text", "")) == "[E] Chop Pine", "prompt names it: %s" % t.get("text", ""))
	# Just outside reach: nothing (unless another node happens to be in reach there).
	var away: Vector3 = n.pos + Vector3(ResourceNodes.GATHER_RANGE + 0.5, 0, 0)
	var far := GatherPrompt.target(away, nd[1])
	check(far.is_empty() or int(far.id) != int(n.id), "out of reach no longer targets it")
	# Spawn Meadow centre is kept clear of nodes.
	check(GatherPrompt.target(Vector3.ZERO, nd[1]).is_empty(), "nothing to gather at the very centre of spawn")


func test_prompt_agrees_with_the_server_rules() -> void:
	# Wherever the prompt shows a node, the server's own reach check agrees, and the command
	# picks that very node (Gathering.pick_target with its kind, on a fresh world).
	var nd := _a_night_and_a_day()
	var state := Gathering.new_state()
	var checked := 0
	for n in ResourceNodes.all().slice(0, 60):
		for off in [Vector3(0.5, 0, 0), Vector3(-2.0, 0, 1.5), Vector3(0, 0, -2.8)]:
			var pos: Vector3 = n.pos + off
			var t := GatherPrompt.target(pos, nd[0])
			if t.is_empty():
				continue
			checked += 1
			check(ResourceNodes.in_range(t.id, pos), "prompted node %d is in reach" % t.id)
			var picked := Gathering.pick_target(state, pos, 0.0, nd[0], t.kind)
			check_eq(picked, t.id, "/gather %s picks the prompted node" % t.kind)
	check(checked > 100, "checked %d positions" % checked)


func test_action_words() -> void:
	var nd := _a_night_and_a_day()
	check_eq(GatherPrompt.target(_first("ash").pos, nd[1]).text, "[E] Chop Ember Ash")
	check_eq(GatherPrompt.target(_first("ember_sap").pos, nd[0]).text, "[E] Collect Ember Sap")


func test_seeps_only_at_night() -> void:
	var nd := _a_night_and_a_day()
	var seep := _first("ember_sap")
	check(not seep.is_empty(), "there is a seep")
	var by_day := GatherPrompt.target(seep.pos, nd[1])
	check(not bool(by_day.can), "a seep can't be gathered by day")
	check(str(by_day.text).contains("only seeps at night"), by_day.text)
	check(bool(GatherPrompt.target(seep.pos, nd[0]).can), "a seep can be gathered at night")


func test_press_interval_and_progress() -> void:
	check(GatherPrompt.PRESS_INTERVAL >= Gathering.COOLDOWN, "never faster than the server's cooldown")
	check(GatherPrompt.PRESS_INTERVAL >= GameConfig.CHAT_COOLDOWN, "never faster than the chat cooldown")
	check(GatherPrompt.can_press(10.0, -INF), "first press goes")
	check(not GatherPrompt.can_press(10.5, 10.0), "too soon")
	check(GatherPrompt.can_press(10.0 + GatherPrompt.PRESS_INTERVAL, 10.0), "ready again")
	check_near(GatherPrompt.progress(0.0), 0.0, 0.0001)
	check_near(GatherPrompt.progress(GatherPrompt.PRESS_INTERVAL * 0.5), 0.5, 0.0001)
	check_near(GatherPrompt.progress(99.0), 1.0, 0.0001)


func test_parses_every_success_line() -> void:
	for n in [_first("ash"), _first("pine"), _first("stone"), _first("ember_sap")]:
		var info := ResourceNodes.kind_info(n.kind)
		for depleted in [false, true]:
			var line := Gathering.success(n.id, 2, 7, depleted)
			var g := GatherPrompt.parse_gain(line)
			check_eq(g.get("qty", -1), 2, line)
			check_eq(g.get("in_pack", -1), 7, line)
			check_eq(g.get("item", ""), str(info.item), line)
			check_eq(GatherPrompt.toast_text(g), "+2 %s  (7)" % {"ash_wood": "Ash wood", "pine_wood": "Pine wood", "stone": "Stone", "ember_sap": "Ember sap"}[str(info.item)], line)
	for other in ["Easy; you're still gathering.", "Nothing to gather within reach. The nearest pine is 14 m to the north.",
			"Your pack can't hold any more stone.", "Ash: You gather 2 ash wood from the pine (1 in your pack)."]:
		check(GatherPrompt.parse_gain(other).is_empty(), "not a gain: %s" % other)


func test_toast_fades() -> void:
	check_near(GatherPrompt.toast_alpha(0.0), 1.0, 0.0001)
	check_near(GatherPrompt.toast_alpha(GatherPrompt.TOAST_SECONDS * 0.5), 1.0, 0.0001)
	var late := GatherPrompt.toast_alpha(GatherPrompt.TOAST_SECONDS * 0.9)
	check(late > 0.0 and late < 1.0, "fading near the end: %f" % late)
	check_near(GatherPrompt.toast_alpha(GatherPrompt.TOAST_SECONDS), 0.0, 0.0001)
	check_near(GatherPrompt.toast_alpha(INF), 0.0, 0.0001)


func test_widget_sends_once_per_interval_and_toasts() -> void:
	var nd := _a_night_and_a_day()
	var n := _first("stone")
	var w := GatherPrompt.new()
	w.setup(Theme.new())
	var sent: Array = []
	var now := 100.0
	for i in 60: # E held for 3 s at 20 fps
		var cmd := w.update(0.05, n.pos, nd[1], now, true)
		if cmd != "":
			sent.append([now, cmd])
		now += 0.05
	check_eq(sent.size(), 2, "holding E for 3 s gathers twice (%s)" % str(sent))
	check_eq(sent[0][1], "/gather stone")
	check(w.prompt_label.visible and w.prompt_label.text == "[E] Mine Stone Outcrop", w.prompt_label.text)
	check(w.bar.visible, "bar shows while gathering")
	check_eq(w.update(0.05, Vector3.ZERO, nd[1], now + 5.0, true), "", "nothing in reach: nothing sent")
	check(not w.prompt_label.visible, "prompt hidden away from nodes")
	check(w.on_system(Gathering.success(n.id, 2, 4, false)), "success line makes a toast")
	check_eq(w.toast_label.text, "+2 Stone  (4)")
	check(not w.on_system("Easy; you're still gathering."), "a refusal makes no toast")
	w.hide_all()
	check(not w.prompt_label.visible and w.toast_label.modulate.a == 0.0, "hidden on disconnect")
	w.free()

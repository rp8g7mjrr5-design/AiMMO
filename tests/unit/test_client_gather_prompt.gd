extends TestCase
## Client gather prompt on protocol v3: shows the nearest live node in reach (and only in
## reach), knows seeps only give at night and spent nodes give nothing, starts and cancels
## timed gathers by node id, fills the bar over the server's seconds, and turns
## s2c_gather_result into a "+2 Ash wood  (6)" toast. Also GatherWatch (hits, then depletion).


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
	check_eq(t.get("doing", ""), "Chopping Pine")
	check(str(t.get("text", "")) == "[E] Chop Pine", "prompt names it: %s" % t.get("text", ""))
	var away: Vector3 = n.pos + Vector3(ResourceNodes.GATHER_RANGE + 0.5, 0, 0)
	var far := GatherPrompt.target(away, nd[1])
	check(far.is_empty() or int(far.id) != int(n.id), "out of reach no longer targets it")
	check(GatherPrompt.target(Vector3.ZERO, nd[1]).is_empty(), "nothing to gather at the very centre of spawn")


func test_prompt_agrees_with_the_server_rules() -> void:
	# Wherever the prompt offers a node, the server's own checks would let you gather it.
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
			check_eq(Gathering.check(state, t.id, pos, 0.0, nd[0], -INF, 0.0), "", "server takes node %d" % t.id)
	check(checked > 100, "checked %d positions" % checked)


func test_spent_nodes_are_skipped() -> void:
	var nd := _a_night_and_a_day()
	var n := _first("stone")
	var t := GatherPrompt.target(n.pos, nd[1], Vector3.ZERO, Vector3.ZERO, {int(n.id): true})
	check(not t.is_empty(), "a spent node still shows (greyed) when it's all there is")
	if int(t.id) == int(n.id):
		check(not bool(t.can), "a spent node can't be gathered")
		check_eq(t.text, "Stone outcrop is spent for now")
	# Away from that node (and any other in reach) the spent set changes nothing.
	check(GatherPrompt.target(Vector3.ZERO, nd[1], Vector3.ZERO, Vector3.ZERO, {int(n.id): true}).is_empty(), "nothing in reach at spawn")


func test_action_words() -> void:
	var nd := _a_night_and_a_day()
	check_eq(GatherPrompt.target(_first("ash").pos, nd[1]).text, "[E] Chop Ember Ash")
	check_eq(GatherPrompt.target(_first("ember_sap").pos, nd[0]).text, "[E] Collect Ember Sap")
	check_eq(GatherPrompt.doing_text("stone"), "Mining Stone Outcrop")
	check_eq(GatherPrompt.doing_text("ember_sap"), "Collecting Ember Sap")
	check_eq(GatherPrompt.doing_text("nope"), "Gathering")


func test_seeps_only_at_night() -> void:
	var nd := _a_night_and_a_day()
	var seep := _first("ember_sap")
	var by_day := GatherPrompt.target(seep.pos, nd[1])
	check(not bool(by_day.can), "a seep can't be gathered by day")
	check(str(by_day.text).contains("night"), by_day.text)
	check(bool(GatherPrompt.target(seep.pos, nd[0]).can), "a seep can be gathered at night")


func test_decide() -> void:
	var t := {"id": 7, "can": true}
	var no := {"id": 7, "can": false}
	check_eq(GatherPrompt.decide(false, true, false, t, false, false, false), {"op": "start", "node": 7}, "press starts")
	check_eq(GatherPrompt.decide(true, false, false, t, false, false, false), {"op": "start", "node": 7}, "holding starts the next")
	check_eq(GatherPrompt.decide(true, false, false, t, false, false, true), {}, "after a refusal, holding waits")
	check_eq(GatherPrompt.decide(false, true, false, t, false, false, true), {"op": "start", "node": 7}, "a fresh press tries again")
	check_eq(GatherPrompt.decide(true, true, false, t, false, true, false), {}, "never twice while a start is unanswered")
	check_eq(GatherPrompt.decide(true, true, true, t, false, false, false), {}, "not while moving")
	check_eq(GatherPrompt.decide(true, true, false, no, false, false, false), {}, "not a seep by day or a spent node")
	check_eq(GatherPrompt.decide(true, true, false, {}, false, false, false), {}, "nothing in reach")
	check_eq(GatherPrompt.decide(true, false, false, t, true, false, false), {}, "holding keeps the gather going")
	check_eq(GatherPrompt.decide(true, true, false, t, true, false, false), {"op": "cancel"}, "E again stops")
	check_eq(GatherPrompt.decide(false, false, true, t, true, false, false), {"op": "cancel"}, "moving stops")


func test_progress_and_words() -> void:
	var ch := {"started": 10.0, "seconds": 2.0}
	check_near(GatherPrompt.progress(ch, 10.0), 0.0, 0.0001)
	check_near(GatherPrompt.progress(ch, 11.0), 0.5, 0.0001)
	check_near(GatherPrompt.progress(ch, 99.0), 1.0, 0.0001)
	check_near(GatherPrompt.progress({}, 11.0), 0.0, 0.0001)
	check_eq(GatherPrompt.notice_text("full"), "Your pack is full")
	for quiet in ["done", "moved", "stopped", "busy", "cooldown", "disconnected"]:
		check_eq(GatherPrompt.notice_text(quiet), "", quiet)
	var n := _first("ash")
	check(GatherPrompt.is_echo(GatherChannel.begin_text(n.id, 2.0)), "start line is an echo")
	check(GatherPrompt.is_echo(Gathering.success(n.id, 2, 4, false)), "haul line is an echo")
	check(GatherPrompt.is_echo(GatherChannel.cancel_text("moved")), "stop line is an echo")
	check(not GatherPrompt.is_echo("Your pack can't hold any more stone."), "a refusal stays in chat")
	check(not GatherPrompt.is_echo("Mara joined."), "join lines stay")


func test_parses_every_success_line() -> void:
	for kind in ResourceNodes.KINDS:
		var info: Dictionary = ResourceNodes.KINDS[kind]
		for n in ResourceNodes.all():
			if n.kind != kind:
				continue
			var line := Gathering.success(n.id, 2, 7, false)
			var g := GatherPrompt.parse_gain(line)
			check_eq(g.get("item", ""), info.item, line)
			check_eq(GatherPrompt.toast_text(g).left(3), "+2 ", line)
			break
	check_eq(GatherPrompt.toast_text({"qty": 2, "label": "ash wood", "in_pack": 6}), "+2 Ash wood  (6)")
	check_eq(GatherPrompt.toast_text({"qty": 1, "label": "ember sap"}), "+1 Ember sap", "no count known")
	check(GatherPrompt.parse_gain("Easy; you're still gathering.").is_empty(), "not a gain")


func test_toast_fades() -> void:
	check_near(GatherPrompt.toast_alpha(0.0), 1.0, 0.0001)
	check_near(GatherPrompt.toast_alpha(GatherPrompt.TOAST_SECONDS * 0.5), 1.0, 0.0001)
	var late := GatherPrompt.toast_alpha(GatherPrompt.TOAST_SECONDS * 0.9)
	check(late > 0.0 and late < 1.0, "fading near the end")
	check_near(GatherPrompt.toast_alpha(GatherPrompt.TOAST_SECONDS), 0.0, 0.0001)
	check_near(GatherPrompt.toast_alpha(INF), 0.0, 0.0001)


func test_widget_runs_a_timed_gather() -> void:
	var nd := _a_night_and_a_day()
	var n := _first("stone")
	var w := GatherPrompt.new()
	w.setup(Theme.new())
	var now := 100.0
	var op := w.update(0.05, n.pos, nd[1], now, true, true)
	check_eq(op, {"op": "start", "node": int(n.id)}, "E at the outcrop starts it")
	check_eq(w.prompt_label.text, "[E] Mine Stone Outcrop")
	now += 0.05
	check_eq(w.update(0.05, n.pos, nd[1], now, true), {}, "no second start while waiting for the server")
	w.on_begun(n.id, 2.4, now)
	check(w.gathering(), "begun")
	now += 1.2
	w.update(0.05, n.pos, nd[1], now, true)
	check(w.bar.visible, "bar shows while gathering")
	check_near(w.bar.value, 0.5, 0.01, "half way after half the server's time")
	check_eq(w.prompt_label.text, "Mining Stone Outcrop")
	# Done: pack first, then the result, then the end; holding E starts the next at once.
	w.pack = {"stone": 4}
	w.on_result("stone", 2)
	check_eq(w.toast_label.text, "+2 Stone  (4)")
	check_eq(w.toast_item(), "stone")
	check_eq(w.on_ended(n.id, "done"), "", "no notice for a finished gather")
	check(not w.gathering(), "ended")
	now += 0.05
	check_eq(w.update(0.05, n.pos, nd[1], now, true), {"op": "start", "node": int(n.id)}, "held E chains the next gather")
	w.on_begun(n.id, 2.4, now)
	# E again stops it at once, and holding doesn't restart it.
	now += 0.3
	check_eq(w.update(0.05, n.pos, nd[1], now, true, true), {"op": "cancel"}, "E again cancels")
	check(not w.gathering() and not w.bar.visible, "bar gone at once")
	check_eq(w.update(0.05, n.pos, nd[1], now + 0.05, true), {}, "still holding: no restart")
	w.on_ended(n.id, "stopped")
	check_eq(w.update(0.05, n.pos, nd[1], now + 0.1, false), {}, "let go")
	check_eq(w.update(0.05, n.pos, nd[1], now + 0.15, true, true), {"op": "start", "node": int(n.id)}, "press again")
	# A refusal: centre notice, and holding doesn't hammer the server.
	check_eq(w.on_ended(n.id, "full"), "Your pack is full")
	check_eq(w.toast_label.text, "Your pack is full")
	check_eq(w.toast_item(), "", "no icon on a notice")
	check_eq(w.update(0.05, n.pos, nd[1], now + 0.2, true), {}, "held after a refusal: nothing")
	# Walking away from nothing; nothing in reach.
	check_eq(w.update(0.05, Vector3.ZERO, nd[1], now + 5.0, true, true), {}, "nothing in reach: nothing sent")
	check(not w.prompt_label.visible, "prompt hidden away from nodes")
	w.hide_all()
	check(not w.prompt_label.visible and w.toast_label.modulate.a == 0.0, "hidden on disconnect")
	check(w.spent.is_empty() and w.pack.is_empty(), "forgets the last session")
	w.free()


func test_unanswered_start_is_asked_again() -> void:
	var nd := _a_night_and_a_day()
	var n := _first("pine")
	var w := GatherPrompt.new()
	w.setup(Theme.new())
	check_eq(w.update(0.05, n.pos, nd[1], 10.0, true, true).get("op", ""), "start")
	check_eq(w.update(0.05, n.pos, nd[1], 10.0 + GatherPrompt.ASK_TIMEOUT * 0.5, true), {}, "waiting")
	check_eq(w.update(0.05, n.pos, nd[1], 10.0 + GatherPrompt.ASK_TIMEOUT + 0.01, true).get("op", ""), "start", "lost answer: ask again")
	w.free()


func test_watch_hits_before_depletion() -> void:
	var w := GatherWatch.new()
	w.begun(5, 40)
	check_eq(w.node_state(40, true, 1.0), [], "emptied while someone gathers it: wait for the hit")
	check_eq(w.ended(5, 40, "done"), [["hit", 40], ["deplete", 40, true]], "hit first, then the empty look")
	check_eq(w.node_state(40, false, 2.0), [["deplete", 40, false]], "regrows at once")
	check_eq(w.node_state(41, true, 2.0), [["deplete", 41, true]], "nobody on it: at once")
	w.begun(6, 42)
	w.node_state(42, true, 3.0)
	check_eq(w.tick(3.1), [], "still waiting")
	check_eq(w.tick(3.0 + GatherWatch.DEFER_MAX), [["deplete", 42, true]], "the end never came: show it anyway")
	check_eq(w.ended(6, 42, "done"), [["hit", 42]], "a late end still shakes it, no second depletion")
	w.begun(7, 43)
	w.node_state(43, true, 4.0)
	check_eq(w.ended(7, 43, "moved"), [["deplete", 43, true]], "a broken-off gather: no hit, empty now")
	w.begun(8, 44)
	w.forget(8)
	check_eq(w.node_state(44, true, 5.0), [["deplete", 44, true]], "a peer who left gathers nothing")
	w.begun(9, 45)
	w.reset()
	check(w.running.is_empty(), "reset")


func test_haul_sounds() -> void:
	var seen := {}
	for kind in ResourceNodes.KINDS:
		var wav := Sfx.haul(kind)
		var secs := wav.data.size() / 2.0 / Sfx.RATE
		check(secs > 0.2 and secs < 0.5, "%s haul is short (%.2f s)" % [kind, secs])
		var peak := 0
		for i in range(0, wav.data.size(), 2):
			var v := wav.data.decode_s16(i)
			peak = maxi(peak, absi(v))
		check(peak > 3000 and peak < 32767, "%s is audible and doesn't clip (%d)" % [kind, peak])
		seen[wav.data.slice(0, 4000).hex_encode().md5_text()] = kind
	check(seen.size() >= 3, "wood, stone and sap sound different")

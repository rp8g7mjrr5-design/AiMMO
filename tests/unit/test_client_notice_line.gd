extends TestCase
## Client: system notices centre screen (chat is for talking). Routing, splitting, pairing
## with the gather prompt's refusal toast, hold and fade, and the node itself.


func test_routes_people_to_chat_and_the_rest_centre() -> void:
	check_eq(NoticeLine.route("Ash has arrived."), "chat", "join stays in chat")
	check_eq(NoticeLine.route("Wren Two has left."), "chat", "leave stays in chat")
	check_eq(NoticeLine.route(ChatCommands.TOO_FAST), "notice", "too fast")
	check_eq(NoticeLine.route(ChatCommands.NOT_FOR_CHAT), "notice", "not for chat")
	check_eq(NoticeLine.route("There is nothing to gather there."), "notice")
	check_eq(NoticeLine.route(Gathering.full_text(int(ResourceNodes.all()[0].id))), "notice", "a full haul: says so")
	check_eq(NoticeLine.route("   "), "drop", "blank")
	check_eq(NoticeLine.route("x".repeat(NoticeLine.MAX_CHARS + 1)), "chat", "long dev answers stay in chat")
	check_eq(NoticeLine.route("Recipes:\nTorch"), "chat", "multi-line answers stay in chat")
	check(not NoticeLine.is_presence("The ash has arrived at last, and more besides, and still more words here."), "only short name lines")


func test_pairs_with_the_gather_toast() -> void:
	# A refusal whose toast already says it: the server's longer line is dropped.
	for reason in ["full", "day", "busy", "cooldown", "tool", "far", "unknown"]:
		check(GatherPrompt.notice_for(reason, -1) != "" or reason in ["busy", "cooldown"], "%s has toast words (or none)" % reason)
		check_eq(NoticeLine.route("Your pack can't hold any more ash wood.", reason), "drop", reason)
	# Depleted adds when it comes back and where the next one is: show it.
	check_eq(NoticeLine.route("This ember ash is spent; it comes back in about 3 minutes. The nearest ember ash is 12 m north.", "depleted"), "notice")
	# Join lines go to chat even straight after a refusal.
	check_eq(NoticeLine.route("Ash has arrived.", "full"), "chat")


func test_splits_headline_and_detail() -> void:
	check_eq(NoticeLine.split(ChatCommands.NOT_FOR_CHAT), {"headline": "Chat is for talking.", "detail": "Press F1 for controls."})
	check_eq(NoticeLine.split("There is nothing to gather there."), {"headline": "There is nothing to gather there.", "detail": ""})
	var d := NoticeLine.split("This ember ash is spent; it comes back in about 3 minutes. The nearest ember ash is 12 m north. Go on!")
	check_eq(d.headline, "This ember ash is spent; it comes back in about 3 minutes.")
	check_eq(d.detail, "The nearest ember ash is 12 m north. Go on!")
	check_eq(NoticeLine.split("Welcome back, Ash."), {"headline": "Welcome back, Ash.", "detail": ""})
	check_eq(NoticeLine.split("Wait! Not yet."), {"headline": "Wait!", "detail": "Not yet."})


func test_hold_and_fade() -> void:
	var short := NoticeLine.hold_seconds("No.")
	var long := NoticeLine.hold_seconds("x".repeat(200))
	check_eq(short, NoticeLine.HOLD_MIN, "short lines hold the minimum")
	check_eq(long, NoticeLine.HOLD_MAX, "long lines are capped")
	check(NoticeLine.hold_seconds(ChatCommands.NOT_FOR_CHAT) > short, "longer lines hold longer")
	check_eq(NoticeLine.alpha(0.0, 3.0), 1.0, "full at once")
	check_eq(NoticeLine.alpha(3.0 - NoticeLine.FADE_SECONDS, 3.0), 1.0, "full until the fade")
	var mid := NoticeLine.alpha(3.0 - NoticeLine.FADE_SECONDS * 0.5, 3.0)
	check(mid > 0.0 and mid < 1.0, "fading: %f" % mid)
	check_eq(NoticeLine.alpha(3.0, 3.0), 0.0, "gone at the end")
	check_eq(NoticeLine.alpha(INF, 3.0), 0.0, "nothing shown")
	check_near(NoticeLine.pop_scale(0.0), NoticeLine.POP_FROM, 0.001, "pops")
	check(NoticeLine.POP_FROM <= 1.06, "a small settle, not a shout (art bible section 9)")
	check_eq(NoticeLine.pop_scale(NoticeLine.POP_SECONDS), 1.0, "settles")
	var last := 2.0
	for i in 15:
		var s := NoticeLine.pop_scale(i * NoticeLine.POP_SECONDS / 14.0)
		check(s <= last + 0.0001, "never grows back")
		last = s


func test_node_shows_pairs_and_fades() -> void:
	var n := NoticeLine.new()
	n.setup(Theme.new())
	check(not n.visible, "hidden at first")
	check_eq(n.on_system("Ash has arrived."), "chat")
	check(not n.visible, "a join shows nothing here")
	check_eq(n.on_system(ChatCommands.NOT_FOR_CHAT), "notice")
	check(n.visible and n.refusal, "a refusal shows")
	check_eq(n.headline_label.text, "Chat is for talking.")
	check_eq(n.detail_label.text, "Press F1 for controls.")
	check_eq(n.text_now(), ChatCommands.NOT_FOR_CHAT)
	# A gather refusal's toast, then the server's longer line in the same tick: dropped.
	n.note_refusal("full")
	check_eq(n.paired_reason(), "full")
	check_eq(n.on_system("Your pack can't hold any more ash wood."), "drop")
	check_eq(n.paired_reason(), "", "one line answers one refusal")
	check_eq(n.headline_label.text, "Chat is for talking.", "the old notice stays")
	# ... but not if it comes much later.
	n.note_refusal("full")
	n.step(NoticeLine.PAIR_WINDOW + 0.1)
	check_eq(n.on_system("There is nothing to gather there."), "notice", "late lines stand alone")
	check_eq(n.headline_label.text, "There is nothing to gather there.", "a new notice replaces the old")
	check(not n.detail_label.visible, "no detail line")
	# A welcome: not a refusal.
	n.show_notice("Welcome back, Ash.", false)
	check(not n.refusal, "a welcome is not a refusal")
	check_eq(n.text_now(), "Welcome back, Ash.")
	# It fades on its own, and never takes the mouse.
	check_eq(n.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	n.step(NoticeLine.HOLD_MAX + 0.1)
	check(not n.visible, "gone after its hold")
	check_eq(n.text_now(), "")
	# The same notice again holds it longer without a second pop.
	n.show_notice(ChatCommands.TOO_FAST)
	n.step(1.0)
	n.show_notice(ChatCommands.TOO_FAST)
	check_eq(n.scale, Vector2.ONE, "no second pop")
	n.step(NoticeLine.hold_seconds(ChatCommands.TOO_FAST) - 0.5)
	check(n.visible, "the repeat restarted the hold")
	n.hide_all()
	check(not n.visible, "hide_all")
	n.free()


func test_nope_sound() -> void:
	var w := Sfx.nope()
	check(w.data.size() > 0, "has samples")
	var secs := float(w.data.size()) / 2.0 / Sfx.RATE
	check(secs > 0.2 and secs < 0.5, "short: %.2f s" % secs)
	var peak := 0
	for i in range(0, w.data.size(), 2):
		var v := w.data.decode_s16(i)
		peak = maxi(peak, absi(v))
	check(peak > 1000 and peak < 16000, "quiet but audible: peak %d" % peak)

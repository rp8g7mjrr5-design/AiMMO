extends TestCase
## Client workbench window: the prompt shows only at the bench, each recipe row lights up
## only when the server would agree (Crafting.check), and Craft goes out as one c2s_craft
## request whose craft_result the window shows (protocol v3; no chat commands).


func _bench() -> Vector3:
	return Crafting.workbench_pos()


func test_prompt_only_at_the_bench() -> void:
	check(CraftWindow.near_bench(_bench()), "at the bench")
	check(CraftWindow.near_bench(_bench() + Vector3(Crafting.BENCH_RANGE - 0.5, 0, 0)), "just inside range")
	check(not CraftWindow.near_bench(_bench() + Vector3(Crafting.BENCH_RANGE + 0.5, 0, 0)), "just outside range")
	check(not CraftWindow.walked_away(_bench() + Vector3(Crafting.BENCH_RANGE + 0.5, 0, 0)), "a step out keeps the window open")
	check(CraftWindow.walked_away(_bench() + Vector3(Crafting.BENCH_RANGE + 2.0, 0, 0)), "walking off closes it")


func test_rows_agree_with_the_server_rules() -> void:
	var packs := [{}, {"ash_wood": 3, "stone": 2}, {"ash_wood": 3, "stone": 2, "stone_axe": 1},
		{"pine_wood": 5, "ember_sap": 2, "stone": 9, "ash_wood": 9}, {"torch": 98, "pine_wood": 1, "ember_sap": 1}]
	var spots := [_bench(), _bench() + Vector3(40, 0, 0)]
	for inv in packs:
		for p in spots:
			for id in Crafting.RECIPE_ORDER:
				var r := CraftWindow.row(inv, id, p)
				check_eq(r.reason, Crafting.check(inv, id, p), "%s with %s" % [id, inv])
				for part in r.parts:
					check_eq(bool(part.ok), int(part.have) >= int(part.need))
	var axe := CraftWindow.row({"ash_wood": 2, "stone": 2}, "stone_axe", _bench())
	check_eq(axe.title, "Stone axe")
	check_eq(axe.hint, "Need 1 ash wood")
	check_eq(axe.parts[0], {"item": "ash_wood", "label": "Ash wood", "have": 2, "need": 3, "ok": false})
	check_eq(axe.parts[1], {"item": "stone", "label": "Stone", "have": 2, "need": 2, "ok": true})
	check(CraftWindow.parts_bbcode(axe.parts).contains("Ash wood 2/3"), "needs text")
	var torch := CraftWindow.row({}, "torch", _bench() + Vector3(40, 0, 0))
	check_eq(torch.title, "Torch ×3")
	check(str(torch.hint).ends_with("craft anywhere"), "torch says anywhere: %s" % torch.hint)
	check_eq(CraftWindow.row({"stone_axe": 1}, "stone_axe", _bench()).button, "Have it")
	check_eq(CraftWindow.toast_text("stone_axe"), "Crafted: Stone axe!")
	check_eq(CraftWindow.toast_text("torch"), "Crafted: 3 Torches!")


## The window sends nothing until you press Craft, then exactly one c2s_craft request, and
## lights its buttons again on the server's answer. No chat line is ever involved.
func test_craft_goes_out_as_one_request() -> void:
	var w := CraftWindow.new()
	w.setup(Theme.new())
	var sent: Array = []
	w.craft_requested.connect(func(id: String): sent.append(id))
	w.open(_bench())
	check_eq(w.status_label.text, "Checking your pack...", "no pack yet")
	check(not w.craft("stone_axe"), "no pack, no request")
	w.seed_pack({"ash_wood": 3, "stone": 2})
	w.open(_bench())
	check_eq(w.status_label.text, "", "pack known: nothing to wait for")
	check(not (w._rows["stone_axe"].button as Button).disabled, "axe is craftable")
	check((w._rows["campfire"].button as Button).disabled, "campfire is not")
	check(w.craft("stone_axe"), "press Craft")
	check_eq(sent, ["stone_axe"], "one request, by exact recipe id")
	check_eq(w.status_label.text, CraftWindow.WORKING)
	check((w._rows["stone_axe"].button as Button).disabled, "buttons wait while crafting")
	check(not w.craft("stone_axe"), "a second press waits for the answer")
	check(not w.craft("moon"), "unknown ids are never sent")
	check_eq(sent.size(), 1, "still one request")
	# The server's answer, then its pack update.
	var server := {"stone_axe": 1}
	var text := Crafting.success("stone_axe", 1, server)
	var r := w.on_craft_result("stone_axe", true, text)
	check(bool(r.ok), "ok")
	check_eq(r.crafted, "stone_axe", "the toast is for the axe")
	check_eq(w.status_label.text, text, "the server's own words")
	check_eq(w.status_label.modulate, CraftWindow.ACCENT)
	check(not w.is_waiting(), "answered")
	w.seed_pack(server)
	check_eq(Inventory.to_wire(w.pack), {"stone_axe": 1}, "pack is the server's")
	check_eq((w._rows["stone_axe"].button as Button).text, "Have it")
	w.free()


func test_refusals_and_lost_answers() -> void:
	var w := CraftWindow.new()
	w.setup(Theme.new())
	var sent: Array = []
	w.craft_requested.connect(func(id: String): sent.append(id))
	var far := _bench() + Vector3(40, 0, 0)
	w.seed_pack({"pine_wood": 1, "ember_sap": 1})
	w.open(far)
	check(w.craft("torch"), "torches are made anywhere")
	var why := Crafting.refusal("missing", {}, "torch", far)
	var r := w.on_craft_result("torch", false, why)
	check(not bool(r.ok) and str(r.crafted) == "", "a refusal makes no toast")
	check_eq(w.status_label.text, why, "the refusal is shown in the window, not chat")
	check_eq(w.status_label.modulate, CraftWindow.SHORT_COLOR)
	# An answer that never comes: the buttons light again after the timeout.
	check(w.craft("torch"), "press again")
	w.tick(CraftWindow.REPLY_TIMEOUT * 0.5, far)
	check(w.is_waiting(), "still waiting")
	w.tick(CraftWindow.REPLY_TIMEOUT, far)
	check(not w.is_waiting(), "gave up")
	check_eq(w.status_label.text, CraftWindow.NO_ANSWER)
	check(not (w._rows["torch"].button as Button).disabled, "torch can be pressed again")
	# A late answer for another recipe doesn't clear the one in flight.
	check(w.craft("torch"), "press once more")
	w.on_craft_result("stone_axe", false, "late")
	check(w.is_waiting(), "torch still in flight")
	w.on_craft_result("torch", true, Crafting.success("torch", 3, {"torch": 3}))
	check(not w.is_waiting(), "torch answered")
	check_eq(sent, ["torch", "torch", "torch"], "three presses, three requests")
	# Disconnect clears everything.
	w.reset()
	check(not w.pack_known and not w.visible and not w.is_waiting(), "reset")
	check_eq(w.status_label.text, "")
	w.free()


func test_walking_away_closes_the_window() -> void:
	var w := CraftWindow.new()
	w.setup(Theme.new())
	w.seed_pack({})
	w.open(_bench())
	var closes := [0]
	w.closed.connect(func(): closes[0] += 1)
	w.tick(0.016, _bench() + Vector3(Crafting.BENCH_RANGE + 0.5, 0, 0))
	check(w.visible, "a step out keeps it open")
	w.tick(0.016, _bench() + Vector3(Crafting.BENCH_RANGE + 3.0, 0, 0))
	check(not w.visible, "closed after walking away")
	check_eq(closes[0], 1, "closed once")
	w.free()


## The whole window script is free of chat: it can't send or parse a slash command.
func test_no_chat_commands_left() -> void:
	var src := FileAccess.get_file_as_string("res://client/craft_window.gd")
	for needle in ["\"/bag", "\"/craft", "c2s_chat", "on_system"]:
		check(not src.contains(needle), "craft_window.gd has no %s" % needle)

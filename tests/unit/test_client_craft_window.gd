extends TestCase
## Client workbench window: the prompt shows only at the bench, the pack mirror follows the
## server's lines exactly (bag, gathers, crafts), each recipe row lights up only when the
## server would agree (Crafting.check), and the window only sends one line per chat cooldown.


func _bench() -> Vector3:
	return Crafting.workbench_pos()


func test_prompt_only_at_the_bench() -> void:
	check(CraftWindow.near_bench(_bench()), "at the bench")
	check(CraftWindow.near_bench(_bench() + Vector3(Crafting.BENCH_RANGE - 0.5, 0, 0)), "just inside range")
	check(not CraftWindow.near_bench(_bench() + Vector3(Crafting.BENCH_RANGE + 0.5, 0, 0)), "just outside range")
	check(not CraftWindow.walked_away(_bench() + Vector3(Crafting.BENCH_RANGE + 0.5, 0, 0)), "a step out keeps the window open")
	check(CraftWindow.walked_away(_bench() + Vector3(Crafting.BENCH_RANGE + 2.0, 0, 0)), "walking off closes it")


func test_parse_pack_matches_the_server_text() -> void:
	var inv := {"ash_wood": 4, "stone": 2, "stone_axe": 1, "ember_sap": 0}
	var parsed: Variant = CraftWindow.parse_pack(Inventory.describe(inv))
	check_eq(parsed, Inventory.to_wire(inv), "round trip of Inventory.describe")
	check_eq(CraftWindow.parse_pack(Inventory.describe({})), {}, "empty pack")
	check_eq(CraftWindow.parse_pack("Ash says hi"), null, "other lines are not packs")
	check_eq(CraftWindow.parse_pack("Your pack: lots of stuff."), null, "garbled pack line")
	# Every item the game has survives the round trip.
	var all := {}
	for i in Inventory.ITEM_ORDER.size():
		all[Inventory.ITEM_ORDER[i]] = i + 1
	check_eq(CraftWindow.parse_pack(Inventory.describe(all)), Inventory.to_wire(all), "every item")


func test_mirror_follows_gathers_and_crafts() -> void:
	var inv := {"ash_wood": 2, "stone": 2}
	var node := {}
	for n in ResourceNodes.all():
		if n.kind == "ash":
			node = n
			break
	var line := Gathering.success(int(node.id), 1, 3, false)
	var after: Variant = CraftWindow.apply_line(inv, line)
	check_eq(Inventory.count(after, "ash_wood"), 3, "gather line sets the count: %s" % line)
	check_eq(Inventory.count(inv, "ash_wood"), 2, "the old mirror is not changed in place")
	# Crafting the axe from the server's own success text uses the parts and adds the axe.
	var server := {"ash_wood": 3, "stone": 2}
	Inventory.remove(server, "ash_wood", 3)
	Inventory.remove(server, "stone", 2)
	Inventory.add(server, "stone_axe", 1)
	var crafted: Variant = CraftWindow.apply_line(after, Crafting.success("stone_axe", 1, server), "stone_axe")
	check_eq(Inventory.to_wire(crafted), Inventory.to_wire(server), "mirror == server after the axe")
	# Torches come three at a time, and the reply says how many you hold.
	var tinv := {"pine_wood": 1, "ember_sap": 1, "torch": 2}
	var tserver := {"torch": 5}
	var t: Variant = CraftWindow.apply_line(tinv, Crafting.success("torch", 3, tserver), "torch")
	check_eq(Inventory.to_wire(t), {"torch": 5}, "torch craft")
	check_eq(CraftWindow.apply_line(inv, "You craft a stone axe.", ""), null, "a craft we didn't ask for changes nothing")
	check_eq(CraftWindow.apply_line(inv, "Ash: hello"), null, "chat changes nothing")


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
	check_eq(axe.parts[0], {"label": "Ash wood", "have": 2, "need": 3, "ok": false})
	check_eq(axe.parts[1], {"label": "Stone", "have": 2, "need": 2, "ok": true})
	check(CraftWindow.parts_bbcode(axe.parts).contains("Ash wood 2/3"), "needs text")
	var torch := CraftWindow.row({}, "torch", _bench() + Vector3(40, 0, 0))
	check_eq(torch.title, "Torch ×3")
	check(str(torch.hint).ends_with("craft anywhere"), "torch says anywhere: %s" % torch.hint)
	check_eq(CraftWindow.row({"stone_axe": 1}, "stone_axe", _bench()).button, "Have it")
	check_eq(CraftWindow.toast_text("stone_axe"), "Crafted: Stone axe!")
	check_eq(CraftWindow.toast_text("torch"), "Crafted: 3 Torches!")


func test_craft_replies() -> void:
	var inv := {"ash_wood": 1}
	var far := _bench() + Vector3(40, 0, 0)
	for reason in ["missing", "bench", "owned", "full"]:
		var text := Crafting.refusal(reason, inv, "stone_axe", far)
		check(not CraftWindow.craft_reply(text, "craft:stone_axe").is_empty(), "%s refusal is an answer: %s" % [reason, text])
		check(not bool(CraftWindow.craft_reply(text, "craft:stone_axe").ok), "refusals aren't ok")
	check(bool(CraftWindow.craft_reply(Crafting.success("stone_axe", 1, {"stone_axe": 1}), "craft:stone_axe").ok), "success")
	check(CraftWindow.craft_reply("Your pack: 1 stone.", "craft:stone_axe").is_empty(), "a pack line isn't a craft answer")
	check(CraftWindow.craft_reply("You need 2 stone more to make a stone axe.", "bag").is_empty(), "nothing awaited, nothing taken")


func test_window_sends_one_line_per_cooldown() -> void:
	var w := CraftWindow.new()
	w.setup(Theme.new())
	w.open(_bench())
	check_eq(w.tick(0.016, _bench()), "/bag", "opening asks for the pack")
	check_eq(w.tick(0.016, _bench()), "", "waits for the answer")
	var r := w.on_system("Your pack: 3 ash wood, 2 stone.")
	check(bool(r.consumed), "the pack answer stays out of chat")
	check(w.pack_known, "pack is known")
	check(not (w._rows["stone_axe"].button as Button).disabled, "axe is craftable")
	check((w._rows["campfire"].button as Button).disabled, "campfire is not")
	w.craft("stone_axe")
	check_eq(w.tick(0.1, _bench()), "", "never faster than the chat cooldown")
	check_eq(w.tick(GameConfig.CHAT_COOLDOWN, _bench()), "/craft stone_axe")
	check((w._rows["stone_axe"].button as Button).disabled, "buttons wait while crafting")
	var done := w.on_system(Crafting.success("stone_axe", 1, {"stone_axe": 1}))
	check(bool(done.consumed) and bool(done.ok), "success consumed")
	check_eq(done.crafted, "stone_axe")
	check_eq(Inventory.to_wire(w.pack), {"stone_axe": 1}, "mirror updated")
	check_eq((w._rows["stone_axe"].button as Button).text, "Have it")
	# A line dropped by the cooldown times out and the pack is asked for again.
	w.close()
	w.open(_bench())
	check_eq(w.tick(1.0, _bench()), "/bag")
	check_eq(w.tick(CraftWindow.REPLY_TIMEOUT + 0.1, _bench()), "/bag", "timed out, so asked again")
	check_eq(w.tick(0.016, _bench()), "", "and waits again")
	# Chat lines that aren't answers are left for the chat box.
	check(not bool(w.on_system("Ash has arrived in Ashgrove.").consumed), "arrivals still show in chat")
	# Walking away closes it.
	w.tick(0.016, _bench() + Vector3(Crafting.BENCH_RANGE + 3.0, 0, 0))
	check(not w.visible, "closed after walking away")
	w.free()

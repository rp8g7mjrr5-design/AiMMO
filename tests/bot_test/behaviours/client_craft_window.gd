extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the workbench window on a real server. Each bot keeps the client's CraftWindow
## (closed) fed with exactly what the real client gets: the login character's pack and every
## system line. Checks, without sending any chat of its own (chat shares one 0.5 s cooldown):
## - whenever the server describes the pack ("Your pack: ...", from gameplay_inventory's /bag),
##   the window's mirror already matched it, through every gather in between;
## - whenever the server refuses "/craft axe" for missing parts (gameplay_crafting), the
##   window's stone axe row said "missing" too, with the same words;
## - the "[E] Use Workbench" prompt shows exactly within Crafting.BENCH_RANGE.

const WindowScript := preload("res://client/craft_window.gd")

var _w: PanelContainer
var pack_checks := 0
var refusal_checks := 0
var bench_frames := 0


func setup(net: Node) -> void:
	_w = WindowScript.new()
	_w.setup(Theme.new())
	net.system_message.connect(_on_system)


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_w.reset()
	_w.seed_pack(character.get("inventory"))
	if not _w.pack_known:
		fail("login character gave the window no pack")


func on_play(_delta: float) -> void:
	if not bot.have_pos:
		return
	var p: Vector3 = bot.my_pos
	var at: bool = WindowScript.near_bench(p)
	var d := Vector2(p.x, p.z).distance_to(Crafting.WORKBENCH_XZ)
	if at != (d <= Crafting.BENCH_RANGE):
		fail("workbench prompt %s at %.2f m" % [at, d])
	if at:
		bench_frames += 1
	_w.pos = p


func _on_system(text: String) -> void:
	var listed: Variant = WindowScript.parse_pack(text)
	if text.begins_with("Your pack") and listed == null:
		fail("window can't read the pack line: %s" % text)
	if listed != null and _w.pack_known:
		pack_checks += 1
		if Inventory.to_wire(_w.pack) != Inventory.to_wire(listed):
			fail("window thought the pack was %s, server says %s" % [Inventory.to_wire(_w.pack), text])
	if text.begins_with("You need") and text.ends_with("to make a stone axe.") and _w.pack_known:
		var r: Dictionary = WindowScript.row(_w.pack, "stone_axe", bot.my_pos)
		if r.reason == "missing":
			refusal_checks += 1
			var want := Crafting.refusal("missing", _w.pack, "stone_axe", bot.my_pos)
			if want != text:
				fail("window would say %s, server said %s" % [want, text])
		elif r.reason != "bench":
			fail("server refused the axe for missing parts, window row said %s" % r.reason)
	_w.on_system(text)


func on_finish() -> void:
	stat("pack_checks", pack_checks)
	stat("refusal_checks", refusal_checks)
	stat("bench_frames", bench_frames)
	if pack_checks < 1:
		fail("never saw a pack line to check the window against")
	if _w:
		_w.free()

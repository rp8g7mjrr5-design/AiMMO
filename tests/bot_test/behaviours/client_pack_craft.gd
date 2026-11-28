extends "res://tests/bot_test/bot_behaviour.gd"
## Client: crafting from the pack (I) on a real server (owner, 2026-11-28). Each bot keeps the
## client's PackWindow fed exactly as the real client does (the login character's pack, every
## s2c_inventory, every craft_result, where it stands every frame) and checks, live:
## - the craft column's pack always equals the server's last s2c_inventory;
## - its "N ready" count is exactly what Crafting.check says for that pack, where the bot stands;
## - the hand recipes come first and stay craftable anywhere, the bench ones only at a bench;
## - a press of a recipe the column greys out never goes out (nothing reaches the server);
## - every craft_result frees the column's Craft buttons;
## - the figure in the window would hold something you really carry (PackPreview.held_for).
## It never sends c2s_craft itself, so client_craft_window's presses and the craft haul's exact
## pack stay as they expect; the Craft path on the wire is the same c2s_craft they prove.
## The figure itself is not built here (no renderer in a bot): set_traveller is never called.

const PackScript := preload("res://client/pack_window.gd")
const PanelScript := preload("res://client/craft_panel.gd")
const CHECK_GAP := 3.0 ## s between full checks of the column

var _w: PanelContainer
var _next_check := 0.0
var pack_checks := 0
var column_checks := 0
var refused_locally := 0
var answers := 0
var ready_seen := 0


func setup(net: Node) -> void:
	_w = PackScript.new()
	_w.setup(Theme.new())
	_w.craft_requested.connect(func(id: String):
		fail("the pack column sent %s on its own" % id))
	net.inventory_changed.connect(_on_inventory)
	net.craft_result.connect(func(recipe_id: String, ok: bool, text: String):
		answers += 1
		_w.crafting.on_craft_result(recipe_id, ok, text)
		if _w.crafting.is_waiting():
			fail("pack column still waiting after the answer for %s" % recipe_id))


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_w.reset()
	_w.seed_places(character.get("pack", []))
	_w.seed_pack(character.get("inventory"))
	if not _w.crafting.pack_known:
		fail("login character gave the pack column no pack")
	_next_check = bot.elapsed + 1.0


func on_play(delta: float) -> void:
	if not bot.have_pos:
		return
	var p: Vector3 = bot.my_pos
	_w.step(delta, p)
	if not _w.visible:
		_w.open()
	if bot.elapsed < _next_check:
		return
	_next_check = bot.elapsed + CHECK_GAP
	_check_column(p)


func _check_column(p: Vector3) -> void:
	column_checks += 1
	var col = _w.crafting
	var want: int = PanelScript.ready_count(col.pack, p)
	if want > 0:
		ready_seen += 1
	if PanelScript.head_text(col.pack, p, true) != ("%d ready" % want if want > 0 else ""):
		fail("pack column header disagrees with Crafting.check (%d ready)" % want)
	var seen_bench := false
	for id in PanelScript.order():
		var bench := bool(Crafting.RECIPES[id].bench)
		if seen_bench and not bench:
			fail("hand recipe %s listed after a bench one" % id)
		seen_bench = seen_bench or bench
		var reason := Crafting.check(col.pack, id, p)
		if not bench and reason == "bench":
			fail("%s asked for a bench; it is made anywhere" % id)
		if reason != "" and not col.is_waiting():
			if col.craft(id):
				fail("pack column sent %s although Crafting.check says '%s'" % [id, reason])
			else:
				refused_locally += 1
	var held: String = PackPreview.held_for(col.pack)
	if held != "" and Inventory.count(col.pack, held) < 1:
		fail("the figure would hold %s, which is not in the pack" % held)


func _on_inventory(items: Dictionary) -> void:
	var want := Inventory.to_wire(Inventory.normalize(items))
	_w.seed_pack(items)
	pack_checks += 1
	if Inventory.to_wire(_w.crafting.pack) != want:
		fail("pack column %s, server sent %s" % [Inventory.to_wire(_w.crafting.pack), want])


func on_finish() -> void:
	stat("pack_checks", pack_checks)
	stat("column_checks", column_checks)
	stat("refused_locally", refused_locally)
	stat("answers", answers)
	stat("ready_seen", ready_seen)
	if column_checks < 1:
		fail("never checked the pack's craft column")
	if refused_locally < 1:
		fail("never saw the column hold back a recipe it can't make")
	if _w:
		_w.free()

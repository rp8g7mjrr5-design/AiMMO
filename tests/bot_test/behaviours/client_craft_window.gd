extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the workbench window on a real server, over protocol v3 (no chat commands).
## Each bot keeps the client's CraftWindow fed exactly as the real client does (the login
## character's pack, every s2c_inventory, every craft_result) and presses its Craft button
## a few times per login, so the press goes out as `net.play.c2s_craft` like a player's:
## - the window's pack always equals the server's last s2c_inventory;
## - every press is answered by craft_result for that recipe, the window shows the server's
##   own words, and its row had predicted the answer (Ready <-> ok, and a "missing" refusal
##   in exactly the server's words);
## - every successful craft also pays Toolcraft XP (the "+N Toolcraft" floater);
## - the "[E] Use Workbench" prompt shows exactly within Crafting.BENCH_RANGE.
## It crafts torches (anywhere) or a campfire (at the bench) only, never a tool, so
## gameplay_crafting's "/craft axe" answers stay as it expects. Presses wait for a quiet
## moment: no gather of ours running or just ended (gameplay_gather_v3 checks the pack a
## second after each haul), no instant "/gather" or "/craft" chat line of another behaviour
## just sent (they change the pack with no gather_begun; a /gather paid between the window's
## last s2c_inventory and the press once made the window short one pine wood, qa
## 2026-11-23), and not near a disconnect (qa_gather_ledger's reconnect check).
##
## --craft-haul (one extra bot after the main run, seeded by seed_crafter.gd at the bench with
## exactly a campfire's and a torch's inputs, see craft_haul.gd): the main bots almost never
## carry a recipe's inputs, so this bot proves the ok path live. It holds still at the bench
## until both are made, presses sooner and more often, and fails unless the campfire and the
## torches were both made, each paid Toolcraft XP, and the pack ended exactly as CraftHaul says.

const WindowScript := preload("res://client/craft_window.gd")
const CraftHaul := preload("res://tests/bot_test/craft_haul.gd")
const HAUL_FIRST_PRESS := 2.0 ## s after login, --craft-haul only
const HAUL_PRESS_GAP := 2.5
const FIRST_PRESS := 6.0 ## s after login
const PRESS_GAP := 12.0 ## s between presses
const MAX_PRESSES := 4 ## per login
const QUIET_AFTER_GATHER := 2.0
const QUIET_BEFORE_DISCONNECT := 6.0
const ANSWER_TIMEOUT := 3.0
const EDGE := 1.5 ## m either side of BENCH_RANGE where position lag may flip the bench check

var _w: PanelContainer
var _next_press := INF
var _presses := 0
var _sent := "" ## recipe id pressed and not answered yet
var _sent_at := 0.0
var _gathering := false
var _gather_ended_at := -1000.0
var _pack_command_at := -1000.0 ## last /gather or /craft chat line this bot sent
var _toolcraft_xp := 0
var presses := 0
var answers := 0
var crafted := 0
var predicted := 0
var pack_checks := 0
var bench_frames := 0
var raced_presses := 0
var _haul := false
var made: Array = [] ## recipe ids the server said ok to, in order


func setup(net: Node) -> void:
	_haul = haul_mode(bot.args)
	_w = WindowScript.new()
	_w.setup(Theme.new())
	_w.craft_requested.connect(func(id: String):
		if bot.multiplayer.multiplayer_peer != null:
			bot.send_play("c2s_craft", [id]))
	net.inventory_changed.connect(_on_inventory)
	net.craft_result.connect(_on_craft_result)
	net.xp_gained.connect(func(skill: String, _g: int, _t: int):
		if skill == "toolcraft":
			_toolcraft_xp += 1)
	net.gather_begun.connect(func(peer: int, _n: int, _s: float):
		if peer == int(bot.my_id):
			_gathering = true)
	net.gather_ended.connect(func(peer: int, _n: int, _r: String):
		if peer == int(bot.my_id):
			_gathering = false
			_gather_ended_at = bot.elapsed)
	bot.command_sent.connect(_on_command_sent)


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_w.reset()
	_w.seed_pack(character.get("inventory"))
	if not _w.pack_known:
		fail("login character gave the window no pack")
	_sent = ""
	_gathering = false
	_presses = 0
	_next_press = bot.elapsed + (HAUL_FIRST_PRESS if _haul else FIRST_PRESS + bot.rng.randf_range(0.0, 2.0))


func on_play(delta: float) -> void:
	if not bot.have_pos:
		return
	if _haul and made.size() < CraftHaul.RECIPES.size() and bot.phase == "playing_1":
		bot.move = Vector2.ZERO # stay at the bench until the haul is crafted, then wander
	var p: Vector3 = bot.my_pos
	var at: bool = WindowScript.near_bench(p)
	var d := Vector2(p.x, p.z).distance_to(Crafting.workbench_xz())
	if at != (d <= Crafting.BENCH_RANGE):
		fail("workbench prompt %s at %.2f m" % [at, d])
	if at:
		bench_frames += 1
	_w.tick(delta, p)
	if _sent != "" and bot.elapsed - _sent_at > ANSWER_TIMEOUT:
		fail("craft %s was never answered (%.1f s)" % [_sent, bot.elapsed - _sent_at])
		_sent = ""
	if _sent == "" and _presses < MAX_PRESSES and bot.elapsed >= _next_press and _quiet():
		_press(p)


func _on_command_sent(text: String) -> void:
	if changes_pack(text):
		_pack_command_at = bot.elapsed


## No gather of ours running or just finished, and no disconnect or end of run coming up.
func _quiet() -> bool:
	if _gathering or bot.elapsed - _gather_ended_at < QUIET_AFTER_GATHER:
		return false
	if bot.elapsed - _pack_command_at < QUIET_AFTER_GATHER:
		return false
	var stop_at: float = bot.disconnect_at if bot.phase == "playing_1" else bot.duration
	return bot.elapsed < stop_at - QUIET_BEFORE_DISCONNECT


func _press(p: Vector3) -> void:
	var id := "torch"
	if WindowScript.row(_w.pack, "campfire", p).reason == "" and Vector2(p.x, p.z).distance_to(Crafting.workbench_xz()) < Crafting.BENCH_RANGE - EDGE:
		id = "campfire"
	_presses += 1
	_next_press = bot.elapsed + (HAUL_PRESS_GAP if _haul else PRESS_GAP)
	if not _w.craft(id):
		fail("the window refused a Craft press for %s (pack known %s)" % [id, _w.pack_known])
		return
	presses += 1
	_sent = id
	_sent_at = bot.elapsed


func _on_inventory(items: Dictionary) -> void:
	var want := Inventory.to_wire(Inventory.normalize(items))
	_w.seed_pack(items)
	pack_checks += 1
	if Inventory.to_wire(_w.pack) != want:
		fail("window pack %s, server sent %s" % [Inventory.to_wire(_w.pack), want])


func _on_craft_result(recipe_id: String, ok: bool, text: String) -> void:
	if _sent == "":
		return # not ours (nothing else sends c2s_craft today)
	if recipe_id != _sent:
		fail("pressed %s, the answer was for %s" % [_sent, recipe_id])
	answers += 1
	# The pack follows the result on the server's next tick, so the window still holds the
	# pack the server judged: its row must have said the same thing.
	var p: Vector3 = bot.my_pos
	var r: Dictionary = WindowScript.row(_w.pack, recipe_id, p)
	var d := Vector2(p.x, p.z).distance_to(Crafting.workbench_xz())
	var edge: bool = bool(Crafting.RECIPES.get(recipe_id, {}).get("bench", false)) and absf(d - Crafting.BENCH_RANGE) < EDGE
	# A pack-changing chat line sent after the press may still have reached the server first.
	var raced: bool = _pack_command_at >= _sent_at - QUIET_AFTER_GATHER
	if raced:
		raced_presses += 1
	if not edge and not raced:
		predicted += 1
		if ok != (r.reason == ""):
			fail("%s: server said ok=%s (%s), window row said '%s'" % [recipe_id, ok, text, r.reason])
		elif not ok and r.reason == "missing":
			var want := Crafting.refusal("missing", _w.pack, recipe_id, p)
			if want != text:
				fail("window would say %s, server said %s" % [want, text])
	var shown: Dictionary = _w.on_craft_result(recipe_id, ok, text)
	if _w.status_label.text != text:
		fail("window shows '%s', server said '%s'" % [_w.status_label.text, text])
	if _w.is_waiting():
		fail("window still waiting after the answer")
	if ok:
		crafted += 1
		made.append(recipe_id)
		if str(shown.crafted) != recipe_id:
			fail("a successful %s made no toast" % recipe_id)
	_sent = ""


## True when the bot was started with --craft-haul (the seeded crafter, see craft_haul.gd).
static func haul_mode(args: Dictionary) -> bool:
	return args.has("craft-haul")


## True for chat lines the server may answer by changing the pack (instant /gather, /craft,
## and /channel, the timed gather). Static so tests/unit/test_qa_craft_window_race.gd can check it.
static func changes_pack(text: String) -> bool:
	return ChatCommands.is_gather(text) or ChatCommands.is_craft(text) or ChatCommands.is_channel(text)


func on_finish() -> void:
	stat("presses", presses)
	stat("answers", answers)
	stat("crafted", crafted)
	stat("predicted", predicted)
	stat("pack_checks", pack_checks)
	stat("bench_frames", bench_frames)
	stat("raced_presses", raced_presses)
	if presses < 1:
		fail("never found a quiet moment to press Craft")
	if pack_checks < 1:
		fail("never got an s2c_inventory to check the window against")
	# s2c_xp is sent before the craft_result it belongs to.
	if _toolcraft_xp < crafted:
		fail("%d crafts but only %d Toolcraft XP gains" % [crafted, _toolcraft_xp])
	if _haul:
		var haul := {"made": made, "presses": presses, "toolcraft_xp": _toolcraft_xp,
			"haul_pack": Inventory.to_wire(_w.pack) if _w else null}
		stat("made", made)
		stat("haul_pack", haul.haul_pack)
		for problem in CraftHaul.verdict(haul):
			fail("craft haul: " + problem)
	if _w:
		_w.free()

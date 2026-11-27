extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): the grid pack (protocol v13; PackGrid, owner direction
## 2026-11-27). Replaces client_pack_window: every bot keeps the counts (login, then every
## s2c_inventory) and the layout (every s2c_pack), as the client's pack window does, and on
## every update checks:
## - s2c_pack always comes with (just before) s2c_inventory;
## - the layout is laid out by PackGrid exactly as the server saved it: every stack named,
##   no two stacks in one cell, all inside the grid;
## - the stacks add up to the counts (nothing lost: what doesn't fit waits below the grid);
## - a stack that rose is what the window lights ("+N" equal to the rise).
## Every bot, once per login, MOVE_AFTER seconds in, drags its first stack to the last free
## spot in the grid (c2s_pack_move) and must see it there in the next s2c_pack, and after a
## reconnect the stack is still there (the layout was saved).

const PackScript := preload("res://client/pack_window.gd")
const MOVE_AFTER := 20.0
const ANSWER_TIMEOUT := 4.0

var _pack := {}
var _places: Array = []
var _known := false
var _pack_since_inv := 0
var _logins := 0
var _moved: Array = [] # [item, index, x, y, turned] we asked for
var _move_at := 0.0
var _sent_at := -1.0
var _kept: Array = [] # the move to find again after the reconnect
var updates := 0
var glows := 0
var moves_ok := 0
var moves_kept := 0
var layouts := 0
var skipped := 0


func setup(net: Node) -> void:
	net.inventory_changed.connect(_on_inventory)
	net.pack_layout_changed.connect(_on_pack)


func on_login(reconnect: bool, character: Dictionary) -> void:
	_logins += 1
	_pack = Inventory.to_wire(Inventory.normalize(character.get("inventory", {})))
	_places = PackGrid.normalize(character.get("pack", []))
	_known = true
	_moved = []
	_sent_at = -1.0
	_move_at = bot.elapsed + MOVE_AFTER
	if reconnect and not _kept.is_empty():
		var laid := PackGrid.layout(_pack, _places)
		var at := PackGrid.stack_at(laid, int(_kept[2]), int(_kept[3]))
		if at.get("item", "") == str(_kept[0]):
			moves_kept += 1
		elif Inventory.count(_pack, str(_kept[0])) > 0:
			fail("moved %s to (%d, %d) but after the reconnect it isn't there" % [_kept[0], _kept[2], _kept[3]])
	_check()


func _on_pack(places: Array) -> void:
	layouts += 1
	_pack_since_inv += 1
	_places = PackGrid.normalize(places)
	if not _moved.is_empty() and _sent_at >= 0.0:
		var laid := PackGrid.layout(_pack, _places)
		var at := PackGrid.stack_at(laid, int(_moved[2]), int(_moved[3]))
		if at.get("item", "") == str(_moved[0]) and int(at.get("index", -1)) == int(_moved[1]):
			moves_ok += 1
			_kept = _moved
			_moved = []
			_sent_at = -1.0
		# else: a layout sent before the server read our move (a haul in the same tick); the
		# answer is still on its way, on_play gives it ANSWER_TIMEOUT.


func _on_inventory(items: Dictionary) -> void:
	if _pack_since_inv == 0:
		fail("s2c_inventory without an s2c_pack before it")
	_pack_since_inv = 0
	var fresh := Inventory.to_wire(Inventory.normalize(items))
	updates += 1
	if _known:
		var up: Dictionary = PackScript.gained(_pack, fresh)
		for item in up:
			if Inventory.count(fresh, item) - Inventory.count(_pack, item) != int(up[item]):
				fail("glow on %s says +%d" % [item, int(up[item])])
		glows += up.size()
	_pack = fresh
	_known = true
	_check()


func _check() -> void:
	var laid := PackGrid.layout(_pack, _places)
	var cells := {}
	var sums := {}
	for p in laid.placed:
		for y in range(int(p.y), int(p.y) + int(p.h)):
			for x in range(int(p.x), int(p.x) + int(p.w)):
				if x < 0 or y < 0 or x >= PackGrid.COLS or y >= PackGrid.ROWS:
					fail("%s sits outside the grid" % p.item)
				if cells.has(Vector2i(x, y)):
					fail("%s and %s share cell (%d, %d)" % [p.item, cells[Vector2i(x, y)], x, y])
				cells[Vector2i(x, y)] = p.item
		sums[p.item] = int(sums.get(p.item, 0)) + int(p.n)
	for o in laid.over:
		sums[o.item] = int(sums.get(o.item, 0)) + int(o.n)
	for item in _pack:
		if int(sums.get(item, 0)) != Inventory.count(_pack, item):
			fail("%s: the stacks hold %d, the server says %d" % [item, int(sums.get(item, 0)), Inventory.count(_pack, item)])
	if _places.size() < (laid.placed as Array).size():
		fail("the server's layout names %d stacks, %d are laid out" % [_places.size(), (laid.placed as Array).size()])


func on_play(_delta: float) -> void:
	if _sent_at >= 0.0:
		if bot.elapsed - _sent_at > ANSWER_TIMEOUT and _sent_at <= bot.elapsed:
			var laid := PackGrid.layout(_pack, _places)
			var still := false
			for p in (laid.placed as Array) + (laid.over as Array):
				still = still or (str(p.item) == str(_moved[0]) and int(p.index) == int(_moved[1]))
			if still:
				fail("asked to move %s#%d to (%d, %d); the server's layout never showed it there" % [_moved[0], _moved[1], _moved[2], _moved[3]])
			else:
				skipped += 1 # the stack was crafted away or eaten in the meantime
			_sent_at = -1.0
			_moved = []
		return
	if _move_at <= 0.0 or bot.elapsed < _move_at or float(bot.duration) - bot.elapsed < 10.0:
		return
	_move_at = 0.0
	var laid := PackGrid.layout(_pack, _places)
	if (laid.placed as Array).is_empty():
		return
	var first: Dictionary = laid.placed[0]
	# The last free spot (bottom-right first) where this stack fits standing up.
	for y in range(PackGrid.ROWS - int(first.h), -1, -1):
		for x in range(PackGrid.COLS - int(first.w), -1, -1):
			var places := PackGrid.move(_pack, _places, str(first.item), int(first.index), x, y, bool(first.turned))
			if not places.is_empty():
				_moved = [str(first.item), int(first.index), x, y, bool(first.turned)]
				bot.send_play("c2s_pack_move", _moved.duplicate())
				_sent_at = bot.elapsed
				return


func on_finish() -> void:
	stat("updates", updates)
	stat("layouts", layouts)
	stat("glows", glows)
	stat("moves_ok", moves_ok)
	stat("moves_kept", moves_kept)
	stat("skipped", skipped)
	if layouts == 0:
		fail("never got an s2c_pack")

extends TestCase
## The grid pack on the server (protocol v13): the server owns the layout, a full pack
## refuses more, moves are checked, a drop takes the whole stack, crafting is all or nothing,
## and the layout is saved with the character and survives junk and old saves.

const ServerScript := preload("res://server/server.gd")


func _server() -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	var ch := CharacterData.normalize({"name": "p1"})
	srv.sessions[1] = {"logged_in": true, "character": ch, "move": Vector2.ZERO, "yaw": 0.0, "seq": -1,
		"last_chat": -1000.0, "last_command": -1000.0, "last_too_fast": -1000.0, "last_gather": -1000.0,
		"channel": {}, "login_attempts": 0, "inv_dirty": false}
	return srv


func _sent(srv: Node, method: String) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == 1 and m[1] == method:
			out.append(m[2])
	return out


func test_give_lays_out_and_stops_at_a_full_pack() -> void:
	var srv := _server()
	var ch: Dictionary = srv.sessions[1].character
	check_eq(srv.give_item(1, "ash_wood", 30), 30)
	check_eq((ch.pack as Array).size(), 2, "two stacks of wood, each with its place")
	var cells := PackGrid.COLS * PackGrid.ROWS
	var fits := PackGrid.room_for(ch.inventory, ch.pack, "stone")
	check_eq(srv.give_item(1, "stone", 10000), fits, "only what the grid holds")
	check_eq(srv.give_item(1, "stone", 1), 0, "then nothing")
	check_eq(srv.give_item(1, "stone", 3, true), 3, "a hand-back is never refused (nothing is lost)")
	check(Inventory.count(ch.inventory, "stone") <= 15 * cells + 3, "never more than the grid holds, plus the hand-back")
	srv.free()


func test_move_and_snap_back() -> void:
	var srv := _server()
	var ch: Dictionary = srv.sessions[1].character
	srv.give_item(1, "stone", 5)
	srv.give_item(1, "ash_wood", 5)
	check(srv.pack_move(1, "stone", 0, 9, 5, false), "into a free corner")
	check_eq(PackGrid.stack_at(PackGrid.layout(ch.inventory, ch.pack), 9, 5), {"item": "stone", "index": 0})
	var before: Array = (ch.pack as Array).duplicate(true)
	check(not srv.pack_move(1, "ash_wood", 0, 9, 4, false), "a log can't stand on the stone")
	check_eq(ch.pack, before, "a refused move changes nothing")
	check_eq(_sent(srv, "s2c_pack").size(), 2, "and the layout goes back either way, so the drag snaps back")
	srv.give_item(1, "stone", 20)
	check_eq(PackGrid.stack_at(PackGrid.layout(ch.inventory, ch.pack), 9, 5), {"item": "stone", "index": 0}, "a haul leaves the stone where it was put")
	srv.free()


func test_drop_a_stack() -> void:
	var srv := _server()
	var ch: Dictionary = srv.sessions[1].character
	srv.give_item(1, "ash_wood", 45) # stacks of 20, 20, 5
	var laid := PackGrid.layout(ch.inventory, ch.pack)
	var last_place: Array = []
	for p in laid.placed:
		if int(p.index) == 2:
			last_place = [int(p.x), int(p.y)]
	check_eq(srv.pack_drop(1, "ash_wood", 0), 20, "the whole first stack")
	check_eq(Inventory.count(ch.inventory, "ash_wood"), 25)
	laid = PackGrid.layout(ch.inventory, ch.pack)
	check_eq(PackGrid.stack_at(laid, last_place[0], last_place[1]), {"item": "ash_wood", "index": 1}, "the part stack stays where it was")
	check_eq(srv.pack_drop(1, "ash_wood", 7), 0, "no such stack")
	srv.free()


func test_a_full_pack_refuses_a_gather_before_the_bar() -> void:
	var srv := _server()
	var cells := PackGrid.COLS * PackGrid.ROWS
	srv.give_item(1, "stone", 15 * cells)
	check_eq(PackGrid.room_for(srv.sessions[1].character.inventory, srv.s_pack(1), "ash_wood"), 0, "no room for a log")
	srv.free()


func test_saved_and_loaded() -> void:
	var ch := CharacterData.normalize({"name": "p", "pack": '[["stone",0,4,2,true]]'})
	check_eq(ch.pack, [["stone", 0, 4, 2, true]], "the JSON text from Postgres")
	var round := CharacterData.normalize(JSON.parse_string(JSON.stringify(ch)))
	check_eq(round.pack, ch.pack, "and the JSON store's floats")
	check_eq(CharacterData.normalize({"name": "old"}).pack, [], "an old save has none")
	check_eq(CharacterData.normalize({"name": "bad", "pack": "{nope"}).pack, [], "junk is dropped, never a crash")
	var sql := FileAccess.get_file_as_string("res://../db/migrations/0007_character_pack_layout.sql")
	check(sql.contains("ADD COLUMN IF NOT EXISTS pack_layout"), "an add-only migration")
	check(not sql.to_upper().contains("DROP COLUMN") and not sql.to_upper().contains("DROP TABLE"), "never drops anything")


func test_login_lays_out_an_old_save() -> void:
	var ch := CharacterData.normalize({"name": "old", "inventory": {"ash_wood": 999, "stone": 3}})
	ServerScript._relayout(ch)
	check((ch.pack as Array).size() > 0, "an old save gets places")
	check_eq(Inventory.count(ch.inventory, "ash_wood"), 999, "and keeps every log, even the ones that don't fit")

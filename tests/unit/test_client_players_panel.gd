extends TestCase
## The players panel (O key): rows from the server's roster, the texts, the gold glow on a
## row that just arrived or levelled, and the O key in the F1 list.


func _roster() -> Array:
	return [
		{"id": 3, "name": "ash", "level": 4},
		{"id": 7, "name": "Bram", "level": 11},
		{"id": 2, "name": "wren", "level": 6},
	]


func test_rows_follow_the_roster() -> void:
	var r := PlayersPanel.rows(_roster(), 7)
	check_eq(r.size(), 3)
	check_eq(r.map(func(x): return str(x.name)), ["ash", "Bram", "wren"], "the server's order (by name)")
	check(bool(r[1].you), "your own row is marked")
	check(not bool(r[0].you) and not bool(r[2].you), "nobody else is you")
	check_eq(int(r[1].level), 11)


func test_rows_skip_bad_entries() -> void:
	var bad := [{"id": 1, "name": "a", "level": 4}, {"id": 1, "name": "again", "level": 9}, "junk", {"name": "no id"}, {"id": 5}]
	var r := PlayersPanel.rows(bad, 0)
	check_eq(r.size(), 2, "a second row for one id, a non-Dictionary and a row with no id are skipped")
	check_eq(str(r[0].name), "a")
	check_eq(int(r[1].level), 0, "a missing level shows as 0")


func test_texts() -> void:
	check_eq(PlayersPanel.header_text(1), "Just you in the valley")
	check_eq(PlayersPanel.header_text(0), "Just you in the valley")
	check_eq(PlayersPanel.header_text(5), "5 in the valley")
	check_eq(PlayersPanel.button_text(0), "Players")
	check_eq(PlayersPanel.button_text(3), "Players 3")
	check_eq(PlayersPanel.level_text(12), "Total level 12")


func test_changes() -> void:
	var a := PlayersPanel.rows(_roster(), 7)
	var more := _roster()
	more[0].level = 6
	more.append({"id": 9, "name": "Yew", "level": 4})
	more.remove_at(2) # wren left
	var ch := PlayersPanel.changes(a, PlayersPanel.rows(more, 7))
	check_eq(ch.joined, [9])
	check_eq(ch.levelled, {3: 2})


func test_panel_glows_on_join_and_level() -> void:
	ControlsOverlay.install_input()
	var p := PlayersPanel.new()
	p.setup(Theme.new())
	p.set_me(7)
	p.on_roster(_roster())
	check_eq(p.header_shown(), "3 in the valley")
	check_eq(p.shown(), ["ash|Total level 4", "Bram  (you)|Total level 11", "wren|Total level 6"])
	check_eq(p.flash_of(3), 0.0, "the first roster after login never glows")
	var r := _roster()
	r.append({"id": 9, "name": "Yew", "level": 4})
	p.on_roster(r)
	check_eq(p.flash_of(9), 1.0, "someone new glows")
	check_eq(p.note_of(9), PlayersPanel.ARRIVED_TEXT)
	check_eq(p.flash_of(2), 0.0)
	r[0].level = 5
	p.on_roster(r)
	check_eq(p.note_of(3), "+1")
	p.step(0.2)
	r[0].level = 6
	p.on_roster(r)
	check_eq(p.note_of(3), "+2", "a second level while still glowing adds up")
	p.step(PlayersPanel.FLASH_SECONDS + 0.1)
	check_eq(p.flash_of(3), 0.0, "the glow fades")
	check_eq(p.note_of(3), "")
	r.remove_at(0)
	p.on_roster(r)
	check_eq(p.shown().size(), 3, "someone who left is gone")
	p.free()


func test_own_join_never_glows_and_reset_forgets() -> void:
	var p := PlayersPanel.new()
	p.setup(Theme.new())
	p.set_me(4)
	p.on_roster([{"id": 1, "name": "a", "level": 4}])
	p.on_roster([{"id": 1, "name": "a", "level": 4}, {"id": 4, "name": "me", "level": 4}])
	check_eq(p.flash_of(4), 0.0, "your own arrival doesn't glow")
	p.reset()
	check_eq(p.entries, [])
	check_eq(p.header_shown(), "Just you in the valley")
	p.set_me(1)
	p.on_roster([{"id": 1, "name": "a", "level": 4}, {"id": 2, "name": "b", "level": 4}])
	check_eq(p.flash_of(2), 0.0, "after a reconnect the first roster doesn't glow again")
	p.free()


func test_roster_before_login_answer_still_marks_you() -> void:
	var p := PlayersPanel.new()
	p.setup(Theme.new())
	p.on_roster([{"id": 5, "name": "Me", "level": 4}])
	p.set_me(5)
	check_eq(p.shown(), ["Me  (you)|Total level 4"])
	p.free()


func test_toggle_and_close() -> void:
	var p := PlayersPanel.new()
	p.setup(Theme.new())
	var closed := [0]
	p.closed.connect(func(): closed[0] += 1)
	p.toggle()
	check(p.visible, "opens")
	p.toggle()
	check(not p.visible, "shuts")
	check_eq(closed[0], 1)
	p.close()
	check_eq(closed[0], 1, "closing a shut panel says nothing")
	p.free()


func test_o_key_is_bound_and_listed() -> void:
	ControlsOverlay.install_input()
	check(InputMap.has_action("toggle_players"), "O is an action")
	check_eq(ControlsOverlay.key_text("toggle_players"), "O")
	check(ControlsOverlay.listed_actions().has("toggle_players"), "O is in the F1 list")
	var used := {}
	for a in ControlsOverlay.DEFAULT_BINDS:
		for k in ControlsOverlay.DEFAULT_BINDS[a]:
			check(not used.has(k) or used[k] == a, "%s bound twice" % OS.get_keycode_string(k))
			used[k] = a


func test_panel_fits_a_small_screen() -> void:
	var p := PlayersPanel.new()
	p.setup(Theme.new())
	var many: Array = []
	for i in 40:
		many.append({"id": i + 1, "name": "Player%02d" % i, "level": 4 + i})
	p.on_roster(many)
	check(p.get_combined_minimum_size().y < 700.0, "forty players scroll, the panel stays under 700 px (%s)" % p.get_combined_minimum_size().y)
	p.free()

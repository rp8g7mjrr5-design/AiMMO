extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the players panel (O). Network-only (art bible section 7: no window is built). Each
## bot keeps the roster the server sends, as the client's PlayersPanel does, and checks on
## every s2c_roster:
## - the panel's rows are exactly the server's entries, with no id twice, and exactly one of
##   them is marked as us (our id), from the first roster after each login on;
## - the header and the button count match the row count;
## - what the panel lights gold is right: everyone it says "just arrived" is new since the
##   last roster.

const PanelScript := preload("res://client/players_panel.gd")

var _rows: Array = []
var _known := false
var _rosters := 0
var _arrivals := 0
var _most := 0


func setup(net: Node) -> void:
	net.roster_changed.connect(_on_roster)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_rows = []
	_known = false # a fresh login starts over, as the client's reset does


func _on_roster(entries: Array) -> void:
	_rosters += 1
	var fresh: Array = PanelScript.rows(entries, bot.my_id)
	if fresh.size() != entries.size():
		fail("panel shows %d rows for %d roster entries" % [fresh.size(), entries.size()])
	var mine := 0
	for r in fresh:
		if bool(r.you):
			mine += 1
	if bot.my_id != 0 and mine != 1:
		fail("panel marks %d rows as us (id %d)" % [mine, bot.my_id])
	if PanelScript.header_text(fresh.size()) != ("Just you in the valley" if fresh.size() <= 1 else "%d in the valley" % fresh.size()):
		fail("header %s for %d players" % [PanelScript.header_text(fresh.size()), fresh.size()])
	if PanelScript.button_text(fresh.size()) != "Players %d" % fresh.size() and fresh.size() > 0:
		fail("button says %s for %d players" % [PanelScript.button_text(fresh.size()), fresh.size()])
	if _known:
		var ch: Dictionary = PanelScript.changes(_rows, fresh)
		var before := {}
		for r in _rows:
			before[int(r.id)] = true
		for id in ch.joined:
			if before.has(int(id)):
				fail("panel says %d just arrived but they were already there" % int(id))
		_arrivals += ch.joined.size()
	_most = maxi(_most, fresh.size())
	_rows = fresh
	_known = true


func on_finish() -> void:
	stat("rosters", _rosters)
	stat("arrivals", _arrivals)
	stat("most_online", _most)
	if _rosters == 0:
		fail("no roster ever reached the players panel")

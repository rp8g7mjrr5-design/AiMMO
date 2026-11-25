extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the Zombai on screen (protocol v10). Network-only (nothing is drawn). Each bot keeps
## a ZombaiView exactly as the client does, fed by s2c_gloam and s2c_gloam_hits, and checks:
## - the walkers it would draw standing are exactly the ones the server just sent (none left
##   behind after they leave view, none missing, none a blow already put down);
## - a new update never makes a walker jump: it starts from where it was drawn, unless the
##   server moved it further than ZombaiView.SNAP_DIST;
## - every walker lands on the server's spot once the blend is over;
## - every raised grab the server sends (state "grab") is a windup moment the client sees, and
##   its arms reach the top (windup 1) exactly when the server's windup_left runs out;
## - every walker a blow puts down becomes a body the client draws where it fell, which has
##   sunk away by ZombaiView.LIE_SECONDS + SINK_SECONDS (bodies_gone counts the ones dropped).
## gameplay_gloam's bot raises and fights one in every long run; on long runs walkers also
## rise on their own near bots outside the meadow.

const ViewScript := preload("res://client/zombai_view.gd")

var _view = ViewScript.new()
var _states := {} ## id -> last state name, our own record
var _expected_windups := 0
var _windups := 0
var _feeds := 0
var _jumps := 0
var _most := 0
var _downs := 0
var _bodies_gone := 0


func setup(net: Node) -> void:
	net.gloam_changed.connect(_on_gloam)
	net.gloam_struck.connect(_on_struck)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_view.clear() # as the client does on login
	_states.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_gloam(entries: PackedFloat32Array) -> void:
	if entries.size() % Gloam.WIRE_STRIDE != 0:
		return # gameplay_gloam fails that one
	_feeds += 1
	var now := _now()
	_bodies_gone += _view.expire(now).size()
	var before := {}
	for id in _view.ids():
		before[id] = _view.position(id, now)
	var sent := {}
	for w in Gloam.from_wire(entries):
		var id := int(w.id)
		if _view.fallen.has(id):
			continue
		sent[id] = w
		if str(w.state) == "grab" and str(_states.get(id, "")) != "grab":
			_expected_windups += 1
		_states[id] = str(w.state)
	for id in _states.keys():
		if not sent.has(id):
			_states.erase(id)
	for e in _view.feed(entries, now):
		if str(e.event) == "windup":
			_windups += 1
	if _windups != _expected_windups:
		fail("client saw %d raised grabs, the server raised %d" % [_windups, _expected_windups])
		_windups = _expected_windups
	var drawn: Array = _view.ids()
	var want: Array = sent.keys()
	want.sort()
	if drawn != want:
		fail("would draw walkers %s, server sent %s" % [str(drawn), str(want)])
	_most = maxi(_most, drawn.size())
	for id in drawn:
		var w: Dictionary = sent[id]
		var p: Vector3 = _view.position(id, now)
		if before.has(id):
			var was: Vector3 = before[id]
			var server_jump := Vector2(float(w.x) - was.x, float(w.z) - was.z).length() > ViewScript.SNAP_DIST
			if not server_jump and Vector2(p.x - was.x, p.z - was.z).length() > 0.01:
				_jumps += 1
				fail("walker %d jumped %.2f m on an update" % [id, Vector2(p.x - was.x, p.z - was.z).length()])
		var landed: Vector3 = _view.position(id, now + ViewScript.BLEND)
		if Vector2(landed.x - float(w.x), landed.z - float(w.z)).length() > 0.01:
			fail("walker %d settles at %s, server has it at (%.2f, %.2f)" % [id, str(landed), float(w.x), float(w.z)])
		if str(w.state) == "grab":
			var at_close := now + float(w.windup_left)
			if absf(_view.windup(id, at_close) - 1.0) > 0.001 or (float(w.windup_left) > 0.05 and _view.windup(id, now) >= 1.0):
				fail("walker %d's arms don't reach the top when its grab closes" % id)


func _on_struck(_peer: int, kind: String, ids: Array, downed: Array) -> void:
	var now := _now()
	for e in _view.struck(kind, ids, downed, now):
		if str(e.event) == "down":
			_downs += 1
			var id := int(e.id)
			if not _view.bodies().has(id) or _view.state(id) != "down" or _view.has(id):
				fail("walker %d went down but the client has no body for it" % id)
			elif absf(_view.sink(id, now + ViewScript.LIE_SECONDS + ViewScript.SINK_SECONDS) - ViewScript.SINK_DEPTH) > 0.001:
				fail("walker %d's body never sinks away" % id)


func on_finish() -> void:
	stat("updates", _feeds)
	stat("windups_seen", _windups)
	stat("most_drawn", _most)
	stat("downs_seen", _downs)
	stat("bodies_gone", _bodies_gone)
	stat("jumps", _jumps)

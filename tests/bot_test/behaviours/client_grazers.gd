extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the grazers on screen (protocol v6). Network-only (art bible section 7: nothing is
## drawn). Each bot keeps a HerdView exactly as the client does and checks on every
## s2c_wildlife:
## - the herd it would draw is exactly the creatures the server just sent (none left behind
##   after they leave view, none missing);
## - a new update never makes a grazer jump: it starts from where it was drawn, unless the
##   server moved it further than HerdView.SNAP_DIST;
## - every grazer lands on the server's spot once the blend is over;
## - the client's bolt moments (snort and dust) are exactly the server's flips into "flee"
##   for grazers we already had in view.

const HerdScript := preload("res://client/herd_view.gd")

var _herd = HerdScript.new()
var _states := {} ## id -> last state index, our own record
var _expected_bolts := 0
var _bolts := 0
var _feeds := 0
var _jumps := 0
var _most := 0


func setup(net: Node) -> void:
	net.wildlife_changed.connect(_on_wildlife)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_herd.clear() # as the client does on login
	_states.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_wildlife(entries: PackedFloat32Array) -> void:
	if entries.size() % Wildlife.WIRE_STRIDE != 0:
		return # gameplay_wildlife fails that one
	_feeds += 1
	var now := _now()
	var before := {}
	for id in _herd.ids():
		before[id] = _herd.position(id, now)
	var sent := {}
	for i in range(0, entries.size(), Wildlife.WIRE_STRIDE):
		var id := int(entries[i])
		var si := int(entries[i + 4])
		sent[id] = Vector3(entries[i + 1], 0.0, entries[i + 2])
		if _states.has(id) and int(_states[id]) != si and si == Wildlife.STATES.find("flee"):
			_expected_bolts += 1
		_states[id] = si
	for id in _states.keys():
		if not sent.has(id):
			_states.erase(id)
	for e in _herd.feed(entries, now):
		if str(e.event) == "bolt":
			_bolts += 1
	if _bolts != _expected_bolts:
		fail("client saw %d bolts, the server flipped %d grazers to flee" % [_bolts, _expected_bolts])
		_bolts = _expected_bolts
	var drawn: Array = _herd.ids()
	var want: Array = sent.keys()
	want.sort()
	if drawn != want:
		fail("would draw grazers %s, server sent %s" % [str(drawn), str(want)])
	_most = maxi(_most, drawn.size())
	for id in drawn:
		var p: Vector3 = _herd.position(id, now)
		if before.has(id):
			var was: Vector3 = before[id]
			var server_jump := Vector2(sent[id].x - was.x, sent[id].z - was.z).length() > HerdScript.SNAP_DIST
			if not server_jump and Vector2(p.x - was.x, p.z - was.z).length() > 0.01:
				_jumps += 1
				fail("grazer %d jumped %.2f m on an update" % [id, Vector2(p.x - was.x, p.z - was.z).length()])
		var landed: Vector3 = _herd.position(id, now + HerdScript.BLEND)
		if Vector2(landed.x - sent[id].x, landed.z - sent[id].z).length() > 0.01:
			fail("grazer %d settles at %s, server has it at %s" % [id, str(landed), str(sent[id])])


func on_finish() -> void:
	stat("updates", _feeds)
	stat("bolts_seen", _bolts)
	stat("most_drawn", _most)
	stat("jumps", _jumps)

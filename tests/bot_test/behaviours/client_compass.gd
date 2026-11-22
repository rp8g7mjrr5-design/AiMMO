extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the compass strip on real snapshots. Each bot turns an imaginary camera slowly,
## builds the strip's marks for every other player in each snapshot, and checks that every
## player gets exactly one mark, every mark sits on the strip, dots on the strip point the
## right way, and chevrons for players out of view point to the side you'd turn to.

const CompassScript := preload("res://client/compass.gd")

var _snapshots := 0
var _marks := 0
var _edge_marks := 0
var _most_seen := 0
var _home_marks := 0


func on_snapshot(_tick: int, entries: Array) -> void:
	var me: Vector3 = bot.my_pos
	var yaw := fposmod(bot.elapsed * 0.7, TAU) - PI # a camera turning at ~40 degrees a second
	var others: Array = []
	var i := 0
	while i + 4 < entries.size():
		if entries[i] != bot.my_id:
			var p := Vector3(entries[i + 1], entries[i + 2], entries[i + 3])
			if Vector2(p.x - me.x, p.z - me.z).length() >= 0.5:
				others.append(p)
		i += 5
	_snapshots += 1
	_most_seen = maxi(_most_seen, others.size())
	var w: float = CompassScript.WIDTH
	var marks: Array = CompassScript.player_marks(yaw, me, others, w)
	if marks.size() != others.size():
		fail("compass shows %d marks for %d other players" % [marks.size(), others.size()])
		return
	var h: float = CompassScript.heading(yaw)
	for k in marks.size():
		var m: Dictionary = marks[k]
		var p: Vector3 = others[k]
		_marks += 1
		if not is_finite(m.x) or m.x < 0.0 or m.x > w:
			fail("compass mark off the strip at x=%s" % str(m.x))
			continue
		var rel: float = CompassScript.relative(h, CompassScript.bearing(me, p))
		if m.edge:
			_edge_marks += 1
			# Out of view: the chevron must point the way to turn (the shorter way round).
			if m.side != (-1 if rel < 0.0 else 1):
				fail("chevron points %d for a player at %.0f degrees" % [m.side, rad_to_deg(rel)])
		else:
			var shown: float = (m.x / w - 0.5) * 2.0 * CompassScript.HALF_SPAN
			if absf(shown - rel) > 0.001:
				fail("dot at %.1f degrees for a player at %.1f degrees" % [rad_to_deg(shown), rad_to_deg(rel)])
	var home: Dictionary = CompassScript.home_mark(yaw, me, w)
	if not home.is_empty():
		_home_marks += 1
		if home.x < 0.0 or home.x > w:
			fail("home marker off the strip at x=%s" % str(home.x))


func on_finish() -> void:
	stat("compass_snapshots", _snapshots)
	stat("compass_marks", _marks)
	stat("compass_edge_marks", _edge_marks)
	stat("compass_most_seen", _most_seen)
	stat("compass_home_marks", _home_marks)
	if _snapshots > 50 and _marks == 0:
		fail("never saw another player on the compass in %d snapshots" % _snapshots)

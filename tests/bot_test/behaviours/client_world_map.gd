extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the world map (M) on real snapshots. Each bot puts itself on the map as the
## client's MapWindow does, and checks on every snapshot that it lands on the sheet, maps
## back to where it stands, and stays under the same screen point when the map is zoomed in
## on it; its arrow points the way an imaginary camera turning round looks. Once, it checks
## that every ruin and coast landmark of the world it plays has a mark.

const MapScript := preload("res://client/map_window.gd")

var _snapshots := 0
var _checked_marks := false


func on_snapshot(_tick: int, _entries: Array) -> void:
	var me: Vector3 = bot.my_pos
	_snapshots += 1
	var uv: Vector2 = MapScript.uv_of(me)
	if not (uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0):
		fail("standing at (%.0f, %.0f) is off the map at %s" % [me.x, me.z, str(uv)])
		return
	var back: Vector2 = MapScript.world_of(uv)
	if absf(back.x - me.x) > 0.05 or absf(back.y - me.z) > 0.05:
		fail("the map puts (%.1f, %.1f) back at %s" % [me.x, me.z, str(back)])
	var area := Rect2(0, 0, 600, 600)
	var at := MapScript.to_screen(uv, MapScript.view_rect(1.0, Vector2(0.5, 0.5)), area)
	var z: Array = MapScript.zoom_about(1.0, Vector2(0.5, 0.5), 2.0, uv)
	var after := MapScript.to_screen(uv, MapScript.view_rect(z[0], z[1]), area)
	if at.distance_to(after) > 0.5:
		fail("zooming in on you moved you on screen by %.1f px" % at.distance_to(after))
	var h := fposmod(bot.elapsed * 0.7, TAU)
	var pts: PackedVector2Array = MapScript.arrow(at, h, 10.0)
	var dir := (pts[0] - at).normalized()
	if dir.distance_to(Vector2(sin(h), -cos(h))) > 0.001:
		fail("the map arrow points %s for heading %.2f" % [str(dir), h])
	if not _checked_marks:
		_checked_marks = true
		var marks: Array = MapScript.marks()
		var want := Ruins.count() + BeachGen.landmarks().size() + (0 if WorldGen.is_kingdom() else 1)
		if marks.size() != want:
			fail("the map shows %d marks for %d places" % [marks.size(), want])


func on_finish() -> void:
	stat("map_snapshots", _snapshots)
	if _snapshots > 50 and not _checked_marks:
		fail("never checked the map's marks")

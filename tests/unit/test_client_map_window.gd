extends TestCase
## The world map (M): world to sheet and back, the view under zoom and drag, the marks on the
## island (every ruin and coast landmark), your arrow, the scale bar, the sheet painted off the
## main thread, and the M key in the F1 list.


func test_sheet_maths_round_trip() -> void:
	WorldGen.configure(1126, 3000, 2)
	check_eq(MapWindow.uv_of(Vector3(-1500, 0, -1500)), Vector2(0, 0), "north-west corner")
	check_eq(MapWindow.uv_of(Vector3(1500, 0, 1500)), Vector2(1, 1), "south-east corner")
	check_eq(MapWindow.uv_of(Vector3.ZERO), Vector2(0.5, 0.5), "the middle")
	var p := Vector3(412.0, 3.0, -977.0)
	var back := MapWindow.world_of(MapWindow.uv_of(p))
	check_near(back.x, p.x, 0.01, "x round trip")
	check_near(back.y, p.z, 0.01, "z round trip")
	WorldGen.reset()


func test_view_stays_on_the_sheet() -> void:
	var v := MapWindow.view_rect(1.0, Vector2(0.9, 0.1))
	check_eq(v, Rect2(0, 0, 1, 1), "zoom 1 shows the whole sheet wherever the centre is")
	v = MapWindow.view_rect(4.0, Vector2(0.99, 0.0))
	check_near(v.size.x, 0.25, 0.0001, "zoom 4 shows a quarter")
	check_near(v.end.x, 1.0, 0.0001, "pushed back inside on the right")
	check_near(v.position.y, 0.0, 0.0001, "and at the top")
	check_eq(MapWindow.view_rect(99.0, Vector2(0.5, 0.5)).size.x, 1.0 / MapWindow.ZOOM_MAX, "zoom is capped")


func test_zoom_keeps_the_point_under_the_cursor() -> void:
	var area := Rect2(100, 50, 600, 600)
	var cursor := Vector2(250, 500)
	var view := MapWindow.view_rect(1.0, Vector2(0.5, 0.5))
	var uv := MapWindow.to_sheet(cursor, view, area)
	var z: Array = MapWindow.zoom_about(1.0, Vector2(0.5, 0.5), 2.0, uv)
	check_eq(z[0], 2.0)
	var after := MapWindow.to_screen(uv, MapWindow.view_rect(z[0], z[1]), area)
	check_near(after.x, cursor.x, 0.01, "the point stays under the cursor (x)")
	check_near(after.y, cursor.y, 0.01, "the point stays under the cursor (y)")
	var out: Array = MapWindow.zoom_about(1.0, Vector2(0.5, 0.5), 0.5, uv)
	check_eq(out[0], 1.0, "can't zoom out past the whole island")


func test_marks_cover_every_ruin_and_landmark() -> void:
	WorldGen.configure(1126, 3000, 2)
	BeachGen.reset()
	var m := MapWindow.marks()
	var ruins := m.filter(func(x): return x.kind == "ruin")
	var marks := m.filter(func(x): return x.kind == "landmark")
	check_eq(ruins.size(), Ruins.count(), "every ruin is on the map")
	check(ruins.size() > 10, "the island has plenty of ruins")
	check_eq(marks.size(), BeachGen.landmarks().size(), "every coast landmark is on the map")
	check(marks.size() > 0, "the island has coast landmarks")
	for x in m:
		check(x.uv.x > 0.0 and x.uv.x < 1.0 and x.uv.y > 0.0 and x.uv.y < 1.0, "%s on the sheet" % x.label)
	var farm := ruins.filter(func(x): return str(x.label).begins_with("Burned Farmstead"))
	check(farm.size() > 0, "the Burned Farmstead is named on the map")
	check(str(farm[0].label).ends_with("(Quiet)"), "with its grade: " + str(farm[0].label))
	check_eq(m.filter(func(x): return x.kind == "home").size(), 0, "no Spawn Meadow on the island")
	BeachGen.reset()
	WorldGen.reset()
	var home := MapWindow.marks()
	check_eq(home.size(), 1, "Ashgrove marks Spawn Meadow only")
	check_eq(str(home[0].label), "Spawn Meadow")
	check_eq(MapWindow.title_text(), "Ashgrove")


func test_arrow_points_the_way_you_look() -> void:
	var north := MapWindow.arrow(Vector2(100, 100), 0.0, 10.0)
	check(north[0].y < 100.0 and absf(north[0].x - 100.0) < 0.001, "heading 0 points up the sheet (north)")
	var east := MapWindow.arrow(Vector2(100, 100), PI * 0.5, 10.0)
	check(east[0].x > 100.0 and absf(east[0].y - 100.0) < 0.001, "heading east points right")
	# The camera looking along -z (yaw 0) is north on the compass, and so up on the map.
	check_near(CompassStrip.heading(0.0), 0.0, 0.0001)


func test_scale_bar_is_a_round_length() -> void:
	check_eq(MapWindow.scale_metres(6.0, 140.0), 500.0, "6 m a pixel, 140 px: 500 m")
	check_eq(MapWindow.scale_metres(1.5, 140.0), 100.0, "zoomed in: 100 m")
	check_eq(MapWindow.scale_metres(1.0, 10.0), 50.0, "never shorter than 50 m")


func test_sheet_paints_on_a_worker_and_window_toggles() -> void:
	WorldGen.configure(77, 800, 2)
	var w := MapWindow.new()
	w.setup(Theme.new())
	check(not w.is_ready(), "nothing painted yet")
	w.prepare(5.0)
	w.step(1.0)
	check(not w.is_ready(), "waits out the delay after a world arrives")
	w.prepare()
	w.settle()
	check(w.is_ready(), "the worker painted the sheet")
	var closed := [0]
	w.closed.connect(func(): closed[0] += 1)
	w.feed(Vector3(10, 0, 10), 1.0)
	w.zoom = 3.0
	w.toggle()
	check(w.visible, "M opens it")
	check_eq(w.zoom, 1.0, "it opens on the whole island")
	w.toggle()
	check(not w.visible, "M shuts it")
	check_eq(closed[0], 1)
	WorldGen.configure(78, 800, 2)
	check(not w.is_ready(), "a new world needs a new sheet")
	w.paint_now(64)
	check(w.is_ready(), "painted for the new world")
	w.free()
	WorldGen.reset()


func test_painter_can_leave_marks_off() -> void:
	WorldGen.configure(1, 1200, 1)
	var with_marks := WorldMap.paint(64)
	var bare := WorldMap.paint(64, false)
	check(with_marks.get_data() != bare.get_data(), "marks are drawn only when asked")
	WorldGen.reset()


func test_m_key_is_bound_and_listed() -> void:
	ControlsOverlay.install_input()
	check(InputMap.has_action("toggle_map"), "M is an action")
	check_eq(ControlsOverlay.key_text("toggle_map"), "M")
	check(ControlsOverlay.listed_actions().has("toggle_map"), "M is in the F1 list")

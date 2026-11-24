extends TestCase
## The character-creation window (LookWindow): its rows, titles, and that it previews,
## saves and cancels without the server in the loop.


func test_rows_follow_appearance_order() -> void:
	var r := LookWindow.rows(Appearance.DEFAULT)
	check_eq(r.size(), Appearance.ORDER.size())
	for i in r.size():
		check_eq(r[i].key, Appearance.ORDER[i])
		check(str(r[i].value) != "", "%s has a name" % r[i].key)
	check_eq(LookWindow.rows({}).size(), Appearance.ORDER.size(), "a never-chosen look still shows every row")


func test_titles() -> void:
	check_eq(LookWindow.title_text(true), LookWindow.CREATE_TITLE)
	check_eq(LookWindow.save_text(true), "Set out")
	check_eq(LookWindow.save_text(false), "Save")


func test_open_preview_save_and_cancel() -> void:
	var w := LookWindow.new() # not set up: no controls, just the logic
	var previews: Array = []
	var saves: Array = []
	w.previewed.connect(func(l): previews.append(l))
	w.saved.connect(func(l): saves.append(l))
	w.open({}, 1234, true)
	check(w.visible, "open")
	check_eq(w.look, Appearance.from_seed(1234), "a first-timer starts on their seed look")
	check_eq(previews.size(), 1, "opening previews")
	w.step("beard", 1)
	check_eq(w.look.beard, 1)
	check_eq(previews.size(), 2, "every step previews")
	w.save()
	check(not w.visible, "closed")
	check_eq(saves.size(), 1, "saved once")
	check_eq(Appearance.check(saves[0]), "", "the saved look is complete and valid")
	var mine := saves[0] as Dictionary
	w.open(mine, 1234, false)
	w.step("skin", 1)
	w.cancel()
	check_eq(previews[previews.size() - 1], mine, "cancel puts the old look back")
	check_eq(saves.size(), 1, "cancel never saves")
	w.drag(30.0)
	check(w.orbit != 0.0, "dragging turns the camera")
	w.free()


func test_look_camera_faces_the_traveller() -> void:
	var ClientScript := load("res://client/client.gd")
	var xf: Transform3D = ClientScript.look_camera(Vector3(10, 0, 5), 0.0)
	check(xf.origin.z > 5.0 + 2.0, "in front of a traveller facing +z")
	check((-xf.basis.z).z < 0.0, "looking back at them")

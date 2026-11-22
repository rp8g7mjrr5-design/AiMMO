extends TestCase


func test_roundtrip() -> void:
	var path := OS.get_user_data_dir().path_join("unit_test_store_%d.json" % Time.get_ticks_usec())
	var s := JsonStore.new()
	s.path = path
	check(s.open(), "opens empty")
	var a := s.create_account("Wren", "wren", "h")
	check(not a.is_empty(), "account created")
	check(s.create_account("WREN", "wren", "h").is_empty(), "duplicate refused")
	var ch := s.load_or_create_character(a)
	ch.x = 12.0
	ch.z = -3.0
	check(s.save_character(ch), "saved")
	var s2 := JsonStore.new()
	s2.path = path
	check(s2.open(), "reopens")
	var back := s2.load_or_create_character(s2.find_account("wren"))
	check_near(back.x, 12.0, 0.0001, "x persisted")
	check_eq(back.id, ch.id, "same character")
	DirAccess.remove_absolute(path)


func test_corrupt_file_is_not_overwritten() -> void:
	var path := OS.get_user_data_dir().path_join("unit_test_corrupt_%d.json" % Time.get_ticks_usec())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var s := JsonStore.new()
	s.path = path
	check(not s.open(), "refuses to open")
	check_eq(FileAccess.get_file_as_string(path), "{not json", "file untouched")
	DirAccess.remove_absolute(path)

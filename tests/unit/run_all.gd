extends SceneTree
## Headless unit test runner:
##   godot --headless --path game -s tests/unit/run_all.gd
## Runs every test_*.gd in this folder. Exit code 0 only if everything passed.


func _init() -> void:
	var dir := "res://tests/unit"
	var files := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed: PackedStringArray = []
	var skipped_db := OS.get_environment("DATABASE_URL") == ""
	for f in files:
		var script: GDScript = load(dir.path_join(f))
		if script == null or not script.can_instantiate():
			failed.append("%s: failed to load" % f)
			continue
		var methods: Array = []
		for m in script.get_script_method_list():
			if str(m.name).begins_with("test_"):
				methods.append(m.name)
		for m in methods:
			var tc: TestCase = script.new()
			tc.current = "%s::%s" % [f.get_basename(), m]
			tc.call(m)
			total += 1
			if tc.failures.is_empty():
				print("  ok    ", tc.current)
			else:
				print("  FAIL  ", tc.current)
				failed.append_array(tc.failures)
	print("")
	if skipped_db:
		print("note: DATABASE_URL not set, Postgres tests were skipped")
	if failed.is_empty():
		print("%d tests passed" % total)
		quit(0)
	else:
		for x in failed:
			printerr("  - ", x)
		printerr("%d of %d tests failed" % [failed.size(), total])
		quit(1)

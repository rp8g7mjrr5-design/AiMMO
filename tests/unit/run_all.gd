extends SceneTree
## Headless unit test runner:
##   godot --headless --path game -s tests/unit/run_all.gd
## Runs every test_*.gd in this folder. Exit code 0 only if everything passed.
##
## A test fails if a check fails, or if it logs a SCRIPT ERROR or ERROR line (Godot aborts
## the function on a script error and carries on, so without this a test that died halfway
## would pass). To do that the runner re-runs itself as a child process with markers around
## each test and reads the child's output (see unit_log.gd). A test that expects an engine
## error calls `expect_error("part of the message")` first.
##
## Options (after `--`):
##   --dir=<path>     run the test_*.gd files in another folder (used by the runner's own test)
##   --unit-child     internal: run the tests and print markers instead of a summary

const UnitLog := preload("res://tests/unit/unit_log.gd")
const DEFAULT_DIR := "res://tests/unit"


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var eq := a.find("=")
			if eq == -1:
				opts[a.substr(2)] = true
			else:
				opts[a.substr(2, eq - 2)] = a.substr(eq + 1)
	var dir: String = opts.get("dir", DEFAULT_DIR)
	if opts.has("unit-child"):
		_run_child(dir)
		quit(0)
	else:
		quit(_run_parent(dir))


func _run_parent(dir: String) -> int:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/unit/run_all.gd", "--", "--unit-child", "--dir=" + dir])
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var log := UnitLog.parse(str(out[0]) if out.size() > 0 else "")
	for line in log.passthrough:
		if line.strip_edges() == "" or line.begins_with("Godot Engine v"):
			continue  # blank, or the banner the parent already printed
		print(line)
	var failed := PackedStringArray()
	for r in log.results:
		if r.ok:
			print("  ok    ", r.name)
		else:
			print("  FAIL  ", r.name)
			for p in r.problems:
				failed.append("%s: %s" % [r.name, p])
	for p in log.loose:
		failed.append(p)
	if code != 0:
		failed.append("test process exited with code %d" % code)
	print("")
	if OS.get_environment("DATABASE_URL") == "":
		print("note: DATABASE_URL not set, Postgres tests were skipped")
	var total: int = log.results.size()
	if total == 0:
		failed.append("no tests ran")
	if failed.is_empty():
		print("%d tests passed" % total)
		return 0
	for x in failed:
		printerr("  - ", x)
	printerr("%d problem(s) in %d tests" % [failed.size(), total])
	return 1


func _run_child(dir: String) -> void:
	var files := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load(dir.path_join(f))
		if script == null or not script.can_instantiate():
			print(UnitLog.PREFIX + "begin " + f.get_basename() + "::load")
			print(UnitLog.PREFIX + "failure failed to load")
			print(UnitLog.PREFIX + "end " + f.get_basename() + "::load")
			continue
		var methods: Array = []
		for m in script.get_script_method_list():
			if str(m.name).begins_with("test_"):
				methods.append(m.name)
		for m in methods:
			var tc: TestCase = script.new()
			tc.current = "%s::%s" % [f.get_basename(), m]
			print(UnitLog.PREFIX + "begin " + tc.current)
			tc.call(m)
			for x in tc.failures:
				var msg: String = x.trim_prefix(tc.current + ": ")
				print(UnitLog.PREFIX + "failure " + msg.replace("\n", " "))
			print(UnitLog.PREFIX + "end " + tc.current)

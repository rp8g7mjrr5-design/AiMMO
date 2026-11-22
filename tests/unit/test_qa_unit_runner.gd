extends TestCase
## The unit runner fails tests that hit a SCRIPT ERROR or log an ERROR, instead of
## reporting them `ok` (client stream's request).

const UnitLog := preload("res://tests/unit/unit_log.gd")
const SELFTEST_DIR := "user://qa_runner_selftest"


func _by_name(log: Dictionary) -> Dictionary:
	var d := {}
	for r in log.results:
		d[r.name] = r
	return d


func test_clean_test_passes() -> void:
	var log := UnitLog.parse("[unit] begin a::test_x\nhello\nWARNING: just a warning\n   at: foo\n[unit] end a::test_x\n")
	check_eq(log.results.size(), 1)
	check(log.results[0].ok, "warnings don't fail a test: %s" % [log.results[0].problems])
	check(log.passthrough.has("hello"), "test output is passed through")
	check(not log.passthrough.has("[unit] end a::test_x"), "markers are not passed through")


func test_script_error_fails_only_that_test() -> void:
	var text := "\n".join([
		"[unit] begin a::test_ok", "[unit] end a::test_ok",
		"[unit] begin a::test_boom",
		"SCRIPT ERROR: Invalid access to property or key 'nope' on a base object of type 'Dictionary'.",
		"          at: test_boom (res://tests/unit/test_a.gd:5)",
		"[unit] end a::test_boom",
	])
	var r := _by_name(UnitLog.parse(text))
	check(r["a::test_ok"].ok, "the clean test still passes")
	check(not r["a::test_boom"].ok, "the test with a script error fails")
	check(str(r["a::test_boom"].problems).find("test_a.gd:5") != -1, "problem names the location")


func test_engine_error_fails_unless_expected() -> void:
	var text := "\n".join([
		"[unit] begin a::test_unexpected", "ERROR: custom err", "   at: push_error (x.cpp:1)", "[unit] end a::test_unexpected",
		"[unit] begin a::test_expected", "[unit] expect-error custom", "ERROR: custom err", "[unit] end a::test_expected",
		"[unit] begin a::test_expected_missing", "[unit] expect-error never", "[unit] end a::test_expected_missing",
		"[unit] begin a::test_other_error", "[unit] expect-error custom", "ERROR: something else", "[unit] end a::test_other_error",
	])
	var r := _by_name(UnitLog.parse(text))
	check(not r["a::test_unexpected"].ok, "an unexpected ERROR fails")
	check(r["a::test_expected"].ok, "an expected ERROR is accepted: %s" % [r["a::test_expected"].problems])
	check(not r["a::test_expected_missing"].ok, "an expected error that never came fails")
	check(not r["a::test_other_error"].ok, "expecting one error doesn't excuse another")


func test_check_failures_and_unfinished_tests() -> void:
	var text := "\n".join([
		"[unit] begin a::test_check", "[unit] failure 1 expected 2", "[unit] end a::test_check",
		"[unit] begin a::test_crash", "partial output",
	])
	var log := UnitLog.parse(text)
	var r := _by_name(log)
	check(not r["a::test_check"].ok, "a failed check fails")
	check_eq(r["a::test_check"].problems, PackedStringArray(["1 expected 2"]))
	check(not r["a::test_crash"].ok, "a test that never ended fails")


func test_errors_outside_tests_are_reported() -> void:
	var log := UnitLog.parse("SCRIPT ERROR: Parse Error: oops\n[unit] begin a::test_x\n[unit] end a::test_x\n")
	check_eq(log.loose.size(), 1)
	check(log.results[0].ok, "the test itself is fine")


## End to end: run the real runner on a folder holding one good test and one that hits a
## script error halfway. The runner must exit 1 and name the broken test.
func test_runner_fails_a_test_with_a_script_error() -> void:
	DirAccess.make_dir_recursive_absolute(SELFTEST_DIR)
	var f := FileAccess.open(SELFTEST_DIR.path_join("test_selftest.gd"), FileAccess.WRITE)
	f.store_string("\n".join([
		"extends TestCase",
		"func test_good() -> void:",
		"\tcheck(true, \"fine\")",
		"func test_dies_halfway() -> void:",
		"\tcheck(true, \"first half\")",
		"\tvar d := {}",
		"\tvar x = d.missing.field",
		"\tcheck(true, \"never reached\")",
		"",
	]))
	f.close()
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/unit/run_all.gd", "--", "--dir=" + SELFTEST_DIR]), out, true)
	var text := str(out[0]) if out.size() > 0 else ""
	check_eq(code, 1, "runner exit code")
	check(text.find("ok    test_selftest::test_good") != -1, "good test reported ok")
	check(text.find("FAIL  test_selftest::test_dies_halfway") != -1, "broken test reported FAIL")
	check(text.find("test_selftest.gd:7") != -1, "failure names the line")
	for name in DirAccess.get_files_at(SELFTEST_DIR):
		DirAccess.remove_absolute(SELFTEST_DIR.path_join(name))
	DirAccess.remove_absolute(SELFTEST_DIR)

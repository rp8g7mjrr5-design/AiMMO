class_name TestCase
extends RefCounted
## Base for unit tests. Methods named test_* are run by run_all.gd.

var failures: PackedStringArray = []
var current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func check_eq(got: Variant, want: Variant, msg: String = "") -> void:
	if typeof(got) != typeof(want) or got != want:
		failures.append("%s: %s expected %s, got %s" % [current, msg, var_to_str(want), var_to_str(got)])


func check_near(got: float, want: float, eps: float, msg: String = "") -> void:
	if absf(got - want) > eps:
		failures.append("%s: %s expected %f, got %f" % [current, msg, want, got])


## Tests that need Postgres call this and return early when it is false.
func has_db() -> bool:
	return OS.get_environment("DATABASE_URL") != ""

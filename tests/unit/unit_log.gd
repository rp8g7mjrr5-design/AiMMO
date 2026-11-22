extends RefCounted
## Reads the output of a unit-test child process and decides which tests passed.
##
## Godot 4.3 has no way to catch a SCRIPT ERROR from GDScript: the failing function just
## returns early and the caller carries on, so a test that dies halfway used to report `ok`.
## run_all.gd therefore runs the tests in a child process with markers around each test,
## and this parser fails any test whose output contains a SCRIPT ERROR or an ERROR line,
## plus any test that started but never finished (the child crashed or hung).
##
## Child markers (one per line):
##   [unit] begin <name>
##   [unit] expect-error <substring>    (from TestCase.expect_error)
##   [unit] failure <message>           (a failed check)
##   [unit] end <name>

const PREFIX := "[unit] "
const OUTSIDE := "(outside any test)"


## Returns {results: [{name, ok, problems}], loose: PackedStringArray, passthrough: PackedStringArray}.
## `loose` holds errors logged outside any test (loading files, shutdown). `passthrough`
## is everything that isn't a marker, in order, for printing.
static func parse(text: String) -> Dictionary:
	var results: Array = []
	var loose := PackedStringArray()
	var passthrough := PackedStringArray()
	var cur: Dictionary = {}
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i].strip_edges(false, true)
		if line.begins_with(PREFIX):
			var rest := line.substr(PREFIX.length())
			var sp := rest.find(" ")
			var kind := rest if sp == -1 else rest.substr(0, sp)
			var arg := "" if sp == -1 else rest.substr(sp + 1)
			match kind:
				"begin":
					if not cur.is_empty():
						_close(cur, results, "did not finish (crashed or aborted)")
					cur = {"name": arg, "problems": PackedStringArray(), "expected": PackedStringArray(), "seen": PackedStringArray()}
				"expect-error":
					if not cur.is_empty():
						cur.expected.append(arg)
				"failure":
					if not cur.is_empty():
						cur.problems.append(arg)
					else:
						loose.append(arg)
				"end":
					if not cur.is_empty():
						_close(cur, results, "")
					cur = {}
			continue
		passthrough.append(lines[i])
		var err := error_text(line)
		if err == "":
			continue
		# Godot prints the location on the next line ("   at: func (res://file.gd:12)").
		if i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("at:"):
			err += " " + lines[i + 1].strip_edges()
		if cur.is_empty():
			loose.append("%s %s" % [OUTSIDE, err])
		else:
			var excused := false
			for want in cur.expected:
				if err.find(want) != -1:
					excused = true
					if not cur.seen.has(want):
						cur.seen.append(want)
			if not excused:
				cur.problems.append(err)
	if not cur.is_empty():
		_close(cur, results, "did not finish (crashed or hung)")
	return {"results": results, "loose": loose, "passthrough": passthrough}


## The error message if `line` is a Godot error line, else "". Warnings don't count.
static func error_text(line: String) -> String:
	var s := line.strip_edges()
	if s.begins_with("SCRIPT ERROR:") or s.begins_with("ERROR:") or s.begins_with("USER ERROR:") \
			or s.begins_with("USER SCRIPT ERROR:"):
		return s
	return ""


static func _close(cur: Dictionary, results: Array, unfinished: String) -> void:
	var problems: PackedStringArray = cur.problems
	if unfinished != "":
		problems.append(unfinished)
	for want in cur.expected:
		if not cur.seen.has(want):
			problems.append("expected an error containing '%s' but none was logged" % want)
	results.append({"name": cur.name, "ok": problems.is_empty(), "problems": problems})

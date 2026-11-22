extends TestCase
## Old clients must be told to update, not left hanging at the login screen.
##
## Godot numbers a node's RPCs by sorting their names, and sends the number, not the name.
## An old client's `c2s_login` therefore lands on whatever method has the same number on
## the current server. If a protocol bump adds an RPC whose name sorts before `c2s_login`
## (e.g. `c2s_gather_start`), an old client's login is delivered to `c2s_input`, fails to
## convert, and the player waits forever with no message. Same for `s2c_login_result` on
## the way back.
##
## tests/protocol/net_v<N>.gd are frozen copies of net.gd as shipped at protocol N. This test
## checks that the two login RPCs keep their number and arguments against every one of them.
## tests/protocol/run_protocol_test.py checks the same thing end to end against a live server.

const CURRENT := "res://shared/net.gd"
const FROZEN_DIR := "res://tests/protocol"
const LOGIN_RPCS := ["c2s_login", "s2c_login_result"]

## Protocol versions whose clients are knowingly locked out without a message, with the
## reason. Keep this empty if at all possible: every entry is a player who sees a hang.
const KNOWN_LOCKED_OUT := {}


## Names of the methods marked @rpc in a GDScript file, sorted the way Godot numbers them.
static func rpc_names(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var pending := false
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("@rpc"):
			pending = true
			# `@rpc(...) func name(` on one line is allowed too.
			var at := line.find("func ")
			if at < 0:
				continue
			line = line.substr(at)
		if pending and line.begins_with("func "):
			out.append(line.substr(5, line.find("(") - 5).strip_edges())
			pending = false
	out.sort()
	return out


## "name(type, type, ...)" for a method, from the script's own method list.
static func signature(script: Script, method: String) -> String:
	for m in script.get_script_method_list():
		if m.name == method:
			var types := PackedStringArray()
			for a in m.args:
				types.append(type_string(a.type))
			return "%s(%s)" % [method, ", ".join(types)]
	return ""


static func frozen_versions() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(FROZEN_DIR):
		if f.begins_with("net_v") and f.ends_with(".gd"):
			var v := f.trim_prefix("net_v").trim_suffix(".gd")
			if v.is_valid_int():
				out[int(v)] = FROZEN_DIR.path_join(f)
	return out


## Every way the login RPCs of `old_path` no longer line up with `new_path`. Empty = fine.
static func login_mismatches(old_path: String, new_path: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var old_names := rpc_names(old_path)
	var new_names := rpc_names(new_path)
	var old_script: Script = load(old_path)
	var new_script: Script = load(new_path)
	for m in LOGIN_RPCS:
		var oi := old_names.find(m)
		var ni := new_names.find(m)
		if oi < 0 or ni < 0:
			problems.append("%s is missing (old #%d, new #%d)" % [m, oi, ni])
			continue
		if oi != ni:
			var before := PackedStringArray()
			for n in new_names.slice(0, ni):
				if not old_names.has(n):
					before.append(n)
			problems.append("%s is RPC #%d for old clients but #%d now (new RPCs sorting before it: %s)"
				% [m, oi, ni, ", ".join(before) if not before.is_empty() else "none, one was removed"])
		var old_sig := signature(old_script, m)
		var new_sig := signature(new_script, m)
		if old_sig != new_sig:
			problems.append("%s changed its arguments: %s -> %s" % [m, old_sig, new_sig])
	return problems


func test_rpc_names_parses_net() -> void:
	var names := rpc_names(CURRENT)
	for m in LOGIN_RPCS + ["c2s_input", "s2c_snapshot"]:
		check(names.has(m), "net.gd has %s, got %s" % [m, names])
	var sorted := names.duplicate()
	sorted.sort()
	check_eq(names, sorted, "sorted like Godot numbers them")
	check(not names.has("_ready"), "only @rpc methods")


func test_every_old_protocol_has_a_frozen_copy() -> void:
	var have := frozen_versions()
	check(not have.is_empty(), "no frozen net_v*.gd in %s" % FROZEN_DIR)
	for v in range(1, GameConfig.PROTOCOL_VERSION):
		if KNOWN_LOCKED_OUT.has(v):
			continue
		check(have.has(v), ("protocol v%d has no frozen copy: when you bump PROTOCOL_VERSION, copy "
			+ "the old game/shared/net.gd to tests/protocol/net_v%d.gd") % [v, v])
	for v in have:
		check(v <= GameConfig.PROTOCOL_VERSION, "net_v%d.gd is newer than PROTOCOL_VERSION %d" % [v, GameConfig.PROTOCOL_VERSION])


func test_old_clients_still_reach_the_login_check() -> void:
	var have := frozen_versions()
	for v in have:
		if KNOWN_LOCKED_OUT.has(v) or v == GameConfig.PROTOCOL_VERSION:
			continue
		for p in login_mismatches(have[v], CURRENT):
			check(false, ("v%d clients will hang at login instead of being told to update: %s. Keep the "
				+ "login RPCs at the same number: put new RPCs on another node, or name them to sort "
				+ "after every existing one. See tests/protocol/README.md.") % [v, p])


func test_frozen_copy_of_current_protocol_matches() -> void:
	var have := frozen_versions()
	if not have.has(GameConfig.PROTOCOL_VERSION):
		return
	check_eq(rpc_names(have[GameConfig.PROTOCOL_VERSION]), rpc_names(CURRENT),
		"net_v%d.gd has the same RPCs as net.gd (bump PROTOCOL_VERSION when they change)" % GameConfig.PROTOCOL_VERSION)


func test_detects_a_new_rpc_that_sorts_before_login() -> void:
	# The exact change that would lock out every v2 client: a new c2s_ RPC before c2s_login.
	# Built on the frozen v2 copy so it never depends on what net.gd looks like today.
	var base := FROZEN_DIR.path_join("net_v2.gd")
	var dir := "user://qa_protocol_compat"
	DirAccess.make_dir_recursive_absolute(dir)
	var src := FileAccess.get_file_as_string(base)
	var bad := src.replace("@rpc(\"any_peer\", \"call_remote\", \"reliable\")\nfunc c2s_chat",
		"@rpc(\"any_peer\", \"call_remote\", \"reliable\")\nfunc c2s_gather_start(node_id: int) -> void:\n\tpass\n\n\n@rpc(\"any_peer\", \"call_remote\", \"reliable\")\nfunc c2s_chat")
	check(bad != src, "fixture edit applied")
	var bad_path := dir.path_join("net_bad.gd")
	var f := FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string(bad)
	f.close()
	var problems := login_mismatches(base, bad_path)
	check_eq(problems.size(), 2, "both login RPCs shift, got %s" % [problems])
	check(problems.size() > 0 and "c2s_gather_start" in problems[0], "names the culprit: %s" % [problems])

	# A new RPC that sorts after every existing one is harmless.
	var ok := src + "\n\n@rpc(\"authority\", \"call_remote\", \"reliable\")\nfunc zz_s2c_later(x: int) -> void:\n\tpass\n"
	var ok_path := dir.path_join("net_ok.gd")
	f = FileAccess.open(ok_path, FileAccess.WRITE)
	f.store_string(ok)
	f.close()
	check_eq(login_mismatches(base, ok_path).size(), 0, "appending after the last RPC keeps login numbers")
	DirAccess.remove_absolute(bad_path)
	DirAccess.remove_absolute(ok_path)

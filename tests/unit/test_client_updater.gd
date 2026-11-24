extends TestCase
## Self-update at startup: reading update.json, deciding between play / download / relaunch,
## never looping on a pack that keeps failing, and building the relaunch command line.

const MANIFEST := """{"build": 57, "engine": "4.3-stable", "files": {
	"linux": {"name": "AiMMO-linux.pck", "size": 260400, "sha256": "ABCDEF"},
	"windows": {"name": "AiMMO-windows.pck", "size": 260500, "sha256": "abcdef"},
	"macos": {"name": "../../evil.pck", "size": 1, "sha256": "00"}}}"""


func _cached(build: int, ok := true, tries := 1, exists := true, engine := "4.3-stable") -> Dictionary:
	return {"build": build, "engine": engine, "path": "user://updates/%d-AiMMO-linux.pck" % build,
		"tries": tries, "ok": ok, "exists": exists}


func test_engine_key_matches_godot_release_tags() -> void:
	check_eq(Updater.engine_key({"major": 4, "minor": 3, "patch": 0, "status": "stable"}), "4.3-stable")
	check_eq(Updater.engine_key({"major": 4, "minor": 2, "patch": 2, "status": "stable"}), "4.2.2-stable")
	check_eq(Updater.engine_key().begins_with("%d." % Engine.get_version_info().major), true, "this engine has a key")


func test_parse_manifest() -> void:
	var m := Updater.parse_manifest(MANIFEST)
	check_eq(m.build, 57)
	check_eq(m.engine, "4.3-stable")
	check_eq(m.files.linux.name, "AiMMO-linux.pck")
	check_eq(m.files.linux.size, 260400)
	check_eq(m.files.linux.sha256, "abcdef", "checksums compare in lower case")
	check(not m.files.has("macos"), "a file name with a path in it is ignored")
	check_eq(Updater.parse_manifest(""), {}, "empty")
	check_eq(Updater.parse_manifest("<html>404</html>"), {}, "not json")
	check_eq(Updater.parse_manifest("""{"build": 0, "engine": "4.3-stable", "files": {}}"""), {}, "no build number")
	check_eq(Updater.parse_manifest("""{"build": 3, "files": {}}"""), {}, "no engine")


func test_download_when_the_release_is_newer() -> void:
	var m := Updater.parse_manifest(MANIFEST)
	var plan := Updater.decide(50, "4.3-stable", "linux", {}, m)
	check_eq(plan.action, "download")
	check_eq(plan.build, 57)
	check_eq(plan.file.name, "AiMMO-linux.pck")
	plan = Updater.decide(50, "4.3-stable", "linux", _cached(52), m)
	check_eq(plan.action, "download", "an older pack on disk is replaced")


func test_play_when_up_to_date() -> void:
	var m := Updater.parse_manifest(MANIFEST)
	check_eq(Updater.decide(57, "4.3-stable", "linux", {}, m).action, "play", "built-in build is the newest")
	check_eq(Updater.decide(57, "4.3-stable", "linux", _cached(57), m).action, "play", "booted from the newest pack")
	check_eq(Updater.decide(60, "4.3-stable", "linux", {}, m).action, "play", "never downgrade")
	check_eq(Updater.decide(50, "4.3-stable", "linux", {}, {}).action, "play", "offline with nothing saved")


func test_relaunch_into_the_newest_pack_on_disk() -> void:
	var m := Updater.parse_manifest(MANIFEST)
	var plan := Updater.decide(50, "4.3-stable", "linux", _cached(57), m)
	check_eq(plan.action, "relaunch", "already downloaded")
	check_eq(plan.build, 57)
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57), {}).action, "relaunch", "offline still plays the newest pack")
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57, true, 1, false), {}).action, "play", "pack file deleted")
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57, true, 1, true, "4.4-stable"), {}).action, "play", "pack for another engine")


func test_a_pack_that_keeps_failing_is_skipped() -> void:
	var m := Updater.parse_manifest(MANIFEST)
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57, false, 2), {}).action, "relaunch", "two failed boots: try again")
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57, false, Updater.MAX_TRIES), {}).action, "play", "three: give up on it")
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57, false, Updater.MAX_TRIES), m).action, "play", "and don't download the same build again")
	var newer := m.duplicate(true)
	newer.build = 58
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57, false, Updater.MAX_TRIES), newer).action, "download", "a newer build gets a fresh chance")
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(57, true, 9), {}).action, "relaunch", "a pack that once reached the game is trusted")


func test_engine_change_asks_for_a_fresh_install() -> void:
	var m := Updater.parse_manifest(MANIFEST)
	m.engine = "4.4-stable"
	var plan := Updater.decide(50, "4.3-stable", "linux", {}, m)
	check_eq(plan.action, "need_install")
	check_eq(plan.fallback, "play")
	check_eq(Updater.decide(50, "4.3-stable", "linux", _cached(55), m).fallback, "relaunch", "meanwhile play the newest pack we can")


func test_missing_platform_plays_on() -> void:
	var m := Updater.parse_manifest(MANIFEST)
	check_eq(Updater.decide(50, "4.3-stable", "macos", {}, m).action, "play")


func test_relaunch_args() -> void:
	var a := Updater.relaunch_args("/u/57.pck", PackedStringArray(["--fullscreen"]), PackedStringArray(["--address=x:1"]))
	check_eq(a, PackedStringArray(["--main-pack", "/u/57.pck", "--fullscreen", "--", "--address=x:1", "--updated"]))
	a = Updater.relaunch_args("/u/58.pck", PackedStringArray(["--main-pack", "/u/57.pck"]), PackedStringArray(["--updated"]))
	check_eq(a, PackedStringArray(["--main-pack", "/u/58.pck", "--", "--updated"]), "old pack and flag replaced")
	a = Updater.relaunch_args("", PackedStringArray(["--main-pack", "/u/57.pck"]), PackedStringArray(["--updated", "--no-update"]))
	check_eq(a, PackedStringArray(), "a restart to update boots the built-in game and checks again")


func test_disabled_outside_installed_builds() -> void:
	# Tests, the editor, bots and the server run from source: no build number, no update screen.
	check(not Updater.enabled({}), "running from source")


func test_renamed_pack_reaches_installed_games() -> void:
	# Release packs went from AiMMO-<os>.pck to ZombAi-<os>.pck. A game that booted from an
	# AiMMO pack must still fetch the newer build by whatever name update.json gives.
	var m := Updater.parse_manifest("""{"build": 90, "engine": "4.3-stable", "files": {
		"linux": {"name": "ZombAi-linux.pck", "size": 260400, "sha256": "abcdef"}}}""")
	var plan := Updater.decide(57, "4.3-stable", "linux", _cached(80), m)
	check_eq(plan.action, "download", "an older AiMMO pack on disk is replaced")
	check_eq(plan.file.name, "ZombAi-linux.pck")

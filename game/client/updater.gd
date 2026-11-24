class_name Updater
extends CanvasLayer
## Self-update at startup, so players install the game once and every launch plays the newest build.
##
## How it works: the release pipeline publishes, next to the zips, one game pack per platform
## (`AiMMO-<platform>.pck`, everything except the Godot engine) and `update.json`:
##   {"build": 57, "engine": "4.3-stable", "files": {"windows": {"name": "AiMMO-windows.pck",
##    "size": 123, "sha256": "..."}, "linux": {...}, "macos": {...}}}
## On launch this screen fetches `update.json` from the latest release. If its build is newer than
## the one running, it downloads that platform's pack into `user://updates/` with a progress bar,
## checks its SHA-256, then starts the same executable again with `--main-pack <pack>` and quits.
## Godot then boots the new pack as the whole game (scripts, classes, project settings), so the
## installed file never changes and nothing has to replace a running exe. Later launches start
## the same way: newest pack on disk, else the built-in one. Offline, it plays the newest pack it
## already has. A pack built for another engine version needs a new install; then the screen says
## so once, with a button to the download page.
##
## Only exported builds update (`OS.has_feature("template")` and a baked build number);
## the editor, tests, bots and the server never see this screen. `-- --no-update` skips it.

signal done ## emitted when the game should start in this process (after a relaunch it quits instead)

const DIR := "user://updates"
const STATE_PATH := "user://updates/current.json"
const BUILD_FILE := "res://client/build_id.txt"
const SOURCE_FILE := "res://client/update_url.txt"
const MANIFEST_TIMEOUT := 6.0 ## seconds; slow or no internet just plays what we have
const STALL_TIMEOUT := 25.0 ## seconds without a byte before a download gives up
const UPDATED_FLAG := "updated" ## user arg on a relaunch: this process already checked, just play
const MAX_TRIES := 3 ## launches into a pack that never reached the game before it is skipped
const ACCENT := Color(1.0, 0.72, 0.35) ## ember, like the gather prompt and workbench
const BG := Color(0.09, 0.08, 0.07)

var _title: Label
var _status: Label
var _bar: ProgressBar
var _detail: Label
var _buttons: HBoxContainer
var _http: HTTPRequest
var _args: Dictionary
var _running_build := 0
var _manifest_url := ""
var _base_url := ""
var _result: Array = [] ## [result, http code] once a download finishes


# --- pure helpers (unit tested) ---

## The engine key a pack must match: the same text as Godot's release tag ("4.3-stable", "4.3.1-stable").
static func engine_key(info: Dictionary = Engine.get_version_info()) -> String:
	var v := "%d.%d" % [info.major, info.minor]
	if int(info.patch) > 0:
		v += ".%d" % info.patch
	return "%s-%s" % [v, info.status]


## Parses JSON without logging an engine error on junk (an error page, a half-written file).
static func _quiet_json(text: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


static func platform_key() -> String:
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("macos"):
		return "macos"
	return "linux"


## Reads update.json text. Returns {} unless it has a positive build, an engine and a files table.
static func parse_manifest(text: String) -> Dictionary:
	var data: Variant = _quiet_json(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if not (data.get("build") is float or data.get("build") is int) or int(data.build) <= 0:
		return {}
	if typeof(data.get("engine")) != TYPE_STRING or typeof(data.get("files")) != TYPE_DICTIONARY:
		return {}
	var files := {}
	for k in data.files:
		var f: Variant = data.files[k]
		if typeof(f) == TYPE_DICTIONARY and typeof(f.get("name")) == TYPE_STRING and typeof(f.get("sha256")) == TYPE_STRING:
			var fname: String = f.name
			if fname.is_valid_filename() and fname.ends_with(".pck"):
				files[str(k)] = {"name": fname, "size": int(f.get("size", 0)), "sha256": str(f.sha256).to_lower()}
	return {"build": int(data.build), "engine": data.engine, "files": files}


## What to do at launch. `running`: build number of this process. `cached`: the state file
## ({build, engine, path, tries, ok}) with `exists` set if its pack is on disk, or {}.
## `manifest`: parse_manifest() of the latest release, or {} when offline.
## Returns {action: "play" | "relaunch" | "download" | "need_install", ...}.
static func decide(running: int, engine: String, platform: String, cached: Dictionary, manifest: Dictionary) -> Dictionary:
	var have := 0 # newest pack on disk we may still boot into
	if cached.get("exists", false) and cached.get("engine", "") == engine \
			and (cached.get("ok", false) or int(cached.get("tries", 0)) < MAX_TRIES):
		have = int(cached.get("build", 0))
	var bad_build := 0 # a pack that kept failing before reaching the game
	if cached.get("exists", false) and not cached.get("ok", false) and int(cached.get("tries", 0)) >= MAX_TRIES:
		bad_build = int(cached.get("build", 0))

	if not manifest.is_empty() and int(manifest.build) > maxi(running, have) and int(manifest.build) != bad_build:
		if manifest.engine != engine:
			return {"action": "need_install", "fallback": "relaunch" if have > running else "play"}
		if manifest.files.has(platform):
			return {"action": "download", "build": int(manifest.build), "file": manifest.files[platform]}
	if have > running:
		return {"action": "relaunch", "build": have}
	return {"action": "play"}


## Command line for booting `pack` with the same engine and user args this process got
## (minus an earlier `--main-pack` and our internal flags). An empty `pack` boots the built-in one
## and checks again; a pack gets `--updated` so the new process doesn't check a second time.
static func relaunch_args(pack_path: String, engine_args: PackedStringArray, user_args: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	if pack_path != "":
		out.append_array(["--main-pack", pack_path])
	var skip := false
	for a in engine_args:
		if skip:
			skip = false
		elif a == "--main-pack":
			skip = true
		elif a != "--":
			out.append(a)
	var keep := PackedStringArray()
	for a in user_args:
		if a != "--no-update" and a != "--" + UPDATED_FLAG:
			keep.append(a)
	if pack_path != "":
		keep.append("--" + UPDATED_FLAG)
	if not keep.is_empty():
		out.append("--")
		out.append_array(keep)
	return out


static func running_build() -> int:
	if not FileAccess.file_exists(BUILD_FILE):
		return 0
	return FileAccess.get_file_as_string(BUILD_FILE).strip_edges().to_int()


## True for an exported, release-built client that knows where its updates live.
static func enabled(args: Dictionary) -> bool:
	return OS.has_feature("template") and not args.has("no-update") and running_build() > 0 \
		and FileAccess.file_exists(SOURCE_FILE) and DisplayServer.get_name() != "headless"


static func load_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var d: Variant = _quiet_json(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	d.exists = typeof(d.get("path")) == TYPE_STRING and FileAccess.file_exists(d.path)
	return d


static func save_state(state: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var s := state.duplicate()
	s.erase("exists")
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s, "  "))


## Called once the game itself is running: marks the pack we booted from as good.
static func mark_running_ok() -> void:
	var s := load_state()
	if not s.is_empty() and int(s.get("build", 0)) == running_build() and not s.get("ok", false):
		s.ok = true
		save_state(s)


## The server turned us away as out of date: start again so the update screen fetches the new build.
## Returns false when this build can't update itself (then the caller shows the server's message).
static func restart_for_update(tree: SceneTree) -> bool:
	if not enabled(CliArgs.parse(OS.get_cmdline_user_args())):
		return false
	if OS.create_process(OS.get_executable_path(), relaunch_args("", OS.get_cmdline_args(), OS.get_cmdline_user_args())) == -1:
		return false
	tree.quit(0)
	return true


# --- the update screen ---

func _init(args: Dictionary = {}) -> void:
	_args = args
	layer = 100
	_build_ui()


func _ready() -> void:
	_running_build = running_build()
	print("[updater] build %d, engine %s, %s" % [_running_build, engine_key(), platform_key()])
	_base_url = FileAccess.get_file_as_string(SOURCE_FILE).strip_edges().trim_suffix("/")
	_manifest_url = _base_url + "/update.json"
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)
	_run.call_deferred()


func _run() -> void:
	_set_status("Checking for updates...", -1.0)
	var manifest := await _fetch_manifest()
	var state := load_state()
	var plan := decide(_running_build, engine_key(), platform_key(), state, manifest)
	match plan.action:
		"download":
			var path := await _download(plan.file, int(plan.build))
			if path != "":
				state = {"build": plan.build, "engine": engine_key(), "path": path, "tries": 0, "ok": false}
				save_state(state)
				_cleanup_old(path)
				_relaunch(state)
				return
			# Download failed: play the best we already have.
			state = load_state()
			if decide(_running_build, engine_key(), platform_key(), state, {}).action == "relaunch":
				_relaunch(state)
				return
		"relaunch":
			_relaunch(state)
			return
		"need_install":
			await _ask_for_install()
			if plan.fallback == "relaunch":
				_relaunch(state)
				return
	_finish()


func _fetch_manifest() -> Dictionary:
	_http.timeout = MANIFEST_TIMEOUT
	_http.download_file = ""
	if _http.request(_manifest_url) != OK:
		return {}
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("[updater] no update info (result %d, HTTP %d)" % [res[0], res[1]])
		return {}
	return parse_manifest((res[3] as PackedByteArray).get_string_from_utf8())


## Downloads one pack with a live progress bar. Returns its user:// path, or "" on any failure.
func _download(file: Dictionary, build: int) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var final_path := "%s/%d-%s" % [DIR, build, file.name]
	var part := final_path + ".part"
	if FileAccess.file_exists(final_path) and FileAccess.get_sha256(final_path) == file.sha256:
		return final_path
	_title.text = "Updating ZombAi"
	_set_status("Downloading the newest world...", 0.0)
	_http.timeout = 0.0
	_http.download_file = part
	if _http.request(_base_url + "/" + file.name) != OK:
		return ""
	var last_bytes := -1
	var last_change := Time.get_ticks_msec()
	_result = []
	_http.request_completed.connect(_on_download_completed, CONNECT_ONE_SHOT)
	while _result.is_empty():
		await get_tree().process_frame
		var got := _http.get_downloaded_bytes()
		var total := _http.get_body_size()
		if total <= 0:
			total = int(file.size)
		if got != last_bytes:
			last_bytes = got
			last_change = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_change > STALL_TIMEOUT * 1000.0:
			_http.cancel_request()
			print("[updater] download stalled")
			DirAccess.remove_absolute(part)
			return ""
		if total > 0:
			_set_status("Downloading the newest world...", clampf(float(got) / total, 0.0, 1.0))
			_detail.text = "%.1f of %.1f MB" % [got / 1048576.0, total / 1048576.0]
	var r: Array = _result
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		print("[updater] download failed (result %d, HTTP %d)" % [r[0], r[1]])
		DirAccess.remove_absolute(part)
		return ""
	_set_status("Checking the download...", 1.0)
	_detail.text = ""
	await get_tree().process_frame
	if FileAccess.get_sha256(part) != file.sha256:
		print("[updater] download did not match its checksum")
		DirAccess.remove_absolute(part)
		return ""
	DirAccess.remove_absolute(final_path)
	if DirAccess.rename_absolute(part, final_path) != OK:
		return ""
	return final_path


func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_result = [result, code]


## Starts this executable again on the pack in `state`, then quits. Falls back to playing here.
func _relaunch(state: Dictionary) -> void:
	_set_status("Starting the newest version...", 1.0)
	await get_tree().process_frame
	state.tries = int(state.get("tries", 0)) + 1
	save_state(state)
	var pack := ProjectSettings.globalize_path(str(state.path))
	var pid := OS.create_process(OS.get_executable_path(), relaunch_args(pack, OS.get_cmdline_args(), OS.get_cmdline_user_args()))
	if pid == -1:
		print("[updater] could not start the new version; playing this one")
		_finish()
		return
	get_tree().quit(0)


func _cleanup_old(keep: String) -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		var p := DIR + "/" + f
		if p != keep and f.ends_with(".pck"):
			d.remove(f)


func _ask_for_install() -> void:
	_title.text = "A new ZombAi installer is out"
	_set_status("This update needs a fresh install, just this once.", -1.0)
	_detail.text = "Download the new version from the page that opens, then play from it."
	var page := Button.new()
	page.text = "Open download page"
	var later := Button.new()
	later.text = "Play this version"
	_buttons.add_child(page)
	_buttons.add_child(later)
	var page_url := _base_url.trim_suffix("/download")
	page.pressed.connect(func(): OS.shell_open(page_url))
	await later.pressed


func _finish() -> void:
	done.emit()
	queue_free()


func _set_status(text: String, progress: float) -> void:
	_status.text = text
	_bar.visible = progress >= 0.0
	if progress >= 0.0:
		_bar.value = progress


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	_title = Label.new()
	_title.text = "ZombAi · Ashgrove"
	_title.add_theme_font_size_override("font_size", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.modulate = Color(1, 1, 1, 0.8)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(460, 14)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.16, 0.14, 0.12)
	track.border_color = Color(ACCENT, 0.5)
	track.set_border_width_all(1)
	track.set_corner_radius_all(7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(7)
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)

	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.modulate = Color(1, 1, 1, 0.55)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_buttons)

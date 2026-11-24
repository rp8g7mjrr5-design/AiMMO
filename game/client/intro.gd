class_name Intro
extends CanvasLayer
## The Budda Games studio intro (owner request, 2026-11-23). Plays once when the desktop
## client starts, in place of Godot's boot splash (project.godot hides the splash image and
## paints its background in the video's own colour, so launch goes straight from that colour
## into the video with no engine logo or flash). Any key, click or pad button skips it with a
## short fade. `finished` fires exactly once, when it ends, is skipped, or cannot play.
##
## The video is the one imported asset in the client: the owner supplied it and asked for it
## (see design bible, owner directions, "Studio intro"). Everything else stays procedural.

signal finished

## Two encodes of the same clip, so the pixel-art logo is drawn 1:1 instead of being squashed by
## the GPU (a 1080p frame bilinear-shrunk into the 1280x720 default window looks blurry).
## The 720p one is downscaled offline with Lanczos. Both were cut at 6.4 s with a fade to BG:
## the owner's recording ran on past the logo into another project's title screen.
const VIDEO_PATH := "res://client/intro/budda_games_intro.ogv"
const VIDEO_PATH_720 := "res://client/intro/budda_games_intro_720.ogv"
const SIZE_1080 := Vector2(1920, 1080)
const SIZE_720 := Vector2(1280, 720)
## The video's first-frame background (#1d161a). The boot splash uses the same colour.
const BG := Color(0.114, 0.086, 0.102)
const SKIP_FADE := 0.25 ## seconds of fade to black when skipped
## Safety net: the clip is 6.4 s; if playback stalls, never hold the player longer than this.
const MAX_SECONDS := 10.0
## Args that mean "an automated run" (smoke tests, bots, auto-login): those start straight in
## so their timings and screenshots don't change. `--no-intro` turns it off by hand, and a
## relaunch after a self-update (`--updated`) has already shown it once.
const SKIP_ARGS := ["no-intro", "updated", "screenshot", "autoconnect", "bot", "server"]

var _player: VideoStreamPlayer
var _native := SIZE_1080 ## pixel size of the encode playing
var _fade: ColorRect
var _done := false
var _skipping := false


## Whether the intro plays for these user args (CliArgs.parse) on this display.
static func should_play(args: Dictionary, display: String = DisplayServer.get_name()) -> bool:
	if display == "headless":
		return false
	if args.has("intro"):
		return true # test hook: force it even alongside other test flags
	for a in SKIP_ARGS:
		if args.has(a):
			return false
	return ResourceLoader.exists(VIDEO_PATH)


## True for input that should skip the intro: a key, mouse button or pad button going down.
static func is_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton or event is InputEventJoypadButton:
		return event.pressed
	return false


func _ready() -> void:
	layer = 128 # above anything the client adds later
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# The video's edges are BG too, so it sits centred on the same colour at any size.
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	var win := get_viewport().get_visible_rect().size
	var path := pick_video(win)
	_native = SIZE_1080 if path == VIDEO_PATH else SIZE_720
	var stream: Resource = load(path) if ResourceLoader.exists(path) else null
	if not stream is VideoStream:
		push_warning("[intro] %s missing, starting without it" % VIDEO_PATH)
		_finish.call_deferred()
		return
	_player.stream = stream
	_layout()
	get_viewport().size_changed.connect(_layout)
	_player.finished.connect(_finish)
	_player.play()
	get_tree().create_timer(MAX_SECONDS).timeout.connect(_finish)


## Which encode to play in a window this size: the 1080p one when it fits 1:1, else the 720p one
## (made for the default 1280x720 window). Falls back to whichever file exists.
static func pick_video(win: Vector2) -> String:
	var want := VIDEO_PATH if win.x >= SIZE_1080.x and win.y >= SIZE_1080.y else VIDEO_PATH_720
	if ResourceLoader.exists(want):
		return want
	return VIDEO_PATH if want == VIDEO_PATH_720 else VIDEO_PATH_720


## On-screen scale for a `native`-sized video in `win`: the largest whole number that fits, so
## every video pixel is drawn as a clean square; only a window smaller than the video shrinks it.
static func video_scale(win: Vector2, native: Vector2) -> float:
	var fit := minf(win.x / native.x, win.y / native.y)
	return floorf(fit) if fit >= 1.0 else fit


func _layout() -> void:
	var win := get_viewport().get_visible_rect().size
	var s := video_scale(win, _native)
	var whole := is_equal_approx(s, roundf(s))
	# Whole-number scales use nearest so pixels stay sharp; a shrink needs linear to not shimmer.
	_player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if whole else CanvasItem.TEXTURE_FILTER_LINEAR
	_player.size = (_native * s).round()
	_player.position = ((win - _player.size) * 0.5).round()


func _input(event: InputEvent) -> void:
	if _done or not is_skip_event(event):
		return
	get_viewport().set_input_as_handled()
	skip()


## Fades out quickly and ends the intro. Safe to call more than once.
func skip() -> void:
	if _done or _skipping:
		return
	_skipping = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, SKIP_FADE)
	tw.parallel().tween_property(_player, "volume_db", -40.0, SKIP_FADE)
	tw.tween_callback(_finish)


func is_done() -> bool:
	return _done


func _finish() -> void:
	if _done:
		return
	_done = true
	if _player != null:
		_player.stop()
	finished.emit()
	queue_free()

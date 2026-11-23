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

const VIDEO_PATH := "res://client/intro/budda_games_intro.ogv"
## The video's first-frame background (#1d161a). The boot splash uses the same colour.
const BG := Color(0.114, 0.086, 0.102)
const SKIP_FADE := 0.25 ## seconds of fade to black when skipped
## Safety net: the clip is 6.9 s; if playback stalls, never hold the player longer than this.
const MAX_SECONDS := 10.0
## Args that mean "an automated run" (smoke tests, bots, auto-login): those start straight in
## so their timings and screenshots don't change. `--no-intro` turns it off by hand, and a
## relaunch after a self-update (`--updated`) has already shown it once.
const SKIP_ARGS := ["no-intro", "updated", "screenshot", "autoconnect", "bot", "server"]

var _player: VideoStreamPlayer
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
	# Letterbox: the 16:9 video keeps its shape in any window, centred on the same colour.
	var box := AspectRatioContainer.new()
	box.ratio = 16.0 / 9.0
	box.stretch_mode = AspectRatioContainer.STRETCH_FIT
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_player)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	var stream: Resource = load(VIDEO_PATH) if ResourceLoader.exists(VIDEO_PATH) else null
	if not stream is VideoStream:
		push_warning("[intro] %s missing, starting without it" % VIDEO_PATH)
		_finish.call_deferred()
		return
	_player.stream = stream
	_player.finished.connect(_finish)
	_player.play()
	get_tree().create_timer(MAX_SECONDS).timeout.connect(_finish)


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

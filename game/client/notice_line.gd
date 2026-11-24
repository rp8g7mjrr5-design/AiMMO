class_name NoticeLine
extends Control
## Centre-screen notices (owner direction 1: chat is for talking). Every system line the
## server sends that isn't a player arriving or leaving shows here, a little above the
## reticle where your eyes already are, instead of scrolling past in chat:
##
##   Chat is for talking.            <- headline, warm, 20 px
##   Press F1 for controls.          <- the rest of the line, smaller and softer
##
## It pops in, holds long enough to read (longer for longer lines), and fades. A new notice
## replaces the old one; the same notice again just holds it longer. It never takes the mouse
## or the keyboard. Refusals ("that line wasn't sent", "this ash is spent") come with a soft
## low two-note "nope" (Sfx.nope) so you hear it even with your eyes on a node.
##
## Join and leave lines stay in chat (they are about people). A server line that only repeats
## what the gather prompt's refusal toast just said ("Your pack is full") is dropped, so it is
## never said twice; one that adds something (when a spent node comes back, where the next
## one is) shows here. Dev command answers that run over a few lines stay in chat.
##
## Routing, splitting, hold time and opacity are static, so they are unit tested headless.

const WIDTH := 640.0
const HEIGHT := 64.0
const MAX_CHARS := 220 ## longer lines (dev command answers) stay in chat
## A server line that arrives within this many seconds of a gather refusal is its partner.
const PAIR_WINDOW := 1.0
## Gather refusal reasons whose toast ("Your pack is full", "Needs Felling 5") already says
## everything the server's longer line does. Any other reason (today "depleted", which adds
## when the node comes back and where the next one is) shows the server's line here.
const SAID_BY_TOAST := ["full", "day", "busy", "cooldown", "level", "far", "unknown"]
const HOLD_MIN := 2.4
const HOLD_MAX := 6.0
const HOLD_PER_CHAR := 0.04 ## seconds of reading per character
const POP_SECONDS := 0.14 ## scale POP_FROM -> 1.0
const POP_FROM := 1.04 ## a small settle, not a shout (art bible section 9)
const FADE_SECONDS := 0.6 ## the last part of the hold
const REFUSAL := HudStyle.NOTE ## GatherPrompt.NOTICE: warm, not alarming
const INFO := Color(0.95, 0.90, 0.78) ## a welcome: a touch brighter than a refusal
const DETAIL := Color(HudStyle.TEXT, 0.85)

var headline_label: Label
var detail_label: Label
var refusal := false ## the notice showing is a refusal (for the sound and the colour)
var _age := INF
var _hold := 0.0
var _clock := 0.0
var _refused_reason := ""
var _refused_at := -INF


## Where a system line goes: "chat" (a player arrived or left, or a long dev answer),
## "drop" (it repeats the refusal toast of `paired_reason`, a gather refusal that came just
## before it; "" for none), or "notice" (centre screen).
static func route(text: String, paired_reason := "") -> String:
	var t := text.strip_edges()
	if t == "":
		return "drop"
	if is_presence(t) or t.length() > MAX_CHARS or t.contains("\n"):
		return "chat"
	if paired_reason != "" and SAID_BY_TOAST.has(paired_reason):
		return "drop"
	return "notice"


## "Ash has arrived." / "Ash has left.": the server's join and leave lines.
static func is_presence(text: String) -> bool:
	return RegEx.create_from_string("^\\S.{0,39} has (arrived|left)\\.$").search(text) != null


## Splits a line into its first sentence (the headline) and the rest (the detail):
## "Chat is for talking. Press F1 for controls." -> {headline: "Chat is for talking.",
## detail: "Press F1 for controls."}. One sentence: detail is "".
static func split(text: String) -> Dictionary:
	var t := text.strip_edges()
	var cut := -1
	for mark in [". ", "! ", "? "]:
		var at := t.find(mark)
		if at > 0 and (cut < 0 or at < cut):
			cut = at
	if cut < 0:
		return {"headline": t, "detail": ""}
	return {"headline": t.substr(0, cut + 1), "detail": t.substr(cut + 2).strip_edges()}


## Seconds a notice of `text` stays up (fade included): long enough to read, never long
## enough to be in the way.
static func hold_seconds(text: String) -> float:
	return clampf(HOLD_MIN * 0.75 + text.length() * HOLD_PER_CHAR, HOLD_MIN, HOLD_MAX)


## Opacity `age` seconds into a notice held `hold` seconds: full, then fades over the end.
static func alpha(age: float, hold: float) -> float:
	if age < 0.0 or age >= hold:
		return 0.0
	var fade_from := maxf(0.0, hold - FADE_SECONDS)
	if age <= fade_from:
		return 1.0
	return 1.0 - smoothstep(fade_from, hold, age)


## The pop: 1.12 at the start, settling to 1.0 over POP_SECONDS.
static func pop_scale(age: float) -> float:
	if age >= POP_SECONDS or age < 0.0:
		return 1.0
	var t := age / POP_SECONDS
	return lerpf(POP_FROM, 1.0, 1.0 - (1.0 - t) * (1.0 - t))


func setup(theme: Theme) -> void:
	self.theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	pivot_offset = Vector2(WIDTH * 0.5, 14.0)
	headline_label = _make_label(17, REFUSAL, 0.0)
	detail_label = _make_label(14, DETAIL, 27.0)
	hide_all()


func _make_label(font_size: int, color: Color, y: float) -> Label:
	var l := Label.new()
	l.position = Vector2(0, y)
	l.size = Vector2(WIDTH, font_size + 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.quiet_label(l, font_size, color)
	add_child(l)
	return l


## A gather refusal with words just showed on the gather prompt's toast (its reason), so
## the server's matching line, if it comes in the next PAIR_WINDOW seconds, can be judged.
func note_refusal(reason: String) -> void:
	_refused_reason = reason
	_refused_at = _clock


## The refusal reason a system line arriving now pairs with ("" for none).
func paired_reason() -> String:
	return _refused_reason if _clock - _refused_at <= PAIR_WINDOW else ""


## A system line from the server. Shows it if it belongs here and returns where it went
## ("chat", "drop" or "notice"); the client puts "chat" lines in chat.
func on_system(text: String) -> String:
	var where := route(text, paired_reason())
	if paired_reason() != "":
		_refused_reason = "" # one line answers one refusal
	if where == "notice":
		show_notice(text, true)
	return where


## Shows `text` centre screen. `is_refusal` picks the warm refusal colour (and tells the
## client to play the nope); false for a welcome. The same text again holds it longer.
func show_notice(text: String, is_refusal := true) -> void:
	var parts := split(text)
	var again: bool = visible_now() and headline_label.text == str(parts.headline) and detail_label.text == str(parts.detail)
	headline_label.text = parts.headline
	detail_label.text = parts.detail
	detail_label.visible = str(parts.detail) != ""
	refusal = is_refusal
	headline_label.add_theme_color_override("font_color", REFUSAL if is_refusal else INFO)
	_hold = hold_seconds(text)
	_age = POP_SECONDS if again else 0.0 # no second pop for a repeat, just a longer hold
	_apply()


func visible_now() -> bool:
	return alpha(_age, _hold) > 0.0


func text_now() -> String:
	if not visible_now():
		return ""
	return headline_label.text if detail_label.text == "" else "%s %s" % [headline_label.text, detail_label.text]


func step(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	if _age < INF:
		_age += maxf(delta, 0.0)
	_apply()


func _apply() -> void:
	var a := alpha(_age, _hold)
	modulate.a = a
	visible = a > 0.0
	var s := pop_scale(_age)
	scale = Vector2(s, s)


func hide_all() -> void:
	_age = INF
	_hold = 0.0
	_refused_reason = ""
	_refused_at = -INF
	refusal = false
	if headline_label:
		headline_label.text = ""
		detail_label.text = ""
	_apply()

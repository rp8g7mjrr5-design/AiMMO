class_name ChatFeed
extends RefCounted
## Chat polish: how chat lines look and when the chat panel fades.
##
## - Every line gets a small in-game timestamp ("14:05"), read from the same shared clock as
##   the sky and the time dial, so "see you at dusk" lines up with what players see.
## - The panel fades out after a while with nothing new, and comes straight back on a new
##   line, on Enter, while typing, or with the mouse over it.
## - The log keeps the last MAX_LINES lines so a long session doesn't grow it forever.
## All of it is static maths or plain state so it is unit tested headless.

const MAX_LINES := 150 ## lines kept in the chat log
const IDLE_HOLD := 12.0 ## seconds a quiet chat stays fully visible
const FADE_TIME := 1.5 ## seconds the fade-out takes
const MIN_ALPHA := 0.0 ## how far it fades (0 = gone until something wakes it)
const FULL_ALPHA := 0.92 ## the panel's normal opacity
const NAME_COLOR := "#ffd27a"
const SYSTEM_COLOR := "#9fd3ff"
const TIME_COLOR := "#ffffff80"

var idle := 0.0 ## seconds since the chat last had a reason to be visible
var line_count := 0


## "14:05" for a moment in world time (24-hour, same as the time dial and /time).
static func timestamp(world_seconds: float) -> String:
	if not is_finite(world_seconds):
		return "--:--"
	var h := WorldClock.hour(world_seconds)
	var hh := int(floor(h)) % 24
	var mm := clampi(int(floor((h - floor(h)) * 60.0)), 0, 59)
	return "%02d:%02d" % [hh, mm]


## Makes text safe to put inside BBCode: brackets become BBCode's escaped brackets. The
## server already strips them from chat, but the client shouldn't trust that.
static func escape(text: String) -> String:
	var out := ""
	for ch in text:
		if ch == "[":
			out += "[lb]"
		elif ch == "]":
			out += "[rb]"
		else:
			out += ch
	return out


## A player's line: dim timestamp, coloured name, then the text.
static func chat_line(world_seconds: float, from_name: String, text: String) -> String:
	return "[color=%s]%s[/color] [color=%s]%s[/color]: %s" % [
		TIME_COLOR, timestamp(world_seconds), NAME_COLOR, escape(from_name), escape(text)]


## A system line (join/leave notices, /who and /time answers): dim timestamp, italic blue.
static func system_line(world_seconds: float, text: String) -> String:
	return "[color=%s]%s[/color] [color=%s][i]%s[/i][/color]" % [
		TIME_COLOR, timestamp(world_seconds), SYSTEM_COLOR, escape(text)]


## The panel's opacity after `idle_seconds` with nothing new. `awake` (typing, mouse over
## the panel, settings open) keeps it fully visible.
static func alpha(idle_seconds: float, awake: bool) -> float:
	if awake or idle_seconds <= IDLE_HOLD:
		return FULL_ALPHA
	var t := clampf((idle_seconds - IDLE_HOLD) / FADE_TIME, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t) # smoothstep, so the fade eases in and out
	return lerpf(FULL_ALPHA, MIN_ALPHA, t)


## How many of the oldest lines to drop after adding one, to stay at MAX_LINES.
static func lines_to_trim(count: int) -> int:
	return maxi(0, count - MAX_LINES)


## Something happened in chat (a new line, Enter pressed): show it again.
func wake() -> void:
	idle = 0.0


## Advances the idle timer and returns the panel's opacity for this frame.
func step(delta: float, awake: bool) -> float:
	if awake:
		idle = 0.0
	else:
		idle += maxf(delta, 0.0)
	return alpha(idle, awake)


## Appends one BBCode line to `label`, trimming the oldest so at most MAX_LINES remain.
func append(label: RichTextLabel, bbcode: String) -> void:
	label.append_text(bbcode + "\n")
	line_count += 1
	var drop := lines_to_trim(line_count)
	for i in drop:
		label.remove_paragraph(0)
	line_count -= drop
	wake()


func clear(label: RichTextLabel) -> void:
	label.clear()
	line_count = 0
	wake()

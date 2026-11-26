class_name WipeSchedule
## When a server wipes (owner, 2026-11-26: "lets do monthly", and it happens on its own).
## The first Thursday of every month at 19:00 UTC: evening in Europe, afternoon in the
## Americas, so most people can be there when the new island opens. "never" (the default)
## never wipes, so a server that doesn't ask for wipes behaves exactly as before.
##
## Pure maths on Unix seconds (UTC), no clock of its own, so tests can pick any date.

const NEVER := "never"
const MONTHLY := "monthly"
const WEEKDAY := 4 ## Thursday (Time's weekday: 0 is Sunday)
const HOUR := 19 ## UTC
const WARN_MINUTES := [60, 10, 1] ## players online get a warning this many minutes before

const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August",
	"September", "October", "November", "December"]
const DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]


## The rule from AIMMO_WIPE / --wipe: "monthly" or "never". Anything else is never.
static func parse(raw: String) -> String:
	return MONTHLY if raw.strip_edges().to_lower() == MONTHLY else NEVER


## The wipe time (Unix seconds) of `year`/`month`: its first Thursday at 19:00 UTC.
static func wipe_in(year: int, month: int) -> int:
	var first := int(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": 1, "hour": HOUR, "minute": 0, "second": 0}))
	var wd := int(Time.get_datetime_dict_from_unix_time(first).weekday)
	return first + ((WEEKDAY - wd + 7) % 7) * 86400


## The first wipe strictly after `unix` under `rule`, or 0 for never.
static func next_after(unix: int, rule: String = MONTHLY) -> int:
	if rule != MONTHLY:
		return 0
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var y := int(d.year)
	var m := int(d.month)
	var t := wipe_in(y, m)
	if t <= unix:
		m += 1
		if m > 12:
			m = 1
			y += 1
		t = wipe_in(y, m)
	return t


## "Thursday 3 December, 19:00 UTC".
static func describe(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%s %d %s, %02d:%02d UTC" % [DAYS[int(d.weekday)], int(d.day), MONTHS[int(d.month) - 1], int(d.hour), int(d.minute)]


## "in 6 days", "in 5 hours", "in 12 minutes", "in under a minute".
static func countdown(seconds: int) -> String:
	if seconds >= 2 * 86400:
		return "in %d days" % (seconds / 86400)
	if seconds >= 2 * 3600:
		return "in %d hours" % (seconds / 3600)
	if seconds >= 120:
		return "in %d minutes" % (seconds / 60)
	if seconds >= 60:
		return "in a minute"
	return "in under a minute"


## The line a player sees at login on a server that wipes.
static func notice(wipe_at: int, now: int) -> String:
	return "This island wipes %s (%s). A new island rolls, packs are cleared, your look stays." % [countdown(wipe_at - now), describe(wipe_at)]


## The warning for `minutes` before the wipe.
static func warning(minutes: int) -> String:
	if minutes <= 1:
		return "The island wipes in one minute. The tide is coming in."
	return "The island wipes in %d minutes. Everything you carry goes with it." % minutes

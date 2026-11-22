class_name WorldClock
## The shared time of day in Ashgrove. The server owns the clock and sends world seconds to
## clients at login and every WORLD_TIME_SYNC_SECONDS (see net.gd s2c_world_time). Everything
## else here is pure maths, so the client, the world visuals, and later systems (night
## danger, lamps, quests) all read time the same way.
##
## World time is real seconds since WORLD_EPOCH_UNIX, which is derived from the wall clock,
## so it survives server restarts with nothing stored and every server agrees on it.
## World second 0 is dawn of day 1: the settlers arrived at sunrise.
##
## A "day fraction" is 0.0 at midnight, 0.25 at sunrise, 0.5 at noon, 0.75 at sunset.

const DAY_SECONDS := 40.0 * 60.0 ## one in-game day lasts 40 real minutes
const WORLD_EPOCH_UNIX := 1795154400.0 ## 2026-11-20 00:00 America/Chicago, the start of Week 00
const START_FRACTION := 0.25 ## world second 0 is sunrise

## Phase boundaries as day fractions. Dawn and dusk are short so most of the day is either
## clearly light or clearly dark.
const DAWN_START := 0.22
const DAY_START := 0.30
const DUSK_START := 0.70
const NIGHT_START := 0.78


## World seconds right now on this machine's wall clock. Only the server should treat this
## as the truth; clients use the synced value (see extrapolate) in case their clock is off.
static func now_seconds(offset_seconds: float = 0.0) -> float:
	return Time.get_unix_time_from_system() - WORLD_EPOCH_UNIX + offset_seconds


## 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
static func day_fraction(world_seconds: float) -> float:
	return fposmod(world_seconds / DAY_SECONDS + START_FRACTION, 1.0)


## Day 1 is the first day. Days roll over at midnight.
static func day_number(world_seconds: float) -> int:
	return int(floor(world_seconds / DAY_SECONDS + START_FRACTION)) + 1


## In-game clock on a 24-hour dial, e.g. 13.5 is half past one in the afternoon.
static func hour(world_seconds: float) -> float:
	return day_fraction(world_seconds) * 24.0


## "dawn", "day", "dusk", or "night".
static func phase(world_seconds: float) -> String:
	var f := day_fraction(world_seconds)
	if f >= NIGHT_START or f < DAWN_START:
		return "night"
	if f < DAY_START:
		return "dawn"
	if f < DUSK_START:
		return "day"
	return "dusk"


static func is_night(world_seconds: float) -> bool:
	return phase(world_seconds) == "night"


## Sun height: +1 at noon, 0 at sunrise and sunset, -1 at midnight.
static func sun_elevation(world_seconds: float) -> float:
	return sin((day_fraction(world_seconds) - 0.25) * TAU)


## Unit vector pointing from the ground toward the sun. The sun rises in the east (+x),
## peaks a little to the south (+z) so noon shadows are not straight down, and sets in the
## west (-x). Below the horizon at night (y < 0).
static func sun_direction(world_seconds: float) -> Vector3:
	var a := (day_fraction(world_seconds) - 0.25) * TAU
	return Vector3(cos(a), sin(a), 0.35).normalized()


## 0.0 in deep night, 1.0 in full day, smooth through dawn and dusk. Handy for blending
## sky colours, lamp glow, or (later) how far hostile creatures roam.
static func daylight(world_seconds: float) -> float:
	return smoothstep(-0.12, 0.12, sun_elevation(world_seconds))


## Client-side: estimate world seconds now from the last value the server sent and how
## much local time has passed since (both in milliseconds from Time.get_ticks_msec()).
static func extrapolate(synced_seconds: float, synced_at_msec: int, now_msec: int) -> float:
	return synced_seconds + maxf(0.0, float(now_msec - synced_at_msec) / 1000.0)


## A readable label like "Day 3, 14:05 (day)" for logs and, later, the HUD.
static func describe(world_seconds: float) -> String:
	var h := hour(world_seconds)
	var hh := int(floor(h))
	var mm := int(floor((h - hh) * 60.0))
	return "Day %d, %02d:%02d (%s)" % [day_number(world_seconds), hh, mm, phase(world_seconds)]

class_name SpawnReturn
extends RefCounted
## "Return to Spawn Meadow" in the Esc menu (gameplay's c2s_unstuck, protocol v5). Pure state,
## no nodes: the settings menu draws the button from `label()` / `enabled()`, client.gd sends
## the ask and feeds the server's answer back with `answered()`.
##
## The button counts the server's cooldown down ("Return to Spawn Meadow (42 s)"), waits for
## an answer after a press ("Heading home..."), and gives the press back if the answer never
## comes (a dropped connection), so it can't stay greyed forever. Times are in milliseconds
## from `Time.get_ticks_msec()` (or any clock a test passes in).

const LABEL := "Return to Spawn Meadow"
const ASKING_LABEL := "Heading home..."
## An ask with no answer after this long is given up (the server always answers, so this only
## covers a lost connection or a server restart).
const ANSWER_TIMEOUT_MS := 5000
const TOOLTIP := "Lost or stuck? Takes you back to Spawn Meadow, by the workbench. Once a minute."

var ready_at_ms := 0 ## the button works again from this time (the server's cooldown)
var asked_at_ms := -1 ## when the open ask went out; -1 when none is open
var asks := 0
var homes := 0


## Forget everything (logout, disconnect): a new session starts with the button ready. The
## server keeps its own cooldown, so a reconnect inside it still gets an honest countdown
## after the first press.
func reset() -> void:
	ready_at_ms = 0
	asked_at_ms = -1


func asking(now_ms: int) -> bool:
	if asked_at_ms < 0:
		return false
	if now_ms - asked_at_ms > ANSWER_TIMEOUT_MS:
		asked_at_ms = -1
		return false
	return true


## Whole seconds until the button works again (0 when it works now).
func seconds_left(now_ms: int) -> int:
	return maxi(0, ceili(float(ready_at_ms - now_ms) / 1000.0))


func enabled(now_ms: int) -> bool:
	return not asking(now_ms) and seconds_left(now_ms) == 0


func label(now_ms: int) -> String:
	if asking(now_ms):
		return ASKING_LABEL
	var s := seconds_left(now_ms)
	return LABEL if s == 0 else "%s (%d s)" % [LABEL, s]


## Call when the press goes out. Returns false (and sends nothing) while the button is off.
func ask(now_ms: int) -> bool:
	if not enabled(now_ms):
		return false
	asked_at_ms = now_ms
	asks += 1
	return true


## The server's answer (s2c_unstuck_result). `wait_seconds` is the cooldown from now: 60 after
## a trip home, the time left on a refusal, 0 for "You're already in Spawn Meadow."
func answered(ok: bool, wait_seconds: float, now_ms: int) -> void:
	asked_at_ms = -1
	if ok:
		homes += 1
	if is_finite(wait_seconds) and wait_seconds > 0.0:
		ready_at_ms = now_ms + int(ceil(wait_seconds * 1000.0))
	else:
		ready_at_ms = now_ms

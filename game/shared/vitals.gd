class_name Vitals
## Health and stamina (roadmap Milestone 2, "First blood"): the rules only, as pure functions
## over a small Dictionary, so they are unit tested without a server. The server will keep
## one per player in its session (and creatures one each) once combat is wired; nothing
## calls this yet, and nothing here is saved or sent (no migration, no protocol change).
##
## Our take (design bible, "Take the best, then beat it"): stamina is the one bar every
## action move spends (dodge roll, heavy swing, block), the way the best action MMOs and
## soulslikes do it, minus what their players hate:
## - **Never locked out.** Running dry doesn't stun you and doesn't refuse the dodge: any
##   stamina left buys one last-gasp roll. You are only "winded" (no new spends) for a short,
##   fixed WINDED_SECONDS after hitting 0, then the bar is already coming back.
## - **No dead time.** Stamina waits only REGEN_DELAY after a spend, then refills fast
##   (empty to full in about 2.5 s). Out of combat it doesn't drain at all: sprinting around
##   the valley is free, so travel never becomes a stamina chore.
## - **Readable blocks.** A block takes most of a hit and pays for it in stamina; a block
##   that runs the bar dry still holds for that hit (no surprise guard break mid-swing) and
##   leaves you winded, which is the fair telegraph that the next one won't.
## - **Health comes back on its own** once you are out of combat, quickly, so after a fight
##   you are back to gathering in seconds, not sitting at a campfire.
##
## A state is {hp, max_hp, stamina, max_stamina, spent_at, hit_at, winded_until}. Times
## (`now`) are real seconds on the server's monotonic clock, like GatherChannel.

const MAX_HP := 100.0
const MAX_STAMINA := 100.0
## What each move costs. Light swings are cheap so a fight is mostly about the big moves.
const COSTS := {"light": 8.0, "heavy": 22.0, "dodge": 25.0, "sprint": 12.0} ## sprint: per second, in combat only
## Stamina back per second, after REGEN_DELAY seconds without a spend.
const REGEN := 40.0
const REGEN_DELAY := 0.6
## Hitting 0 stamina: no new spends for this long (the bar is already refilling).
const WINDED_SECONDS := 1.0
## A block takes this share of a hit's damage off, and costs BLOCK_COST stamina per point it took off.
const BLOCK_SHARE := 0.75
const BLOCK_COST := 0.8
## In combat for this long after the last hit taken or dealt; health regenerates only outside it.
const COMBAT_SECONDS := 6.0
## Health back per second out of combat, as a share of max (10%: full in 10 s).
const HP_REGEN_SHARE := 0.10


## A fresh, full state.
static func full(max_hp: float = MAX_HP, max_stamina: float = MAX_STAMINA) -> Dictionary:
	return {"hp": max_hp, "max_hp": max_hp, "stamina": max_stamina, "max_stamina": max_stamina,
		"spent_at": -INF, "hit_at": -INF, "winded_until": -INF}


static func is_cost(action: String) -> bool:
	return COSTS.has(action)


static func in_combat(v: Dictionary, now: float) -> bool:
	return now - float(v.hit_at) < COMBAT_SECONDS


static func is_winded(v: Dictionary, now: float) -> bool:
	return now < float(v.winded_until)


static func is_dead(v: Dictionary) -> bool:
	return float(v.hp) <= 0.0


## Why `action` can't be done now, or "" when it can: "dead", "winded", "tired" (not enough
## stamina for a light/heavy swing), "unknown". A dodge needs only some stamina left (the
## last-gasp roll); sprinting out of combat always can.
static func check(v: Dictionary, action: String, now: float) -> String:
	if not is_cost(action):
		return "unknown"
	if is_dead(v):
		return "dead"
	if action == "sprint" and not in_combat(v, now):
		return ""
	if is_winded(v, now):
		return "winded"
	var st := float(v.stamina)
	if action in ["dodge", "sprint"]:
		return "" if st > 0.0 else "tired"
	return "" if st >= float(COSTS[action]) else "tired"


## Spends stamina for `action` (sprint: for `seconds` of it). Returns {ok, reason, spent}.
## A refused spend changes nothing. Reaching 0 makes you winded.
static func spend(v: Dictionary, action: String, now: float, seconds: float = 1.0) -> Dictionary:
	var why := check(v, action, now)
	if why != "":
		return {"ok": false, "reason": why, "spent": 0.0}
	var cost := float(COSTS[action])
	if action == "sprint":
		if not in_combat(v, now):
			return {"ok": true, "reason": "", "spent": 0.0}
		cost *= maxf(seconds, 0.0)
	var spent := minf(cost, float(v.stamina))
	_drain(v, spent, now)
	return {"ok": true, "reason": "", "spent": spent}


## A hit of `amount` damage lands at `now`. Blocking takes BLOCK_SHARE off it for stamina;
## if the bar can't pay in full, the block still holds for this hit and you end winded.
## Returns {taken, blocked, dead}. Starts (or extends) combat either way.
static func hit(v: Dictionary, amount: float, now: float, blocking: bool = false) -> Dictionary:
	if is_dead(v) or amount <= 0.0:
		return {"taken": 0.0, "blocked": 0.0, "dead": is_dead(v)}
	v.hit_at = now
	var blocked := 0.0
	if blocking and float(v.stamina) > 0.0 and not is_winded(v, now):
		blocked = amount * BLOCK_SHARE
		_drain(v, minf(blocked * BLOCK_COST, float(v.stamina)), now)
	var taken := amount - blocked
	v.hp = maxf(float(v.hp) - taken, 0.0)
	return {"taken": taken, "blocked": blocked, "dead": is_dead(v)}


## You landed a hit: that's combat too (no health regen while you're trading blows).
static func dealt(v: Dictionary, now: float) -> void:
	v.hit_at = now


## Advances regen to `now` over `dt` seconds (call once per server tick). Stamina refills
## REGEN/s once REGEN_DELAY has passed since the last spend; health refills out of combat.
## The dead regain nothing (respawn uses full()).
static func tick(v: Dictionary, now: float, dt: float) -> void:
	if is_dead(v) or dt <= 0.0:
		return
	if now - float(v.spent_at) >= REGEN_DELAY:
		v.stamina = minf(float(v.stamina) + REGEN * dt, float(v.max_stamina))
	if not in_combat(v, now):
		v.hp = minf(float(v.hp) + float(v.max_hp) * HP_REGEN_SHARE * dt, float(v.max_hp))


## Health and stamina as 0..1, for a bar.
static func shares(v: Dictionary) -> Dictionary:
	return {"hp": float(v.hp) / maxf(float(v.max_hp), 1.0), "stamina": float(v.stamina) / maxf(float(v.max_stamina), 1.0)}


static func _drain(v: Dictionary, amount: float, now: float) -> void:
	v.stamina = maxf(float(v.stamina) - amount, 0.0)
	v.spent_at = now
	if float(v.stamina) <= 0.0:
		v.winded_until = now + WINDED_SECONDS

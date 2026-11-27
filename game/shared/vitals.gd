class_name Vitals
## Health and stamina (roadmap Milestone 2, "First blood"): the rules only, as pure functions
## over a small Dictionary, so they are unit tested without a server. The server will keep
## one per player in its session (and creatures one each). Since 2026-11-24 the server keeps
## one per logged-in player (Server.vitals_of): full on login, ticked every server tick, hurt
## by Server.hurt (only the hidden /hurt dev command until creatures fight), knocked down at
## 0 (KNOCKED_DOWN_TEXT). Not saved (a relog is full health); s2c_vitals goes out once at
## login and on every change (protocol v7), and attacks spend from it (Server.attack_request).
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
## - **Health is worth something** (owner direction, 2026-11-26: "a full zombie survival.
##   Bandages and other things like that"). Out of combat it only trickles back, and only to
##   half (HP_REGEN_CAP); above that, a bandage (BANDAGE_HEAL over BANDAGE_SECONDS) is what
##   patches you up. It was 10 s from empty to full, which made a medkit pointless.
##
## A state is {hp, max_hp, stamina, max_stamina, spent_at, hit_at, winded_until, heal_left}. Times
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
## Health back per second out of combat, as a share of max (0.5%: empty to half in 100 s),
## and only while under HP_REGEN_CAP of max: past that, it takes a bandage.
const HP_REGEN_SHARE := 0.005
const HP_REGEN_CAP := 0.5
## A bandage (Inventory "bandage", applied with Server.use_item) heals this much over
## BANDAGE_SECONDS, in combat or out, up to full. One at a time.
const BANDAGE_HEAL := 35.0
const BANDAGE_SECONDS := 4.0
const BANDAGE_ITEM := "bandage"
## What a player is told about a bandage (use_check's reasons, and success).
const BANDAGE_TEXTS := {
	"": "You bind your wounds with a bandage.",
	"full": "You're not hurt.",
	"busy": "Your last bandage is still doing its work.",
	"dead": "",
	"no_item": "You have no bandage. Twist one from 3 plant fibre (scrub).",
}
## Fair failure (roadmap Milestone 2): at 0 health you are knocked down and come to at once
## in Spawn Meadow, full, with everything you carried. No corpse run,
## no lost pack, no timer: losing costs the walk back, which is the lesson, not a punishment.
const KNOCKED_DOWN_TEXT := "You were knocked down. You come to in Spawn Meadow with everything you carried."


## A fresh, full state.
static func full(max_hp: float = MAX_HP, max_stamina: float = MAX_STAMINA) -> Dictionary:
	return {"hp": max_hp, "max_hp": max_hp, "stamina": max_stamina, "max_stamina": max_stamina,
		"spent_at": -INF, "hit_at": -INF, "winded_until": -INF, "heal_left": 0.0}


static func is_cost(action: String) -> bool:
	return COSTS.has(action)


static func in_combat(v: Dictionary, now: float) -> bool:
	return now - float(v.hit_at) < COMBAT_SECONDS


## Seconds until `v` is out of combat (0 when it already is).
static func combat_left(v: Dictionary, now: float) -> float:
	return maxf(COMBAT_SECONDS - (now - float(v.hit_at)), 0.0)


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


## Like spend, but the move costs `cost` instead of the flat COSTS[action] (a weapon's
## Weapons.stamina_cost: a maul swing costs more than a jab). "tired" when a light or heavy
## swing can't pay `cost` in full; a dodge still only needs some stamina left. Returns
## {ok, reason, spent}; a refused spend changes nothing.
static func spend_cost(v: Dictionary, action: String, cost: float, now: float) -> Dictionary:
	var why := check(v, action, now)
	if why == "tired" and action in ["light", "heavy"] and float(v.stamina) >= cost:
		why = "" # a light weapon's swing can be cheaper than the flat cost
	if why == "" and action in ["light", "heavy"] and float(v.stamina) < cost:
		why = "tired"
	if why != "":
		return {"ok": false, "reason": why, "spent": 0.0}
	var spent := minf(maxf(cost, 0.0), float(v.stamina))
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
## The dead regain nothing (respawn uses full()). `regen` scales stamina coming back and
## `heal` allows the out-of-combat trickle: hunger slows one and stops the other (Needs).
static func tick(v: Dictionary, now: float, dt: float, regen: float = 1.0, heal: bool = true) -> void:
	if is_dead(v) or dt <= 0.0:
		return
	if now - float(v.spent_at) >= REGEN_DELAY:
		v.stamina = minf(float(v.stamina) + REGEN * maxf(regen, 0.0) * dt, float(v.max_stamina))
	var cap := float(v.max_hp) * HP_REGEN_CAP
	if heal and not in_combat(v, now) and float(v.hp) < cap:
		v.hp = minf(float(v.hp) + float(v.max_hp) * HP_REGEN_SHARE * dt, cap)
	var left := float(v.get("heal_left", 0.0))
	if left > 0.0:
		var h := minf(left, BANDAGE_HEAL / BANDAGE_SECONDS * dt)
		v.hp = minf(float(v.hp) + h, float(v.max_hp))
		v.heal_left = 0.0 if float(v.hp) >= float(v.max_hp) else left - h


## Why a bandage can't go on now, or "" when it can: "dead", "full" (not hurt), "busy" (the
## last one is still healing).
static func bandage_check(v: Dictionary) -> String:
	if is_dead(v):
		return "dead"
	if float(v.hp) >= float(v.max_hp):
		return "full"
	if float(v.get("heal_left", 0.0)) > 0.0:
		return "busy"
	return ""


## Puts a bandage on: BANDAGE_HEAL is healed over the next BANDAGE_SECONDS (tick). Returns
## bandage_check's reason; "" means it went on.
static func apply_bandage(v: Dictionary) -> String:
	var why := bandage_check(v)
	if why == "":
		v.heal_left = BANDAGE_HEAL
	return why


static func bandage_text(reason: String) -> String:
	return str(BANDAGE_TEXTS.get(reason, ""))


## Health and stamina as 0..1, for a bar.
static func shares(v: Dictionary) -> Dictionary:
	return {"hp": float(v.hp) / maxf(float(v.max_hp), 1.0), "stamina": float(v.stamina) / maxf(float(v.max_stamina), 1.0)}


static func _drain(v: Dictionary, amount: float, now: float) -> void:
	v.stamina = maxf(float(v.stamina) - amount, 0.0)
	v.spent_at = now
	if float(v.stamina) <= 0.0:
		v.winded_until = now + WINDED_SECONDS


## Whole points [hp, stamina], what a health bar can show. The server sends s2c_vitals only
## when this changes, so a full, idle player costs nothing on the wire.
static func shown(v: Dictionary) -> Array:
	return [roundi(float(v.hp)), roundi(float(v.stamina))]


## "Health 70/100, stamina 100/100, in combat." for the hidden /vitals dev command.
static func describe(v: Dictionary, now: float) -> String:
	var where := "in combat" if in_combat(v, now) else "out of combat"
	return "Health %d/%d, stamina %d/%d, %s." % [roundi(float(v.hp)), roundi(float(v.max_hp)),
		roundi(float(v.stamina)), roundi(float(v.max_stamina)), where]

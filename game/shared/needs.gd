class_name Needs
## Hunger, the first of the survival needs (owner, 2026-11-27: "study project zomboid and put
## that system into our game"; the survival plan, roadmap Phase 2). Thirst, warmth and rest
## join it later in the same shape. The rules only, as pure functions over the character
## Dictionary (where hunger is saved) and the session's Vitals, so they are unit tested
## without a server. Every number lives here.
##
## Our take (design bible, "Take the best, then beat it"): a need you can feel and fix, never
## a slow chore.
## - **Three tiers, felt not read.** Fine, low and bad (TIERS). Fine does nothing. Low slows
##   stamina coming back. Bad slows it more and wears health down, but only to HP_FLOOR:
##   hunger alone never knocks you down, it leaves you one bad fight from it.
## - **Quick to fix.** One cooked meat is a big step back up (FOODS); it lands at once.
## - **A meal about every half hour of play.** Full to low takes about 30 real minutes, full to
##   empty about an hour (DRAIN), and it only drains while you are logged in.
## - **Cooking pays.** Raw meat feeds a little and turns your stomach (RAW_HURT); cooked at a lit
##   campfire (Campfires.WARM_RADIUS) it feeds far more.
##
## Hunger is 0 (starving) to MAX (full), saved as `hunger` on the character (CharacterData,
## migration 0006). Old saves load full.
##
## **Thirst** (step 3 of the survival plan) works the same way and on the same tiers, only
## faster (THIRST_DRAIN: full to empty in 45 minutes): it is the need that pulls you to the
## lakes and rivers. Drink at fresh water (at_fresh_water) to fill up at once, and carry water
## in a waterskin (DRINKS). The two never stack into a double penalty: stamina comes back at
## the worse need's pace, and starving and parched together wear health at the same rate.
## Saved as `thirst` (migration 0008). Old saves load full.

const MAX := 100.0
## Points lost per real second while logged in: full to empty in an hour.
const DRAIN := MAX / 3600.0
## Tiers by hunger: at or above LOW_AT is fine, at or above BAD_AT is low, under it is bad.
const LOW_AT := 50.0
const BAD_AT := 20.0
const TIERS := ["fine", "low", "bad"]
## How fast stamina comes back in each tier (Vitals.tick's REGEN times this).
const STAMINA_REGEN := {"fine": 1.0, "low": 0.75, "bad": 0.5}
## Bad: health lost per second, never below HP_FLOOR (and no natural healing).
const HP_DRAIN := 0.2
const HP_FLOOR := 15.0
## Knocked down: you come to with at least this much hunger, so you never wake up starving.
const AFTER_KNOCKDOWN := 50.0
## Refused when you are this full already (nothing would be wasted under it).
const FULL_AT := 95.0

## Thirst points lost per real second while logged in: full to empty in 45 minutes, so low
## after about 22 (a drink about twice per meal).
const THIRST_DRAIN := MAX / 2700.0
## What a drink gives: fresh water fills you up; a full waterskin gives a big swallow and
## comes back empty (`leaves`). Waterskins fill at fresh water (FILLS).
const DRINKS := {
	"full_waterskin": {"thirst": 45.0, "leaves": "waterskin"},
}
const FILLS := {"waterskin": "full_waterskin"}
## Fresh water: within this many metres of a lake's edge or a river's line. The sea is salt.
const LAKE_REACH := 3.0
const RIVER_REACH := 5.0

## What each food gives, and what you eat first when you press the eat key (best first).
## Ids are Inventory ids. `hurt`: health lost (raw meat turns your stomach).
const FOODS := {
	"cooked_meat": {"hunger": 40.0, "hurt": 0.0},
	"berries": {"hunger": 10.0, "hurt": 0.0},
	"raw_meat": {"hunger": 15.0, "hurt": 8.0},
}
const EAT_ORDER := ["cooked_meat", "berries", "raw_meat"]

## What a cook at a fire turns into what (all of it at once).
const COOKS := {"raw_meat": "cooked_meat"}

## The lines a player reads. Tier changes (`low`, `bad`, `fine`) go out once, when they happen.
const TEXTS := {
	"low": "You're getting hungry. Press F to eat.",
	"bad": "You're starving. You tire fast and feel yourself weakening. Eat something.",
	"fine": "",
	"ate": "You eat %s.",
	"ate_raw": "You eat raw meat. It fills you a little, and your stomach turns.",
	"full": "You're not hungry.",
	"no_food": "You have nothing to eat. Cook meat at a campfire, or pick berries from scrub.",
	"dead": "",
	"cooked": "You cook %d meat over the fire.",
	"thirst_low": "You're thirsty. Drink at a lake or a river, or from a waterskin (F).",
	"thirst_bad": "You're parched. You tire fast and feel yourself weakening. Find water.",
	"drank_fresh": "You drink your fill of fresh water.",
	"drank_fresh_filled": "You drink your fill and fill %d waterskin(s).",
	"filled": "You fill %d waterskin(s).",
	"drank_skin": "You drink from your waterskin.",
	"not_thirsty": "You're not thirsty.",
	"no_water": "You have nothing to drink. Find a lake or a river, or carry a waterskin.",
	"no_fire": "You need to stand at a lit campfire to cook.",
	"no_raw": "You have nothing to cook. Hunt a grazer for meat.",
}


## The character's hunger, 0..MAX (a missing or broken value reads as full).
static func hunger_of(ch: Dictionary) -> float:
	var h: Variant = ch.get("hunger", MAX)
	var f := float(h) if typeof(h) in [TYPE_INT, TYPE_FLOAT] else MAX
	return clampf(f, 0.0, MAX) if is_finite(f) else MAX


static func tier(hunger: float) -> String:
	if hunger >= LOW_AT:
		return "fine"
	if hunger >= BAD_AT:
		return "low"
	return "bad"


static func tier_of(ch: Dictionary) -> String:
	return tier(hunger_of(ch))


## Stamina comes back at the worse need's pace (they never multiply).
static func stamina_regen(ch: Dictionary) -> float:
	return minf(float(STAMINA_REGEN[tier_of(ch)]), float(STAMINA_REGEN[thirst_tier_of(ch)]))


## Whether natural healing (Vitals' out-of-combat trickle) is allowed: not while starving or
## parched.
static func can_heal(ch: Dictionary) -> bool:
	return tier_of(ch) != "bad" and thirst_tier_of(ch) != "bad"


## Advances hunger by `dt` real seconds on `ch` and, when starving, wears `v` (Vitals) down
## toward HP_FLOOR. Returns the tier now. The dead (knocked down) lose nothing.
static func tick(ch: Dictionary, v: Dictionary, dt: float) -> String:
	if dt <= 0.0:
		return tier_of(ch)
	ch.hunger = maxf(hunger_of(ch) - DRAIN * dt, 0.0)
	ch.thirst = maxf(thirst_of(ch) - THIRST_DRAIN * dt, 0.0)
	var t := tier_of(ch)
	if (t == "bad" or thirst_tier_of(ch) == "bad") and not v.is_empty() and not Vitals.is_dead(v):
		var hp := float(v.hp)
		if hp > HP_FLOOR:
			v.hp = maxf(hp - HP_DRAIN * dt, HP_FLOOR)
	return t


## Sets hunger (clamped). For tests, the dev command and knockdowns.
static func set_hunger(ch: Dictionary, value: float) -> void:
	ch.hunger = clampf(value, 0.0, MAX) if is_finite(value) else MAX


## After a knockdown: never wake up starving or parched.
static func after_knockdown(ch: Dictionary) -> void:
	set_hunger(ch, maxf(hunger_of(ch), AFTER_KNOCKDOWN))
	set_thirst(ch, maxf(thirst_of(ch), AFTER_KNOCKDOWN))


## --- Thirst ---

## The character's thirst, 0 (parched) .. MAX (quenched); missing or broken reads as full.
static func thirst_of(ch: Dictionary) -> float:
	var h: Variant = ch.get("thirst", MAX)
	var f := float(h) if typeof(h) in [TYPE_INT, TYPE_FLOAT] else MAX
	return clampf(f, 0.0, MAX) if is_finite(f) else MAX


static func thirst_tier_of(ch: Dictionary) -> String:
	return tier(thirst_of(ch))


static func set_thirst(ch: Dictionary, value: float) -> void:
	ch.thirst = clampf(value, 0.0, MAX) if is_finite(value) else MAX


static func is_drink(item: String) -> bool:
	return DRINKS.has(item)


## Whether `pos` is at fresh water: near a lake's edge or a river's line (WorldGen). The sea
## and Ashgrove have none.
static func at_fresh_water(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	for l in WorldGen.lakes():
		var c: Vector2 = l.center
		if p.distance_to(c) <= float(l.radius) + LAKE_REACH:
			return true
	for line in WorldGen.rivers():
		var pts: PackedVector2Array = line
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) <= RIVER_REACH:
				return true
	return false


## What a drink would do from where you stand: "fresh" (at water: drink and fill skins),
## "skin" (drink a full waterskin), or why not: "dead", "not_thirsty", "no_water".
static func drink_check(ch: Dictionary, v: Dictionary, at_water: bool) -> String:
	if not v.is_empty() and Vitals.is_dead(v):
		return "dead"
	var inv: Dictionary = ch.get("inventory", {})
	if at_water:
		if thirst_of(ch) >= FULL_AT and Inventory.count(inv, "waterskin") <= 0:
			return "not_thirsty"
		return "fresh"
	if Inventory.count(inv, "full_waterskin") <= 0:
		return "no_water"
	if thirst_of(ch) >= FULL_AT:
		return "not_thirsty"
	return "skin"


## Drinks one `item` from DRINKS (the caller swaps the skin): thirst goes up. Returns thirst.
static func drink(ch: Dictionary, item: String) -> float:
	var d: Dictionary = DRINKS.get(item, {"thirst": 0.0})
	set_thirst(ch, thirst_of(ch) + float(d.thirst))
	return thirst_of(ch)


## Thirst as a whole number 0..100, as sent.
static func shown_thirst(ch: Dictionary) -> int:
	return roundi(thirst_of(ch) / MAX * 100.0)


## "Thirst 72/100 (fine)." for the hidden /vitals dev command.
static func describe_thirst(ch: Dictionary) -> String:
	return "Thirst %d/100 (%s)." % [shown_thirst(ch), thirst_tier_of(ch)]


static func is_food(item: String) -> bool:
	return FOODS.has(item)


## The food the eat key would eat from `inv`, best first, or "" for none.
static func best_food(inv: Dictionary) -> String:
	for item in EAT_ORDER:
		if Inventory.count(inv, item) > 0:
			return item
	return ""


## Why `item` (or the best food, for "") can't be eaten now, or "" when it can:
## "no_food", "full", "dead".
static func eat_check(ch: Dictionary, v: Dictionary, item: String = "") -> String:
	if not v.is_empty() and Vitals.is_dead(v):
		return "dead"
	var food := item if item != "" else best_food(ch.get("inventory", {}))
	if food == "" or not is_food(food) or Inventory.count(ch.get("inventory", {}), food) <= 0:
		return "no_food"
	if hunger_of(ch) >= FULL_AT:
		return "full"
	return ""


## Eats one `food` (the caller has already taken it from the pack): hunger goes up, raw meat
## hurts a little (never to 0). Returns {hunger, hurt}.
static func eat(ch: Dictionary, v: Dictionary, food: String) -> Dictionary:
	var f: Dictionary = FOODS.get(food, {"hunger": 0.0, "hurt": 0.0})
	set_hunger(ch, hunger_of(ch) + float(f.hunger))
	var hurt := 0.0
	if float(f.hurt) > 0.0 and not v.is_empty():
		var hp := float(v.hp)
		hurt = minf(float(f.hurt), maxf(hp - 1.0, 0.0))
		v.hp = hp - hurt
	return {"hunger": hunger_of(ch), "hurt": hurt}


## The player line for eating `food`.
static func ate_text(food: String) -> String:
	if food == "raw_meat":
		return str(TEXTS.ate_raw)
	return str(TEXTS.ate) % Inventory.label(food)


static func text(reason: String) -> String:
	return str(TEXTS.get(reason, ""))


## Hunger as a whole number 0..100, what the client is sent (s2c_needs). The server sends only
## when this changes.
static func shown(ch: Dictionary) -> int:
	return roundi(hunger_of(ch) / MAX * 100.0)


## What goes over the wire in s2c_needs: {"hunger": 0..100}. Thirst, warmth and rest join this
## Dictionary later without a protocol bump.
static func to_wire(ch: Dictionary) -> Dictionary:
	return {"hunger": shown(ch), "thirst": shown_thirst(ch)}


## "Hunger 72/100 (fine)." for the hidden /vitals dev command.
static func describe(ch: Dictionary) -> String:
	return "Hunger %d/100 (%s)." % [shown(ch), tier_of(ch)]

class_name Weapons
## The first crafted weapons (roadmap Milestone 2, "First blood"): the rules only, as data and
## pure functions, so they are unit tested without a server. Since protocol v7 the server
## swings with it (Server.attack_request: c2s_attack, stamina, the windup, targets_hit against
## the grazers, which bolt when struck). There is no recipe or item yet, so everyone fights
## bare-handed (Server.weapon_of) until the spear and maul can be made.
##
## Two weapons that play differently (design bible, "Weapons you made"), plus bare hands:
## - **Ash spear**: long reach and quick, cheap thrusts in a narrow line. It hits only the
##   first thing in front of it, so aim matters, and you fight from outside a creature's reach.
## - **Stone maul**: short and slow, but a wide sweep that hits up to three things at once,
##   and its heavy swing staggers. You commit to every swing and win by reading the moment.
## - **Bare hands**: what you fight with before you make either. Weak on purpose: the first
##   weapon you craft should feel like a real step up.
##
## Our take on what players love and hate (owner direction 6, see docs/devlog/gameplay.md,
## 2026-11-24): weapons with their own identity and no single "best" one (damage per stamina
## of the two weapons stays within BALANCE_BAND of each other, checked in tests); a heavy swing
## that is a real commitment but never a long lock (windup at most MAX_WINDUP); and you can
## always bail out of a windup with a dodge (`can_cancel`), so a misread never stuns you.
##
## Facing follows the rest of the game: `yaw`'s forward is Vector3(sin(yaw), 0, cos(yaw))
## (see Wildlife). Distances are flat (x, z), like VIEW_RANGE and gathering.

const FISTS := "fists"
## Display and crafting order.
const ORDER := ["ash_spear", "stone_maul"]
const ATTACKS := ["light", "heavy"]

## Per weapon: label, reach (m, from the attacker's centre to the target's edge), arc (degrees,
## the full width of the swing), max_targets per swing, the mastery skill that will level by
## use (not in Skills.ORDER yet), and per attack: damage, windup (the telegraph, cancellable
## by a dodge), active (when it hits), recovery (after the hit), stamina (a scale on
## Vitals.COSTS[attack]), lunge (m added to reach on that attack) and stagger.
const WEAPONS := {
	"fists": {
		"label": "Bare hands", "reach": 1.4, "arc": 70.0, "max_targets": 1, "mastery": "",
		"light": {"damage": 4.0, "windup": 0.12, "active": 0.10, "recovery": 0.22, "stamina": 0.6, "lunge": 0.0, "stagger": false},
		"heavy": {"damage": 9.0, "windup": 0.40, "active": 0.12, "recovery": 0.40, "stamina": 0.8, "lunge": 0.0, "stagger": false},
	},
	"ash_spear": {
		"label": "Ash spear", "reach": 3.0, "arc": 30.0, "max_targets": 1, "mastery": "spearwork",
		"light": {"damage": 9.0, "windup": 0.18, "active": 0.10, "recovery": 0.30, "stamina": 0.75, "lunge": 0.0, "stagger": false},
		"heavy": {"damage": 21.0, "windup": 0.50, "active": 0.14, "recovery": 0.50, "stamina": 0.9, "lunge": 1.5, "stagger": false},
	},
	"stone_maul": {
		"label": "Stone maul", "reach": 2.1, "arc": 110.0, "max_targets": 3, "mastery": "maulwork",
		"light": {"damage": 13.0, "windup": 0.32, "active": 0.14, "recovery": 0.46, "stamina": 1.25, "lunge": 0.0, "stagger": false},
		"heavy": {"damage": 34.0, "windup": 0.85, "active": 0.18, "recovery": 0.70, "stamina": 1.4, "lunge": 0.0, "stagger": true},
	},
}

## No windup is longer than this: a heavy swing is a commitment, never a long lock.
const MAX_WINDUP := 0.9
## Damage per point of stamina of every crafted weapon's attack stays within this ratio of
## the others' (no strictly best weapon).
const BALANCE_BAND := 1.35
## Each mastery level above 1 adds this share of damage (level 10: +9%). Small and visible,
## like gathering's per-level speed gain; the named unlocks come with the mastery skills.
const MASTERY_DAMAGE_PER_LEVEL := 0.01


static func exists(id: String) -> bool:
	return WEAPONS.has(id)


## The weapon's data; an unknown id fights bare-handed.
static func data(id: String) -> Dictionary:
	return WEAPONS.get(id, WEAPONS[FISTS])


static func label(id: String) -> String:
	return str(data(id).label)


static func is_attack(kind: String) -> bool:
	return kind in ATTACKS


## One attack's numbers ({} for an unknown attack kind).
static func attack(id: String, kind: String) -> Dictionary:
	return data(id).get(kind, {}) if is_attack(kind) else {}


## Damage of one hit, with the mastery bonus (level 1 = base).
static func damage(id: String, kind: String, mastery_level: int = 1) -> float:
	var a := attack(id, kind)
	if a.is_empty():
		return 0.0
	return float(a.damage) * (1.0 + MASTERY_DAMAGE_PER_LEVEL * float(maxi(mastery_level, 1) - 1))


## Stamina this attack costs: Vitals' cost for the move, scaled by the weapon's weight.
static func stamina_cost(id: String, kind: String) -> float:
	var a := attack(id, kind)
	if a.is_empty():
		return 0.0
	return float(Vitals.COSTS[kind]) * float(a.stamina)


## Seconds from pressing the attack to being free to act again.
static func swing_seconds(id: String, kind: String) -> float:
	var a := attack(id, kind)
	if a.is_empty():
		return 0.0
	return float(a.windup) + float(a.active) + float(a.recovery)


## Seconds after the press when the hit lands (the end of the windup).
static func hit_at(id: String, kind: String) -> float:
	var a := attack(id, kind)
	return float(a.windup) if not a.is_empty() else 0.0


## True while a dodge may still cancel the swing: during the windup, before it lands.
static func can_cancel(id: String, kind: String, since_press: float) -> bool:
	var a := attack(id, kind)
	return not a.is_empty() and since_press >= 0.0 and since_press < float(a.windup)


## How far this attack reaches (m): the weapon's reach plus the attack's lunge.
static func reach(id: String, kind: String) -> float:
	var a := attack(id, kind)
	if a.is_empty():
		return 0.0
	return float(data(id).reach) + float(a.lunge)


## True if a target at `target_pos` with radius `target_radius` is inside this attack's
## reach and arc, swung from `from` facing `yaw`. A target standing inside the attacker
## (closer than 0.3 m) is always in the arc.
static func in_swing(from: Vector3, yaw: float, target_pos: Vector3, target_radius: float, id: String, kind: String) -> bool:
	if attack(id, kind).is_empty():
		return false
	var d := Vector2(target_pos.x - from.x, target_pos.z - from.z)
	var dist := d.length()
	if dist - maxf(target_radius, 0.0) > reach(id, kind):
		return false
	if dist < 0.3:
		return true
	var forward := Vector2(sin(yaw), cos(yaw))
	var half := deg_to_rad(float(data(id).arc) * 0.5)
	# A wide target's edge can be in the arc even when its centre is just outside.
	var widen := atan2(maxf(target_radius, 0.0), dist)
	return absf(forward.angle_to(d)) <= half + widen


## Which targets one swing hits: `targets` is an Array of {id, pos: Vector3, radius}. Returns
## their ids, nearest first, at most the weapon's max_targets (the spear stops at the first).
static func targets_hit(from: Vector3, yaw: float, id: String, kind: String, targets: Array) -> Array:
	var inside := []
	for t in targets:
		var pos: Vector3 = t.pos
		if in_swing(from, yaw, pos, float(t.get("radius", 0.0)), id, kind):
			inside.append([Vector2(pos.x - from.x, pos.z - from.z).length(), t.id])
	inside.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
	var hit := []
	for e in inside:
		if hit.size() >= int(data(id).max_targets):
			break
		hit.append(e[1])
	return hit


## What a player is told when a swing is refused (Server.attack_request's reasons). "busy"
## (pressed again mid-swing) says nothing: the swing you are in is the answer.
const REFUSALS := {
	"winded": "You're winded. Catch your breath.",
	"tired": "Not enough stamina for that swing.",
	"dead": "",
	"busy": "",
	"gathering": "",
	"unknown": "",
}


static func refusal_text(reason: String) -> String:
	return str(REFUSALS.get(reason, ""))


## Damage per point of stamina for one attack (a balance measure, see BALANCE_BAND).
static func damage_per_stamina(id: String, kind: String) -> float:
	var cost := stamina_cost(id, kind)
	return damage(id, kind) / cost if cost > 0.0 else 0.0


## Damage per second of swinging this attack back to back (a balance measure).
static func damage_per_second(id: String, kind: String) -> float:
	var t := swing_seconds(id, kind)
	return damage(id, kind) / t if t > 0.0 else 0.0


## A one-line summary for players or logs: "Ash spear: reach 3.0 m, hits 1, light 9 / heavy 21".
static func describe(id: String) -> String:
	var w := data(id)
	return "%s: reach %.1f m, hits %d, light %d / heavy %d" % [w.label, float(w.reach), int(w.max_targets), int(damage(id, "light")), int(damage(id, "heavy"))]

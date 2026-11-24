class_name Gloam
## The Gloam walker, server side (Phase 2 build-ahead, `docs/vision.md` "The Gloam"): the
## kingdom's dead, emptied by the Dimming. The rules only, as pure functions over plain data
## like Wildlife and Vitals, so they are unit tested without a server. The server owns one
## state from new_state() and calls step() every tick with the players and the fires.
##
## What a walker does (our own undead, inspired by the genre, never copied):
## - **Shambles by day, quicker at night.** DAY_SPEED is a third of a walking player's, so by
##   day you can always walk away; NIGHT_SPEED is still slower than you walk, so a night caught
##   out is dangerous only when they gather.
## - **Drawn by noise.** Every swing and every finished gather is a noise; a walker within
##   NOISE_RADIUS that isn't already hunting shambles to where it came from. It sees a player
##   only up close (SIGHT_DAY / SIGHT_NIGHT), then hunts them until they are LOSE_RADIUS away.
## - **A grab you can read.** In reach it raises its arms for GRAB_WINDUP (the telegraph), then
##   grabs whoever is still within GRAB_REACH for GRAB_DAMAGE through Vitals. Step back during
##   the windup and it closes on air. A heavy blow during the windup staggers it and breaks
##   the grab: hitting first is the answer, not a stat check.
## - **Goes down to a few blows**: KINDS.walker.hp is more than a grazer's (12), three spear
##   haymakers or about five bare-handed swings.
## - **Ember keeps them wary.** A walker never comes within FIRE_KEEPAWAY of a lit fire (the
##   server passes campfires and torches once players can place them; none yet).
## - **Only where someone is.** Walkers rise only near online players, outside the Spawn
##   Meadow's SAFE_RADIUS, a few per player (more at night, more for a crowd), and crumble
##   once nobody is near (`docs/vision.md`: nothing attacks what nobody is there to defend).
##
## Off by default: the server spawns walkers only with `--gloam` / AIMMO_GLOAM (the live world
## is untouched until client and world can draw them), and the hidden /gloam dev command
## raises one walker bound to its caller for the bot test. Not saved: a restart clears them.
##
## Facing like Wildlife: yaw's forward is Vector3(sin(yaw), 0, cos(yaw)). Distances are flat.

## Per kind: label, hp, body radius (Weapons.targets_hit), grab damage.
const KINDS := {"walker": {"label": "Gloam walker", "hp": 30.0, "radius": 0.45, "grab_damage": 15.0}}

## Movement, m/s. GameConfig.WALK_SPEED is 6.
const DAY_SPEED := 1.8
const NIGHT_SPEED := 3.4
const WANDER_SPEED := 0.8 ## idle shuffle around where it rose
const WANDER_RADIUS := 8.0

## Senses, metres.
const NOISE_RADIUS := 25.0
const SIGHT_DAY := 9.0
const SIGHT_NIGHT := 14.0
const LOSE_RADIUS := 22.0 ## a hunted player this far off is lost; it goes to where it last saw them

## The grab, metres and seconds.
const GRAB_START := 1.5 ## starts the windup this close (centre to centre)
const GRAB_REACH := 2.0 ## at the end of the windup, a player still this close is grabbed
const GRAB_WINDUP := 0.9 ## arms up: the telegraph (Weapons.MAX_WINDUP for players is 0.9 too)
const GRAB_RECOVER := 1.2 ## after a grab, hit or miss
const STAGGER_SECONDS := 0.7 ## a heavy blow staggers it (and breaks a grab in its windup)

## Fire, metres: a walker turns away from a lit fire this close.
const FIRE_KEEPAWAY := 6.0

## Rising and crumbling.
const SAFE_RADIUS := 40.0 ## never rises this close to the world's spawn (the meadow's starter ring ends at 34 m)
const RISE_MIN := 26.0 ## rises at least this far from every player (out of sight, never under your feet)
const RISE_MAX := 40.0
const PER_PLAYER_DAY := 1
const PER_PLAYER_NIGHT := 3
const CROWD_RADIUS := 40.0 ## players this close together share a cap that grows with the crowd
const CROWD_BONUS := 1 ## each extra player in a crowd adds this many on top of PER_PLAYER
const MAX_WALKERS := 24 ## the whole world's cap (8 players at night)
const RISE_EVERY_DAY := 45.0 ## seconds between rise attempts per player
const RISE_EVERY_NIGHT := 12.0
const CRUMBLE_RADIUS := 70.0 ## a walker with no player this close for CRUMBLE_SECONDS is gone
const CRUMBLE_SECONDS := 20.0
const SUMMON_DISTANCE := 7.0 ## /gloam raises a walker this far in front of you

const STATES := ["wander", "drawn", "hunt", "grab", "recover", "stagger", "wary"]


## A fresh, empty Gloam: {walkers: Array, next_id, rng, rise_at: {player_key: seconds},
## downs}. Each walker is {id, kind, pos, yaw, home, hp, state, until, target, prey, bound,
## lonely_since, grab_at, grabs, struck}.
static func new_state(seed_extra: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(WorldGen.config().seed) + 409 + seed_extra
	return {"walkers": [], "next_id": 0, "rng": rng, "rise_at": {}, "downs": 0}


static func max_hp(kind: String) -> float:
	return float(KINDS.get(kind, KINDS.walker).hp)


static func radius(kind: String) -> float:
	return float(KINDS.get(kind, KINDS.walker).radius)


static func grab_damage(kind: String) -> float:
	return float(KINDS.get(kind, KINDS.walker).grab_damage)


static func speed(night: bool) -> float:
	return NIGHT_SPEED if night else DAY_SPEED


static func sight(night: bool) -> float:
	return SIGHT_NIGHT if night else SIGHT_DAY


static func count(state: Dictionary) -> int:
	return state.walkers.size()


static func get_by_id(state: Dictionary, id: int) -> Dictionary:
	for w in state.walkers:
		if int(w.id) == id:
			return w
	return {}


## Raises a walker at `pos` (ground height from Terrain). `bound` >= 0 ties it to one
## player (the /gloam dev command): it only ever hunts them. Returns the new walker.
static func rise(state: Dictionary, pos: Vector3, now: float, bound: int = -1, kind: String = "walker") -> Dictionary:
	var p := Vector3(pos.x, Terrain.height(pos.x, pos.z), pos.z)
	var w := {
		"id": int(state.next_id), "kind": kind, "pos": p, "yaw": 0.0, "home": p,
		"hp": max_hp(kind), "state": "wander", "until": now, "target": p, "prey": -1,
		"bound": bound, "lonely_since": -1.0, "grab_at": 0.0, "grabs": 0, "struck": 0,
	}
	state.next_id = int(state.next_id) + 1
	state.walkers.append(w)
	return w


## A noise at `pos` (a swing landing, a gather finishing): every walker within `radius` that
## isn't hunting or mid-grab shambles towards it. Returns the ids it drew.
static func noise(state: Dictionary, pos: Vector3, now: float, radius: float = NOISE_RADIUS) -> Array:
	var drawn: Array = []
	for w in state.walkers:
		if str(w.state) in ["hunt", "grab", "recover", "stagger"]:
			continue
		if _flat(w.pos).distance_to(_flat(pos)) <= radius:
			w.state = "drawn"
			w.target = pos
			w.until = now
			drawn.append(int(w.id))
	return drawn


## One tick. `players` is an Array of {id: int, pos: Vector3}; `fires` an Array of Vector3
## (lit campfires and torches). Returns {grabs: [{walker, player, damage}], missed: [walker
## ids whose grab closed on air], crumbled: [ids]}.
static func step(state: Dictionary, players: Array, fires: Array, now: float, dt: float, night: bool) -> Dictionary:
	var out := {"grabs": [], "missed": [], "crumbled": []}
	var keep: Array = []
	for w in state.walkers:
		if _crumbles(w, players, now):
			out.crumbled.append(int(w.id))
			continue
		keep.append(w)
		_think(w, players, now, night, out)
		_move(w, fires, dt, night)
	state.walkers = keep
	return out


## Whether walker `w` has had nobody within CRUMBLE_RADIUS for CRUMBLE_SECONDS (a bound
## walker whose player left goes at once).
static func _crumbles(w: Dictionary, players: Array, now: float) -> bool:
	if int(w.bound) >= 0:
		return _player(players, int(w.bound)).is_empty()
	var near := false
	for p in players:
		if _flat(w.pos).distance_to(_flat(p.pos)) <= CRUMBLE_RADIUS:
			near = true
			break
	if near:
		w.lonely_since = -1.0
		return false
	if float(w.lonely_since) < 0.0:
		w.lonely_since = now
	return now - float(w.lonely_since) >= CRUMBLE_SECONDS


static func _player(players: Array, id: int) -> Dictionary:
	for p in players:
		if int(p.id) == id:
			return p
	return {}


## Who walker `w` may hunt: everyone, or only its bound player.
static func _candidates(w: Dictionary, players: Array) -> Array:
	if int(w.bound) < 0:
		return players
	var p := _player(players, int(w.bound))
	return [] if p.is_empty() else [p]


static func _think(w: Dictionary, players: Array, now: float, night: bool, out: Dictionary) -> void:
	var cands := _candidates(w, players)
	match str(w.state):
		"stagger", "recover":
			if now < float(w.until):
				return
			w.state = "hunt" if int(w.prey) >= 0 else "wander"
		"grab":
			var prey := _player(cands, int(w.prey))
			if now < float(w.grab_at):
				if not prey.is_empty():
					w.yaw = _yaw_to(w.pos, prey.pos)
				return
			w.state = "recover"
			w.until = now + GRAB_RECOVER
			if not prey.is_empty() and _flat(w.pos).distance_to(_flat(prey.pos)) <= GRAB_REACH:
				w.grabs = int(w.grabs) + 1
				out.grabs.append({"walker": int(w.id), "player": int(prey.id), "damage": grab_damage(str(w.kind))})
			else:
				out.missed.append(int(w.id))
			return
	# Hunting: keep after the prey until it is out of reach of the senses.
	if str(w.state) == "hunt":
		var prey := _player(cands, int(w.prey))
		if prey.is_empty() or _flat(w.pos).distance_to(_flat(prey.pos)) > LOSE_RADIUS:
			w.state = "drawn" if not prey.is_empty() else "wander"
			w.target = prey.pos if not prey.is_empty() else w.home
			w.prey = -1
		else:
			w.target = prey.pos
			if _flat(w.pos).distance_to(_flat(prey.pos)) <= GRAB_START:
				w.state = "grab"
				w.grab_at = now + GRAB_WINDUP
				w.yaw = _yaw_to(w.pos, prey.pos)
			return
	# Not hunting: anyone close enough to see?
	var seen := _nearest(w.pos, cands, INF if int(w.bound) >= 0 else sight(night))
	if not seen.is_empty():
		w.state = "hunt"
		w.prey = int(seen.id)
		w.target = seen.pos
		return
	if str(w.state) == "drawn" and _flat(w.pos).distance_to(_flat(w.target)) < 1.0:
		w.state = "wander" # nothing here: it lingers where the noise was
		w.home = w.pos
	if str(w.state) == "wander" and now >= float(w.until):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(w.id), int(now * 10.0)])
		var a := rng.randf() * TAU
		var r := rng.randf() * WANDER_RADIUS
		w.target = Vector3(w.home.x + cos(a) * r, 0.0, w.home.z + sin(a) * r)
		w.until = now + rng.randf_range(4.0, 9.0)


## The nearest of `players` within `radius` of `pos`, or {}.
static func _nearest(pos: Vector3, players: Array, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for p in players:
		var d := _flat(pos).distance_to(_flat(p.pos))
		if d <= radius and d < best_d:
			best_d = d
			best = p
	return best


static func _move(w: Dictionary, fires: Array, dt: float, night: bool) -> void:
	var st := str(w.state)
	if st in ["grab", "recover", "stagger"]:
		return
	var v := 0.0
	match st:
		"hunt", "drawn":
			v = speed(night)
		"wander", "wary":
			v = WANDER_SPEED
	var to := _flat(w.target) - _flat(w.pos)
	var stop := GRAB_START * 0.8 if st == "hunt" else 0.3
	if to.length() <= stop:
		v = 0.0
	var dir := to.normalized() if to.length() > 0.01 else Vector2.ZERO
	# Ember keeps them wary: inside a fire's ring, walk straight out of it; heading into one,
	# stop at its edge.
	for f in fires:
		var from_fire := _flat(w.pos) - _flat(f)
		if from_fire.length() < FIRE_KEEPAWAY:
			dir = from_fire.normalized() if from_fire.length() > 0.01 else Vector2(1, 0)
			v = maxf(v, DAY_SPEED) # backs off briskly
			w.state = "wary"
			break
		var next := _flat(w.pos) + dir * v * dt
		if next.distance_to(_flat(f)) < FIRE_KEEPAWAY:
			v = 0.0
	if st == "wary" and v > 0.0 and fires.all(func(f): return _flat(w.pos).distance_to(_flat(f)) >= FIRE_KEEPAWAY):
		w.state = "wander"
		w.home = w.pos
		w.until = 0.0
	if v <= 0.0 or dir == Vector2.ZERO:
		if dir != Vector2.ZERO:
			w.yaw = atan2(dir.x, dir.y)
		return
	var stride := minf(v * dt, to.length()) if st != "wary" else v * dt
	var x: float = w.pos.x + dir.x * stride
	var z: float = w.pos.z + dir.y * stride
	var lim := WorldGen.half_size() - 1.0
	x = clampf(x, -lim, lim)
	z = clampf(z, -lim, lim)
	w.pos = Vector3(x, Terrain.height(x, z), z)
	w.yaw = atan2(dir.x, dir.y)


## --- Being struck ---

## Every walker as a hit target for Weapons.targets_hit: [{id: "w<id>", pos, radius}]. The
## string ids keep walkers apart from the grazers' int ids in one swing.
static func targets(state: Dictionary) -> Array:
	var out: Array = []
	for w in state.walkers:
		out.append({"id": target_key(int(w.id)), "pos": w.pos, "radius": radius(str(w.kind))})
	return out


static func target_key(id: int) -> String:
	return "w%d" % id


## The walker id in a target key ("w3" -> 3), or -1.
static func id_of_key(key: Variant) -> int:
	var s := str(key)
	if typeof(key) != TYPE_STRING or not s.begins_with("w") or not s.substr(1).is_valid_int():
		return -1
	return s.substr(1).to_int()


## A blow of `damage` from player `by` standing at `from` lands on walker `id`. A heavy blow
## (`stagger`) staggers it and breaks a grab still in its windup; any blow turns it on whoever
## struck it. At 0 hp it is gone. Returns {down: bool, broke_grab: bool} or {} for an unknown id.
static func strike(state: Dictionary, id: int, by: int, from: Vector3, now: float, damage: float, stagger: bool) -> Dictionary:
	var w := get_by_id(state, id)
	if w.is_empty():
		return {}
	w.struck = int(w.struck) + 1
	w.hp = maxf(float(w.hp) - maxf(damage, 0.0), 0.0)
	if float(w.hp) <= 0.0:
		state.walkers.erase(w)
		state.downs = int(state.downs) + 1
		return {"down": true, "broke_grab": false}
	var broke := false
	if int(w.bound) < 0 or int(w.bound) == by:
		w.prey = by
	if stagger:
		broke = str(w.state) == "grab" and now < float(w.grab_at)
		w.state = "stagger"
		w.until = now + STAGGER_SECONDS
	elif not str(w.state) in ["grab", "recover", "stagger"]:
		w.state = "hunt"
		w.target = from
	return {"down": false, "broke_grab": broke}


## --- Rising near players ---

## How many walkers may be about player `p` (one of `players`): PER_PLAYER (day or night),
## plus CROWD_BONUS for each other player within CROWD_RADIUS, so a band draws more than a
## lone traveller, but a crowd's cap is shared (counted over walkers near any of them).
static func cap_near(p: Dictionary, players: Array, night: bool) -> int:
	var crowd := 0
	for o in players:
		if int(o.id) != int(p.id) and _flat(o.pos).distance_to(_flat(p.pos)) <= CROWD_RADIUS:
			crowd += 1
	return (PER_PLAYER_NIGHT if night else PER_PLAYER_DAY) + crowd * CROWD_BONUS


## Walkers within CRUMBLE_RADIUS of `pos` (the ones that count against a player's cap).
static func count_near(state: Dictionary, pos: Vector3) -> int:
	var n := 0
	for w in state.walkers:
		if _flat(w.pos).distance_to(_flat(pos)) <= CRUMBLE_RADIUS:
			n += 1
	return n


## Rise attempts for every player who is due one (RISE_EVERY_DAY / _NIGHT apart, per player):
## a walker rises RISE_MIN..RISE_MAX from them on dry, standable ground, never within
## SAFE_RADIUS of the world's spawn and never closer than RISE_MIN to any player, while the
## walkers about them are under cap_near and the world under MAX_WALKERS. Returns the new
## walkers' ids.
static func rise_near_players(state: Dictionary, players: Array, now: float, night: bool) -> Array:
	var risen: Array = []
	var rng: RandomNumberGenerator = state.rng
	var every := RISE_EVERY_NIGHT if night else RISE_EVERY_DAY
	for p in players:
		var key := str(p.id)
		if not state.rise_at.has(key):
			state.rise_at[key] = now + every * rng.randf_range(0.5, 1.0) # nobody is met by one on login
			continue
		if now < float(state.rise_at[key]):
			continue
		state.rise_at[key] = now + every
		if count(state) >= MAX_WALKERS or count_near(state, p.pos) >= cap_near(p, players, night):
			continue
		var spot := rise_spot(p.pos, players, rng)
		if spot == Vector3.INF:
			continue
		risen.append(int(rise(state, spot, now).id))
	# Forget players who left.
	for key in state.rise_at.keys():
		var here := false
		for p in players:
			if str(p.id) == key:
				here = true
				break
		if not here:
			state.rise_at.erase(key)
	return risen


## A place for a walker to rise near `pos`, or Vector3.INF if none was found in a few tries.
static func rise_spot(pos: Vector3, players: Array, rng: RandomNumberGenerator) -> Vector3:
	var sp := WorldGen.spawn_point()
	for attempt in 12:
		var a := rng.randf() * TAU
		var r := rng.randf_range(RISE_MIN, RISE_MAX)
		var x := pos.x + cos(a) * r
		var z := pos.z + sin(a) * r
		if Vector2(x - sp.x, z - sp.z).length() < SAFE_RADIUS:
			continue
		if not good_ground(x, z):
			continue
		var too_close := false
		for p in players:
			if Vector2(x - p.pos.x, z - p.pos.z).length() < RISE_MIN:
				too_close = true
				break
		if too_close:
			continue
		return Vector3(x, Terrain.height(x, z), z)
	return Vector3.INF


## Dry land inside the world: where a walker can stand (steep ground is fine, they climb).
static func good_ground(x: float, z: float) -> bool:
	var lim := WorldGen.half_size() - 4.0
	if absf(x) > lim or absf(z) > lim:
		return false
	return Terrain.height(x, z) >= Terrain.water_level() + 0.3


## The hidden /gloam dev command: a walker bound to player `id` rises SUMMON_DISTANCE in
## front of `pos` along `yaw`. Returns it.
static func summon(state: Dictionary, id: int, pos: Vector3, yaw: float, now: float) -> Dictionary:
	var at := Vector3(pos.x + sin(yaw) * SUMMON_DISTANCE, 0.0, pos.z + cos(yaw) * SUMMON_DISTANCE)
	var w := rise(state, at, now, id)
	w.yaw = _yaw_to(w.pos, pos)
	return w


## "Gloam walker 3: 22/30 health, 1.4 m from you, grab." for the /gloam dev command.
static func describe_walker(w: Dictionary, from: Vector3) -> String:
	return "%s %d: %d/%d health, %.1f m from you, %s." % [KINDS.get(str(w.kind), KINDS.walker).label, int(w.id),
		roundi(float(w.hp)), roundi(max_hp(str(w.kind))), _flat(w.pos).distance_to(_flat(from)), str(w.state)]


## One line for the server log.
static func describe(on: bool) -> String:
	if not on:
		return "off (no walkers rise; /gloam raises one where dev commands are on)"
	return "on: walkers rise near players, %d each by day, %d at night, at most %d" % [PER_PLAYER_DAY, PER_PLAYER_NIGHT, MAX_WALKERS]


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := _flat(to) - _flat(from)
	return atan2(d.x, d.y)


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

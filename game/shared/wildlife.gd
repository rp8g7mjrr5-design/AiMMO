class_name Wildlife
## Gentle wildlife, server side (Milestone 2 build-ahead, the old Week 04): herds of grazers
## in the hills just outside the Spawn Meadow. They graze, amble about their home, look up
## when someone comes close, bolt as a herd when you rush them, settle again once you are
## far off, and wander home. At night they lie down at home and let you walk much closer.
##
## The fun it is for: the land past the meadow is alive. Walk out and a herd lifts its heads;
## charge and the whole herd bolts over the hill; creep in, freeze when they look up, and you
## can get close enough to watch them graze. Later (Milestone 2) these are the first things
## you hunt, and the creep-and-freeze rule is what makes stalking one feel like a skill.
##
## Pure rules over plain data, like Gathering and Vitals: the server owns one state from
## new_state() and calls step() every tick with the players' positions. Since protocol v6 the
## server sends each player to_wire_near(state, their position) about 5 times a second
## (s2c_wildlife on Net/Play).
##
## Facing: `yaw` is the angle whose forward is Vector3(sin(yaw), 0, cos(yaw)), so yaw 0 looks
## along +z. Ids are permanent and append only, like resource node ids.

const SEED_OFFSET := 307 ## rng seed = WORLD_SEED + this (nodes use +101 and +211)

## Herd placement: a ring of herds on the dry, gentle land just past the meadow's edge.
const HERD_COUNT := 6
const HERD_MIN_SIZE := 3
const HERD_MAX_SIZE := 4
const HERD_MIN_RADIUS := 44.0 ## the meadow's starter ring ends at 34 m
const HERD_MAX_RADIUS := 110.0
const HERD_SPACING := 30.0 ## between herd homes
const MEMBER_SPREAD := 5.0 ## members start this close to their herd's home
const MAX_HEIGHT := 14.0 ## grazers keep to the lower slopes
const MAX_SLOPE := 0.9 ## same measure as ResourceNodes._slope: rise over 1 m in x plus in z

## Behaviour, in metres and seconds.
const HOME_RADIUS := 9.0 ## where a calm grazer ambles
const GRAZE_MIN := 3.0
const GRAZE_MAX := 8.0
const AMBLE_SPEED := 1.3
const RETURN_SPEED := 2.4
const FLEE_SPEED := 8.5 ## faster than a walking player (GameConfig.WALK_SPEED 6): you can't run one down
const ALERT_RADIUS := 13.0 ## a player this close makes a grazer look up
const BOLT_RADIUS := 4.5 ## this close, it bolts at once
const PERSONAL_SPACE := 2.0 ## a calm grazer never ambles closer than BOLT_RADIUS + this to anyone
const ALERT_SECONDS := 1.0 ## the look-up: freeze now and it settles
const CREEP_TOLERANCE := 0.4 ## how much closer you may drift while it looks at you
const SETTLE_STEP := 1.5 ## once settled, it looks up again only if you come this much closer
const CALM_RADIUS := 22.0 ## a fleeing grazer runs until nobody is this close
const FLEE_MIN := 2.0
const FLEE_MAX := 7.0
const HERD_RADIUS := 16.0 ## one bolts, every herd-mate this close bolts with it
const LEASH := 40.0 ## fleeing turns for home past this distance from it
const REST_SCALE := 0.45 ## at night, resting: alert distance shrinks to this share
const EDGE_MARGIN := 6.0

const STATES := ["graze", "amble", "alert", "flee", "return", "rest"]
const KINDS := {"grazer": {"label": "grazer"}}


## A fresh world's wildlife: {creatures: Array, rng: RandomNumberGenerator}. Each creature is
## {id, kind, herd, home, pos, yaw, state, until, min_until, target, threat, tolerated,
## alert_dist}.
static func new_state(seed_extra: int = 0) -> Dictionary:
	var creatures: Array = []
	for spawn in spawns():
		var c := {
			"id": int(spawn.id), "kind": str(spawn.kind), "herd": int(spawn.herd),
			"home": spawn.home, "pos": spawn.pos, "yaw": float(spawn.yaw),
			"state": "graze", "until": 0.0, "target": spawn.pos, "threat": Vector3.ZERO,
			"tolerated": ALERT_RADIUS, "alert_dist": 0.0, "min_until": 0.0,
		}
		creatures.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + SEED_OFFSET + 1 + seed_extra
	return {"creatures": creatures, "rng": rng}


static var _spawns: Array = []


## Where every creature starts, from the world seed alone (cached). Each entry is
## {id, kind, herd, home: Vector3, pos: Vector3, yaw}. Ids follow the list order.
static func spawns() -> Array:
	if _spawns.is_empty():
		_spawns = generate()
	return _spawns


## Builds the spawn list from scratch. Use spawns(); public for tests.
static func generate() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + SEED_OFFSET
	var out: Array = []
	var homes: Array = []
	for h in HERD_COUNT:
		var home := Vector3.INF
		for attempt in 80:
			var ang := TAU * (float(h) + 0.5) / HERD_COUNT + rng.randf_range(-0.4, 0.4)
			var dist := lerpf(HERD_MIN_RADIUS, HERD_MAX_RADIUS, rng.randf())
			var p := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
			if not good_ground(p.x, p.z):
				continue
			var crowded := false
			for other in homes:
				if _flat(other).distance_to(_flat(p)) < HERD_SPACING:
					crowded = true
					break
			if crowded:
				continue
			home = Vector3(p.x, Terrain.height(p.x, p.z), p.z)
			break
		if home == Vector3.INF:
			continue
		homes.append(home)
		var size := rng.randi_range(HERD_MIN_SIZE, HERD_MAX_SIZE)
		for m in size:
			var pos := home
			for attempt in 12:
				var a := rng.randf() * TAU
				var r := rng.randf_range(1.0, MEMBER_SPREAD)
				var x := home.x + cos(a) * r
				var z := home.z + sin(a) * r
				if good_ground(x, z):
					pos = Vector3(x, Terrain.height(x, z), z)
					break
			out.append({"id": out.size(), "kind": "grazer", "herd": homes.size() - 1, "home": home, "pos": pos, "yaw": rng.randf() * TAU})
	return out


## Dry, not too high, not too steep, inside the world: where a grazer can stand.
static func good_ground(x: float, z: float) -> bool:
	var lim := GameConfig.WORLD_HALF_SIZE - EDGE_MARGIN
	if absf(x) > lim or absf(z) > lim:
		return false
	var y := Terrain.height(x, z)
	if y < Terrain.water_level() + 0.5 or y > MAX_HEIGHT:
		return false
	var slope := absf(Terrain.height(x + 1.0, z) - y) + absf(Terrain.height(x, z + 1.0) - y)
	return slope <= MAX_SLOPE


static func count(state: Dictionary) -> int:
	return state.creatures.size()


static func get_by_id(state: Dictionary, id: int) -> Dictionary:
	if id < 0 or id >= state.creatures.size():
		return {}
	return state.creatures[id]


## One tick. `players` is an Array of Vector3 (every logged-in player's position), `now` the
## server's seconds, `night` WorldClock.is_night. Returns the ids that bolted this tick (for
## a future "startled" sound or message, and for tests).
static func step(state: Dictionary, players: Array, now: float, dt: float, night: bool) -> Array:
	var bolted: Array = []
	var rng: RandomNumberGenerator = state.rng
	for c in state.creatures:
		_think(c, players, now, night, rng, bolted)
	# The herd follows whoever bolted: herd-mates nearby that are not already running.
	for id in bolted.duplicate():
		var lead: Dictionary = state.creatures[id]
		for c in state.creatures:
			if c.herd != lead.herd or c.state == "flee":
				continue
			if _flat(c.pos).distance_to(_flat(lead.pos)) <= HERD_RADIUS:
				_bolt(c, lead.threat, now, rng)
				bolted.append(c.id)
	for c in state.creatures:
		_move(c, dt)
	return bolted


## Nearest player within `radius` (flat distance): [distance, position], or [INF, ZERO].
static func _nearest(pos: Vector3, players: Array, radius: float) -> Array:
	var best := INF
	var at := Vector3.ZERO
	var here := _flat(pos)
	for p in players:
		var d := here.distance_to(_flat(p))
		if d < best and d <= radius:
			best = d
			at = p
	return [best, at]


## How close a player may come before this grazer looks up.
static func alert_distance(c: Dictionary) -> float:
	var r: float = minf(ALERT_RADIUS, float(c.tolerated))
	if c.state == "rest":
		r *= REST_SCALE
	return r


static func _think(c: Dictionary, players: Array, now: float, night: bool, rng: RandomNumberGenerator, bolted: Array) -> void:
	var near := _nearest(c.pos, players, CALM_RADIUS)
	var d: float = near[0]
	var who: Vector3 = near[1]
	# Nobody inside the alert ring any more: the next visitor is judged afresh.
	if d > ALERT_RADIUS:
		c.tolerated = ALERT_RADIUS
	match c.state:
		"flee":
			if now >= float(c.until) or (d > CALM_RADIUS and now >= float(c.get("min_until", 0.0))):
				_enter(c, "return", now, 0.0)
				c.target = _wander_point(c, rng)
				c.tolerated = ALERT_RADIUS
			elif d <= CALM_RADIUS:
				c.threat = who # keep running from whoever is closest
			return
		"alert":
			if d <= BOLT_RADIUS:
				_bolt(c, who, now, rng)
				bolted.append(c.id)
			elif now >= float(c.until):
				if d < float(c.alert_dist) - CREEP_TOLERANCE:
					_bolt(c, who, now, rng) # you kept coming: off it goes
					bolted.append(c.id)
				else:
					c.tolerated = minf(ALERT_RADIUS, d - SETTLE_STEP) # you froze: it settles, but now watches that line
					_enter(c, "rest" if night else "graze", now, rng.randf_range(GRAZE_MIN, GRAZE_MAX))
			return
	if d <= BOLT_RADIUS:
		_bolt(c, who, now, rng)
		bolted.append(c.id)
		return
	if d <= alert_distance(c):
		_enter(c, "alert", now, ALERT_SECONDS)
		c.alert_dist = d
		c.threat = who
		c.yaw = _yaw_to(c.pos, who)
		return
	var from_home := _flat(c.pos).distance_to(_flat(c.home))
	if night:
		if c.state != "rest":
			if from_home > 2.0:
				if c.state != "return":
					_enter(c, "return", now, 0.0)
					c.target = c.home
			else:
				_enter(c, "rest", now, 0.0)
		return
	match c.state:
		"rest":
			_enter(c, "graze", now, rng.randf_range(GRAZE_MIN, GRAZE_MAX)) # morning
		"graze":
			if now >= float(c.until):
				_enter(c, "amble", now, 0.0)
				c.target = _wander_point(c, rng, players)
		"amble", "return":
			if c.state == "amble" and d <= BOLT_RADIUS + PERSONAL_SPACE:
				_enter(c, "graze", now, rng.randf_range(GRAZE_MIN, GRAZE_MAX)) # never walks into you
			elif _flat(c.pos).distance_to(_flat(c.target)) < 0.5:
				_enter(c, "graze", now, rng.randf_range(GRAZE_MIN, GRAZE_MAX))


static func _bolt(c: Dictionary, threat: Vector3, now: float, rng: RandomNumberGenerator) -> void:
	_enter(c, "flee", now, FLEE_MAX)
	c.threat = threat
	c.tolerated = ALERT_RADIUS
	c.min_until = now + FLEE_MIN + rng.randf_range(0.0, 0.5)


static func _enter(c: Dictionary, s: String, now: float, seconds: float) -> void:
	c.state = s
	c.until = now + seconds


static func _wander_point(c: Dictionary, rng: RandomNumberGenerator, players: Array = []) -> Vector3:
	for attempt in 8:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * HOME_RADIUS
		var x: float = c.home.x + cos(a) * r
		var z: float = c.home.z + sin(a) * r
		if good_ground(x, z) and _nearest(Vector3(x, 0.0, z), players, BOLT_RADIUS + PERSONAL_SPACE)[0] == INF:
			return Vector3(x, Terrain.height(x, z), z)
	return c.pos if not players.is_empty() else c.home


static func _move(c: Dictionary, dt: float) -> void:
	var speed := 0.0
	var dir := Vector2.ZERO
	match c.state:
		"amble":
			speed = AMBLE_SPEED
			dir = _flat(c.target) - _flat(c.pos)
		"return":
			speed = RETURN_SPEED
			dir = _flat(c.target) - _flat(c.pos)
		"flee":
			speed = FLEE_SPEED
			dir = _flat(c.pos) - _flat(c.threat)
			if dir.length() < 0.01:
				dir = Vector2(sin(float(c.yaw)), cos(float(c.yaw)))
			var home := _flat(c.home) - _flat(c.pos)
			if home.length() > LEASH:
				dir = dir.normalized() + home.normalized() * 1.5 # swing round towards home
	if speed <= 0.0 or dir.length() < 0.01:
		return
	var stride := minf(speed * dt, dir.length()) if c.state != "flee" else speed * dt
	dir = dir.normalized()
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
		var d := dir.rotated(turn)
		var x: float = c.pos.x + d.x * stride
		var z: float = c.pos.z + d.y * stride
		if good_ground(x, z):
			c.pos = Vector3(x, Terrain.height(x, z), z)
			c.yaw = atan2(d.x, d.y)
			return
	# Boxed in (water, cliff, world edge): stand. A fleeing grazer gives up and turns home.
	if c.state == "flee":
		_enter(c, "return", 0.0, 0.0)
		c.target = c.home


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := _flat(to) - _flat(from)
	return atan2(d.x, d.y)


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## The wire form (s2c_wildlife, protocol v6): a PackedFloat32Array of
## [id, x, z, yaw, state_index] per creature (clients take y from Terrain.height). Packed
## 32-bit floats are 4 bytes a value on the wire, a third of a plain Array's, which keeps 21
## grazers 5 times a second under 20 kbit/s per player; ids and state indexes are small
## whole numbers, exact as floats, and positions keep millimetres out to kilometres.
static func to_wire(state: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in state.creatures:
		_wire_one(out, c)
	return out


## Values per creature in the wire form.
const WIRE_STRIDE := 5


## to_wire for only the creatures within `radius` of `pos` (flat distance), in id order: what
## one player at `pos` is sent.
static func to_wire_near(state: Dictionary, pos: Vector3, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var here := _flat(pos)
	for c in state.creatures:
		if _flat(c.pos).distance_to(here) <= radius:
			_wire_one(out, c)
	return out


static func _wire_one(out: PackedFloat32Array, c: Dictionary) -> void:
	out.append_array(PackedFloat32Array([float(c.id), c.pos.x, c.pos.z, float(c.yaw), float(STATES.find(str(c.state)))]))


## One line for the server log at start-up.
static func describe() -> String:
	var herds := {}
	for s in spawns():
		herds[s.herd] = true
	return "%d grazers in %d herds" % [spawns().size(), herds.size()]

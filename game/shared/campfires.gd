class_name Campfires
## Placed campfires (Phase 2 build-ahead, `docs/vision.md`: "torches keep the Gloam wary").
## The rules only, as pure functions over a small Dictionary, so they are unit tested without
## a server. The server keeps one state for the world (Server.campfires), places fires from a
## player's pack (Server.place_request), steps it every tick, and hands the lit fires to the
## Gloam walkers, which keep Gloam.FIRE_KEEPAWAY from every one of them.
##
## A crafted campfire is set down PLACE_DISTANCE in front of you, on dry ground, clear of the
## workbench, of resource nodes (so nobody's gathering spot gets blocked) and of other fires.
## It burns BURN_WORLD_HOURS of world time (about a third of a night), then goes out and is
## gone. One player keeps at most MAX_PER_PLAYER burning; a refused placement costs nothing.
##
## Not saved yet: a restart puts every fire out (a fire burns under seven real minutes, and a
## save needs an add-only table after #197's migration 0004; devlog follow-up). Not drawn yet
## either: s2c_campfires (to_wire) is produced but only goes out once a protocol bump adds it,
## and only dev servers can place fires (/place, /kindle) until client's place action exists.
##
## A state is {fires: {id: fire}, next_id}. A fire is {id, pos: Vector3, owner: String
## (lower-case character name, so it survives a reconnect), lit_at, out_at}. Times (`now`)
## are real seconds on the server's monotonic clock, like Vitals and GatherChannel.

## The one item that can be placed today (bandages are used through the same message).
const ITEM := "campfire"
## Metres in front of you that a fire is set down.
const PLACE_DISTANCE := 1.5
## World hours a fire burns (one world hour is WorldClock.DAY_SECONDS / 24 real seconds).
const BURN_WORLD_HOURS := 4.0
## No two fires closer than this, metres (a ring of fires is fine, a pile of them is not).
const MIN_SPACING := 3.0
## Kept clear: metres from any resource node's centre and from the workbench.
const NODE_CLEARANCE := 2.5
const BENCH_CLEARANCE := 2.5
## Keep a fire this far inside the world's border, metres.
const EDGE_MARGIN := 3.0
## Ground must stand this far above the water, metres (no fires in the shallows).
const DRY_ABOVE_WATER := 0.2
## Fires one player may have burning at once, and in the whole world.
const MAX_PER_PLAYER := 3
const MAX_FIRES := 32
## Metres around a fire that count as "at the fire" (cooking, resting by it; backlog).
const WARM_RADIUS := 4.0

## What a refusal says, by reason.
const REFUSALS := {
	"no_item": "You have no campfire to set down. Make one at the workbench.",
	"water": "The ground here is too wet for a fire.",
	"edge": "Too close to the edge of the world for a fire.",
	"crowded": "There is a fire burning right here already.",
	"node": "Not on top of something you could gather. Step aside a little.",
	"bench": "Not against the workbench. Step aside a little.",
	"too_many": "You already have %d fires burning. Let one burn down first." % MAX_PER_PLAYER,
	"world_full": "Too many fires are burning in the world. Let one burn down first.",
	"down": "You can't set a fire down right now.",
	"unknown": "That can't be set down.",
}


static func new_state() -> Dictionary:
	return {"fires": {}, "next_id": 1}


## Real seconds a fire burns.
static func burn_seconds() -> float:
	return WorldClock.DAY_SECONDS / 24.0 * BURN_WORLD_HOURS


static func refusal_text(reason: String) -> String:
	return str(REFUSALS.get(reason, REFUSALS.unknown))


## Where a fire set down by someone standing at `pos` facing `yaw` would go (on the ground).
## Forward is (sin yaw, cos yaw), as everywhere else (Gloam.summon, Wildlife.lure).
static func spot_in_front(pos: Vector3, yaw: float) -> Vector3:
	var x := pos.x + sin(yaw) * PLACE_DISTANCE
	var z := pos.z + cos(yaw) * PLACE_DISTANCE
	return Vector3(x, Terrain.height(x, z), z)


## Why a fire can't go at `at` for `owner`, or "" when it can. Doesn't look at the pack.
static func check_spot(state: Dictionary, owner: String, at: Vector3) -> String:
	var lim := WorldGen.half_size() - EDGE_MARGIN
	if absf(at.x) > lim or absf(at.z) > lim:
		return "edge"
	if Terrain.height(at.x, at.z) < Terrain.water_level() + DRY_ABOVE_WATER:
		return "water"
	var fires: Dictionary = state.fires
	if fires.size() >= MAX_FIRES:
		return "world_full"
	if count_owned(state, owner) >= MAX_PER_PLAYER:
		return "too_many"
	for id in fires:
		if _flat(fires[id].pos).distance_to(_flat(at)) < MIN_SPACING:
			return "crowded"
	if Crafting.workbench_xz().distance_to(_flat(at)) < BENCH_CLEARANCE:
		return "bench"
	if not ResourceNodes.near(at, NODE_CLEARANCE).is_empty():
		return "node"
	return ""


## Lights a fire for `owner` in front of `pos`/`yaw` if the spot is good. Returns
## {ok, reason, fire}; a refusal changes nothing.
static func place(state: Dictionary, owner: String, pos: Vector3, yaw: float, now: float) -> Dictionary:
	var at := spot_in_front(pos, yaw)
	var why := check_spot(state, owner, at)
	if why != "":
		return {"ok": false, "reason": why, "fire": {}}
	var id := int(state.next_id)
	state.next_id = id + 1
	var fire := {"id": id, "pos": at, "owner": owner.to_lower(), "lit_at": now, "out_at": now + burn_seconds()}
	state.fires[id] = fire
	return {"ok": true, "reason": "", "fire": fire}


## Fires that burned down by `now` go out and are removed. Returns the fires that went out.
static func step(state: Dictionary, now: float) -> Array:
	var out: Array = []
	var fires: Dictionary = state.fires
	for id in fires.keys():
		if now >= float(fires[id].out_at):
			out.append(fires[id])
			fires.erase(id)
	return out


static func count(state: Dictionary) -> int:
	return state.fires.size()


static func count_owned(state: Dictionary, owner: String) -> int:
	var n := 0
	var who := owner.to_lower()
	for id in state.fires:
		if str(state.fires[id].owner) == who:
			n += 1
	return n


static func get_by_id(state: Dictionary, id: int) -> Dictionary:
	return state.fires.get(id, {})


## Every lit fire's position, for Gloam.step (walkers keep FIRE_KEEPAWAY from each).
static func positions(state: Dictionary) -> Array:
	var out: Array = []
	for id in state.fires:
		out.append(state.fires[id].pos)
	return out


## Fires within `radius` of `pos` (flat distance), nearest first.
static func near(state: Dictionary, pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for id in state.fires:
		if _flat(state.fires[id].pos).distance_to(_flat(pos)) <= radius:
			out.append(state.fires[id])
	out.sort_custom(func(a, b): return _flat(a.pos).distance_to(_flat(pos)) < _flat(b.pos).distance_to(_flat(pos)))
	return out


## Whether `pos` is at a lit fire (WARM_RADIUS): where cooking and resting will happen.
static func is_warm(state: Dictionary, pos: Vector3) -> bool:
	return not near(state, pos, WARM_RADIUS).is_empty()


## s2c_campfires' payload: [id, x, y, z, seconds_left] per fire, by id. Few enough (MAX_FIRES)
## that every player gets the whole list on each change.
static func to_wire(state: Dictionary, now: float) -> PackedFloat32Array:
	var ids: Array = state.fires.keys()
	ids.sort()
	var out := PackedFloat32Array()
	for id in ids:
		var f: Dictionary = state.fires[id]
		out.append_array([float(id), f.pos.x, f.pos.y, f.pos.z, maxf(float(f.out_at) - now, 0.0)])
	return out


## "Campfire 3: 2.1 m from you, burns 6 more minutes." for the /kindle status dev command.
static func describe_fire(f: Dictionary, from: Vector3, now: float) -> String:
	var left := maxf(float(f.out_at) - now, 0.0)
	var mins := ceili(left / 60.0)
	return "Campfire %d: %.1f m from you, burns %d more minute%s." % [int(f.id), _flat(f.pos).distance_to(_flat(from)),
		mins, "" if mins == 1 else "s"]


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)

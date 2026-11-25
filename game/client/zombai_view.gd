class_name ZombaiView
extends RefCounted
## What the client knows about the Zombai walkers in view (protocol v10: `net.gloam_changed`
## and `net.gloam_struck`), as plain data: where each one is drawn now, which way it faces,
## what it is doing, how long its raised grab has left, and the walkers just put down, which
## stay on the ground a while before they sink away. No meshes, so the bot test and unit tests
## use it as is; `ZombaiFigures` draws from it.
##
## The fun it is for: you see one coming, you hear it, its arms come up and you have a moment
## to step back or hit first, and when your last blow lands it goes over where it stood.
##
## Smoothing is HerdView's: updates come about 5 a second, unreliable, so each starts a BLEND
## from where the walker is drawn to where the server has it; a first sighting or a jump past
## SNAP_DIST is placed at once. An empty update, or a walker missing from one, has left view,
## unless a blow just put it down: then it becomes a body (`fallen`) for LIE_SECONDS, sinks
## for SINK_SECONDS and is gone.

const BLEND := 0.24 ## a little longer than the 0.2 s between sends, so motion never stalls
const SNAP_DIST := 10.0 ## metres between updates that count as a jump (they walk 3.4 m/s at most)
const LIE_SECONDS := 6.0 ## a body stays down this long ...
const SINK_SECONDS := 2.0 ## ... then sinks into the ground over this long
const SINK_DEPTH := 0.6 ## metres it sinks
const FLINCH_SECONDS := 0.25 ## a struck walker jerks for this long

## id -> {from, to, from_yaw, to_yaw, since, state, windup_left, windup_at, flinch_at, stagger_at}
var walkers := {}
## id -> {pos, yaw, since}: walkers put down, lying where they fell
var fallen := {}
var updates := 0
var windups := 0 ## raised grabs seen since the last clear()
var downs := 0 ## walkers seen put down since the last clear()


## One s2c_gloam at time `now`. Returns the moments it brought, each {id, event}: "appear",
## "leave", "windup" (its arms just came up: the grab's telegraph) or "hunt" (it just turned
## on someone: the groan that says it saw you).
func feed(entries: PackedFloat32Array, now: float) -> Array:
	updates += 1
	var events: Array = []
	if entries.size() % Gloam.WIRE_STRIDE != 0:
		return events # malformed: keep what we have, the next one replaces it
	var seen := {}
	for w in Gloam.from_wire(entries):
		var id := int(w.id)
		if fallen.has(id):
			continue # a late packet about one we already saw go down
		var target := Vector3(float(w.x), Terrain.height(float(w.x), float(w.z)), float(w.z))
		var yaw := float(w.yaw)
		var st := str(w.state)
		seen[id] = true
		if not walkers.has(id):
			walkers[id] = {"from": target, "to": target, "from_yaw": yaw, "to_yaw": yaw, "since": now,
				"state": st, "windup_left": float(w.windup_left), "windup_at": now, "flinch_at": -INF, "stagger_at": -INF}
			events.append({"id": id, "event": "appear"})
			if st == "grab":
				windups += 1
				events.append({"id": id, "event": "windup"})
			continue
		var c: Dictionary = walkers[id]
		var drawn := position(id, now)
		if Vector2(drawn.x - target.x, drawn.z - target.z).length() > SNAP_DIST:
			drawn = target
		c.from = drawn
		c.from_yaw = facing(id, now)
		c.to = target
		c.to_yaw = yaw
		c.since = now
		if st != str(c.state):
			if st == "grab":
				windups += 1
				events.append({"id": id, "event": "windup"})
			elif st == "hunt" and not str(c.state) in ["grab", "recover", "stagger"]:
				events.append({"id": id, "event": "hunt"})
			if st == "stagger":
				c.stagger_at = now
		if st == "grab":
			c.windup_left = float(w.windup_left)
			c.windup_at = now
		c.state = st
	for id in walkers.keys():
		if not seen.has(id):
			walkers.erase(id)
			events.append({"id": id, "event": "leave"})
	return events


## s2c_gloam_hits: a blow landed on `ids`; `downed` went down for good. Returns the moments,
## each {id, event}: "struck" for a walker still standing, "down" for one put down. A heavy
## blow staggers at once (before the next s2c_gloam says so), so the hit reads on the frame.
func struck(kind: String, ids: Array, downed: Array, now: float) -> Array:
	var events: Array = []
	for raw in ids:
		var id := int(raw)
		if not walkers.has(id):
			continue
		if downed.has(raw) or downed.has(id):
			fallen[id] = {"pos": position(id, now), "yaw": facing(id, now), "since": now}
			walkers.erase(id)
			downs += 1
			events.append({"id": id, "event": "down"})
			continue
		var c: Dictionary = walkers[id]
		c.flinch_at = now
		if kind == "heavy":
			c.state = "stagger"
			c.stagger_at = now
		events.append({"id": id, "event": "struck"})
	return events


## Drops bodies that have finished sinking. Returns the ids dropped.
func expire(now: float) -> Array:
	var gone: Array = []
	for id in fallen.keys():
		if now - float(fallen[id].since) >= LIE_SECONDS + SINK_SECONDS:
			fallen.erase(id)
			gone.append(id)
	return gone


## Forget every walker and body (logout, disconnect).
func clear() -> void:
	walkers.clear()
	fallen.clear()


func has(id: int) -> bool:
	return walkers.has(id)


func blend(id: int, now: float) -> float:
	var c: Dictionary = walkers.get(id, {})
	if c.is_empty():
		return 1.0
	var t := clampf((now - float(c.since)) / BLEND, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Where a walker is drawn at `now`, on the ground (a body: where it fell, sinking at the end).
## Vector3.ZERO for one we don't know.
func position(id: int, now: float) -> Vector3:
	if fallen.has(id):
		var f: Dictionary = fallen[id]
		var p: Vector3 = f.pos
		return Vector3(p.x, Terrain.height(p.x, p.z) - sink(id, now), p.z)
	var c: Dictionary = walkers.get(id, {})
	if c.is_empty():
		return Vector3.ZERO
	var q: Vector3 = (c.from as Vector3).lerp(c.to, blend(id, now))
	q.y = Terrain.height(q.x, q.z)
	return q


## How far a body has sunk into the ground at `now`, 0 until LIE_SECONDS.
func sink(id: int, now: float) -> float:
	if not fallen.has(id):
		return 0.0
	var k := clampf((now - float(fallen[id].since) - LIE_SECONDS) / SINK_SECONDS, 0.0, 1.0)
	return SINK_DEPTH * k * k


func facing(id: int, now: float) -> float:
	if fallen.has(id):
		return float(fallen[id].yaw)
	var c: Dictionary = walkers.get(id, {})
	if c.is_empty():
		return 0.0
	return lerp_angle(float(c.from_yaw), float(c.to_yaw), blend(id, now))


func state(id: int) -> String:
	if fallen.has(id):
		return "down"
	return str(walkers.get(id, {}).get("state", ""))


## How far through its raised grab a walker is at `now`, 0..1 (1: the grab closes), counted
## down from the server's windup_left so the pose lands on the server's moment. 0 when it
## isn't winding up.
func windup(id: int, now: float) -> float:
	var c: Dictionary = walkers.get(id, {})
	if c.is_empty() or str(c.state) != "grab":
		return 0.0
	var left := float(c.windup_left) - (now - float(c.windup_at))
	return clampf(1.0 - left / Gloam.GRAB_WINDUP, 0.0, 1.0)


## Seconds since a walker was last struck (INF if never), and since it last staggered.
func since_flinch(id: int, now: float) -> float:
	return now - float(walkers.get(id, {}).get("flinch_at", -INF))


func since_stagger(id: int, now: float) -> float:
	return now - float(walkers.get(id, {}).get("stagger_at", -INF))


## Seconds since a body went down.
func since_down(id: int, now: float) -> float:
	return now - float(fallen.get(id, {}).get("since", now))


## Walkers standing in view, lowest id first.
func ids() -> Array:
	var out := walkers.keys()
	out.sort()
	return out


## Bodies on the ground, lowest id first.
func bodies() -> Array:
	var out := fallen.keys()
	out.sort()
	return out

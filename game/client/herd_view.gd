class_name HerdView
extends RefCounted
## What the client knows about the grazers in view (protocol v6, `net.wildlife_changed`), as
## plain data: where each one is drawn right now, which way it faces, what it is doing, and the
## moments worth a sound (a bolt). No meshes, so the bot test and unit tests use it as is;
## `GrazerFigures` draws from it with world's `Grazers` model and poses.
##
## The fun it is for: the land past the meadow is alive. A herd lifts its heads as you walk
## up, and if you rush it the whole herd snorts and bolts over the hill.
##
## Smoothing: updates come about 5 a second and are unreliable, so each one starts a short
## blend (BLEND seconds) from where the creature is drawn now to where the server has it. A
## creature seen for the first time, or one that jumped further than SNAP_DIST, is placed
## at once (no slide in from nowhere). An empty update, or a creature missing from a non-empty
## one, means it left your view: it is dropped.

const BLEND := 0.24 ## seconds; a little longer than the 0.2 s between sends, so motion never stalls
const SNAP_DIST := 12.0 ## metres between updates that count as a jump, not a run (flee is 8.5 m/s)

## id -> {from: Vector3, to: Vector3, from_yaw, to_yaw, since: float, state: String}
var creatures := {}
var updates := 0
var bolts := 0 ## state flips into "flee" seen since the last clear()


## One s2c_wildlife at time `now` (seconds, any steady clock). Returns the moments it brought,
## each {id, event}: "appear", "leave", "bolt" (a known grazer flipped to flee: snort and dust)
## or "alert" (it just looked up at someone).
func feed(entries: PackedFloat32Array, now: float) -> Array:
	updates += 1
	var events: Array = []
	if entries.size() % Wildlife.WIRE_STRIDE != 0:
		return events # malformed: keep what we have, the next one replaces it
	var seen := {}
	for i in range(0, entries.size(), Wildlife.WIRE_STRIDE):
		var id := int(entries[i])
		var si := int(entries[i + 4])
		var state: String = Wildlife.STATES[si] if si >= 0 and si < Wildlife.STATES.size() else "graze"
		var x := float(entries[i + 1])
		var z := float(entries[i + 2])
		var target := Vector3(x, Terrain.height(x, z), z)
		var yaw := float(entries[i + 3])
		seen[id] = true
		if not creatures.has(id):
			creatures[id] = {"from": target, "to": target, "from_yaw": yaw, "to_yaw": yaw, "since": now, "state": state}
			events.append({"id": id, "event": "appear"})
			continue
		var c: Dictionary = creatures[id]
		var drawn := position(id, now)
		if Vector2(drawn.x - target.x, drawn.z - target.z).length() > SNAP_DIST:
			drawn = target
		c.from = drawn
		c.from_yaw = facing(id, now)
		c.to = target
		c.to_yaw = yaw
		c.since = now
		if state != c.state:
			if state == "flee":
				bolts += 1
				events.append({"id": id, "event": "bolt"})
			elif state == "alert":
				events.append({"id": id, "event": "alert"})
		c.state = state
	for id in creatures.keys():
		if not seen.has(id):
			creatures.erase(id)
			events.append({"id": id, "event": "leave"})
	return events


## Forget every grazer (logout, disconnect).
func clear() -> void:
	creatures.clear()


func has(id: int) -> bool:
	return creatures.has(id)


## How far into the current blend a creature is, 0 to 1.
func blend(id: int, now: float) -> float:
	var c: Dictionary = creatures.get(id, {})
	if c.is_empty():
		return 1.0
	var t := clampf((now - float(c.since)) / BLEND, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Where a grazer is drawn at `now`, on the ground. Vector3.ZERO for one we don't know.
func position(id: int, now: float) -> Vector3:
	var c: Dictionary = creatures.get(id, {})
	if c.is_empty():
		return Vector3.ZERO
	var p: Vector3 = (c.from as Vector3).lerp(c.to, blend(id, now))
	p.y = Terrain.height(p.x, p.z)
	return p


## Which way it faces at `now` (yaw 0 looks along +z, as on the wire).
func facing(id: int, now: float) -> float:
	var c: Dictionary = creatures.get(id, {})
	if c.is_empty():
		return 0.0
	return lerp_angle(float(c.from_yaw), float(c.to_yaw), blend(id, now))


func state(id: int) -> String:
	return str(creatures.get(id, {}).get("state", ""))


## Ids in view, lowest first (a stable order for drawing).
func ids() -> Array:
	var out := creatures.keys()
	out.sort()
	return out

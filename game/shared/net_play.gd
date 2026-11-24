extends Node
## Net/Play: the RPCs added in protocol v3 (gathering, the pack, crafting), v4 (skills), v5
## (roster, Return to Spawn Meadow), v6 (wildlife) and v7 (health, stamina, the first swing). A child of Net so
## Net's own RPC numbering, and with it every old client's login, never changes (see net.gd
## and tests/protocol/README.md). No logic: each RPC re-emits the matching signal on Net.
## Clients call these as `net.play.c2s_*.rpc_id(1, ...)`; the server's _send finds them here.


func _net() -> Node:
	return get_parent()


## Who sent the RPC being handled (0 outside a scene tree, e.g. in unit tests).
func _sender() -> int:
	return multiplayer.get_remote_sender_id() if multiplayer != null else 0


# --- client to server ---

## Start a timed gather on node_id (press E at a tree, rock or seep).
@rpc("any_peer", "call_remote", "reliable")
func c2s_gather_start(node_id: int) -> void:
	_net().gather_start_requested.emit(_sender(), node_id)


## Stop the running gather (let go of E, or the client's Esc).
@rpc("any_peer", "call_remote", "reliable")
func c2s_gather_cancel() -> void:
	_net().gather_cancel_requested.emit(_sender())


## Craft one recipe by its exact id (the crafting window).
@rpc("any_peer", "call_remote", "reliable")
func c2s_craft(recipe_id: String) -> void:
	_net().craft_requested.emit(_sender(), recipe_id)


## Go back to Spawn Meadow (v5): the Esc menu's "Return to Spawn Meadow" button. The server
## answers with s2c_unstuck_result.
@rpc("any_peer", "call_remote", "reliable")
func c2s_unstuck() -> void:
	_net().unstuck_requested.emit(_sender())


# --- server to client ---

@rpc("authority", "call_remote", "reliable")
func s2c_gather_begin(peer_id: int, node_id: int, seconds: float) -> void:
	_net().gather_begun.emit(peer_id, node_id, seconds)


@rpc("authority", "call_remote", "reliable")
func s2c_gather_end(peer_id: int, node_id: int, reason: String) -> void:
	_net().gather_ended.emit(peer_id, node_id, reason)


@rpc("authority", "call_remote", "reliable")
func s2c_gather_result(item_id: String, count: int) -> void:
	_net().gather_result.emit(item_id, count)


@rpc("authority", "call_remote", "reliable")
func s2c_inventory(items: Dictionary) -> void:
	_net().inventory_changed.emit(items)


@rpc("authority", "call_remote", "reliable")
func s2c_nodes(depleted_ids: Array) -> void:
	_net().nodes_depleted.emit(depleted_ids)


@rpc("authority", "call_remote", "reliable")
func s2c_node_state(node_id: int, depleted: bool) -> void:
	_net().node_state.emit(node_id, depleted)


@rpc("authority", "call_remote", "reliable")
func s2c_craft_result(recipe_id: String, ok: bool, text: String) -> void:
	_net().craft_result.emit(recipe_id, ok, text)


# --- protocol v4: skills and XP (Milestone 1) ---

## After login: every skill's XP, skill id -> total XP (all four, 0 for untouched ones).
## The client works out levels and progress with the shared Skills table.
@rpc("authority", "call_remote", "reliable")
func s2c_skills(skills: Dictionary) -> void:
	_net().skills_changed.emit(skills)


## You earned XP: `gained` in `skill`, now `total_xp`. Sent right after the gather or craft
## result it came from, so the client shows the haul and the "+10 Felling" together.
@rpc("authority", "call_remote", "reliable")
func s2c_xp(skill: String, gained: int, total_xp: int) -> void:
	_net().xp_gained.emit(skill, gained, total_xp)


## You reached `level` in `skill`. `unlocks`: the named unlocks reached on the way, each
## {level, name, text, soon?, yield?}, for the banner. Follows the s2c_xp that caused it.
@rpc("authority", "call_remote", "reliable")
func s2c_level_up(skill: String, level: int, unlocks: Array) -> void:
	_net().level_up.emit(skill, level, unlocks)


## Someone in view (not you) levelled up: play the burst over them.
@rpc("authority", "call_remote", "reliable")
func s2c_level_up_seen(peer_id: int, skill: String, level: int) -> void:
	_net().level_up_seen.emit(peer_id, skill, level)


# --- protocol v5: who is online, and getting home ---

## Everyone online, [{id, name, level}, ...] sorted by name (level = total of all skill
## levels). At login, on every join and leave, and when anyone levels up. Replaces /who.
@rpc("authority", "call_remote", "reliable")
func s2c_roster(entries: Array) -> void:
	_net().roster_changed.emit(entries)


## The answer to c2s_unstuck: ok (you stand in Spawn Meadow now; your next snapshot has the
## new spot, so snap the camera rather than slide), or why not. wait_seconds: until the
## button works again (0 when it is ready).
@rpc("authority", "call_remote", "reliable")
func s2c_unstuck_result(ok: bool, text: String, wait_seconds: float) -> void:
	_net().unstuck_result.emit(ok, text, wait_seconds)


# --- protocol v6: the wildlife outside the meadow ---

## The grazers within GameConfig.VIEW_RANGE of you, sent about 5 times a second (every
## Server.WILDLIFE_SEND_TICKS ticks; interpolate between them). A PackedFloat32Array, 5 values
## per creature (Wildlife.WIRE_STRIDE): [id, x, z, yaw, state_index] (Wildlife.to_wire; int()
## the id and state; y from Terrain.height, yaw 0 looks along +z, state names in
## Wildlife.STATES). A state flipping to "flee" is the bolt: play the
## snort and the dust kick then. Sent only while any are in view, plus one empty Array when the
## last one leaves it (drop them all); one missing from a non-empty list has left your view. Unreliable: a lost one is replaced 0.2 s later.
@rpc("authority", "call_remote", "unreliable_ordered")
func s2c_wildlife(entries: PackedFloat32Array) -> void:
	_net().wildlife_changed.emit(entries)


# --- protocol v7: health, stamina and the first swing (Milestone 2, "First blood") ---

## Swing (left click: kind "light", hold or right click: "heavy") facing `yaw` (the camera
## heading, like c2s_input's). The server answers s2c_swing to everyone in view, then
## s2c_swing_hits when the blow lands, or s2c_attack_refused to you alone.
@rpc("any_peer", "call_remote", "reliable")
func c2s_attack(kind: String, yaw: float) -> void:
	_net().attack_requested.emit(_sender(), kind, yaw)


## Your health and stamina bar, whole points: once right after login and whenever a whole
## point changes (a hit, a swing's stamina, regen). Nothing is sent while it stays put.
@rpc("authority", "call_remote", "reliable")
func s2c_vitals(hp: int, max_hp: int, stamina: int, max_stamina: int) -> void:
	_net().vitals_changed.emit(hp, max_hp, stamina, max_stamina)


## Someone in view (maybe you) swings `weapon` (Weapons id, "fists" bare-handed) with a
## `kind` attack that takes `seconds` in all; the blow lands Weapons.hit_at(weapon, kind)
## seconds in. Play the windup and the whoosh at once.
@rpc("authority", "call_remote", "reliable")
func s2c_swing(peer_id: int, weapon: String, kind: String, seconds: float) -> void:
	_net().swing_begun.emit(peer_id, weapon, kind, seconds)


## The blow of peer_id's swing landed: the grazer ids it struck, nearest first (each one
## bolts). You always get your own, even an empty one (a whiff); others get it only on a hit.
@rpc("authority", "call_remote", "reliable")
func s2c_swing_hits(peer_id: int, kind: String, creature_ids: Array) -> void:
	_net().swing_landed.emit(peer_id, kind, creature_ids)


## Your swing didn't start: reason "busy" (still in the last swing: drop it quietly),
## "gathering" (send c2s_gather_cancel before c2s_attack to swing out of a gather),
## "winded" or "tired" (show Weapons.refusal_text and flash the stamina bar), "dead",
## "unknown" (a bad kind).
@rpc("authority", "call_remote", "reliable")
func s2c_attack_refused(kind: String, reason: String) -> void:
	_net().attack_refused.emit(kind, reason)

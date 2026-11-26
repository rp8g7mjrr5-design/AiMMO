# FROZEN: game/shared/net_play.gd as shipped at protocol v10 (the Play child of net_v10.gd).
# Never edit (see tests/protocol/README.md).
extends Node
## Net/Play: the RPCs added in protocol v3 (gathering, the pack, crafting), v4 (skills, retired), v5
## (roster, Return to Spawn Meadow), v6 (wildlife), v7 (health, stamina, the first swing), v8
## (character customization), v9 (the world config, placed campfires) and v10 (the Gloam
## walkers). A child of Net so
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


# --- protocol v4: skills and XP, retired ---
# The leveling system is gone (owner direction, 2026-11-26), but RPCs are append-only: these
# four keep their place so every RPC after them keeps its number and old clients still log
# in (tests/protocol/README.md). The server never sends them and they do nothing.

@rpc("authority", "call_remote", "reliable")
func s2c_skills(_skills: Dictionary) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func s2c_xp(_skill: String, _gained: int, _total_xp: int) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func s2c_level_up(_skill: String, _level: int, _unlocks: Array) -> void:
	pass


@rpc("authority", "call_remote", "reliable")
func s2c_level_up_seen(_peer_id: int, _skill: String, _level: int) -> void:
	pass


# --- protocol v5: who is online, and getting home ---

## Everyone online, [{id, name}, ...] sorted by name. At login and on every join and leave. Replaces /who.
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


# --- protocol v8: character customization ---

## Save my look (the character-creation window's "Set out" or "Save"): a complete Appearance
## look, every key a whole number in range. The server checks it (Appearance.check), stores
## it and answers with s2c_look to everyone, you included; a bad look is refused quietly
## with s2c_system(Appearance.REFUSED).
@rpc("any_peer", "call_remote", "reliable")
func c2s_set_look(look: Dictionary) -> void:
	_net().look_requested.emit(_sender(), look)


## peer_id's look (Appearance; {} = never chosen: draw them from their appearance seed).
## Sent right after s2c_player_joined for everyone already online and for the newcomer, and
## to everyone when someone saves a new look. Your own look comes in s2c_login_result's
## character ("look") and again here whenever you change it.
@rpc("authority", "call_remote", "reliable")
func s2c_look(peer_id: int, look: Dictionary) -> void:
	_net().look_changed.emit(peer_id, look)


# --- protocol v9: which world this is, and campfires you set down ---

## The world this server runs (WorldGen.config(): {seed, size_m, gen_version}). Sent once,
## right after s2c_login_result and before anything else about the world. Call
## WorldGen.apply(config) and build terrain, nodes and spawn from it; gen_version 0 is
## Ashgrove, today's valley, exactly as before.
@rpc("authority", "call_remote", "reliable")
func s2c_world(config: Dictionary) -> void:
	_net().world_config.emit(config)


## Set `item` down in front of you (today only "campfire", from the pack). The server places
## it Campfires.PLACE_DISTANCE ahead of where it has you standing, facing your last yaw, and
## answers with s2c_place_result; on success everyone also gets s2c_campfires.
@rpc("any_peer", "call_remote", "reliable")
func c2s_place(item: String) -> void:
	_net().place_requested.emit(_sender(), item)


## The answer to c2s_place: ok, or why not. reason is "" on success, else a Campfires.REFUSALS
## key ("no_item", "water", "edge", "crowded", "node", "bench", "too_many", "world_full",
## "down", "unknown"); text is the line to show as a notice either way.
@rpc("authority", "call_remote", "reliable")
func s2c_place_result(item: String, ok: bool, reason: String, text: String) -> void:
	_net().place_result.emit(item, ok, reason, text)


## Every campfire burning in the world, as a PackedFloat32Array of 5 values per fire
## (Campfires.to_wire): [id, x, y, z, seconds_left] (int() the id). Sent at login when
## any burn, and to everyone whenever one is lit or burns down. A fire missing from the list
## has gone out: leave ash, then nothing. An empty list means none burn.
@rpc("authority", "call_remote", "reliable")
func s2c_campfires(entries: PackedFloat32Array) -> void:
	_net().campfires_changed.emit(entries)


# --- protocol v10: the Gloam walkers (Basics 2, zombie survival) ---

## The walkers within GameConfig.VIEW_RANGE of you, about 5 times a second, as 6 values per
## walker (Gloam.to_wire_near): [id, x, z, yaw, state_index, windup_left] (int() the id and
## the state; names in Gloam.STATES; y from Terrain.height). State "grab" is the arms-up
## telegraph and windup_left the seconds until it closes on whoever is still in reach: show
## it, it is the player's cue to step back or land a heavy blow. Unreliable like
## s2c_wildlife; an empty list means the last walker just left your view (sent a few times).
@rpc("authority", "call_remote", "unreliable_ordered")
func s2c_gloam(entries: PackedFloat32Array) -> void:
	_net().gloam_changed.emit(entries)


## peer_id's `kind` blow landed on these walkers (ids from s2c_gloam), nearest first; `downed`
## lists the ones that blow put down (they drop out of the next s2c_gloam). Sent to everyone
## in view, the swinger included, right after s2c_swing_hits, only when a walker was struck.
@rpc("authority", "call_remote", "reliable")
func s2c_gloam_hits(peer_id: int, kind: String, walker_ids: Array, downed: Array) -> void:
	_net().gloam_struck.emit(peer_id, kind, walker_ids, downed)

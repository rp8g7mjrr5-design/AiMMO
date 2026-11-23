# FROZEN: game/shared/net_play.gd as shipped at protocol v4 (the Play child of net_v4.gd).
# Never edit (see tests/protocol/README.md).
extends Node
## Net/Play: the RPCs added in protocol v3 (gathering, the pack, crafting) and v4 (skills). A child of Net so
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

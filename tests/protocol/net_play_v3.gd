# FROZEN: game/shared/net_play.gd as shipped at protocol v3 (the Play child of net_v3.gd).
# Never edit (see tests/protocol/README.md).
extends Node
## Net/Play: the RPCs added in protocol v3 (gathering, the pack, crafting). A child of Net so
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

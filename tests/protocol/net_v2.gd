# FROZEN: game/shared/net.gd as shipped at protocol v2. Never edit; it stands in for players
# who have not updated (see tests/protocol/README.md).
extends Node
## The one RPC endpoint. It lives at /root/Main/Net on every peer, carries no logic, and
## re-emits each RPC as a signal so the server, client, and bots can handle them.
## Clients call c2s_* on the server (peer 1). The server calls s2c_* on clients.

signal login_requested(peer_id: int, protocol: int, username: String, password: String)
signal input_received(peer_id: int, seq: int, move: Vector2, yaw: float)
signal chat_requested(peer_id: int, text: String)

signal login_result(ok: bool, message: String, my_id: int, character: Dictionary)
signal player_joined(id: int, name: String, appearance_seed: int)
signal player_left(id: int)
signal snapshot(tick: int, entries: Array)
signal chat_message(from_name: String, text: String)
signal system_message(text: String)
signal world_time(world_seconds: float)


# --- client to server ---

@rpc("any_peer", "call_remote", "reliable")
func c2s_login(protocol: int, username: String, password: String) -> void:
	login_requested.emit(multiplayer.get_remote_sender_id(), protocol, username, password)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c2s_input(seq: int, move: Vector2, yaw: float) -> void:
	input_received.emit(multiplayer.get_remote_sender_id(), seq, move, yaw)


@rpc("any_peer", "call_remote", "reliable")
func c2s_chat(text: String) -> void:
	chat_requested.emit(multiplayer.get_remote_sender_id(), text)


# --- server to client ---

@rpc("authority", "call_remote", "reliable")
func s2c_login_result(ok: bool, message: String, my_id: int, character: Dictionary) -> void:
	login_result.emit(ok, message, my_id, character)


@rpc("authority", "call_remote", "reliable")
func s2c_player_joined(id: int, player_name: String, appearance_seed: int) -> void:
	player_joined.emit(id, player_name, appearance_seed)


@rpc("authority", "call_remote", "reliable")
func s2c_player_left(id: int) -> void:
	player_left.emit(id)


## entries: flat array [id, x, y, z, yaw, id, x, y, z, yaw, ...]
@rpc("authority", "call_remote", "unreliable_ordered")
func s2c_snapshot(tick: int, entries: Array) -> void:
	snapshot.emit(tick, entries)


@rpc("authority", "call_remote", "reliable")
func s2c_chat(from_name: String, text: String) -> void:
	chat_message.emit(from_name, text)


@rpc("authority", "call_remote", "reliable")
func s2c_system(text: String) -> void:
	system_message.emit(text)


## The shared clock, in world seconds (see WorldClock). Sent right after a successful login
## and every GameConfig.WORLD_TIME_SYNC_SECONDS. Clients extrapolate between syncs.
@rpc("authority", "call_remote", "reliable")
func s2c_world_time(world_seconds: float) -> void:
	world_time.emit(world_seconds)

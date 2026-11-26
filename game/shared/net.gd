extends Node
## The one RPC endpoint. It lives at /root/Main/Net on every peer, carries no logic, and
## re-emits each RPC as a signal so the server, client, and bots can handle them.
## Clients call c2s_* on the server (peer 1). The server calls s2c_* on clients.
##
## Net's own RPC list must never change again: Godot numbers RPCs by sorted name, so a new
## one here would shift c2s_login / s2c_login_result and old clients would hang at login
## instead of being told to update (tests/protocol/README.md). Every RPC added from v3 on
## lives on the child node `Net/Play` (net_play.gd), which every role gets from _ready, and
## re-emits its signal here so callers keep using `net.<signal>`.

const PlayScript := preload("res://shared/net_play.gd")

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
## Emitted just before `snapshot`, with the last input seq the server applied for this
## client (-1 before the first). Also kept in last_ack_seq. Protocol v3.
signal snapshot_ack(ack_seq: int)

# --- protocol v3, carried by Net/Play (see net_play.gd) ---
signal gather_start_requested(peer_id: int, node_id: int)
signal gather_cancel_requested(peer_id: int)
signal craft_requested(peer_id: int, recipe_id: String)
## Someone in view (peer_id, maybe you) started a timed gather on node_id, `seconds` long.
signal gather_begun(peer_id: int, node_id: int, seconds: float)
## That gather ended: reason "done", or why it stopped ("moved", "far", "stopped",
## "disconnected", "depleted", "full", ...). Also sent to you alone when a start is refused.
signal gather_ended(peer_id: int, node_id: int, reason: String)
## Your gather paid out: what you got, for the haul toast.
signal gather_result(item_id: String, count: int)
## Your whole pack, item id -> count, after login and after every change.
signal inventory_changed(items: Dictionary)
## At login: every resource node that is empty right now.
signal nodes_depleted(depleted_ids: Array)
## A node emptied (true) or came back (false).
signal node_state(node_id: int, depleted: bool)
signal craft_result(recipe_id: String, ok: bool, text: String)

# --- protocol v5, carried by Net/Play: who is online, and getting home ---
## Who is online, for the players panel: [{id, name}, ...] sorted by name. Sent at login and
## when anyone joins or leaves. (Servers before 2026-11-26 also sent a total skill `level`.)
signal roster_changed(entries: Array)
## A player asked to go back to Spawn Meadow (the Esc menu's "Return to Spawn Meadow").
signal unstuck_requested(peer_id: int)
## The answer: ok (you are at spawn now) or why not, and the seconds until you can ask again.
signal unstuck_result(ok: bool, text: String, wait_seconds: float)

# --- protocol v6, carried by Net/Play: the wildlife outside the meadow ---
## The grazers within GameConfig.VIEW_RANGE of you, about 5 times a second: a PackedFloat32Array
## of [id, x, z, yaw, state_index] per creature (Wildlife.to_wire; y from Terrain.height, state
## names in Wildlife.STATES). An empty one means the last one just left your view.
signal wildlife_changed(entries: PackedFloat32Array)

# --- protocol v7, carried by Net/Play: health, stamina and the first swing ---
## A player swings: kind "light" or "heavy", facing yaw.
signal attack_requested(peer_id: int, kind: String, yaw: float)
## Your health and stamina, whole points: at login and on every change.
signal vitals_changed(hp: int, max_hp: int, stamina: int, max_stamina: int)
## Someone in view (maybe you) started a swing of `seconds` with `weapon`.
signal swing_begun(peer_id: int, weapon: String, kind: String, seconds: float)
## That swing's blow landed on these grazer ids (empty: a whiff, sent only to the swinger).
signal swing_landed(peer_id: int, kind: String, creature_ids: Array)
## Your swing was refused: "busy", "winded", "tired", "dead" or "unknown".
signal attack_refused(kind: String, reason: String)

# --- protocol v8, carried by Net/Play: character customization ---
## A player saved a new look (Appearance) from the character-creation window.
signal look_requested(peer_id: int, look: Dictionary)
## peer_id's look ({} = never chosen: draw them from their appearance seed).
signal look_changed(peer_id: int, look: Dictionary)

# --- protocol v9, carried by Net/Play: the world config, placed campfires ---
## The world the server runs: {seed, size_m, gen_version} (WorldGen.config). Once, after login.
signal world_config(config: Dictionary)
## A player wants to set `item` (today "campfire") down in front of them.
signal place_requested(peer_id: int, item: String)
## The answer to that: ok, or why not (a Campfires.REFUSALS key) and the line to show.
signal place_result(item: String, ok: bool, reason: String, text: String)
## Every campfire burning: [id, x, y, z, seconds_left] per fire (Campfires.to_wire).
signal campfires_changed(entries: PackedFloat32Array)

# --- protocol v10, carried by Net/Play: the Gloam walkers ---
## The walkers within GameConfig.VIEW_RANGE of you, about 5 times a second: a
## PackedFloat32Array of [id, x, z, yaw, state_index, windup_left] per walker (Gloam.to_wire;
## y from Terrain.height, state names in Gloam.STATES). windup_left is the seconds until a
## raised grab closes ("grab" state), else 0. An empty one means the last one left your view.
signal gloam_changed(entries: PackedFloat32Array)
## peer_id's blow landed on these walker ids; `downed` are the ones it put down for good.
signal gloam_struck(peer_id: int, kind: String, walker_ids: Array, downed: Array)

var last_ack_seq := -1
var play: Node


func _ready() -> void:
	play = PlayScript.new()
	play.name = "Play"
	add_child(play)


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
## ack_seq: the last c2s_input seq the server applied for the receiving player (v3), so the
## client can replay its newer inputs on top of the server's position.
@rpc("authority", "call_remote", "unreliable_ordered")
func s2c_snapshot(tick: int, entries: Array, ack_seq: int) -> void:
	last_ack_seq = ack_seq
	snapshot_ack.emit(ack_seq)
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

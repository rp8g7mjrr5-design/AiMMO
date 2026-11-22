extends SceneTree
## A stand-in for a player who has not updated their game. It builds the same
## /root/Main/Net node a real client has, but from an older copy of net.gd (so its RPC set
## can differ from the server's), connects, logs in with an older protocol number, and
## writes what happened to a JSON file. run_protocol_test.py judges the result.
##
## Args (after --): --net=res://tests/protocol/net_v1.gd --protocol=1 --name=old_1
##   --password=... --address=127.0.0.1:7777 --transport=enet --timeout=15 --result=/path.json

var _args := {}
var _net: Node
var _t := 0.0
var _timeout := 15.0
var _connected_at := -1.0
var _result := {"connected": false, "got_reply": false, "ok": false, "message": "",
	"reply_seconds": -1.0, "server_dropped_us": false, "rpcs_before_reply": []}
var _done := false


var _started := false


func _start() -> void:
	_started = true
	_args = CliArgs.parse(OS.get_cmdline_user_args())
	_timeout = float(_args.get("timeout", "15"))
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	var script: Script = load(str(_args.get("net", "res://shared/net.gd")))
	_net = script.new()
	_net.name = "Net"
	main.add_child(_net)
	_net.login_result.connect(_on_login_result)
	# Anything else the server sends before the login reply is a sign it treated us as logged in.
	for sig in ["player_joined", "snapshot", "chat_message", "system_message"]:
		if _net.has_signal(sig):
			_net.connect(sig, func(_a = null, _b = null, _c = null): _note(sig))
	var parsed := Transport.parse_address(str(_args.get("address", "127.0.0.1:%d" % GameConfig.DEFAULT_PORT)), str(_args.get("transport", "enet")))
	var made := Transport.create_client(parsed[0], parsed[1], parsed[2])
	if made[1] != OK:
		_result.message = "could not create client: " + error_string(made[1])
		_finish()
		return
	get_multiplayer().multiplayer_peer = made[0]
	get_multiplayer().connected_to_server.connect(_on_connected)
	get_multiplayer().connection_failed.connect(func(): _result.message = "connection failed"; _finish())
	get_multiplayer().server_disconnected.connect(func(): _result.server_dropped_us = true; _finish())


func _on_connected() -> void:
	_result.connected = true
	_connected_at = _t
	_net.c2s_login.rpc_id(1, int(_args.get("protocol", "1")), str(_args.get("name", "old_1")), str(_args.get("password", "old-password")))


func _note(sig: String) -> void:
	if not _result.got_reply and sig not in _result.rpcs_before_reply:
		_result.rpcs_before_reply.append(sig)


func _on_login_result(ok: bool, message: String, _id: int, _character: Dictionary) -> void:
	if _result.got_reply:
		return
	_result.got_reply = true
	_result.ok = ok
	_result.message = message
	_result.reply_seconds = _t - _connected_at
	_finish()


func _process(delta: float) -> bool:
	if not _started:
		_start()  # the multiplayer API is not ready yet in _initialize
		return _done
	_t += delta
	if not _done and _t > _timeout:
		if _result.message == "":
			_result.message = "no reply within %.0fs" % _timeout
		_finish()
	return _done


func _finish() -> void:
	if _done:
		return
	_done = true
	var path := str(_args.get("result", ""))
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(_result, "  "))
		f.close()
	print("[old-client] ", JSON.stringify(_result))
	if get_multiplayer().multiplayer_peer != null:
		get_multiplayer().multiplayer_peer.close()

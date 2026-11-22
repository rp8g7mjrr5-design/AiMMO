class_name Transport
## Builds the MultiplayerPeer. ENet (UDP) is the default. WebSocket (TCP) carries the same
## high-level multiplayer API and is used where UDP is not available (see devlog week 00).


static func create_server(kind: String, port: int) -> Array:
	if kind == "websocket":
		var ws := WebSocketMultiplayerPeer.new()
		var err := ws.create_server(port)
		return [ws, err]
	var enet := ENetMultiplayerPeer.new()
	var e := enet.create_server(port, 256)
	return [enet, e]


static func create_client(kind: String, host: String, port: int) -> Array:
	if kind == "websocket":
		var ws := WebSocketMultiplayerPeer.new()
		var scheme := "ws://"
		var err := ws.create_client("%s%s:%d" % [scheme, host, port])
		return [ws, err]
	var enet := ENetMultiplayerPeer.new()
	var e := enet.create_client(host, port)
	return [enet, e]


## Splits "host:port" (or "ws://host:port" / "enet://host:port") into [kind, host, port].
static func parse_address(addr: String, default_kind: String) -> Array:
	var kind := default_kind
	var a := addr.strip_edges()
	if a.begins_with("ws://"):
		kind = "websocket"
		a = a.substr(5)
	elif a.begins_with("enet://"):
		kind = "enet"
		a = a.substr(7)
	var port := GameConfig.DEFAULT_PORT
	var colon := a.rfind(":")
	if colon != -1:
		port = a.substr(colon + 1).to_int()
		a = a.substr(0, colon)
	if a == "":
		a = "127.0.0.1"
	return [kind, a, port]

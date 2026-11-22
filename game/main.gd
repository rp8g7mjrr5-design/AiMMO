extends Node
## Entry point. Picks a role from the command line and builds the matching node tree.
## Every role creates the same `Net` child so RPC node paths match on all peers.

const NetScript := preload("res://shared/net.gd")


func _ready() -> void:
	var args := CliArgs.parse(OS.get_cmdline_user_args())
	var net: Node = NetScript.new()
	net.name = "Net"
	add_child(net)

	var role: Node
	if args.has("server") or DisplayServer.get_name() == "headless" and not args.has("bot"):
		role = load("res://server/server.gd").new()
	elif args.has("bot"):
		role = load("res://tests/bot_test/bot.gd").new()
	else:
		role = load("res://client/client.gd").new()
	role.name = "Role"
	add_child(role)
	role.call("start", net, args)

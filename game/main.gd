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
	var updates := false
	if args.has("server") or DisplayServer.get_name() == "headless" and not args.has("bot"):
		role = load("res://server/server.gd").new()
	elif args.has("bot"):
		role = load("res://tests/bot_test/bot.gd").new()
	else:
		updates = Updater.enabled(args)
		if updates and not args.has(Updater.UPDATED_FLAG):
			# Installed game: fetch the newest build first. It may restart into it and quit.
			var updater := Updater.new(args)
			add_child(updater)
			await updater.done
		role = load("res://client/client.gd").new()
	role.name = "Role"
	add_child(role)
	role.call("start", net, args)
	if updates:
		# The game got this far on this build, so it is safe to boot into again.
		get_tree().create_timer(8.0).timeout.connect(Updater.mark_running_ok)

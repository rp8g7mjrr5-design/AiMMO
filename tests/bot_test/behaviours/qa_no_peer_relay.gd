extends "res://tests/bot_test/bot_behaviour.gd"
## QA: the server must not relay peers to each other. Clients only talk to the server, so a
## bot should only ever know peer 1. With SceneMultiplayer's server_relay on, every client
## also learns every other client's peer id, and the server's relay notices to half-closed
## ENet peers logged "Unable to send packet on channel 0, max channels: 0" (a CI flake).

var _checks := 0
var _max_peers := 0
var _failed := false


func on_play(_delta: float) -> void:
	var mp: MultiplayerAPI = bot.multiplayer
	if mp == null or mp.multiplayer_peer == null:
		return
	var peers := mp.get_peers()
	_checks += 1
	_max_peers = maxi(_max_peers, peers.size())
	for p in peers:
		if p != 1 and not _failed:
			_failed = true
			fail("client was told about another client (peer %d): server relay is on" % p)
			return


func on_finish() -> void:
	stat("peer_checks", _checks)
	stat("max_known_peers", _max_peers)

extends TestCase
## The player cap (owner direction 8, ZombAi Phase 1): a world for 2 to 8 friends. MAX_PLAYERS
## (or --max-players) caps how many are logged in at once; unset means no cap. A login past
## the cap is refused politely and never kicks anyone who is already in.

const ServerScript := preload("res://server/server.gd")


func _server(cap: int) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.max_players = cap
	var st := JsonStore.new()
	st.path = "user://test_player_cap_%d/players.json" % Time.get_ticks_usec()
	st.open()
	srv.store = st
	return srv


func _connect_and_login(srv: Node, id: int, char_name: String) -> void:
	srv._on_peer_connected(id)
	srv._on_login(id, GameConfig.PROTOCOL_VERSION, char_name, "hunter22pass")


func _last_login(srv: Node, id: int) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == "s2c_login_result":
			out = m[2]
	return out


func test_parse_max_players() -> void:
	check_eq(ServerScript.parse_max_players(""), 0, "unset: no cap")
	check_eq(ServerScript.parse_max_players("8"), 8)
	check_eq(ServerScript.parse_max_players(" 4 "), 4, "spaces are fine")
	check_eq(ServerScript.parse_max_players("0"), 0, "0: no cap")
	check_eq(ServerScript.parse_max_players("-3"), 0, "negative: no cap, never a lockout")
	check_eq(ServerScript.parse_max_players("eight"), 0, "junk: no cap, never a lockout")


func test_the_ninth_friend_is_turned_away_politely() -> void:
	var srv := _server(8)
	for i in 8:
		_connect_and_login(srv, 10 + i, "Friend%s" % char(65 + i))
		check(bool(_last_login(srv, 10 + i)[0]), "friend %d gets in" % (i + 1))
	check_eq(srv.players_online(), 8)
	_connect_and_login(srv, 99, "Latecomer")
	var r := _last_login(srv, 99)
	check(not bool(r[0]), "the ninth is refused")
	check_eq(r[1], "The world is full (8 / 8). Try again soon.")
	check_eq(srv.players_online(), 8, "nobody was kicked")
	check(not srv.sessions[99].logged_in, "the latecomer is still at the login screen")
	check_eq(srv.store.find_account("latecomer"), {}, "no account made for a refused login")
	srv.free()


func test_a_seat_opens_when_someone_leaves() -> void:
	var srv := _server(2)
	_connect_and_login(srv, 1, "Ash")
	_connect_and_login(srv, 2, "Bram")
	_connect_and_login(srv, 3, "Cole")
	check(not bool(_last_login(srv, 3)[0]), "full at 2 / 2")
	srv._on_peer_disconnected(2)
	srv._on_login(3, GameConfig.PROTOCOL_VERSION, "Cole", "hunter22pass")
	check(bool(_last_login(srv, 3)[0]), "Cole gets Bram's seat on the next try")
	srv.free()


func test_a_peer_at_the_login_screen_takes_no_seat() -> void:
	var srv := _server(1)
	srv._on_peer_connected(5) # connected, never logs in
	_connect_and_login(srv, 6, "Ash")
	check(bool(_last_login(srv, 6)[0]), "a connected-but-not-logged-in peer doesn't count")
	srv.free()


func test_no_cap_by_default() -> void:
	var srv := _server(0)
	for i in 10:
		_connect_and_login(srv, 20 + i, "Bot%s" % char(65 + i))
	check_eq(srv.players_online(), 10, "unset: the bot test's extra bots all get in")
	check(not srv.is_world_full(), "never full without a cap")
	srv.free()


func test_an_old_client_hears_about_the_update_first() -> void:
	var srv := _server(1)
	_connect_and_login(srv, 1, "Ash")
	srv._on_peer_connected(2)
	srv._on_login(2, GameConfig.PROTOCOL_VERSION - 1, "Bram", "hunter22pass")
	check(String(_last_login(srv, 2)[1]).contains("out of date"), "the update message wins over the cap")
	srv.free()


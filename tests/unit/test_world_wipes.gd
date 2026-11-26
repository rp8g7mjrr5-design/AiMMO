extends TestCase
## World stream: monthly wipes (owner, 2026-11-26: "lets do monthly", automatic). The first
## Thursday of every month at 19:00 UTC a wiping server rolls a new island; packs are emptied
## (and archived, never deleted) the next time each player logs in, and looks stay.
## Ashgrove and any server without AIMMO_WIPE=monthly never wipe.

const ServerScript := preload("res://server/server.gd")
const ISLAND := {"seed": 31, "size_m": 1500.0, "gen_version": 2}


func _unix(y: int, mo: int, d: int, h: int = 0, mi: int = 0) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": h, "minute": mi, "second": 0}))


func test_the_first_thursday_of_every_month_at_seven_pm_utc() -> void:
	check_eq(WipeSchedule.next_after(_unix(2026, 11, 26, 12)), _unix(2026, 12, 3, 19), "after today: Thursday 3 December")
	check_eq(WipeSchedule.next_after(_unix(2026, 12, 3, 18, 59)), _unix(2026, 12, 3, 19), "a minute before")
	check_eq(WipeSchedule.next_after(_unix(2026, 12, 3, 19)), _unix(2027, 1, 7, 19), "at the wipe, the next one is in January")
	check_eq(WipeSchedule.next_after(_unix(2026, 11, 1)), _unix(2026, 11, 5, 19), "November 2026 starts on a Sunday")
	check_eq(WipeSchedule.next_after(_unix(2027, 4, 1, 20)), _unix(2027, 5, 6, 19), "1 April 2027 is a Thursday, past 19:00 it's May's")
	check_eq(WipeSchedule.next_after(_unix(2027, 4, 1, 10)), _unix(2027, 4, 1, 19), "and before 19:00 it's that day")
	var t := _unix(2026, 1, 1)
	for i in 40:
		t = WipeSchedule.next_after(t)
		var d := Time.get_datetime_dict_from_unix_time(t)
		check(int(d.weekday) == 4 and int(d.day) <= 7 and int(d.hour) == 19 and int(d.minute) == 0, "a first Thursday, 19:00 (%s)" % WipeSchedule.describe(t))
	check_eq(WipeSchedule.describe(_unix(2026, 12, 3, 19)), "Thursday 3 December, 19:00 UTC")
	check_eq(WipeSchedule.next_after(_unix(2026, 11, 26), WipeSchedule.NEVER), 0, "never is never")
	check_eq(WipeSchedule.parse(" Monthly "), WipeSchedule.MONTHLY)
	check_eq(WipeSchedule.parse(""), WipeSchedule.NEVER, "unset is never")
	check_eq(WipeSchedule.parse("weekly"), WipeSchedule.NEVER, "anything else is never")
	check_eq(WipeSchedule.countdown(6 * 86400 + 5), "in 6 days")
	check_eq(WipeSchedule.countdown(30), "in under a minute")


func _store() -> JsonStore:
	var st := JsonStore.new()
	st.path = "user://test_wipes_%d/players.json" % Time.get_ticks_usec()
	st.open()
	return st


func _server(st: PlayerStore, unix: int) -> Node:
	var srv: Node = ServerScript.new()
	srv.test_now = 100.0
	srv.test_unix = unix
	srv.store = st
	srv.use_world(ISLAND)
	srv.start_wipes(WipeSchedule.MONTHLY, ISLAND)
	return srv


func _login(srv: Node, id: int, name: String) -> Dictionary:
	srv._on_peer_connected(id)
	srv._on_login(id, GameConfig.PROTOCOL_VERSION, name, "hunter22pass")
	return srv.sessions[id].character


func _texts(srv: Node, id: int) -> Array:
	var out: Array = []
	for m in srv.test_outbox:
		if m[0] == id and m[1] == "s2c_system":
			out.append(m[2][0])
	return out


func _done(srv: Node) -> void:
	srv.use_world(WorldGen.parse(""))
	srv.free()


func test_the_store_keeps_every_world() -> void:
	var st := _store()
	check(st.current_world().is_empty(), "no world before the first")
	var a := st.begin_world(ISLAND, 1000)
	check_eq([a.seed, a.gen_version, a.size_m, a.wipes_at], [31, 2, 1500.0, 1000])
	var b := st.begin_world({"seed": 99, "size_m": 1500.0, "gen_version": 2}, 2000)
	check(b.id != a.id, "a new id")
	check_eq(st.current_world(), b, "the newest is current")
	check_eq(st._data.worlds.size(), 2, "the old one is kept")
	check(int(st._data.worlds[0].wiped_at) > 0, "and marked wiped")
	var re := JsonStore.new()
	re.path = st.path
	re.open()
	check_eq(re.current_world(), b, "it survives a restart")


func test_a_server_without_wipes_is_unchanged() -> void:
	var st := _store()
	var srv: Node = ServerScript.new()
	srv.test_unix = _unix(2026, 11, 26)
	srv.store = st
	srv.start_wipes(WipeSchedule.NEVER, ISLAND)
	check(srv.world_record.is_empty(), "never: no world record")
	srv.start_wipes(WipeSchedule.MONTHLY, WorldGen.parse(""))
	check(srv.world_record.is_empty(), "Ashgrove never wipes, even when asked")
	check(st.current_world().is_empty(), "and the store wasn't touched")
	srv._on_peer_connected(1)
	srv._on_login(1, GameConfig.PROTOCOL_VERSION, "Fern", "hunter22pass")
	for t in _texts(srv, 1):
		check(not str(t).contains("wipes"), "no wipe notice")
	srv.free()


func test_a_monthly_wipe_end_to_end() -> void:
	var st := _store()
	var now := _unix(2026, 11, 26, 12)
	var srv := _server(st, now)
	check(not srv.world_record.is_empty(), "a world record")
	check_eq(int(srv.world_record.seed), 31, "the first world keeps the owner's seed")
	check_eq(int(srv.world_record.wipes_at), _unix(2026, 12, 3, 19), "and ends on the first Thursday")
	var fern := _login(srv, 1, "Fern")
	var moss := _login(srv, 2, "Moss")
	check(_texts(srv, 1).any(func(t): return str(t).contains("Thursday 3 December, 19:00 UTC")), "a newcomer is told when the island wipes")
	check_eq(int(fern.world_id), int(srv.world_record.id), "and is on this world")
	fern.inventory = {"stone": 12, "torch": 1}
	fern.look = Appearance.DEFAULT.duplicate()
	fern.look.hair = 2
	moss.inventory = {"stone": 3}
	var old_seed := int(srv.world_record.seed)
	var old_id := int(srv.world_record.id)

	# Warnings at 60, 10 and 1 minutes, once each.
	srv.test_outbox.clear()
	srv._tick_wipe(int(srv.world_record.wipes_at) - 59 * 60)
	srv._tick_wipe(int(srv.world_record.wipes_at) - 58 * 60)
	srv._tick_wipe(int(srv.world_record.wipes_at) - 9 * 60)
	srv._tick_wipe(int(srv.world_record.wipes_at) - 30)
	check_eq(_texts(srv, 1), [WipeSchedule.warning(60), WipeSchedule.warning(10), WipeSchedule.warning(1)], "three warnings")

	# The wipe.
	srv.test_outbox.clear()
	var at := int(srv.world_record.wipes_at)
	srv.test_unix = at + 2
	srv._tick_wipe(at + 2)
	check(_texts(srv, 1).has(ServerScript.WIPE_TEXT), "everyone is told why they're sent off")
	check(srv.sessions.is_empty(), "and sent off")
	check(int(srv.world_record.seed) != old_seed, "a new seed")
	check_eq(int(srv.world_record.wipes_at), _unix(2027, 1, 7, 19), "next wipe in January")
	check_eq(WorldGen.config().seed, srv.world_record.seed, "the server runs the new island")
	var saved := st.find_character_by_name("Fern")
	check_eq(int(saved.inventory.stone), 12, "nothing is cleared before they come back")

	# Fern comes back: pack archived and emptied, look kept, on a beach.
	srv.test_outbox.clear()
	var back := _login(srv, 3, "Fern")
	check_eq(Inventory.count(back.inventory, "stone"), 0, "the pack is empty")
	check_eq(Inventory.count(back.inventory, "torch"), 0)
	check(back.inventory.has("stone"), "its rows stay (qty 0), never deleted")
	check_eq(int(back.look.hair), 2, "the look stays")
	check_eq(int(back.world_id), int(srv.world_record.id), "on the new world")
	var on_beach := false
	for q in WorldGen.landings():
		if Vector2(back.x, back.z).distance_to(q) < 1.0:
			on_beach = true
	check(on_beach, "washed up on a beach")
	check(_texts(srv, 3).has(ServerScript.WASHED_UP_TEXT), "and told so")
	var arch := st.wipe_archive(int(back.id))
	check_eq(arch.size(), 1, "the old pack is archived")
	check_eq(int(arch[0].world_id), old_id)
	check_eq(int(arch[0].inventory.stone), 12)
	check_eq(int(arch[0].inventory.torch), 1)
	check_eq(int(st.find_character_by_name("Fern").inventory.stone), 0, "and the empty pack is saved")

	# Logging in again on the same world changes nothing.
	srv._on_peer_disconnected(3)
	var again := _login(srv, 4, "Fern")
	check_eq(st.wipe_archive(int(again.id)).size(), 1, "archived once")
	_done(srv)


func test_a_restart_keeps_the_world_until_it_is_due() -> void:
	var st := _store()
	var srv := _server(st, _unix(2026, 11, 26))
	var first: Dictionary = srv.world_record.duplicate()
	srv.free()
	var again := _server(st, _unix(2026, 12, 1))
	check_eq(again.world_record, first, "a restart before the wipe keeps the island")
	again.free()
	var late := _server(st, _unix(2026, 12, 4))
	check(int(late.world_record.id) != int(first.id), "a server that was down at wipe time wipes when it boots")
	check(int(late.world_record.seed) != int(first.seed), "with a new seed")
	_done(late)


func test_postgres_keeps_worlds_and_archives() -> void:
	if not has_db():
		return
	var st := PgStore.new()
	st.url = OS.get_environment("DATABASE_URL")
	st.migrations_dir = Migrator.default_dir()
	check(st.open(), "opens: " + st.last_error)
	var a := st.begin_world(ISLAND, 1000)
	var b := st.begin_world({"seed": 77, "size_m": 3000.0, "gen_version": 2}, 2000)
	check(int(b.id) > int(a.id), "a new world row")
	check_eq(st.current_world(), b, "the newest is current")
	check_eq([b.seed, b.gen_version, b.size_m, b.wipes_at], [77, 2, 3000.0, 2000])
	var name := "wipe%d" % (Time.get_ticks_usec() % 1000000)
	var acc := st.create_account(name, name, "h")
	var ch := st.load_or_create_character(acc)
	ch.inventory = {"stone": 4}
	ch.world_id = int(a.id)
	check(st.save_character(ch), "saved: " + st.last_error)
	check_eq(int(st.find_character_by_name(name).world_id), int(a.id), "world_id is stored")
	check(WorldWipe.on_login(st, ch, b), "wiped on the next world")
	check(st.save_character(ch), "saved again")
	var back := st.find_character_by_name(name)
	check_eq(Inventory.count(back.inventory, "stone"), 0, "empty pack")
	check_eq(int(back.world_id), int(b.id))
	var arch := st.wipe_archive(int(ch.id))
	check_eq(arch.size(), 1, "archived")
	check_eq(int(arch[0].inventory.stone), 4)
	check_eq(int(arch[0].world_id), int(a.id))
	st.close()
	WorldGen.reset()

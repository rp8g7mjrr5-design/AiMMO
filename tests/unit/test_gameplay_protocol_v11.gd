extends TestCase
## Protocol v11: no new RPCs. The official world moved onto a 3 km island (owner, 2026-11-26),
## and only clients that build whatever world s2c_world names can play it; clients before this
## always drew Ashgrove, so they are told to update instead of walking on the wrong ground.

const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")


func test_v11_adds_no_rpcs() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 11, "v11 or later")
	if GameConfig.PROTOCOL_VERSION == 11:
		check_eq(ProtocolCompat.rpc_names("res://shared/net_play.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_play_v10.gd"), "Play unchanged since v10")
		check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v10.gd"), "Net unchanged since v10")


func test_the_official_world_is_a_wiping_island() -> void:
	var docker := FileAccess.get_file_as_string("res://../Dockerfile")
	if docker == "":
		return # not in a checkout (the server image has no Dockerfile)
	var cfg := WorldGen.parse(_env(docker, "AIMMO_WORLD"))
	check_eq(int(cfg.gen_version), WorldGen.ISLAND, "the live world is an island")
	check_eq(float(cfg.size_m), 3000.0, "3 km")
	check_eq(WipeSchedule.parse(_env(docker, "AIMMO_WIPE")), WipeSchedule.MONTHLY, "that wipes monthly")
	check(WorldWipe.enabled(WipeSchedule.MONTHLY, cfg), "and wipes are on for it")


func _env(docker: String, key: String) -> String:
	var re := RegEx.create_from_string(key + "=(\\S+)")
	var m := re.search(docker)
	return m.get_string(1) if m != null else ""

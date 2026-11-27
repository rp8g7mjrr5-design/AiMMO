extends TestCase
## Protocol v13: the grid pack on Net/Play (c2s_pack_move, c2s_pack_drop, s2c_pack). Net's
## own list is unchanged.

const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")


func test_v13_adds_the_pack_rpcs_only() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 13, "v13 or later")
	if GameConfig.PROTOCOL_VERSION != 13:
		return
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v12.gd"), "Net unchanged since v12")
	var now := Array(ProtocolCompat.rpc_names("res://shared/net_play.gd"))
	var was := Array(ProtocolCompat.rpc_names("res://tests/protocol/net_play_v12.gd"))
	for rpc in ["c2s_pack_move", "c2s_pack_drop", "s2c_pack"]:
		check(now.has(rpc), "%s is on Play" % rpc)
		now.erase(rpc)
	check_eq(now, was, "and nothing else changed on Play")


func test_places_go_over_the_wire_as_plain_arrays() -> void:
	var places := PackGrid.places_of(PackGrid.layout({"stone": 3, "ash_wood": 25}, []))
	for p in places:
		check_eq(typeof(p), TYPE_ARRAY, "a place is a plain array")
		check_eq((p as Array).size(), 5, "[item, index, x, y, turned]")
	check_eq(PackGrid.normalize(places), places, "and comes back the same")

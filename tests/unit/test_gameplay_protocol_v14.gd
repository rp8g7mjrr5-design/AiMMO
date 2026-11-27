extends TestCase
## Protocol v14: no new RPCs. Thirst (step 3 of the owner's survival plan) rides in the existing
## s2c_needs Dictionary and the drink in c2s_place("drink"), but a client without the thirst
## mark and the drink key would go thirsty with nothing on screen, so older clients are told to
## update.

const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")


func test_v14_adds_no_rpcs() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 14, "v14 or later")
	if GameConfig.PROTOCOL_VERSION != 14:
		return
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v13.gd"), "Net unchanged since v13")
	check_eq(ProtocolCompat.rpc_names("res://shared/net_play.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_play_v13.gd"), "Play unchanged since v13")


func test_needs_carry_thirst() -> void:
	var wire := Needs.to_wire({"hunger": 80.0, "thirst": 40.0})
	check_eq(wire, {"hunger": 80, "thirst": 40})

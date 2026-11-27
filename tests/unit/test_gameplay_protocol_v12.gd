extends TestCase
## Protocol v12: s2c_needs on Net/Play carries the survival needs ({"hunger": 0..100} today),
## and c2s_place also takes "eat" (or a food's id) and "cook". Net's own list is unchanged.

const ProtocolCompat := preload("res://tests/unit/test_qa_protocol_compat.gd")


func test_v12_adds_s2c_needs_only() -> void:
	check(GameConfig.PROTOCOL_VERSION >= 12, "v12 or later")
	if GameConfig.PROTOCOL_VERSION != 12:
		return
	check_eq(ProtocolCompat.rpc_names("res://shared/net.gd"), ProtocolCompat.rpc_names("res://tests/protocol/net_v11.gd"), "Net unchanged since v11")
	var now := Array(ProtocolCompat.rpc_names("res://shared/net_play.gd"))
	var was := Array(ProtocolCompat.rpc_names("res://tests/protocol/net_play_v11.gd"))
	check(now.has("s2c_needs"), "s2c_needs is on Play")
	now.erase("s2c_needs")
	check_eq(now, was, "and nothing else changed on Play")


func test_needs_go_over_the_wire_as_a_dictionary() -> void:
	var wire := Needs.to_wire({"hunger": 72.4})
	check_eq(int(wire.hunger), 72)
	check_eq(typeof(wire), TYPE_DICTIONARY, "room for thirst, warmth and rest without another bump")

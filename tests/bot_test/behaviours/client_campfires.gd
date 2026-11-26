extends "res://tests/bot_test/bot_behaviour.gd"
## Client: campfires on screen and the place ghost (B), on a real server. Every bot runs the
## client's own reading of each s2c_campfires it gets (PlaceGhost.fires_from_wire, as client.gd
## does before it draws them) and checks what the player would get:
## - every fire on the wire reads back whole (none lost, none doubled, ids unique);
## - the place ghost (PlaceGhost.reason_at, the client's copy of the spot rules) is red on
##   top of every fire it was sent, so nobody is invited to stack a fire on a fire.
## Drawing is checked in unit tests (test_client_place_ghost, test_world_campfire_props): bot
## behaviours stay art-free (art bible section 7). The fire comes from gameplay_campfires'
## /kindle (bot *_5); gameplay_world_v9 requires it to reach every bot, so a run with no fire
## is counted here, not failed.

var updates := 0
var most := 0
var ghost_checks := 0


func setup(net: Node) -> void:
	net.campfires_changed.connect(_on_campfires)


func _on_campfires(entries: PackedFloat32Array) -> void:
	updates += 1
	var fires := PlaceGhost.fires_from_wire(entries)
	most = maxi(most, fires.size())
	if fires.size() != entries.size() / 5:
		fail("%d floats on the wire read back as %d fires" % [entries.size(), fires.size()])
	var ids := {}
	for f in fires:
		if ids.has(int(f.id)):
			fail("fire %d is on the wire twice" % int(f.id))
		ids[int(f.id)] = true
		ghost_checks += 1
		if PlaceGhost.reason_at(fires, f.pos) == "":
			fail("the place ghost would let a fire go on top of fire %d" % int(f.id))


func on_finish() -> void:
	stat("updates", updates)
	stat("most_fires", most)
	stat("ghost_checks", ghost_checks)

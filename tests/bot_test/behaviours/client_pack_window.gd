extends "res://tests/bot_test/bot_behaviour.gd"
## Client: the pack window (I). Network-only (art bible section 7: no window is built). Each
## bot keeps the pack the server sends (the login character's inventory, then every
## s2c_inventory), as the client's PackWindow does, and checks on every update:
## - the window's slots are exactly the stacks the server holds, in a stable order, with the
##   server's counts, none over a full stack and no item twice;
## - the header total adds up to the slots, and the grid always has room for every slot;
## - a stack that rose is what the window lights gold ("+N" equal to the rise).

const PackScript := preload("res://client/pack_window.gd")

var _pack := {}
var _known := false
var _updates := 0
var _glows := 0


func setup(net: Node) -> void:
	net.inventory_changed.connect(_on_inventory)


func on_login(_reconnect: bool, character: Dictionary) -> void:
	_pack = Inventory.to_wire(Inventory.normalize(character.get("inventory", {})))
	_known = true
	_check(_pack)


func _on_inventory(items: Dictionary) -> void:
	var fresh := Inventory.to_wire(Inventory.normalize(items))
	_updates += 1
	if _known:
		var up: Dictionary = PackScript.gained(_pack, fresh)
		for item in up:
			if Inventory.count(fresh, item) - Inventory.count(_pack, item) != int(up[item]):
				fail("glow on %s says +%d" % [item, int(up[item])])
		_glows += up.size()
	_pack = fresh
	_known = true
	_check(fresh)


func _check(inv: Dictionary) -> void:
	var slots: Array = PackScript.slots(inv)
	var seen := {}
	var sum := 0
	for s in slots:
		var item := str(s.item)
		if seen.has(item):
			fail("%s shows twice in the pack window" % item)
		seen[item] = true
		if int(s.count) != Inventory.count(inv, item) or int(s.count) <= 0:
			fail("slot %s shows %d, server says %d" % [item, int(s.count), Inventory.count(inv, item)])
		if int(s.count) > Inventory.MAX_STACK:
			fail("slot %s holds %d, over a full stack" % [item, int(s.count)])
		sum += int(s.count)
	for item in inv:
		if Inventory.count(inv, item) > 0 and not seen.has(str(item)):
			fail("server pack has %s but the window has no slot for it" % item)
	if slots.size() > PackScript.slot_count(slots.size()):
		fail("%d stacks but only %d slots" % [slots.size(), PackScript.slot_count(slots.size())])
	var want := "Empty" if sum == 0 else "%d item%s" % [sum, "" if sum == 1 else "s"]
	if PackScript.total_text(inv) != want:
		fail("pack header %s, slots add up to %s" % [PackScript.total_text(inv), want])


func on_finish() -> void:
	stat("updates", _updates)
	stat("glows", _glows)

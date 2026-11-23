extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): procedural item icons.
##
## At every login the bot draws the icon for every item in its pack (whatever ids the
## server sends, including ones the client may not know) and for every item in
## Inventory.ITEMS, the way the inventory window and the gather toast will, and checks each
## one is a real picture: the right size, something drawn, nothing clipped at the edge, and
## its own icon rather than the fallback bundle for known items. Small (24 px) to stay cheap.

const SIZE := 24

var drawn := 0
var pack_items := 0


func on_login(_reconnect: bool, character: Dictionary) -> void:
	var ids := {}
	for item in Inventory.ITEMS:
		ids[item] = true
	var pack = character.get("inventory", {})
	if typeof(pack) == TYPE_DICTIONARY:
		for item in pack:
			ids[str(item)] = true
			pack_items += 1
	for item in ids:
		_check(item)


func _check(item: String) -> void:
	var tex := ItemIcons.texture(item, SIZE)
	if tex == null or tex.get_width() != SIZE:
		fail("no %d px icon for %s" % [SIZE, item])
		return
	var img := ItemIcons.image(item, SIZE)
	var solid := 0
	var edge := 0.0
	for y in SIZE:
		for x in SIZE:
			var a := img.get_pixel(x, y).a
			if a > 0.5:
				solid += 1
			if x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1:
				edge = maxf(edge, a)
	if solid < SIZE * SIZE / 10:
		fail("icon for %s is nearly empty (%d px)" % [item, solid])
	if edge > 0.2:
		fail("icon for %s is clipped at the edge" % item)
	if Inventory.is_item(item) and not ItemIcons.has_icon(item):
		fail("known item %s fell back to the bundle" % item)
	drawn += 1


func on_finish() -> void:
	stat("icons_drawn", drawn)
	stat("pack_items_seen", pack_items)
	if drawn < Inventory.ITEMS.size():
		fail("drew only %d icons" % drawn)

extends "res://tests/bot_test/bot_behaviour.gd"
## Client: item icons on a real server. Each bot starts the client's IconShelf thread at
## launch, exactly as the client does, and keeps a GatherPrompt fed with s2c_inventory and
## s2c_gather_result, as the client does.
## Checks, without sending anything of its own:
## - the shelf finishes drawing every icon while the bot is still logging in or playing (and
##   reports how long it took, so a slow icon change shows up here before players feel it);
## - every gather result the server sends becomes a toast with that item's own icon (never
##   the fallback bundle), at toast size, straight from the shelf.

const PromptScript := preload("res://client/gather_prompt.gd")
const ShelfScript := preload("res://client/icon_shelf.gd")

var _shelf: RefCounted
var _w: Control
var _started_ms := 0
var _ready_ms := -1
var iconed_toasts := 0


func setup(net: Node) -> void:
	_started_ms = Time.get_ticks_msec()
	_shelf = ShelfScript.new()
	_shelf.start()
	_w = PromptScript.new()
	_w.setup(Theme.new())
	_w.icons = _shelf
	net.inventory_changed.connect(func(items: Dictionary): _w.pack = items)
	net.gather_result.connect(_on_result)


func on_play(_delta: float) -> void:
	if _ready_ms < 0 and _shelf.ready_count() >= ShelfScript.wanted().size():
		_ready_ms = Time.get_ticks_msec() - _started_ms


func _on_result(item: String, count: int) -> void:
	if _w == null:
		return
	_w.on_result(item, count)
	if item == "" or not ItemIcons.has_icon(item):
		fail("gather toast has no icon of its own: %s" % item)
		return
	if _w.toast_item() != item:
		fail("toast for %s shows the %s icon" % [item, _w.toast_item()])
	var tex: Texture2D = _w.toast_icon.texture
	if tex == null or tex.get_width() != ShelfScript.TOAST_SIZE:
		fail("toast icon for %s is %s" % [item, tex])
	iconed_toasts += 1


func on_finish() -> void:
	if _ready_ms < 0 and _shelf.ready_count() >= ShelfScript.wanted().size():
		_ready_ms = Time.get_ticks_msec() - _started_ms
	_shelf.finish()
	stat("icons_ready_ms", _ready_ms)
	stat("iconed_toasts", iconed_toasts)
	if _ready_ms < 0:
		fail("icon shelf drew only %d of %d icons in the whole run" % [_shelf.ready_count(), ShelfScript.wanted().size()])
	if _w:
		_w.free()
		_w = null

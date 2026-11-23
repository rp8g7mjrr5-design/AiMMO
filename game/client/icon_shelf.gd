class_name IconShelf
extends RefCounted
## The client's item icons, drawn ahead of time so the first "+2 Ash wood" toast never hitches.
##
## World's `ItemIcons` draws each icon in plain maths on an `Image`: about 20 ms at 32 px and
## 75 ms at 64 px, too slow to do in the frame a toast first needs it. So the client draws every
## icon it uses (every item in `Inventory.ITEM_ORDER`, at each size in `SIZES`) on a background
## thread as soon as the game starts, while you are still on the login screen. Drawing an
## `Image` touches no shared state, so it is safe off the main thread; turning it into an
## `ImageTexture` (cheap) happens on the main thread the first time `texture()` asks for it.
##
## `texture()` never returns null and never waits: if the thread hasn't reached an icon yet it
## draws that one icon now (through `ItemIcons.texture`, world's cache), so the worst case is
## the old behaviour.

const TOAST_SIZE := 32 ## the icon beside a gather or craft toast
const ROW_SIZE := 32 ## a recipe's product in the workbench window (same as a toast: one drawing)
const PART_SIZE := 18 ## each part ("Ash wood 2/3") in the workbench window
const SLOT_SIZE := 44 ## a slot in the pack window (I)
const SIZES := [TOAST_SIZE, PART_SIZE, SLOT_SIZE] ## every distinct size above

var _thread: Thread
var _mutex := Mutex.new()
var _images := {} ## "item@size" -> Image, filled by the thread
var _textures := {} ## "item@size" -> ImageTexture, main thread only
var _stop := false


## Every [item, size] the client draws ahead, in the order the thread draws them (toast size
## first, because a gather toast is the first icon most players see).
static func wanted() -> Array:
	var out: Array = []
	for size in SIZES:
		for item in Inventory.ITEM_ORDER:
			out.append([item, size])
	return out


static func key(item: String, size: int) -> String:
	return "%s@%d" % [item, size]


## Starts drawing every wanted icon on a background thread. Calling it twice does nothing.
func start() -> void:
	if _thread != null:
		return
	_stop = false
	_thread = Thread.new()
	_thread.start(_draw_all, Thread.PRIORITY_LOW)


## Draws every wanted icon right here (tests and headless tools).
func draw_all_now() -> void:
	_draw_all()


## Waits for the background thread (call before quitting, or Godot warns about a live thread).
func finish() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	_thread.wait_to_finish()
	_thread = null


## How many of the wanted icons are drawn so far.
func ready_count() -> int:
	_mutex.lock()
	var n := _images.size()
	_mutex.unlock()
	return n


func is_ready(item: String, size: int) -> bool:
	var k := key(item, size)
	if _textures.has(k):
		return true
	_mutex.lock()
	var has := _images.has(k)
	_mutex.unlock()
	return has


## The icon for `item` at `size` px, never null. Unknown items get world's cloth bundle.
func texture(item: String, size: int) -> Texture2D:
	var k := key(item, size)
	if _textures.has(k):
		return _textures[k]
	_mutex.lock()
	var img: Image = _images.get(k)
	_mutex.unlock()
	if img == null:
		return ItemIcons.texture(item, size)
	var tex := ImageTexture.create_from_image(img)
	_textures[k] = tex
	return tex


func _draw_all() -> void:
	for w in wanted():
		_mutex.lock()
		var stop := _stop
		var done := _images.has(key(w[0], w[1]))
		_mutex.unlock()
		if stop:
			return
		if done:
			continue
		var img := ItemIcons.image(str(w[0]), int(w[1]))
		_mutex.lock()
		_images[key(w[0], w[1])] = img
		_mutex.unlock()

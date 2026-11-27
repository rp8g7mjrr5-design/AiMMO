class_name MapWindow
extends Control
## The world map (M): the whole island on one sheet, so you can plan the next run. The
## ground is WorldMap's painted relief (sea, sand, forest, moor, stone hills, rivers, the
## king's roads); on top, drawn crisp at any zoom: every ruin marked by grade (pale stone
## for Quiet to deep red for Deadly), the coast's landmarks (wrecks, piers, whale bones) as
## small driftwood squares, and you as an ember arrow pointing where the camera looks.
## Hover a mark for its name; zoom in (wheel) and every place is named. Drag to move around,
## right-click to see the whole island again.
##
## The island is new each monthly wipe, so the sheet is painted from WorldGen when the world
## arrives, on a worker thread (a few seconds at 768 px for a 3 km island) a few seconds after
## you wash ashore, so it never stalls joining or the M key. Ashgrove gets its map too.
##
## Every colour and size the map draws with is in the "Look" block below and comes from
## HudStyle and Palette, so the game's UI style can restyle the map in one place.
## The maths (world to sheet, the view under zoom, the marks, the arrow) are static functions
## so unit tests and the bot test check them without a window.

signal closed

const SHEET_PX := 768 ## the painted sheet, square (about 4 m a pixel on the 3 km island)
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.25 ## per wheel notch
const PAINT_DELAY := 5.0 ## seconds after a world arrives before the sheet is painted
const HOVER_PX := 14.0 ## how near the cursor must be to a mark to name it
const NAMES_FROM_ZOOM := 2.0 ## at this zoom and closer, every place on the sheet is named

# --- Look (restyle here) -------------------------------------------------------------------
const SHADE := Color(0.03, 0.03, 0.025, 0.55) ## dims the world behind the sheet
const PANEL_OPACITY := 0.92
const TITLE := HudStyle.EMBER
const TEXT := HudStyle.TEXT
const TEXT_DIM := HudStyle.TEXT_DIM
const INK := Palette.MAP_INK ## outlines round every mark
const CHART_TEXT := HudStyle.TEXT ## the scale bar and the north mark, which sit over the sea
const SHEET_EDGE := Color(Palette.MAP_INK, 0.9)
const GRADE := Palette.MAP_GRADE ## ruin fills, 1 Quiet to 4 Deadly
const LANDMARK := Palette.DRIFTWOOD ## the coast's landmarks
const HOME := Palette.LINEN ## Spawn Meadow on Ashgrove
const YOU := HudStyle.EMBER ## your arrow
const YOU_HALO := Color(HudStyle.TEXT, 0.85) ## the ring round you, so you are found at a glance
const LABEL_BOX := Color(0.13, 0.12, 0.11, 0.86)
const TITLE_SIZE := 21
const BODY_SIZE := 14
const SMALL_SIZE := 12
const MARGIN := 18.0
const HEAD_H := 34.0 ## title row
const FOOT_H := 30.0 ## legend row
const RUIN_R := [3.5, 4.0, 5.0, 6.0] ## mark radius by grade at zoom 1
const ARROW_LEN := 20.0
# -------------------------------------------------------------------------------------------

var zoom := 1.0
var center := Vector2(0.5, 0.5) ## the sheet point (0..1) in the middle of the view
var me := Vector3.ZERO
var heading := 0.0 ## compass heading of the camera: 0 north, PI/2 east (CompassStrip.heading)
var has_me := false

var _tex: ImageTexture
var _painted_for := {} ## the WorldGen config the sheet shows
var _marks: Array = []
var _task := -1
var _task_for := {}
var _task_img: Image
var _paint_in := -1.0 ## countdown to painting; < 0 when nothing is waiting
var _title: Label
var _mouse := Vector2(-1, -1)
var _dragging := false


## Where a world position sits on the sheet, 0..1 each way (x east, y south: north is up).
static func uv_of(pos: Vector3) -> Vector2:
	var size := WorldGen.size_m()
	var half := WorldGen.half_size()
	return Vector2((pos.x + half) / size, (pos.z + half) / size)


## The world (x, z) under a sheet point (the inverse of uv_of).
static func world_of(uv: Vector2) -> Vector2:
	var size := WorldGen.size_m()
	var half := WorldGen.half_size()
	return Vector2(uv.x * size - half, uv.y * size - half)


## What the map marks, for the configured world: [{kind ("ruin", "landmark" or "home"),
## label, grade (ruins; 0 otherwise), uv: Vector2}]. Ruins come first, so they win a hover.
static func marks() -> Array:
	var out: Array = []
	for r in Ruins.all():
		out.append({"kind": "ruin", "label": Ruins.title(r), "grade": int(r.grade), "uv": uv_of(r.pos)})
	for l in BeachGen.landmarks():
		out.append({"kind": "landmark", "label": BeachGen.label(str(l.kind)), "grade": 0, "uv": uv_of(l.pos)})
	if not WorldGen.is_kingdom():
		out.append({"kind": "home", "label": "Spawn Meadow", "grade": 0, "uv": uv_of(Vector3.ZERO)})
	return out


## The part of the sheet in view (0..1 units) at `z` zoom around `c`, kept on the sheet.
static func view_rect(z: float, c: Vector2) -> Rect2:
	var span := 1.0 / clampf(z, 1.0, ZOOM_MAX)
	var cc := clamp_center(z, c)
	return Rect2(cc - Vector2(span, span) * 0.5, Vector2(span, span))


## `c` moved just enough that the view at zoom `z` stays on the sheet.
static func clamp_center(z: float, c: Vector2) -> Vector2:
	var h := 0.5 / clampf(z, 1.0, ZOOM_MAX)
	return Vector2(clampf(c.x, h, 1.0 - h), clampf(c.y, h, 1.0 - h))


## A sheet point on screen, for a view `view` drawn into `area`.
static func to_screen(uv: Vector2, view: Rect2, area: Rect2) -> Vector2:
	return area.position + (uv - view.position) / view.size * area.size


## The screen point back on the sheet.
static func to_sheet(p: Vector2, view: Rect2, area: Rect2) -> Vector2:
	return view.position + (p - area.position) / area.size * view.size


## Zoom by `factor` keeping the sheet point under `anchor_uv` where it is on screen:
## returns [new zoom, new centre].
static func zoom_about(z: float, c: Vector2, factor: float, anchor_uv: Vector2) -> Array:
	var nz := clampf(z * factor, 1.0, ZOOM_MAX)
	var cc := clamp_center(z, c)
	var nc := anchor_uv + (cc - anchor_uv) * (z / nz)
	return [nz, clamp_center(nz, nc)]


## The arrow for you: a slim triangle with a notched tail at `at`, pointing along compass
## heading `h` (0 = up the sheet, north).
static func arrow(at: Vector2, h: float, length: float = ARROW_LEN) -> PackedVector2Array:
	var f := Vector2(sin(h), -cos(h))
	var s := Vector2(-f.y, f.x)
	return PackedVector2Array([
		at + f * length * 0.6,
		at - f * length * 0.4 + s * length * 0.38,
		at - f * length * 0.18,
		at - f * length * 0.4 - s * length * 0.38,
	])


## A round length for the scale bar: the biggest of 50/100/250/500/1000/2000 m that fits in
## `max_px` at `m_per_px` metres a pixel.
static func scale_metres(m_per_px: float, max_px: float) -> float:
	var best := 50.0
	for m in [50.0, 100.0, 250.0, 500.0, 1000.0, 2000.0]:
		if m / m_per_px <= max_px:
			best = m
	return best


## The map's title.
static func title_text() -> String:
	if WorldGen.is_island():
		return "The Island"
	if WorldGen.is_kingdom():
		return "The Kingdom"
	return "Ashgrove"


func setup(theme_res: Theme) -> void:
	theme = theme_res
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # a smooth sheet when zoomed in, not blocks
	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	# The game's window title look when HudStyle has one (the UI style), else the ember title.
	var hs: Script = HudStyle
	if hs.has_method("title"):
		hs.call("title", _title, TITLE_SIZE)
	else:
		_title.add_theme_font_size_override("font_size", TITLE_SIZE)
		_title.add_theme_color_override("font_color", TITLE)
	add_child(_title)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _title != null:
		_place_title()


func _place_title() -> void:
	var sheet: Rect2 = layout().sheet
	_title.text = title_text()
	_title.position = Vector2(sheet.position.x, sheet.position.y - HEAD_H - 4.0)
	_title.size = Vector2(sheet.size.x * 0.5, HEAD_H)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Paint the sheet for the world WorldGen holds now, after `delay` seconds (0: start now).
## Does nothing when it is already painted or being painted for this world.
func prepare(delay: float = 0.0) -> void:
	var cfg := WorldGen.config()
	if _tex != null and _painted_for == cfg:
		return
	if _task >= 0 and _task_for == cfg:
		return
	if delay > 0.0:
		_paint_in = delay if _paint_in < 0.0 else minf(_paint_in, delay)
		return
	_paint_in = -1.0
	if _task >= 0:
		settle() # an old world's sheet is still drawing: finish it (thrown away) first
	# Build every lazy table on this thread, so the worker only reads.
	WorldGen.ruin_sites()
	Terrain.height(0.0, 0.0)
	_task_for = cfg
	_task_img = null
	_task = WorkerThreadPool.add_task(_paint_job.bind(SHEET_PX, cfg), false, "world map")


## Paint synchronously at `px` (tests and screenshots).
func paint_now(px: int = SHEET_PX) -> void:
	settle()
	_apply(WorldMap.paint(px, false), WorldGen.config())


## Wait for a sheet that is drawing. Call before WorldGen changes world: the worker reads it.
func settle() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if _task_img != null and _task_for == WorldGen.config():
		_apply(_task_img, _task_for)
	_task_img = null


func _paint_job(px: int, cfg: Dictionary) -> void:
	if cfg != WorldGen.config():
		return
	_task_img = WorldMap.paint(px, false)


func _apply(img: Image, cfg: Dictionary) -> void:
	_tex = ImageTexture.create_from_image(img)
	_painted_for = cfg
	_marks = marks()
	queue_redraw()


func is_ready() -> bool:
	return _tex != null and _painted_for == WorldGen.config()


## Every frame: runs the paint countdown, picks up a finished sheet, and redraws while open.
func step(delta: float) -> void:
	if _paint_in >= 0.0:
		_paint_in -= delta
		if _paint_in < 0.0:
			_paint_in = -1.0
			prepare()
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		settle()
		if not is_ready():
			prepare()


## Where you are and which way the camera looks (CompassStrip.heading of the camera's yaw).
func feed(pos: Vector3, compass_heading: float) -> void:
	me = pos
	heading = compass_heading
	has_me = true
	if visible:
		queue_redraw()


func open() -> void:
	if not is_ready():
		prepare()
	zoom = 1.0
	center = Vector2(0.5, 0.5)
	_dragging = false
	visible = true
	_place_title()
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	_dragging = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## On disconnect: shut, and let the next world paint its own sheet.
func reset() -> void:
	visible = false
	settle()
	_paint_in = -1.0
	has_me = false


# --- Layout ----------------------------------------------------------------------------------

## The panel and the sheet inside it, for the window's current size.
func layout() -> Dictionary:
	var avail := size
	if avail.x <= 0.0:
		avail = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var side := floorf(minf(avail.x - MARGIN * 4.0, avail.y - HEAD_H - FOOT_H - MARGIN * 4.0))
	side = maxf(side, 200.0)
	var panel_size := Vector2(side + MARGIN * 2.0, side + HEAD_H + FOOT_H + MARGIN * 2.0)
	var panel := Rect2(((avail - panel_size) * 0.5).floor(), panel_size)
	var sheet := Rect2(panel.position + Vector2(MARGIN, MARGIN + HEAD_H), Vector2(side, side))
	return {"panel": panel, "sheet": sheet}


func _gui_input(event: InputEvent) -> void:
	var lay := layout()
	var sheet: Rect2 = lay.sheet
	var view := view_rect(zoom, center)
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _dragging:
			center = clamp_center(zoom, center - event.relative / sheet.size * view.size)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.pressed and sheet.has_point(event.position) and \
			(event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var f := ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
		var z := zoom_about(zoom, center, f, to_sheet(event.position, view, sheet))
		zoom = z[0]
		center = z[1]
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and sheet.has_point(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click: back to the whole island.
		zoom = 1.0
		center = Vector2(0.5, 0.5)
		queue_redraw()
		accept_event()


# --- Drawing ---------------------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	var lay := layout()
	var panel: Rect2 = lay.panel
	var sheet: Rect2 = lay.sheet
	draw_rect(Rect2(Vector2.ZERO, size), SHADE)
	draw_style_box(HudStyle.panel(PANEL_OPACITY), panel)
	var head_base := panel.position.y + MARGIN + HEAD_H * 0.5 + TITLE_SIZE * 0.32
	draw_string(font, Vector2(sheet.position.x, head_base), "Wheel to zoom · drag to move · M to close",
		HORIZONTAL_ALIGNMENT_RIGHT, sheet.size.x, SMALL_SIZE, TEXT_DIM)
	draw_rect(sheet.grow(1.0), SHEET_EDGE, false, 2.0)
	if not is_ready():
		draw_rect(sheet, Color(INK, 0.6))
		draw_string(font, Vector2(sheet.position.x, sheet.get_center().y), "Drawing the map...",
			HORIZONTAL_ALIGNMENT_CENTER, sheet.size.x, BODY_SIZE, TEXT_DIM)
		_draw_legend(font, panel, sheet)
		return
	var view := view_rect(zoom, center)
	var px := float(_tex.get_width())
	draw_texture_rect_region(_tex, sheet, Rect2(view.position * px, view.size * px))
	# Marks, then you, then names (so a name is never hidden under your arrow).
	var grow := sqrt(zoom)
	var hover := -1
	var best := HOVER_PX
	for i in _marks.size():
		var m: Dictionary = _marks[i]
		var p := to_screen(m.uv, view, sheet)
		if not sheet.grow(-2.0).has_point(p):
			continue
		_draw_mark(m, p, grow)
		var d := p.distance_to(_mouse)
		if d < best:
			best = d
			hover = i
	if has_me:
		var p := to_screen(uv_of(me), view, sheet)
		if sheet.has_point(p):
			var len := ARROW_LEN * clampf(grow, 1.0, 1.4)
			draw_circle(p, len * 0.75, Color(INK, 0.35))
			draw_arc(p, len * 0.75, 0.0, TAU, 32, YOU_HALO, 1.5, true)
			var pts := arrow(p, heading, len)
			draw_colored_polygon(pts, YOU)
			var ring := pts.duplicate()
			ring.append(pts[0])
			draw_polyline(ring, INK, 1.5, true)
	if zoom >= NAMES_FROM_ZOOM:
		for i in _marks.size():
			var m: Dictionary = _marks[i]
			if i == hover:
				continue
			var p := to_screen(m.uv, view, sheet)
			if sheet.grow(-2.0).has_point(p):
				_draw_name(font, str(m.label), p, 8.0 * grow, SMALL_SIZE, TEXT_DIM, sheet, false)
	if hover >= 0:
		var m: Dictionary = _marks[hover]
		_draw_name(font, str(m.label), to_screen(m.uv, view, sheet), 12.0, BODY_SIZE, TEXT, sheet, true)
	_draw_north(font, sheet)
	_draw_scale(font, sheet, view)
	_draw_legend(font, panel, sheet)


func _draw_mark(m: Dictionary, p: Vector2, grow: float) -> void:
	match str(m.kind):
		"ruin":
			var g := clampi(int(m.grade), 1, 4)
			var r: float = RUIN_R[g - 1] * grow
			draw_circle(p, r + 1.5, INK)
			draw_circle(p, r, GRADE[g - 1])
		"landmark":
			var r := 3.0 * grow
			draw_rect(Rect2(p - Vector2(r + 1.5, r + 1.5), Vector2(r + 1.5, r + 1.5) * 2.0), INK)
			draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), LANDMARK)
		_:
			var r := 4.0 * grow
			draw_circle(p, r + 1.5, INK)
			draw_circle(p, r, HOME)


## A mark's name beside it (`gap` px to the right, or to the left when it would run off the
## sheet), on a small dark tab (`boxed`) or with just a soft shadow.
func _draw_name(font: Font, text: String, mark: Vector2, gap: float, font_size: int, colour: Color, sheet: Rect2, boxed: bool) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := mark + Vector2(gap, font_size * 0.35)
	if pos.x + w + 6.0 > sheet.end.x:
		pos.x = mark.x - gap - w
	pos.y = clampf(pos.y, sheet.position.y + font_size + 4.0, sheet.end.y - 6.0)
	if boxed:
		var box := Rect2(pos + Vector2(-6.0, -font_size - 1.0), Vector2(w + 12.0, font_size + 9.0))
		draw_rect(box, LABEL_BOX)
		draw_rect(box, Color(HudStyle.PANEL_EDGE, 0.6), false, 1.0)
	else:
		draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, HudStyle.SHADOW)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


func _draw_north(font: Font, sheet: Rect2) -> void:
	var c := sheet.position + Vector2(sheet.size.x - 26.0, 30.0)
	var tip := PackedVector2Array([c + Vector2(0, -14), c + Vector2(6, 4), c + Vector2(0, 0), c + Vector2(-6, 4)])
	draw_colored_polygon(tip, CHART_TEXT)
	draw_string(font, c + Vector2(-4, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, CHART_TEXT)


func _draw_scale(font: Font, sheet: Rect2, view: Rect2) -> void:
	var m_per_px := WorldGen.size_m() * view.size.x / sheet.size.x
	var metres := scale_metres(m_per_px, sheet.size.x * 0.22)
	var w := metres / m_per_px
	var a := sheet.position + Vector2(14.0, sheet.size.y - 14.0)
	draw_line(a, a + Vector2(w, 0), CHART_TEXT, 2.0)
	draw_line(a + Vector2(0, -4), a + Vector2(0, 2), CHART_TEXT, 2.0)
	draw_line(a + Vector2(w, -4), a + Vector2(w, 2), CHART_TEXT, 2.0)
	var label := "%d m" % int(metres) if metres < 1000.0 else "%s km" % str(metres / 1000.0)
	draw_string(font, a + Vector2(0, -7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, CHART_TEXT)


## The key under the sheet: the four grades, the coast landmarks, and you.
func _draw_legend(font: Font, _panel: Rect2, sheet: Rect2) -> void:
	var y := sheet.end.y + FOOT_H * 0.5 + 4.0
	var x := sheet.position.x + 6.0
	if not WorldGen.is_kingdom():
		draw_circle(Vector2(x, y), 6.5, INK)
		draw_circle(Vector2(x, y), 5.0, HOME)
		draw_string(font, Vector2(x + 11.0, y + 5.0), "Spawn Meadow", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, TEXT_DIM)
		x += 30.0 + font.get_string_size("Spawn Meadow", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x
	for g in ([1, 2, 3, 4] if WorldGen.is_kingdom() else []):
		draw_circle(Vector2(x, y), 6.5, INK)
		draw_circle(Vector2(x, y), 5.0, GRADE[g - 1])
		var name := Ruins.grade_name(g)
		draw_string(font, Vector2(x + 11.0, y + 5.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, TEXT_DIM)
		x += 22.0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x
	if WorldGen.is_island():
		x += 8.0
		draw_rect(Rect2(Vector2(x - 4.5, y - 4.5), Vector2(9, 9)), INK)
		draw_rect(Rect2(Vector2(x - 3.0, y - 3.0), Vector2(6, 6)), LANDMARK)
		draw_string(font, Vector2(x + 11.0, y + 5.0), "Coast landmark", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, TEXT_DIM)
		x += 22.0 + font.get_string_size("Coast landmark", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x
	x += 8.0
	draw_colored_polygon(arrow(Vector2(x, y), 0.0, 13.0), YOU)
	draw_string(font, Vector2(x + 11.0, y + 5.0), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE, TEXT_DIM)

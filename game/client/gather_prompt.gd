class_name GatherPrompt
extends Control
## Gathering as a game action, on protocol v3's timed gather: when you stand within reach of
## a tree, rock or seep, a small prompt above the chat says "[E] Chop Ember Ash". Press (or
## hold) E and the client sends c2s_gather_start(node_id) for that very node. The server
## answers s2c_gather_begin with how long it takes, a bar fills over exactly that time
## ("Chopping Ember Ash"), and s2c_gather_result pops a "+2 Ash wood  (6)" toast. Keep E held
## and the next gather starts the moment one ends (no dead time); press E again or walk off
## and it stops. A refusal ("pack full", "spent") shows as a short centre-screen notice.
##
## The server still decides everything: reach, depletion, night-only seeps, pack room, the
## timing. The client only knows which nodes are spent (s2c_nodes / s2c_node_state) so the
## prompt never offers one. All the rules are static functions so they are unit tested headless.

const WIDTH := 380.0 ## room for "Rich Stone Seam · needs a pickaxe" and the longest names
const BAR_WIDTH := 150.0
const HEIGHT := 64.0
const KEY_LABEL := "E"
## The action word per node kind, as in the design bible ("[E] Chop Ember Ash").
const VERBS := {"ash": "Chop", "pine": "Chop", "stone": "Mine", "ember_sap": "Collect"}
const DOING := {"Chop": "Chopping", "Mine": "Mining", "Collect": "Collecting", "Gather": "Gathering"}
## A start the server hasn't answered yet is asked again after this many seconds.
const ASK_TIMEOUT := 1.5
const TOAST_SECONDS := 2.2
const TOAST_RISE := 26.0 ## px the toast floats up while it fades
const ACCENT := HudStyle.EMBER ## the HUD's one accent (art bible section 9)
const NOTICE := HudStyle.NOTE ## a refusal: warm, softer than the haul toast
const DIM := HudStyle.TEXT_DIM
const ICON_GAP := 6.0 ## px between a toast's icon and its text
## Short centre-screen words for a refused or broken-off gather (s2c_gather_end's reason).
## Reasons the player caused on purpose ("moved", "stopped") or that need no words ("done",
## "busy", "cooldown", "disconnected") show nothing. The server's longer line (with where the
## next node is) still goes to chat.
const NOTICES := {
	"full": "Your pack is full",
	"depleted": "Nothing left here for now",
	"day": "Ember sap only seeps at night",
	"far": "Out of reach",
	"unknown": "Nothing to gather there",
	"tool": "You need the right tool", ## notice_for() names it ("Needs an axe") when it can
}

var prompt_label: Label
var bar: ProgressBar
var toast_label: Label
var toast_icon: TextureRect
## Where toast icons come from (set by the client; without one, toasts fall back to world's cache).
var icons: IconShelf
## node id -> true for every node the server says is empty right now.
var spent := {}
## Your pack as the server last sent it (s2c_inventory), for the toast's "(6)", and so a
## tier-2 node you have no tool for says what it needs instead of offering E.
var pack := {}
var _target := {}
var _channel := {} ## your running gather: {node_id, kind, text, started, seconds}
var _asked_node := -1 ## a start we sent and the server hasn't answered yet
var _asked_at := -INF
var _hold_blocked := false ## after a refusal, holding E doesn't ask again until you let go
var _toast_age := INF
## True for the one frame a left-click did nothing (see missed_click); client.gd plays
## Sfx.miss() for it, so a click at the sky or at a spent node is felt, not silent.
var click_missed := false
var _miss_age := INF


## What the prompt shows for a player at `pos` at world time `world_seconds`: the live node
## within ResourceNodes.GATHER_RANGE under the reticle (look-to-interact, when `look` is
## given: the camera's eye and look direction), else the nearest live one in reach. With
## only spent nodes in reach it names the nearest one, greyed out. {} for nothing in reach.
## A tier-2 node your pack (`inv`) has no tool for shows what it needs, greyed:
## "Old Ember Ash · needs an axe".
## {id, kind, label, can: bool (false for a spent node, a seep in daylight or a node you have
## no tool for), needs_tool: bool, aimed: bool (the reticle is on it, so a left-click takes
## it; false for the nearest-node fallback), text, doing}.
static func target(pos: Vector3, world_seconds: float, eye := Vector3.ZERO, look := Vector3.ZERO, spent_ids := {}, inv := {}) -> Dictionary:
	var in_reach := ResourceNodes.near(pos, ResourceNodes.GATHER_RANGE)
	if in_reach.is_empty():
		return {}
	var live: Array = in_reach.filter(func(n): return not spent_ids.has(int(n.id)))
	var n: Dictionary = pick(live, eye, look) if not live.is_empty() else in_reach[0]
	var aimed := not live.is_empty() and look != Vector3.ZERO \
		and int(ActionCamera.aimed_node(eye, look.normalized(), live).get("id", -1)) == int(n.id)
	var info := ResourceNodes.info(n)
	var label := str(info.get("label", n.kind))
	var what := _what(str(n.kind), label)
	var verb := str(VERBS.get(n.kind, "Gather"))
	var is_spent := live.is_empty()
	var night_only := bool(info.get("night_only", false)) and not WorldClock.is_night(world_seconds)
	var no_tool := not Gathering.can_work(n, inv)
	var text := "[%s] %s %s" % [KEY_LABEL, verb, what]
	if is_spent:
		text = "%s is spent for now" % label
	elif no_tool:
		text = need_text(n, inv)
	elif night_only:
		text = "%s only seeps at night" % label
	return {
		"id": int(n.id),
		"kind": str(n.kind),
		"label": label,
		"can": not is_spent and not night_only and not no_tool,
		"needs_tool": no_tool,
		"aimed": aimed,
		"text": text,
		"doing": doing_for(n),
	}


## "Old Ember Ash · needs an axe" for a node your pack has no tool for, so the prompt is a
## goal rather than a wall. "" when `inv` may work `node`.
static func need_text(node: Dictionary, inv: Dictionary) -> String:
	if Gathering.can_work(node, inv):
		return ""
	var info := ResourceNodes.info(node)
	return "%s · needs %s" % [_what(str(node.kind), str(info.get("label", node.kind))), Gathering.tool_word(str(node.kind))]


## The node's name as the prompt shows it: "Old Ember Ash", "Ember Sap".
static func _what(kind: String, label: String) -> String:
	return "Ember Sap" if kind == "ember_sap" else label.capitalize()


## "Chopping Ember Ash", "Mining Stone Outcrop", "Collecting Ember Sap": the bar's caption
## for a kind's tier-1 node. For one node (a tier-2 one has its own name) use doing_for().
static func doing_text(kind: String) -> String:
	var info := ResourceNodes.kind_info(kind)
	if info.is_empty():
		return "Gathering"
	return "%s %s" % [DOING.get(VERBS.get(kind, "Gather"), "Gathering"), _what(kind, str(info.label))]


## "Chopping Old Ember Ash": the bar's caption for one node.
static func doing_for(node: Dictionary) -> String:
	var info := ResourceNodes.info(node)
	if info.is_empty():
		return "Gathering"
	var kind := str(node.kind)
	return "%s %s" % [DOING.get(VERBS.get(kind, "Gather"), "Gathering"), _what(kind, str(info.label))]


## Look-to-interact: from `in_reach` (nearest first), the node under the reticle, falling
## back to the nearest. Protocol v3 gathers by node id, so the aimed node is the one you get.
static func pick(in_reach: Array, eye: Vector3, look: Vector3) -> Dictionary:
	if look == Vector3.ZERO:
		return in_reach[0]
	var aimed := ActionCamera.aimed_node(eye, look.normalized(), in_reach)
	return in_reach[0] if aimed.is_empty() else aimed


## What E does this frame. `held` / `pressed` (just pressed) for E, `moving` for any movement
## key, `target` from target(), `gathering` while your own gather runs, `waiting` while a
## start is unanswered, `blocked` after a refusal until E (and the mouse button) is let go.
## `click_held` / `click_pressed` are the left mouse button (action camera: "E or left-click").
## A click only takes the node under the reticle (`target.aimed`), never the nearest-node
## fallback, so clicking at the sky doesn't start chopping the tree beside you. And a click
## never stops a gather: hammering the button while you chop keeps chopping (E or moving stops).
## {"op": "start", "node": id}, {"op": "cancel"}, or {} for nothing.
static func decide(held: bool, pressed: bool, moving: bool, target: Dictionary, gathering: bool, waiting: bool, blocked: bool, click_held: bool = false, click_pressed: bool = false) -> Dictionary:
	if gathering:
		return {"op": "cancel"} if pressed or moving else {}
	if waiting or moving or target.is_empty() or not bool(target.get("can", false)):
		return {}
	if pressed or (held and not blocked):
		return {"op": "start", "node": int(target.id)}
	if bool(target.get("aimed", false)) and (click_pressed or (click_held and not blocked)):
		return {"op": "start", "node": int(target.id)}
	return {}


## True when a fresh left-click this frame did nothing at all: it didn't start a gather
## (`op` from decide()), no gather is running (a click while chopping keeps chopping, which
## is not a miss), and no start is waiting on the server (that click is already answered by
## the bar or a refusal). `since_last` is seconds since the last miss: clicks closer than
## MISS_GAP make one tick, so a hammered button patters instead of buzzing.
const MISS_GAP := 0.12


static func missed_click(click_pressed: bool, op: Dictionary, gathering: bool, waiting: bool, since_last: float = INF) -> bool:
	return click_pressed and op.is_empty() and not gathering and not waiting and since_last >= MISS_GAP


## How full the gathering bar is, 0..1, at `now` for a channel {started, seconds}.
static func progress(channel: Dictionary, now: float) -> float:
	if channel.is_empty():
		return 0.0
	var secs := float(channel.seconds)
	if secs <= 0.0:
		return 1.0
	return clampf((now - float(channel.started)) / secs, 0.0, 1.0)


## The centre-screen words for a gather that ended with `reason`, or "" for none.
static func notice_text(reason: String) -> String:
	return str(NOTICES.get(reason, ""))


## notice_text, but a "tool" refusal on a known node names what it needs: "Needs an axe".
static func notice_for(reason: String, node_id: int) -> String:
	if reason == "tool":
		var n := ResourceNodes.get_by_id(node_id)
		if not n.is_empty() and Gathering.needs_tool(n):
			return "Needs %s" % Gathering.tool_word(str(n.kind))
	return notice_text(reason)


## True for the server's own system lines about your timed gather (start, haul, stop): the
## bar, toast and notices already say it, so they stay out of chat (chat is for talking).
static func is_echo(text: String) -> bool:
	return text.begins_with("You start gathering") or text.begins_with("You gather ") or text.begins_with("You stop gathering")


## Reads the server's full-stack line ("Your pack can't hold any more ash wood, so you leave
## it.", see Gathering.full_text; older servers said ". You leave it, but the work still
## counts.") into {item, label}, or {} for any other.
static func parse_full(text: String) -> Dictionary:
	var m := RegEx.create_from_string("^Your pack can't hold any more (.+?)(?:, so you|\\. You) leave it").search(text)
	if m == null:
		return {}
	var label := m.get_string(1)
	for id in Inventory.ITEM_ORDER:
		if Inventory.label(id).to_lower() == label.to_lower():
			return {"item": id, "label": label}
	return {"item": "", "label": label}


## The full-stack toast: "Pack full: Ash wood (99)", which says why no "+2" came.
static func full_toast_text(item: String, in_pack: int) -> String:
	var label := Inventory.label(item) if item != "" else "that"
	return "Pack full: %s (%d)" % [label.left(1).to_upper() + label.substr(1), in_pack]


## Reads the server's success line ("You gather 2 ash wood from the ember ash (6 in your
## pack).", see Gathering.success) into {qty, item, label, in_pack}, or {} for any other line.
## The workbench's pack mirror uses it; toasts come from s2c_gather_result.
static func parse_gain(text: String) -> Dictionary:
	var m := RegEx.create_from_string("^You gather (\\d+) (.+?) from the .+? \\((\\d+) in your pack\\)").search(text)
	if m == null:
		return {}
	var label := m.get_string(2)
	var item := ""
	for id in Inventory.ITEM_ORDER:
		if Inventory.label(id).to_lower() == label.to_lower():
			item = id
	return {"qty": m.get_string(1).to_int(), "item": item, "label": label, "in_pack": m.get_string(3).to_int()}


## "+2 Ash wood  (6)" for a gain {qty, label, in_pack}; without in_pack (or below 0) just "+2 Ash wood".
static func toast_text(gain: Dictionary) -> String:
	var label := str(gain.label)
	var head := "+%d %s" % [int(gain.qty), label.left(1).to_upper() + label.substr(1)]
	var in_pack := int(gain.get("in_pack", -1))
	return head if in_pack < 0 else "%s  (%d)" % [head, in_pack]


## Left edge of a toast's icon so icon + gap + text sit centred in WIDTH, for text `text_w` px wide.
static func icon_x(text_w: float, icon_size: float = IconShelf.TOAST_SIZE) -> float:
	return (WIDTH - (icon_size + ICON_GAP + text_w)) * 0.5


## Toast opacity `age` seconds after it appeared: holds, then fades over the last third.
static func toast_alpha(age: float) -> float:
	if age < 0.0 or age >= TOAST_SECONDS:
		return 0.0
	var fade_from := TOAST_SECONDS * 2.0 / 3.0
	if age <= fade_from:
		return 1.0
	return 1.0 - smoothstep(fade_from, TOAST_SECONDS, age)


func setup(theme: Theme) -> void:
	self.theme = theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	toast_label = _make_label(15, ACCENT)
	toast_label.position = Vector2(0, 0)
	toast_label.modulate.a = 0.0
	toast_icon = TextureRect.new()
	toast_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	toast_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	toast_icon.size = Vector2(IconShelf.TOAST_SIZE, IconShelf.TOAST_SIZE)
	toast_icon.visible = false
	add_child(toast_icon)
	prompt_label = _make_label(15, HudStyle.TEXT)
	prompt_label.position = Vector2(0, 26)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2((WIDTH - BAR_WIDTH) * 0.5, 52)
	bar.size = Vector2(BAR_WIDTH, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = HudStyle.TRACK
	bar.add_theme_stylebox_override("background", bg)
	bar.visible = false
	add_child(bar)
	prompt_label.visible = false


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.size = Vector2(WIDTH, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.quiet_label(l, font_size, color)
	add_child(l)
	return l


## Called every logged-in frame with where you stand, E held / just pressed, whether you are
## moving, (optionally) the camera's eye and look direction for look-to-interact, and the
## left mouse button held / just pressed (click-to-gather on the aimed node).
## Returns what to send now: {"op": "start", "node": id} (c2s_gather_start), {"op": "cancel"}
## (c2s_gather_cancel), or {}.
func update(delta: float, pos: Vector3, world_seconds: float, now: float, held: bool, pressed: bool = false, moving: bool = false, eye := Vector3.ZERO, look := Vector3.ZERO, click_held: bool = false, click_pressed: bool = false) -> Dictionary:
	_target = target(pos, world_seconds, eye, look, spent, pack)
	if not held and not click_held:
		_hold_blocked = false
	var waiting := _asked_node >= 0 and now - _asked_at < ASK_TIMEOUT
	if not waiting:
		_asked_node = -1
	var op := decide(held, pressed, moving, _target, not _channel.is_empty(), waiting, _hold_blocked, click_held, click_pressed)
	_miss_age += delta
	click_missed = missed_click(click_pressed, op, not _channel.is_empty(), waiting, _miss_age)
	if click_missed:
		_miss_age = 0.0
	if op.get("op", "") == "start":
		_asked_node = int(op.node)
		_asked_at = now
	elif op.get("op", "") == "cancel":
		_channel = {} # the bar goes at once; the server's "stopped" end is then a no-op
		_hold_blocked = true # E pressed to stop: don't start again until it is let go
	var gathering := not _channel.is_empty()
	prompt_label.visible = gathering or not _target.is_empty()
	if gathering:
		prompt_label.text = str(_channel.text)
		prompt_label.add_theme_color_override("font_color", HudStyle.TEXT)
	elif not _target.is_empty():
		prompt_label.text = _target.text
		prompt_label.add_theme_color_override("font_color", HudStyle.TEXT if _target.can else DIM)
	bar.visible = gathering
	bar.value = progress(_channel, now)
	_toast_age += delta
	toast_label.modulate.a = toast_alpha(_toast_age)
	toast_label.position.y = -TOAST_RISE * clampf(_toast_age / TOAST_SECONDS, 0.0, 1.0)
	toast_icon.modulate.a = toast_label.modulate.a
	toast_icon.position.y = toast_label.position.y + (24.0 - IconShelf.TOAST_SIZE) * 0.5
	return op


## s2c_gather_begin for your own gather: the bar starts filling over the server's `seconds`.
func on_begun(node_id: int, seconds: float, now: float) -> void:
	_asked_node = -1
	var node := ResourceNodes.get_by_id(node_id)
	_channel = {"node_id": node_id, "kind": str(node.get("kind", "")), "text": doing_for(node), "started": now, "seconds": seconds}


## s2c_gather_end for your own gather (or a refused start). Shows the refusal notice, if
## any, and returns its text ("" for none).
func on_ended(node_id: int, reason: String) -> String:
	if _channel.is_empty() or int(_channel.node_id) == node_id:
		_channel = {}
	_asked_node = -1 # a refused start is answered by its end alone
	var words := notice_for(reason, node_id)
	if reason != "done":
		_hold_blocked = true # holding E doesn't hammer a refusal; let go and press again
	if words != "":
		show_toast(words, "", NOTICE)
	return words


## s2c_gather_result: the haul toast "+2 Ash wood  (6)" with the item's icon. s2c_inventory
## arrives first, so `pack` already holds the new count.
func on_result(item_id: String, count: int) -> void:
	var in_pack := int(pack.get(item_id, -1)) if pack.has(item_id) else -1
	show_toast(toast_text({"qty": count, "label": Inventory.label(item_id), "in_pack": in_pack}), item_id)


## A system line: true if it is an echo of your timed gather (keep it out of chat). A gather
## that finished on a full stack (no s2c_gather_result) gets its own quiet toast here
## instead of a centre-screen refusal: nothing went wrong, there was just no room.
func on_system(text: String) -> bool:
	var full := parse_full(text)
	if not full.is_empty():
		show_toast(full_toast_text(str(full.item), int(pack.get(full.item, Inventory.MAX_STACK))), str(full.item), NOTICE)
		return true
	return is_echo(text)


## Your own gather is running (begun, not yet ended or cancelled).
func gathering() -> bool:
	return not _channel.is_empty()


func channel() -> Dictionary:
	return _channel


## Shows `text` (for example "[E] Use Workbench") in the prompt line when no node is in
## reach; the node prompt always wins. Call after update() each frame; "" shows nothing extra.
func show_hint(text: String) -> void:
	if _target.is_empty() and _channel.is_empty():
		prompt_label.visible = text != ""
		prompt_label.text = text
		prompt_label.add_theme_color_override("font_color", HudStyle.TEXT)


## Pops a floating toast like "Crafted: Stone axe!", with `item`'s icon beside it ("" = no icon).
func show_toast(text: String, item: String = "", color: Color = ACCENT) -> void:
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", color)
	_toast_age = 0.0
	toast_label.modulate.a = 1.0
	toast_icon.visible = item != ""
	toast_icon.modulate.a = 1.0
	toast_icon.set_meta("item", item)
	if item != "":
		toast_icon.texture = icons.texture(item, IconShelf.TOAST_SIZE) if icons else ItemIcons.texture(item, IconShelf.TOAST_SIZE)
		var text_w := toast_label.get_minimum_size().x
		toast_icon.position = Vector2(icon_x(text_w), (24.0 - IconShelf.TOAST_SIZE) * 0.5)
		# Shift the text right by half the icon so the pair, not the text, is centred.
		toast_label.position.x = (IconShelf.TOAST_SIZE + ICON_GAP) * 0.5
	else:
		toast_label.position.x = 0.0


func toast_item() -> String:
	return "" if not toast_icon.visible else str(toast_icon.get_meta("item", ""))


func current_target() -> Dictionary:
	return _target


func hide_all() -> void:
	_target = {}
	_channel = {}
	_asked_node = -1
	_hold_blocked = false
	spent = {}
	pack = {}
	prompt_label.visible = false
	bar.visible = false
	_toast_age = INF
	toast_label.modulate.a = 0.0
	toast_icon.visible = false

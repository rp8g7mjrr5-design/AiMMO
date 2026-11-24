class_name VitalsBar
extends Control
## Your health and stamina, bottom centre under the XP bar (gameplay's protocol v7
## `s2c_vitals`, roadmap Milestone 2 "First blood"). Built to read at a glance mid-swing:
## - **A hit you can see land.** Health drops at once, the bar flashes bright, and the part
##   you just lost stays behind as a pale chip for CHIP_HOLD before it drains away, so a big
##   hit and a small one look different even if you blinked. A soft low thump goes with it
##   (`Sfx.hurt`, played by client.gd on `hurt`).
## - **Low health pulses** below LOW_SHARE, so "back off now" is felt without reading numbers.
## - **Stamina** is its own thinner bar in sage green (XP owns gold); `flash_stamina()` reddens
##   its track when a swing is refused for being winded or tired, so the "why" is on the bar
##   your eyes go to.
## - **Out of the way when it doesn't matter.** Both bars full: they fade out HOLD_SECONDS
##   after the last change, so gathering in peace has a clean screen. Anything not full, they
##   stay. The first s2c_vitals at login (full) doesn't pop the bars up at all.
##
## Pure static helpers (fractions, chip, fades, pulse) are unit tested; the node only draws.

const WIDTH := 260.0
const HEIGHT := 26.0
const HP_H := 9.0
const ST_H := 5.0
const GAP := 4.0
const HEALTH := Color(0.86, 0.29, 0.2) ## ember red: warm like the valley, not alarm red
const CHIP := Color(1.0, 0.86, 0.66) ## the just-lost part, pale ember
const STAMINA := HudStyle.OK ## sage green; ember is XP's
const TRACK := HudStyle.TRACK
const TRACK_WARN := Color(0.62, 0.12, 0.08, 0.85) ## the stamina track when a swing is refused
const LABEL := HudStyle.TEXT
const CHIP_HOLD := 0.45 ## the lost chip waits this long...
const CHIP_RATE := 0.9 ## ...then drains at this share of the bar per second
const FLASH_SECONDS := 0.22 ## a hit brightens the health fill for this long
const FLASH_GLOW := Color(1.9, 1.7, 1.5)
const LOW_SHARE := 0.3 ## at or under this share of max health the fill pulses
const LOW_PERIOD := 0.9 ## seconds per pulse
const WARN_SECONDS := 0.45 ## the stamina track stays red this long after a refusal
const HOLD_SECONDS := 2.5 ## both full: the bars stay this long after the last change...
const FADE_SECONDS := 0.6 ## ...then fade out over this
const SMOOTH := 18.0 ## fills ease toward the server's value (1-point regen steps glide)
const HURT_GAP := 0.15 ## at most one thump per this many seconds

var health_track: Panel
var chip_fill: Panel
var health_fill: Panel
var stamina_track: Panel
var stamina_fill: Panel
var health_label: Label

var hp := 0
var max_hp := 0
var stamina := 0
var max_stamina := 0
var known := false ## has the server told us anything since login?
var shown_hp := 1.0 ## the drawn health fraction (eases toward the server's)
var shown_stamina := 1.0
var chip_from := 1.0 ## where the chip started draining from
var _since_loss := INF
var _since_change := INF
var _since_hit := INF
var _since_warn := INF
var _since_thump := INF
var _t := 0.0


## Share of a bar, 0..1 (an empty or unknown max reads as full, never a divide by zero).
static func fraction(value: int, maximum: int) -> float:
	if maximum <= 0:
		return 1.0
	return clampf(float(value) / float(maximum), 0.0, 1.0)


## The chip (the part just lost) `since` seconds after the last loss: it holds at `from`
## for CHIP_HOLD, then drains at CHIP_RATE down to `to`. It never sits under the health fill.
static func chip_value(from: float, to: float, since: float) -> float:
	if from <= to:
		return to
	if since < CHIP_HOLD:
		return from
	return maxf(to, from - CHIP_RATE * (since - CHIP_HOLD))


## Alpha of both bars: always 1 while either is not full; when both are, 1 for HOLD_SECONDS
## after the last change, then a fade over FADE_SECONDS.
static func bars_alpha(both_full: bool, since_change: float) -> float:
	if not both_full:
		return 1.0
	if since_change <= HOLD_SECONDS:
		return 1.0
	return clampf(1.0 - (since_change - HOLD_SECONDS) / FADE_SECONDS, 0.0, 1.0)


## Brightness of the health fill: 1 above LOW_SHARE; at or under it, a pulse between about
## 0.65 and 1.35 every LOW_PERIOD seconds (stronger the lower you are).
static func low_pulse(share: float, t: float) -> float:
	if share > LOW_SHARE or share <= 0.0:
		return 1.0
	var depth := 0.2 + 0.15 * (1.0 - share / LOW_SHARE)
	return 1.0 + depth * sin(TAU * t / LOW_PERIOD)


## How bright a hit's flash is `since` seconds after it: 1 at the hit, 0 after FLASH_SECONDS.
static func flash_amount(since: float) -> float:
	if since >= FLASH_SECONDS:
		return 0.0
	return 1.0 - since / FLASH_SECONDS


## What an s2c_vitals means next to what we knew: {hurt, lost, knocked, emptied}
## (on_vitals adds `thump`: hurt, and the last thump was HURT_GAP or more ago). `lost` is
## health points gone (0 on the first message after login: nothing was "lost" then).
static func change(known_before: bool, old_hp: int, new_hp: int, old_st: int, new_st: int) -> Dictionary:
	var lost := maxi(0, old_hp - new_hp) if known_before else 0
	return {
		"hurt": lost > 0,
		"lost": lost,
		"knocked": known_before and old_hp > 0 and new_hp <= 0,
		"emptied": known_before and old_st > 0 and new_st <= 0,
	}


func setup(p_theme: Theme) -> void:
	theme = p_theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	var bar_w := WIDTH - 60.0
	health_track = _panel(TRACK, Vector2(0, 0), Vector2(bar_w, HP_H))
	chip_fill = _panel(CHIP, Vector2(0, 0), Vector2(bar_w, HP_H))
	health_fill = _panel(HEALTH, Vector2(0, 0), Vector2(bar_w, HP_H))
	stamina_track = _panel(TRACK, Vector2(0, HP_H + GAP), Vector2(bar_w, ST_H))
	stamina_fill = _panel(STAMINA, Vector2(0, HP_H + GAP), Vector2(bar_w, ST_H))
	health_label = Label.new()
	health_label.position = Vector2(bar_w + 8.0, -6.0)
	health_label.size = Vector2(52, 20)
	health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.quiet_label(health_label, 13, LABEL)
	add_child(health_label)
	_draw_bars()


func _panel(color: Color, pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = pos
	p.size = sz
	add_child(p)
	return p


## s2c_vitals: the server's whole points. Returns change() plus `thump` for client.gd
## and for tests and bots.
func on_vitals(p_hp: int, p_max_hp: int, p_stamina: int, p_max_stamina: int) -> Dictionary:
	var c := change(known, hp, p_hp, stamina, p_stamina)
	var was_known := known
	if c.hurt:
		# The chip starts from what was drawn (or still draining), so two quick hits read as one longer chip.
		chip_from = maxf(current_chip(), shown_hp)
		_since_loss = 0.0
		_since_hit = 0.0
	if c.emptied:
		_since_warn = 0.0
	var changed := not was_known or p_hp != hp or p_max_hp != max_hp or p_stamina != stamina or p_max_stamina != max_stamina
	hp = p_hp
	max_hp = p_max_hp
	stamina = p_stamina
	max_stamina = p_max_stamina
	known = true
	if not was_known:
		# The login message: draw it as it is, no slide in from full.
		shown_hp = fraction(hp, max_hp)
		shown_stamina = fraction(stamina, max_stamina)
		chip_from = shown_hp
		# Full at login: stay hidden (as if it changed long ago). Hurt at login: show.
		_since_change = INF if full() else 0.0
	elif changed:
		_since_change = 0.0
	if c.hurt:
		shown_hp = fraction(hp, max_hp) # a loss shows at once; the chip carries the drama
	c["thump"] = c.hurt and _since_thump >= HURT_GAP
	if c.thump:
		_since_thump = 0.0
	_draw_bars()
	return c


## A swing refused for "winded" or "tired": redden the stamina track for WARN_SECONDS.
func flash_stamina() -> void:
	_since_warn = 0.0
	_since_change = 0.0
	_draw_bars()


## Every frame while playing.
func step(delta: float) -> void:
	_t += delta
	_since_loss += delta
	_since_change += delta
	_since_hit += delta
	_since_warn += delta
	_since_thump += delta
	if known:
		var k := 1.0 - exp(-SMOOTH * delta)
		var want_hp := fraction(hp, max_hp)
		# Health gains (regen in 1-point steps) glide; a loss already showed in on_vitals.
		shown_hp = lerpf(shown_hp, want_hp, k) if want_hp > shown_hp else want_hp
		shown_stamina = lerpf(shown_stamina, fraction(stamina, max_stamina), k)
	_draw_bars()


## Both bars full (or nothing known yet).
func full() -> bool:
	return not known or (hp >= max_hp and stamina >= max_stamina)


## Is anything on screen right now?
func showing() -> bool:
	return known and bars_alpha(full(), _since_change) > 0.0


func current_chip() -> float:
	return chip_value(chip_from, shown_hp, _since_loss)


## Is the stamina track red right now (a refusal or running dry just happened)?
func warning() -> bool:
	return _since_warn < WARN_SECONDS


func hide_all() -> void:
	known = false
	hp = 0
	max_hp = 0
	stamina = 0
	max_stamina = 0
	shown_hp = 1.0
	shown_stamina = 1.0
	chip_from = 1.0
	_since_loss = INF
	_since_change = INF
	_since_hit = INF
	_since_warn = INF
	_draw_bars()


func _draw_bars() -> void:
	if health_fill == null:
		return
	var bar_w := health_track.size.x
	modulate.a = bars_alpha(full(), _since_change) if known else 0.0
	health_fill.size.x = bar_w * shown_hp
	chip_fill.size.x = bar_w * current_chip()
	stamina_fill.size.x = bar_w * shown_stamina
	var glow := Color.WHITE.lerp(FLASH_GLOW, flash_amount(_since_hit))
	var pulse := low_pulse(fraction(hp, max_hp), _t)
	health_fill.self_modulate = Color(glow.r * pulse, glow.g * pulse, glow.b * pulse, 1.0)
	var track_box := stamina_track.get_theme_stylebox("panel") as StyleBoxFlat
	if track_box != null:
		track_box.bg_color = TRACK_WARN if warning() else TRACK
	health_label.text = "%d/%d" % [hp, max_hp] if known else ""

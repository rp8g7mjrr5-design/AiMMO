class_name ClientSettings
extends RefCounted
## Player preferences for this computer: mouse feel, sound, and graphics. Saved to
## user://settings.cfg (separate from client.cfg, which the login screen rewrites).
## Every value is clamped on load, so a hand-edited or old file can never break the client.

const PATH := "user://settings.cfg"
const SECTION := "settings"

const SENS_MIN := 0.25
const SENS_MAX := 3.0
const DRAW_MIN := 150.0
const DRAW_MAX := 600.0
const SHADOW_NAMES := ["Off", "Low", "High"]
const FOV_MIN := 55.0
const FOV_MAX := 100.0

var mouse_sensitivity := 1.0 ## multiplier on the base look speed
var invert_y := false
var master_volume := 0.8 ## linear, 0 to 1
var shadow_quality := 1 ## 0 off, 1 low (60 m, the art bible's Medium default), 2 high (120 m). A saved value always wins.
var draw_distance := 600.0 ## metres, camera far plane
var field_of_view := 70.0 ## degrees, vertical
var shoulder_right := true ## the action camera sits over the right shoulder (false: left)


static func from_config(cfg: ConfigFile) -> ClientSettings:
	var s := ClientSettings.new()
	s.mouse_sensitivity = _num(cfg.get_value(SECTION, "mouse_sensitivity", s.mouse_sensitivity), s.mouse_sensitivity)
	var inv: Variant = cfg.get_value(SECTION, "invert_y", s.invert_y)
	s.invert_y = typeof(inv) == TYPE_BOOL and inv
	s.master_volume = _num(cfg.get_value(SECTION, "master_volume", s.master_volume), s.master_volume)
	s.shadow_quality = int(_num(cfg.get_value(SECTION, "shadow_quality", s.shadow_quality), s.shadow_quality))
	s.draw_distance = _num(cfg.get_value(SECTION, "draw_distance", s.draw_distance), s.draw_distance)
	s.field_of_view = _num(cfg.get_value(SECTION, "field_of_view", s.field_of_view), s.field_of_view)
	var sh: Variant = cfg.get_value(SECTION, "shoulder_right", s.shoulder_right)
	s.shoulder_right = sh if typeof(sh) == TYPE_BOOL else true
	s.sanitize()
	return s


static func load_from(path: String = PATH) -> ClientSettings:
	var cfg := ConfigFile.new()
	cfg.load(path) # a missing or broken file just leaves the defaults
	return from_config(cfg)


func to_config() -> ConfigFile:
	sanitize()
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value(SECTION, "invert_y", invert_y)
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "shadow_quality", shadow_quality)
	cfg.set_value(SECTION, "draw_distance", draw_distance)
	cfg.set_value(SECTION, "field_of_view", field_of_view)
	cfg.set_value(SECTION, "shoulder_right", shoulder_right)
	return cfg


func save_to(path: String = PATH) -> Error:
	return to_config().save(path)


func sanitize() -> void:
	mouse_sensitivity = clampf(mouse_sensitivity, SENS_MIN, SENS_MAX)
	master_volume = clampf(master_volume, 0.0, 1.0)
	shadow_quality = clampi(shadow_quality, 0, SHADOW_NAMES.size() - 1)
	draw_distance = clampf(draw_distance, DRAW_MIN, DRAW_MAX)
	field_of_view = clampf(field_of_view, FOV_MIN, FOV_MAX)


## Vertical look multiplier: mouse up looks up unless invert Y is on.
func pitch_sign() -> float:
	return -1.0 if invert_y else 1.0


## The action camera's shoulder: +1 right, -1 left.
func shoulder_side() -> float:
	return 1.0 if shoulder_right else -1.0


## Volume in decibels for the master bus. Zero is silent (the bus is muted separately).
func volume_db() -> float:
	return linear_to_db(maxf(master_volume, 0.0001))


## Shadow distance in metres for the sun; 0 means shadows are off.
func shadow_distance() -> float:
	return [0.0, 60.0, 120.0][shadow_quality]


static func _num(v: Variant, fallback: float) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f := float(v)
		return f if is_finite(f) else fallback
	return fallback

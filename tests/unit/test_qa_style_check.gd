extends TestCase
## The client smoke test's Emberlight style check (art bible, "Colour"): it measures flat
## pictures correctly, masks the HUD, and fails too much ember, a black or grey night, and a big
## move away from the art bible, while a move toward it is only a note.

const Style := preload("res://tests/client_smoke/style_check.gd")

const EMBER := Color("#F2A541")
const GRASS := Color(0.45, 0.62, 0.32) ## muted natural green, saturation ~0.48
const MOON := Color(0.10, 0.14, 0.26) ## moonlit night blue


func _flat(c: Color) -> Image:
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img


func _baseline() -> Dictionary:
	return {
		"big": {"luma": 0.12, "sat_mean": 0.12, "neon_share": 0.15, "ember_share": 0.04, "warmth": 0.08, "blue_minus_green": 0.08},
		"small": {"luma": 0.03, "sat_mean": 0.03, "neon_share": 0.03, "ember_share": 0.01, "warmth": 0.02, "blue_minus_green": 0.02},
		"shots": {
			"noon": Style.measure(_flat(GRASS), 1),
			"night": Style.measure(_flat(MOON), 1),
		},
	}


func test_measure_flat_colours() -> void:
	var white := Style.measure(_flat(Color.WHITE), 1)
	check_near(white.luma, 1.0, 0.01, "white luma")
	check_near(white.sat_mean, 0.0, 0.01, "white has no saturation")
	check_near(white.warmth, 0.0, 0.01, "white is neutral")
	var ember := Style.measure(_flat(EMBER), 1)
	check_near(ember.ember_share, 1.0, 0.01, "EMBER counts as ember")
	check_near(ember.neon_share, 0.0, 0.01, "ember glow is allowed to be bright, it is not neon")
	check(ember.warmth > 0.4, "ember is warm")
	var neon := Style.measure(_flat(Color(0.1, 1.0, 0.1)), 1)
	check_near(neon.neon_share, 1.0, 0.01, "pure green is neon")
	check_near(Style.measure(_flat(GRASS), 1).neon_share, 0.0, 0.01, "muted grass is not neon")
	var moon := Style.measure(_flat(MOON), 1)
	check(moon.warmth < 0.0, "moonlight is cool")
	check(moon.blue_minus_green > 0.0, "moonlight is blue, not green")
	check(Style.measure(Image.new()).is_empty(), "empty image is unreadable")
	check(Style.measure(null).is_empty(), "null image is unreadable")


func test_hud_is_masked() -> void:
	var img := _flat(GRASS)
	img.fill_rect(Rect2i(0, 0, 64, 4), EMBER) # top bar: under the mask (14% of 36 px = 5 px)
	img.fill_rect(Rect2i(0, 24, 20, 12), EMBER) # chat box corner
	check_near(Style.measure(img, 1).ember_share, 0.0, 0.001, "ember HUD pixels are not counted")
	img.fill_rect(Rect2i(40, 20, 24, 16), EMBER)
	check(Style.measure(img, 1).ember_share > 0.2, "ember in the world is counted")


func test_baseline_shots_pass() -> void:
	var b := _baseline()
	check_eq(Style.check_shot("noon", b.shots.noon, b).fail.size(), 0, "noon at baseline")
	check_eq(Style.check_shot("night", b.shots.night, b).fail.size(), 0, "night at baseline")


func test_too_much_ember_fails() -> void:
	var img := _flat(GRASS)
	img.fill_rect(Rect2i(30, 10, 34, 26), EMBER) # ~40% of the unmasked area
	var r := Style.check_shot("noon", Style.measure(img, 1), _baseline())
	check(r.fail.size() > 0, "ember covering the screen fails")
	check("10%" in "\n".join(r.fail), "the failure names the 60/30/10 rule")


func test_black_and_grey_nights_fail() -> void:
	var b := _baseline()
	check(Style.check_shot("night", Style.measure(_flat(Color.BLACK), 1), b).fail.size() > 0, "black night fails")
	check(Style.check_shot("night", Style.measure(_flat(Color(0.2, 0.2, 0.2)), 1), b).fail.size() > 0, "grey night fails")
	check(Style.check_shot("noon", Style.measure(_flat(Color.BLACK), 1), b).fail.size() > 0, "black noon fails")
	check(Style.check_shot("noon", {}, b).fail.size() > 0, "unreadable shot fails")


func test_drift_is_direction_aware() -> void:
	var b := _baseline()
	# A night that turns warm orange-brown: a big move away from "night is blue" fails.
	var warm_night := Style.measure(_flat(Color(0.30, 0.18, 0.08)), 1)
	check(Style.check_shot("night", warm_night, b).fail.size() > 0, "night turning warm fails")
	# Grass turning neon: fails.
	var neon_noon := Style.measure(_flat(Color(0.2, 0.95, 0.1)), 1)
	check(Style.check_shot("noon", neon_noon, b).fail.size() > 0, "neon grass fails")
	# The baseline night is green-lit; a bluer, calmer night moves toward the art bible and is
	# only a note asking for the baseline to follow.
	b.shots.night = Style.measure(_flat(Color(0.08, 0.25, 0.05)), 1)
	var r := Style.check_shot("night", Style.measure(_flat(MOON), 1), b)
	check_eq(r.fail.size(), 0, "a bluer night never fails")
	check("update the baseline" in "\n".join(r.note), "it says the baseline can follow")


func test_small_drift_and_missed_targets_are_notes() -> void:
	var b := _baseline()
	var s: Dictionary = b.shots.noon.duplicate()
	s.luma += 0.05
	var r := Style.check_shot("noon", s, b)
	check_eq(r.fail.size(), 0, "small drift does not fail")
	check("small drift" in "\n".join(r.note), "small drift is printed")
	var green_night := Style.measure(_flat(Color(0.08, 0.25, 0.05)), 1)
	b.shots.night = green_night
	r = Style.check_shot("night", green_night, b)
	check_eq(r.fail.size(), 0, "today's green night does not fail on its own baseline")
	check("art bible target missed" in "\n".join(r.note), "but the missed target is printed")
	check("no baseline yet" in "\n".join(Style.check_shot("dusk", green_night, b).note), "a shot without a baseline says so")


func test_real_baseline_file_is_valid() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Style.BASELINE_PATH))
	check(parsed is Dictionary, "style_baseline.json parses")
	if not parsed is Dictionary:
		return
	for shot in ["noon", "night"]:
		var base: Dictionary = parsed.get("shots", {}).get(shot, {})
		check(not base.is_empty(), "baseline has " + shot)
		for key in Style.DIRECTION[shot]:
			check(base.has(key), "%s baseline has %s" % [shot, key])
			check(parsed.big.has(key) and parsed.small.has(key), "tolerances for " + key)
		check_eq(Style.check_shot(shot, base, parsed).fail.size(), 0, "%s baseline passes its own check" % shot)


func test_low_preset_is_held_to_noon() -> void:
	var b := _baseline()
	var r: Dictionary = Style.check_shot("low", b.shots.noon, b)
	check_eq(r.fail.size(), 0, "Low that looks like noon passes")
	check(not ("no baseline" in "\n".join(r.note)), "Low borrows noon's baseline, it needs none of its own")
	var neon := Style.check_shot("low", Style.measure(_flat(Color(0.1, 1.0, 0.1)), 1), b)
	check(neon.fail.size() > 0, "Low that turns neon fails against noon's baseline")
	check("noon baseline" in "\n".join(neon.fail), "the failure says it compared with noon")
	check(Style.check_shot("low", Style.measure(_flat(Color.BLACK), 1), b).fail.size() > 0, "a black Low frame fails noon's luma floor")


func test_hud_shots_get_hard_rules_only() -> void:
	var b := _baseline()
	# A dark overlay over the world is a big move from noon, but the HUD shots have no baseline.
	var dim := Style.check_shot("controls", Style.measure(_flat(Color(0.12, 0.12, 0.14)), 1), b)
	check_eq(dim.fail.size(), 0, "a dimmed F1 overlay is not a style failure")
	check_eq(dim.note.size(), 0, "and asks for no baseline")
	check(Style.check_shot("toast", Style.measure(_flat(Color.BLACK), 1), b).fail.size() > 0, "a black toast shot fails")
	var gold := _flat(GRASS)
	gold.fill_rect(Rect2i(30, 10, 34, 26), EMBER)
	check(Style.check_shot("toast", Style.measure(gold, 1), b).fail.size() > 0, "a toast that floods the screen with ember fails")

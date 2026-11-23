extends SceneTree
## Emberlight style check for the client smoke test's screenshots (art bible, "Colour").
##
##   godot --headless --path game -s tests/client_smoke/style_check.gd -- \
##     --shot=noon=/abs/world.png --shot=night=/abs/world-night.png \
##     --out=/abs/style_stats.json [--sheet=/abs/contact_sheet.html] [--write-baseline]
##
## Measures each shot's world area (the HUD bands are masked out) and compares it with
## tests/client_smoke/style_baseline.json:
## - Hard rules (fail): ember stays rare (the 10 of the 60/30/10 rule), night is not black and
##   not grey, and nothing is unreadable.
## - Big drift from the baseline in the wrong direction (fail): a PR that suddenly turns the
##   grass neon, the night warm, or the screen grey. Drift toward the art bible is never a
##   failure; it prints a note so the baseline can follow the world.
## - Small drift and missed art-bible targets are printed for the integrator, not failed.
## --write-baseline rewrites the baseline's numbers from these shots (for a world PR that
## changes the look on purpose; say so in the PR). --sheet writes an HTML contact sheet of every
## PNG next to the shots, with these numbers under the style shots.

const BASELINE_PATH := "res://tests/client_smoke/style_baseline.json"

## HUD areas, as fractions of the frame: the top bar, compass and goal line, and the clock and
## chat box in the bottom-left. They look the same at any time of day, so they would only
## dilute the world's numbers.
const MASKS: Array[Rect2] = [Rect2(0.0, 0.0, 1.0, 0.14), Rect2(0.0, 0.55, 0.375, 0.45)]

## Ember: the EMBER/EMBER_CORE/ASH_LEAF family, hue 15..50 degrees, strong and bright.
const EMBER_HUE_MIN := 15.0 / 360.0
const EMBER_HUE_MAX := 50.0 / 360.0
const EMBER_MIN_S := 0.5
const EMBER_MIN_V := 0.55
## Neon: "natural colours stay below about 0.65 saturation"; dark pixels don't read as neon.
const NEON_MIN_S := 0.65
const NEON_MIN_V := 0.25

## Hard rules: these fail whatever the baseline says.
const MAX_EMBER_SHARE := 0.10 ## 60/30/10: at most 10% of the screen is ember
const MIN_LUMA := {"noon": 0.15, "night": 0.02} ## a black frame means the world did not render
const MIN_NIGHT_SAT := 0.12 ## a grey night lost its moonlight blue and its ember

## Art-bible targets: printed when missed, never failed (the world is moving toward them).
const TARGETS := {
	"noon": {"neon_share": ["max", 0.10], "warmth": ["min", 0.0]},
	"night": {"neon_share": ["max", 0.10], "warmth": ["max", 0.0], "blue_minus_green": ["min", 0.0]},
}

## Which way each measure should move. "down": lower is closer to the art bible, so only a big
## rise fails. "up": the reverse. "both": a big move either way fails.
const DIRECTION := {
	"noon": {"luma": "both", "sat_mean": "down", "neon_share": "down", "ember_share": "both", "warmth": "up", "blue_minus_green": "both"},
	"night": {"luma": "both", "sat_mean": "down", "neon_share": "down", "ember_share": "both", "warmth": "down", "blue_minus_green": "up"},
}


static func _masked(x: float, y: float) -> bool:
	for r in MASKS:
		if r.has_point(Vector2(x, y)):
			return true
	return false


## Colour measures of the world area of `img`, sampled on a grid. Empty when unreadable.
## luma: mean Rec. 709 luminance. sat_mean: mean HSV saturation. neon_share: share of pixels
## over NEON_MIN_S that are not ember. ember_share: share of ember pixels. warmth: mean red
## minus blue (above 0 warm, below 0 cool). blue_minus_green: mean blue minus green (a
## moonlit night is above 0; a green-lit night is below).
static func measure(img: Image, step: int = 4) -> Dictionary:
	if img == null or img.is_empty():
		return {}
	var w := float(img.get_width())
	var h := float(img.get_height())
	var n := 0
	var luma := 0.0
	var sat := 0.0
	var neon := 0
	var ember := 0
	var warmth := 0.0
	var bg := 0.0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			if _masked(x / w, y / h):
				continue
			var c := img.get_pixel(x, y)
			n += 1
			luma += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sat += c.s
			warmth += c.r - c.b
			bg += c.b - c.g
			var is_ember := c.h >= EMBER_HUE_MIN and c.h <= EMBER_HUE_MAX and c.s >= EMBER_MIN_S and c.v >= EMBER_MIN_V
			if is_ember:
				ember += 1
			elif c.s > NEON_MIN_S and c.v > NEON_MIN_V:
				neon += 1
	if n == 0:
		return {}
	return {
		"luma": snappedf(luma / n, 0.001),
		"sat_mean": snappedf(sat / n, 0.001),
		"neon_share": snappedf(float(neon) / n, 0.001),
		"ember_share": snappedf(float(ember) / n, 0.001),
		"warmth": snappedf(warmth / n, 0.001),
		"blue_minus_green": snappedf(bg / n, 0.001),
	}


## Checks one shot. Returns {"fail": [...], "note": [...]} of human-readable lines.
static func check_shot(shot: String, stats: Dictionary, baseline: Dictionary) -> Dictionary:
	var fail: Array[String] = []
	var note: Array[String] = []
	if stats.is_empty():
		fail.append("%s: screenshot could not be read" % shot)
		return {"fail": fail, "note": note}
	# Hard rules.
	if float(stats.ember_share) > MAX_EMBER_SHARE:
		fail.append("%s: %.1f%% of the screen is ember, over the art bible's 10%% (ember must stay rare to read)" % [shot, stats.ember_share * 100.0])
	if float(stats.luma) < float(MIN_LUMA.get(shot, 0.02)):
		fail.append("%s: the frame is black (luma %.3f): did the world render?" % [shot, stats.luma])
	if shot == "night" and float(stats.sat_mean) < MIN_NIGHT_SAT:
		fail.append("night: the frame is grey (mean saturation %.3f < %.2f); night is blue and ember" % [stats.sat_mean, MIN_NIGHT_SAT])
	# Art-bible targets: notes only.
	var targets: Dictionary = TARGETS.get(shot, {})
	for key in targets:
		var t: Array = targets[key]
		var v := float(stats.get(key, 0.0))
		if (t[0] == "max" and v > float(t[1])) or (t[0] == "min" and v < float(t[1])):
			note.append("%s: art bible target missed: %s %.3f (want %s %.2f)" % [shot, key, v, "at most" if t[0] == "max" else "at least", t[1]])
	# Drift from the baseline.
	var base: Dictionary = baseline.get("shots", {}).get(shot, {})
	if base.is_empty():
		note.append("%s: no baseline yet; run with --write-baseline" % shot)
		return {"fail": fail, "note": note}
	var big: Dictionary = baseline.get("big", {})
	var small: Dictionary = baseline.get("small", {})
	var dirs: Dictionary = DIRECTION.get(shot, {})
	for key in base:
		if not stats.has(key):
			continue
		var d := float(stats[key]) - float(base[key])
		var dir: String = dirs.get(key, "both")
		var worse := absf(d) if dir == "both" else (d if dir == "down" else -d)
		var line := "%s: %s %.3f vs baseline %.3f (%+.3f)" % [shot, key, stats[key], base[key], d]
		if worse > float(big.get(key, INF)):
			fail.append(line + ", a big move away from the art bible")
		elif absf(d) > float(small.get(key, INF)):
			note.append(line + (", toward the art bible: update the baseline" if worse < 0.0 else ", small drift"))
	return {"fail": fail, "note": note}


static func _write_sheet(path: String, shots: Dictionary, results: Dictionary) -> void:
	var dir := path.get_base_dir()
	var pngs := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			pngs.append(f)
	pngs.sort()
	var html := "<!doctype html><meta charset=utf-8><title>AiMMO smoke shots</title>"
	html += "<style>body{font:14px sans-serif;background:#222;color:#eee;margin:16px}figure{display:inline-block;margin:8px;vertical-align:top}img{width:420px;display:block}pre{margin:4px 0;font-size:12px;white-space:pre-wrap;max-width:420px}</style>"
	html += "<h1>Client smoke shots</h1>"
	for f in pngs:
		html += "<figure><a href=\"%s\"><img src=\"%s\"></a><figcaption>%s" % [f, f, f]
		for shot in shots:
			if str(shots[shot]).get_file() == f:
				html += "<pre>style (%s): %s</pre>" % [shot, JSON.stringify(results[shot].stats)]
				for line in results[shot].fail + results[shot].note:
					html += "<pre>%s</pre>" % line.xml_escape()
		html += "</figcaption></figure>"
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa:
		fa.store_string(html + "\n")


func _init() -> void:
	var shots := {}
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var kv := a.substr(7)
			shots[kv.substr(0, kv.find("="))] = kv.substr(kv.find("=") + 1)
		elif a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	var baseline: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	if parsed is Dictionary:
		baseline = parsed
	var results := {}
	var failed := false
	for shot in shots:
		var stats := measure(Image.load_from_file(str(shots[shot])))
		var r := check_shot(shot, stats, baseline)
		r["stats"] = stats
		results[shot] = r
		print("[style] %s: %s" % [shot, JSON.stringify(stats)])
		for line in r.note:
			print("[style] note: " + line)
		for line in r.fail:
			print("[style] FAILED: " + line)
		failed = failed or not r.fail.is_empty()
	if args.has("out"):
		var fa := FileAccess.open(str(args.out), FileAccess.WRITE)
		if fa:
			fa.store_string(JSON.stringify(results, "  ") + "\n")
	if args.has("sheet"):
		_write_sheet(str(args.sheet), shots, results)
	if args.has("write-baseline"):
		var new_shots := {}
		for shot in results:
			new_shots[shot] = results[shot].stats
		baseline["shots"] = new_shots
		var fa := FileAccess.open(ProjectSettings.globalize_path(BASELINE_PATH), FileAccess.WRITE)
		fa.store_string(JSON.stringify(baseline, "  ", false) + "\n")
		print("[style] baseline written")
	print("[style] style check " + ("FAILED" if failed else "passed"))
	quit(1 if failed else 0)

extends SceneTree
## Brightness check for the client smoke test's screenshots.
##
##   godot --headless --path game -s tests/client_smoke/image_stats.gd -- \
##     --day=/abs/world.png --night=/abs/world-night.png
##
## Prints the mean luminance (0..1) of each picture and exits 1 unless:
## - the day picture is not near-black (the world actually rendered),
## - the night picture is clearly darker than the day one (the sky follows the clock),
## - the night picture is not pure black (moon, stars and ambient light still show the world).
## Thresholds are loose on purpose: software OpenGL under xvfb renders slightly differently
## from a GPU, and art direction will keep tuning the colours.

const MIN_DAY := 0.15 ## a lit world is well above this; a black or failed render is below it
const MIN_NIGHT := 0.01 ## pure black means the night scene lost all its light
const MAX_NIGHT_RATIO := 0.8 ## night must be at most 80% as bright as day


## Mean Rec. 709 luminance of an image, sampled on a grid (fast, and plenty for a mean).
static func mean_luminance(img: Image, step: int = 4) -> float:
	if img == null or img.is_empty():
		return -1.0
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return total / n if n > 0 else -1.0


## Returns a list of human-readable problems; empty means the pair looks right.
static func check(day_lum: float, night_lum: float) -> Array[String]:
	var problems: Array[String] = []
	if day_lum < 0.0:
		problems.append("day screenshot could not be read")
	if night_lum < 0.0:
		problems.append("night screenshot could not be read")
	if not problems.is_empty():
		return problems
	if day_lum < MIN_DAY:
		problems.append("day screenshot is too dark (%.3f < %.2f): did the world render?" % [day_lum, MIN_DAY])
	if night_lum < MIN_NIGHT:
		problems.append("night screenshot is black (%.3f < %.2f)" % [night_lum, MIN_NIGHT])
	if night_lum > day_lum * MAX_NIGHT_RATIO:
		problems.append("night is not darker than day (night %.3f vs day %.3f)" % [night_lum, day_lum])
	return problems


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var day := Image.load_from_file(str(args.get("day", "")))
	var night := Image.load_from_file(str(args.get("night", "")))
	var d := mean_luminance(day)
	var n := mean_luminance(night)
	print("[smoke] mean luminance: day %.3f, night %.3f" % [d, n])
	var problems := check(d, n)
	for p in problems:
		print("[smoke] brightness check failed: " + p)
	if problems.is_empty():
		print("[smoke] brightness check passed")
	quit(1 if not problems.is_empty() else 0)

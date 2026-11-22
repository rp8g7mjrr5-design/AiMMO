extends TestCase
## The client smoke test's day/night brightness check: it measures pictures correctly and
## catches a black render, a black night, and a night that is as bright as day.

const ImageStats := preload("res://tests/client_smoke/image_stats.gd")


func _flat(c: Color) -> Image:
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img


func test_mean_luminance() -> void:
	check_near(ImageStats.mean_luminance(_flat(Color.WHITE)), 1.0, 0.01, "white")
	check_near(ImageStats.mean_luminance(_flat(Color.BLACK)), 0.0, 0.01, "black")
	check_near(ImageStats.mean_luminance(_flat(Color(0, 1, 0))), 0.7152, 0.01, "green weighs most")
	var half := _flat(Color.BLACK)
	half.fill_rect(Rect2i(0, 0, 32, 36), Color.WHITE)
	check_near(ImageStats.mean_luminance(half), 0.5, 0.05, "half white")
	check(ImageStats.mean_luminance(Image.new()) < 0.0, "empty image is unreadable")
	check(ImageStats.mean_luminance(null) < 0.0, "null image is unreadable")


func test_check_passes_real_shots() -> void:
	# Measured from the smoke test's own noon and midnight screenshots on 2026-11-22.
	check_eq(ImageStats.check(0.735, 0.081).size(), 0, "real day/night pair passes")


func test_check_catches_problems() -> void:
	check_eq(ImageStats.check(0.02, 0.01).size() > 0, true, "black day render fails")
	check_eq(ImageStats.check(0.7, 0.0).size() > 0, true, "pure black night fails")
	check_eq(ImageStats.check(0.7, 0.7).size() > 0, true, "night as bright as day fails")
	check_eq(ImageStats.check(-1.0, 0.1).size() > 0, true, "missing day shot fails")
	check_eq(ImageStats.check(0.7, -1.0).size() > 0, true, "missing night shot fails")

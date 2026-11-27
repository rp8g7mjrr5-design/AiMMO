extends TestCase
## The windows' leather (art bible section 9, owner pick 2026-11-27): one generated texture,
## see-through outside the rounded rim, dark muted leather inside, tan stitches and iron studs.


func test_leather_texture() -> void:
	var img := UiSkin.leather()
	check_eq(img.get_width(), UiSkin.SIZE)
	check_eq(img.get_height(), UiSkin.SIZE)
	check(img.get_pixel(0, 0).a < 0.05, "the corner outside the rounded rim is see-through")
	var mid := img.get_pixel(UiSkin.SIZE / 2, UiSkin.SIZE / 2)
	check(mid.a > 0.9, "the leather is nearly opaque, so text reads on a noon sky")
	check(mid.v < 0.35, "the leather is dark")
	check(mid.s < 0.6, "the leather is a muted natural")
	check(mid.r >= mid.b, "the leather is warm brown")
	var stud := img.get_pixel(24, 24)
	check(stud.s < 0.2 and stud.v > 0.3, "an iron stud sits in the corner")
	var stitched := 0
	for x in range(60, 160):
		var c := img.get_pixel(x, 13)
		if c.v > 0.45 and c.r > c.b:
			stitched += 1
	check(stitched > 40 and stitched < 90, "a dashed tan stitch runs along the top (%d px lit)" % stitched)


func test_shared_and_cheap() -> void:
	check(UiSkin.panel_texture() == UiSkin.panel_texture(), "built once and shared by every window")
	var box := UiSkin.panel_box(6.0)
	check_eq(box.texture_margin_left, float(UiSkin.MARGIN), "a nine-patch: the studs and stitches never stretch at the corners")
	check_eq(box.content_margin_top, 6.0)


func test_check_box_reads_on_the_leather() -> void:
	var off := UiSkin.check_icon(false).get_image()
	var on := UiSkin.check_icon(true).get_image()
	check(off.get_pixel(0, 9).v > 0.5, "the box has a pale thread rim you can see on dark leather")
	var ember := 0
	for y in on.get_height():
		for x in on.get_width():
			if on.get_pixel(x, y).is_equal_approx(Palette.EMBER):
				ember += 1
	check(ember > 10, "a ticked box shows an ember tick (%d px)" % ember)

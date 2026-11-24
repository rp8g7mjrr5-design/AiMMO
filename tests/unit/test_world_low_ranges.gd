extends TestCase

const LOW := 0.5 ## Chunks.RANGE_SCALES[Quality.LOW]
## World stream: the Low Graphics preset pulls every chunked layer's draw distance in (qa's
## "Low barely draws less", 2026-11-23). Low cuts at half of each layer's range, Medium and High
## keep today's ranges, the chunk padding still holds so nothing inside the shorter range is
## cut, and a Settings change rescales the built world within one poll.


func _instances(n: int, spread: float) -> Array:
	var out: Array = []
	for i in n:
		var p := Vector3(fmod(i * 37.0, spread) - spread * 0.5, 0.0, fmod(i * 53.0, spread) - spread * 0.5)
		out.append([Transform3D(Basis(), p), Color(0.5, 0.5, 0.5)])
	return out


func test_scales_by_level() -> void:
	check_eq(Chunks.range_scale(Quality.LOW), 0.5, "Low draws half of each range")
	check_eq(Chunks.range_scale(Quality.MEDIUM), 1.0, "Medium is today's look")
	check_eq(Chunks.range_scale(Quality.HIGH), 1.0, "High is today's look")
	check_eq(Chunks.range_scale(-3), 0.5, "out of range clamps low")
	check_eq(Chunks.range_scale(9), 1.0, "out of range clamps high")
	check_eq(Chunks.RANGE_SCALES.size(), Quality.NAMES.size(), "one scale per Graphics level")


func test_cut_keeps_padding() -> void:
	for l in Chunks.RANGES:
		var full := Chunks.cut_of(l)
		var low := Chunks.cut_of(l, LOW)
		check(low < full, "%s: Low cuts nearer (%.0f < %.0f)" % [l, low, full])
		check(low >= Chunks.range_of(l) * LOW + Chunks.size_of(l) * 0.7071, "%s: nothing inside the Low range is cut" % l)
	check_eq(Chunks.cut_of("Water", LOW), 0.0, "unlisted layers stay unlimited on Low")
	check(Chunks.cut_of("Trunks", LOW) < Chunks.cut_of("Trunks") - 140.0 and Chunks.cut_of("Trunks", LOW) < 250.0, "Low trees stop 150 m sooner, well inside the 400 m far plane")
	for l in NodeProps.RANGES:
		check(NodeProps.cut_of(l, LOW) < NodeProps.cut_of(l), "%s: node layer cuts nearer on Low" % l)
	for l in ["NodeTrunks", "NodeAshCrowns", "NodePineTiers", NodeProps.GLOW_LAYER]:
		check_eq(NodeProps.cut_of(l, LOW), 0.0, "%s: whole landmark layers are never cut" % l)


func test_build_reads_quality_and_rescales() -> void:
	var was := Quality.level
	Quality.level = Quality.LOW
	check_eq(Chunks.quality_range_scale(), LOW, "reads the client's Quality.level")
	var layer := Chunks.build("Rocks", BoxMesh.new(), _instances(60, 400.0), StandardMaterial3D.new())
	check(layer.get_child_count() > 1, "several chunks")
	for c in layer.get_children():
		check(is_equal_approx((c as GeometryInstance3D).visibility_range_end, Chunks.cut_of("Rocks", LOW)), "built on Low: Low cut")
	check_eq(Chunks.apply_range_scale(layer, 1.0), layer.get_child_count(), "every chunk rescaled")
	for c in layer.get_children():
		check(is_equal_approx((c as GeometryInstance3D).visibility_range_end, Chunks.cut_of("Rocks")), "back to the full cut")
	check_eq(float(layer.get_meta("range_scale")), 1.0, "remembers the scale")
	Quality.level = was
	layer.free()
	var plain := Chunks.build("Water", BoxMesh.new(), _instances(10, 300.0), StandardMaterial3D.new())
	check_eq(Chunks.apply_range_scale(plain, LOW), 0, "unranged layers are left alone")
	for c in plain.get_children():
		check_eq((c as GeometryInstance3D).visibility_range_end, 0.0, "still unlimited")
	plain.free()
	check_eq(Chunks.apply_range_scale(null, LOW), 0, "null is safe")


func test_node_props_follow_low() -> void:
	var was := Quality.level
	Quality.level = Quality.LOW
	var root := NodeProps.build(ResourceNodes.all())
	Quality.level = was
	for l in NodeProps.RANGES:
		for c in root.get_node(l).get_children():
			check(is_equal_approx((c as GeometryInstance3D).visibility_range_end, NodeProps.cut_of(l, LOW)), "%s built on Low" % l)
	Chunks.apply_range_scale(root, 1.0)
	for l in NodeProps.RANGES:
		for c in root.get_node(l).get_children():
			check(is_equal_approx((c as GeometryInstance3D).visibility_range_end, NodeProps.cut_of(l)), "%s back to full" % l)
	root.free()


func test_watch_follows_the_setting() -> void:
	var was := Quality.level
	var root := Node3D.new()
	var layer := Chunks.build("Trunks", BoxMesh.new(), _instances(40, 500.0), StandardMaterial3D.new())
	root.add_child(layer)
	var watch := Chunks.RangeWatch.new()
	root.add_child(watch)
	Quality.level = Quality.LOW
	watch._process(1.0)
	check_eq(float(root.get_meta("range_scale")), LOW, "pulled in within one poll")
	var c0 := layer.get_child(0) as GeometryInstance3D
	check(is_equal_approx(c0.visibility_range_end, Chunks.cut_of("Trunks", LOW)), "trees cut nearer on Low")
	Quality.level = Quality.HIGH
	watch._process(0.1)
	check_eq(float(root.get_meta("range_scale")), LOW, "waits for the next poll")
	watch._process(1.0)
	check(is_equal_approx(c0.visibility_range_end, Chunks.cut_of("Trunks")), "High puts the full range back")
	Quality.level = was
	root.free()

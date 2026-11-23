extends TestCase
## World stream: the Graphics quality thins the wildflowers (art bible section 7, client's
## `Quality.flora_density()`). Low draws half the patches, Medium and High all of them, a
## patch is drawn or hidden whole, and birches and boulders (landmarks with camera solids)
## never thin.


func _flowers() -> Array:
	return Flora.spots().filter(func(s): return s.kind == "flowers")


func test_rank_is_stable_and_spread() -> void:
	var low := 0
	var flowers := _flowers()
	for s in flowers:
		var r := Flora.rank(s)
		check(r >= 0.0 and r < 1.0, "rank in 0..1")
		check_eq(Flora.rank(s), r, "same rank every time")
		if r < 0.5:
			low += 1
	var share := float(low) / flowers.size()
	check(share > 0.35 and share < 0.65, "about half the patches stay on Low (%.2f)" % share)


func test_shown_count() -> void:
	var ranks := PackedFloat32Array([0.1, 0.2, 0.2, 0.6, 0.9])
	check_eq(Flora.shown_count(ranks, 1.0), 5, "density 1 shows everything")
	check_eq(Flora.shown_count(ranks, 0.5), 3, "density 0.5 shows ranks under 0.5")
	check_eq(Flora.shown_count(ranks, 0.0), 0, "density 0 shows nothing")
	check_eq(Flora.shown_count(PackedFloat32Array(), 0.5), 0, "empty chunk")


func test_ranked_layout_keeps_every_flower() -> void:
	var ranked := Flora.ranked_layout(Flora.spots())
	var lay := Flora.layout(Flora.spots())
	for l in Flora.THINNED:
		check_eq(ranked[l].size(), lay[l].size(), "%s: same number of parts, only reordered" % l)
		var prev := -1.0
		var sorted := true
		for inst in ranked[l]:
			sorted = sorted and inst[2] >= prev
			prev = inst[2]
		check(sorted, "%s in rank order" % l)
	check(not Flora.THINNED.has("BirchBark") and not Flora.THINNED.has("MossRocks"), "landmarks with camera solids never thin")


func test_low_draws_half_the_patches_whole() -> void:
	var flora := Flora.build()
	check_eq(float(flora.get_meta("density")), 1.0, "Medium (the default) draws every flower")
	check(flora.get_node_or_null("QualityWatch") != null, "follows the Graphics setting live")
	var want := 0
	for s in _flowers():
		if Flora.rank(s) < Quality.flora_density(Quality.LOW):
			want += 1
	Flora.apply_density(flora, Quality.flora_density(Quality.LOW))
	var shown := {}
	for l in Flora.THINNED:
		var n := 0
		var total := 0
		for c in flora.get_node(l).get_children():
			var mm := (c as MultiMeshInstance3D).multimesh
			total += mm.instance_count
			n += mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		shown[l] = n
		check(n < total * 0.65 and n > total * 0.35, "%s: Low draws about half (%d of %d)" % [l, n, total])
	check_eq(shown["FlowerStems"], want * Flora.FLOWERS_PER_PATCH, "whole patches: every stem of a shown patch")
	check_eq(shown["FlowerBlooms"], shown["FlowerStems"], "never a stem without its bloom")
	for c in flora.get_node("BirchBark").get_children():
		check_eq((c as MultiMeshInstance3D).multimesh.visible_instance_count, -1, "birches stay whole on Low")
	Flora.apply_density(flora, Quality.flora_density(Quality.HIGH))
	for c in flora.get_node("FlowerBlooms").get_children():
		check_eq((c as MultiMeshInstance3D).multimesh.visible_instance_count, -1, "back to every flower on High")
	flora.free()


func test_watch_follows_the_setting() -> void:
	var was := Quality.level
	var flora := Flora.build()
	var watch := flora.get_node("QualityWatch")
	Quality.level = Quality.LOW
	check_eq(Flora.quality_density(), 0.5, "reads the client's Quality")
	watch._process(1.0)
	check_eq(float(flora.get_meta("density")), 0.5, "thinned within one poll")
	Quality.level = was
	watch._process(1.0)
	check_eq(float(flora.get_meta("density")), Quality.flora_density(), "fills back in")
	flora.free()

extends TestCase
## World stream: Emberlight part 4 (art bible sections 4 and 5). The day spends longer in
## golden light, nights are blue and ember (never green-black), the valley floors hold a
## warm height haze, and ember motes rise over the old ember ash from dusk to dawn,
## capped by the Graphics quality.


func _warmth(c: Color) -> float:
	return c.r - c.b


func test_golden_hour_lasts() -> void:
	# Sample the daylight hours: most of them must have a clearly warm key light.
	var warm := 0
	var day := 0
	for i in 200:
		var s := SkyClock.sample(i / 200.0)
		if s.sun_height <= 0.05:
			continue
		day += 1
		if _warmth(s.light_color) > 0.2:
			warm += 1
	check(day > 50, "enough daylight samples")
	check(float(warm) / day > 0.6, "the sun is golden most of the day (%d of %d)" % [warm, day])
	var noon := SkyClock.sample(0.5)
	check(_warmth(noon.light_color) > 0.08, "noon is short and still warm")
	check(_warmth(SkyClock.sample(0.30).light_color) > _warmth(noon.light_color), "mid-morning warmer than noon")
	# The day's fog is the art bible's warm valley HAZE.
	check(_warmth(SkyClock.sample(0.33).fog) > 0.2, "golden haze by day")


func test_nights_are_blue_and_ember() -> void:
	var night := SkyClock.sample(0.0)
	var l: Color = night.light_color
	check(l.b > l.r and l.b > l.g, "moonlight is blue")
	check((night.fog as Color).b > (night.fog as Color).r, "night haze is blue")
	check((night.fog as Color).get_luminance() > 0.08, "night haze is never black")
	check((night.sky_top as Color).b > (night.sky_top as Color).g, "night sky leans blue")
	check_near(night.night, 1.0, 0.001, "full night paint at midnight")
	check_eq(SkyClock.sample(0.5).night, 0.0, "no night paint at noon")
	# It eases in through the blue hour, after the lamps are already lit.
	var dusk := 0.77
	check(SkyClock.night_amount(dusk) > 0.0 and SkyClock.night_amount(dusk) < 1.0, "easing in at dusk")
	check(Lamps.night_glow(0.76) > SkyClock.night_amount(0.76), "lamps come on before the night paint")


func test_night_paint_in_the_shader() -> void:
	var src := Emberlight.source("solid")
	check(src.contains("global uniform float ember_night"), "every Emberlight surface reads the night")
	check(src.contains("night_desat"), "and drains its colour by it")
	Emberlight.set_night(0.7) # registered with the renderer, no error
	Emberlight.set_night(0.0)


func test_height_haze_and_sun_scatter() -> void:
	var we := WorldBuilder._environment()
	var env := we.environment
	check(env.fog_height_density > 0.0, "height haze on")
	check(env.fog_height > Terrain.water_level() and env.fog_height < 6.0, "haze sits in the valley floor, under the forest line")
	check(env.fog_sun_scatter > 0.0, "the haze glows towards the sun")
	we.free()


func test_motes_anchor_on_ember_things() -> void:
	var anchors := Motes.anchors()
	check(anchors.size() > 100, "motes rise over every ember ash (%d)" % anchors.size())
	var kinds := {}
	var tier2 := 0
	for a in anchors:
		kinds[a.kind] = true
		check(a.kind == "ash", "only ember things breathe motes (if it glows ember, you can use it)")
		if a.weight > 1.0:
			tier2 += 1
	check(kinds.has("ash") and not kinds.has("scrub"), "ash breathes motes, scrub never does")
	check(tier2 > 0, "the old ember ashes get a taller plume")


func test_mote_pool_follows_quality() -> void:
	check_eq(Motes.per_anchor(Quality.motes_scale(Quality.LOW)), 3, "Low: 3 per anchor")
	check_eq(Motes.per_anchor(Quality.motes_scale(Quality.MEDIUM)), Motes.PER_ANCHOR, "Medium: the default")
	check_eq(Motes.per_anchor(Quality.motes_scale(Quality.HIGH)), 9, "High: 9 per anchor")
	check_eq(Motes.per_anchor(9.0), 9, "capped at the pool size")
	var anchors := Motes.anchors()
	var pool := Motes.layout(anchors)
	check_eq(pool.size(), anchors.size() * 9, "the pool is built at High")
	# Any prefix covers every anchor: the first N motes are one per anchor, in anchor order.
	for a in anchors.size():
		var m: Dictionary = pool[a]
		var flat := Vector2(m.origin.x - anchors[a].pos.x, m.origin.z - anchors[a].pos.z)
		var k: Array = Motes.KINDS[anchors[a].kind]
		var spread: float = anchors[a].scale * (Motes.TIER2_SPREAD if anchors[a].weight > 1.0 else 1.0)
		check(flat.length() <= k[1] * spread + 0.001, "mote %d near its anchor" % a)
		check(flat.length() >= k[0] * spread - 0.001, "mote %d outside the crown" % a)
	check_eq(Motes.layout(anchors), pool, "deterministic")


func test_motes_rise_and_fade() -> void:
	var pool := Motes.layout(Motes.anchors())
	var m: Dictionary = pool[3]
	var life := 1.0 / (m.custom as Color).g
	var t0 := (1.0 - (m.custom as Color).r) * life + 0.05 # just after a birth
	var a := Motes.mote_at(m, t0)
	var b := Motes.mote_at(m, t0 + life * 0.5)
	check(b.pos.y > a.pos.y + 1.0, "it rises")
	check(a.alpha < 0.2, "born faint")
	check(b.alpha > 0.9, "brightest mid-rise")
	check(Motes.amount(0.5) == 0.0 and Motes.amount(0.0) == 1.0, "none by day, all at night")
	check(Motes.amount(0.755) > 0.3, "already rising at dusk")


func test_motes_node_one_draw_and_live_quality() -> void:
	var world := Node3D.new()
	var mmi := Motes.build()
	world.add_child(mmi)
	check_eq(mmi.name, StringName(Motes.NODE_NAME), "named")
	check(not mmi.visible, "hidden until dusk")
	check_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow pass")
	check(mmi.material_override == Motes.material(), "one shared material")
	var anchors: int = mmi.get_meta("anchors")
	var was := Quality.level
	Quality.level = Quality.MEDIUM
	Motes.apply(world, 1.0)
	check(mmi.visible, "on at night")
	check_eq(mmi.multimesh.visible_instance_count, anchors * Motes.PER_ANCHOR, "Medium count")
	Quality.level = Quality.LOW
	Motes.apply(world, 1.0)
	check_eq(mmi.multimesh.visible_instance_count, anchors * 3, "Low thins them live")
	Motes.apply(world, 0.0)
	check(not mmi.visible, "gone by day")
	Quality.level = was
	Motes.apply(null, 1.0) # safe without a world
	world.free()


func test_shader_source_compiles_shape() -> void:
	var code: String = Motes.material().shader.code
	check(code.contains("blend_add") and code.contains("unshaded"), "additive, unlit sparks")
	check(not code.contains("$"), "every placeholder filled")
	check(code.contains("ember_pulse"), "they swell with the heartbeat")

extends TestCase
## World stream: night on the Compatibility renderer (opengl3). Godot 4.3's Compatibility
## renderer linearises a shader's ALBEDO and EMISSION itself; ours are linear already, so
## without a fix every colour was linearised twice and night went near black. Emberlight,
## Motes and the level-up sparks encode their colours once, on Compatibility only.


func test_encode_inverts_godots_own_conversion() -> void:
	# Night lives in the darks: the round trip must hold there, not just at mid grey.
	for lin in [0.0005, 0.002, 0.01, 0.03, 0.08, 0.2, 0.5, 1.0, 2.5]:
		var back := Emberlight.compat_decode(Emberlight.compat_encode(lin))
		check(absf(back - lin) <= maxf(lin * 0.01, 0.00002), "linear %.4f survives Compatibility's conversion (got %.5f)" % [lin, back])
	check_eq(Emberlight.compat_encode(-0.5), 0.0, "negative paint is clamped, never NaN")
	# The bug in numbers: a mid tone linearised twice keeps about a fifth of its brightness.
	check(Emberlight.compat_decode(0.2) < 0.2 * 0.25, "a double conversion really is that dark")


func test_shaders_switch_on_compat_only() -> void:
	for v in Emberlight.VARIANTS:
		var on := Emberlight.source(v, true)
		var off := Emberlight.source(v, false)
		check(on.begins_with("#define COMPAT_SRGB"), "%s: Compatibility gets the encode" % v)
		check(not off.contains("#define COMPAT_SRGB"), "%s: Forward+ and Mobile don't" % v)
		check(on.contains("ALBEDO = compat_encode(") and on.contains("EMISSION = compat_encode(EMISSION)"), "%s: albedo and glow both encoded" % v)
		check(on.contains("compat_decode(emission_lin)"), "%s: the sRGB emission colour uniform is linearised first" % v)
		check(not on.contains("$") and not off.contains("$"), "%s: every token filled in" % v)
		check(on.find("void fragment()") < on.rfind("compat_encode(ALBEDO"), "%s: the encode is the last word on ALBEDO" % v)
	check(not Emberlight.srgb_output(), "the headless test run is not Compatibility")
	check(Emberlight.COMPAT_ALBEDO > 0.3 and Emberlight.COMPAT_ALBEDO <= 1.0, "the brightness match is a gentle scale, never a blackout")


func test_detection_can_be_pinned() -> void:
	Emberlight.force_srgb_output = 1
	check(Emberlight.srgb_output(), "pinned on")
	check(Emberlight.compat_define() != "", "the define follows the pin")
	Emberlight.force_srgb_output = 0
	check(not Emberlight.srgb_output(), "pinned off")
	Emberlight.force_srgb_output = -1


func test_motes_and_sparks_carry_the_fix() -> void:
	# Built headless, so the define is off; the guarded encode must still be in the source.
	var motes: String = Motes.material().shader.code
	check(motes.contains("#ifdef COMPAT_SRGB") and motes.contains("ALBEDO = compat_encode(ALBEDO)"), "motes encode on Compatibility")
	check(not motes.contains("$"), "motes: every token filled in")
	var sparks: String = LevelUpFx._spark_shader().code
	check(sparks.contains("ALBEDO = compat_encode(ALBEDO)") and not sparks.contains("$"), "level-up sparks encode on Compatibility")

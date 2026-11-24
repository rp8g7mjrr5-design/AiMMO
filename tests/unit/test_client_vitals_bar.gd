extends TestCase
## Health and stamina bar (protocol v7 s2c_vitals): a hit drops the fill at once and leaves a
## pale chip that holds then drains; low health pulses; regen glides; both full fades the bars
## out; the login message at full never pops them up; a winded refusal reddens the stamina
## track; and the thump is rate limited.


func _bar() -> VitalsBar:
	var b := VitalsBar.new()
	b.setup(Theme.new())
	return b


func _run(b: VitalsBar, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		b.step(0.02)
		t += 0.02


func test_fraction() -> void:
	check(is_equal_approx(VitalsBar.fraction(70, 100), 0.7), "70 of 100 is 0.7")
	check(VitalsBar.fraction(150, 100) == 1.0 and VitalsBar.fraction(-5, 100) == 0.0, "clamped")
	check(VitalsBar.fraction(0, 0) == 1.0, "unknown max reads full, no divide by zero")


func test_chip_holds_then_drains() -> void:
	check(VitalsBar.chip_value(1.0, 0.6, 0.0) == 1.0, "the chip starts where health was")
	check(VitalsBar.chip_value(1.0, 0.6, VitalsBar.CHIP_HOLD * 0.9) == 1.0, "it holds for CHIP_HOLD")
	var mid := VitalsBar.chip_value(1.0, 0.6, VitalsBar.CHIP_HOLD + 0.2)
	check(mid < 1.0 and mid > 0.6, "then drains (%.3f)" % mid)
	check(VitalsBar.chip_value(1.0, 0.6, 10.0) == 0.6, "and stops at the health fill")
	check(VitalsBar.chip_value(0.4, 0.6, 0.0) == 0.6, "never under the fill")
	var gone := VitalsBar.CHIP_HOLD + 0.4 / VitalsBar.CHIP_RATE
	check(gone < 1.0, "a 40-point chip is gone within a second (%.2f s), no lingering clutter" % gone)


func test_fades_only_when_full() -> void:
	check(VitalsBar.bars_alpha(false, 99.0) == 1.0, "not full: always shown")
	check(VitalsBar.bars_alpha(true, VitalsBar.HOLD_SECONDS) == 1.0, "full: held a moment")
	check(VitalsBar.bars_alpha(true, VitalsBar.HOLD_SECONDS + VitalsBar.FADE_SECONDS) == 0.0, "then gone")
	var half := VitalsBar.bars_alpha(true, VitalsBar.HOLD_SECONDS + VitalsBar.FADE_SECONDS * 0.5)
	check(half > 0.4 and half < 0.6, "fading halfway (%.2f)" % half)


func test_low_health_pulses() -> void:
	check(VitalsBar.low_pulse(0.8, 0.3) == 1.0, "healthy: steady")
	var lo := 9.0
	var hi := -9.0
	for i in 40:
		var v := VitalsBar.low_pulse(0.1, i * VitalsBar.LOW_PERIOD / 40.0)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	check(hi - lo > 0.4, "at 10%% it pulses visibly (%.2f..%.2f)" % [lo, hi])
	check(lo > 0.5 and hi < 1.5, "but never blacks out or blows out")
	var shallow := VitalsBar.low_pulse(0.29, VitalsBar.LOW_PERIOD * 0.25)
	var deep := VitalsBar.low_pulse(0.05, VitalsBar.LOW_PERIOD * 0.25)
	check(deep > shallow, "lower health pulses harder")


func test_change_reads_the_message() -> void:
	var first := VitalsBar.change(false, 0, 100, 0, 100)
	check(not first.hurt and first.lost == 0, "the login message is not a hit")
	var hit := VitalsBar.change(true, 100, 70, 100, 100)
	check(hit.hurt and hit.lost == 30, "30 points lost")
	check(not VitalsBar.change(true, 70, 71, 100, 100).hurt, "regen is not a hit")
	check(VitalsBar.change(true, 10, 0, 100, 100).knocked, "0 health is a knock-down")
	check(VitalsBar.change(true, 100, 100, 8, 0).emptied, "stamina running dry")


func test_login_at_full_stays_hidden() -> void:
	var b := _bar()
	check(not b.showing(), "nothing known: nothing shown")
	var c := b.on_vitals(100, 100, 100, 100)
	check(not c.hurt and not c.thump, "no thump at login")
	check(not b.showing(), "full at login: the bars don't pop up")
	check(b.health_label.text == "100/100", "the number is ready for when they do")
	b.free()


func test_a_hit_shows_drops_and_chips() -> void:
	var b := _bar()
	b.on_vitals(100, 100, 100, 100)
	var c := b.on_vitals(70, 100, 100, 100)
	check(c.hurt and c.thump and c.lost == 30, "a hit thumps")
	check(b.showing() and b.modulate.a == 1.0, "a hit shows the bars")
	check(is_equal_approx(b.shown_hp, 0.7), "the fill drops at once")
	check(b.current_chip() == 1.0, "the lost 30 stays as a chip")
	var w := b.health_track.size.x
	check(is_equal_approx(b.health_fill.size.x, w * 0.7), "drawn fill matches")
	check(is_equal_approx(b.chip_fill.size.x, w), "drawn chip matches")
	check(b.health_fill.self_modulate.r > 1.2, "the fill flashes bright on the hit")
	_run(b, 1.5)
	check(is_equal_approx(b.current_chip(), 0.7), "the chip drained to the fill")
	check(is_equal_approx(b.health_fill.self_modulate.r, 1.0), "the flash is over")
	check(b.showing(), "not full: the bars stay up")
	b.free()


func test_two_quick_hits_make_one_longer_chip() -> void:
	var b := _bar()
	b.on_vitals(100, 100, 100, 100)
	b.on_vitals(80, 100, 100, 100)
	b.step(0.05)
	var c := b.on_vitals(60, 100, 100, 100)
	check(b.current_chip() == 1.0, "the chip still starts at full health")
	check(not c.thump, "and the second thump inside HURT_GAP is dropped")
	b.step(VitalsBar.HURT_GAP)
	check(b.on_vitals(50, 100, 100, 100).thump, "a later hit thumps again")
	b.free()


func test_regen_glides_and_full_fades_out() -> void:
	var b := _bar()
	b.on_vitals(100, 100, 100, 100)
	b.on_vitals(60, 100, 100, 100)
	_run(b, 1.0)
	b.on_vitals(61, 100, 100, 100)
	check(b.shown_hp < 0.61, "a gain doesn't jump")
	_run(b, 0.5)
	check(absf(b.shown_hp - 0.61) < 0.005, "it glides there")
	b.on_vitals(100, 100, 100, 100)
	_run(b, VitalsBar.HOLD_SECONDS * 0.5)
	check(b.showing(), "back to full: held a moment")
	_run(b, VitalsBar.HOLD_SECONDS + VitalsBar.FADE_SECONDS)
	check(not b.showing() and b.modulate.a == 0.0, "then the bars fade away")
	b.free()


func test_stamina_warns_on_a_refusal_and_running_dry() -> void:
	var b := _bar()
	b.on_vitals(100, 100, 100, 100)
	b.flash_stamina()
	check(b.warning() and b.showing(), "a winded refusal reddens the stamina track and shows it")
	var box := b.stamina_track.get_theme_stylebox("panel") as StyleBoxFlat
	check(box.bg_color == VitalsBar.TRACK_WARN, "drawn red")
	_run(b, VitalsBar.WARN_SECONDS + 0.05)
	check(not b.warning() and box.bg_color == VitalsBar.TRACK, "then back to normal")
	b.on_vitals(100, 100, 0, 100)
	check(b.warning(), "running dry warns too")
	check(is_equal_approx(b.stamina_fill.size.x, b.stamina_track.size.x), "stamina eases down, not snaps")
	_run(b, 0.5)
	check(b.stamina_fill.size.x < 1.0, "and is empty soon after")
	b.free()


func test_hide_all_forgets() -> void:
	var b := _bar()
	b.on_vitals(100, 100, 100, 100)
	b.on_vitals(40, 100, 100, 100)
	b.hide_all()
	check(not b.known and not b.showing() and b.modulate.a == 0.0, "disconnect hides and forgets")
	var c := b.on_vitals(100, 100, 100, 100)
	check(not c.hurt, "the next login is not a hit")
	b.free()


func test_hurt_sound() -> void:
	var w := Sfx.hurt()
	check(w.data.size() == int(Sfx.RATE * Sfx.HURT_LENGTH) * 2, "0.2 s of 16-bit mono")
	var peak := 0
	var tail := 0
	for i in range(0, w.data.size(), 2):
		var v := w.data[i] | (w.data[i + 1] << 8)
		if v >= 32768:
			v -= 65536
		peak = maxi(peak, absi(v))
		if i >= w.data.size() - 8:
			tail = maxi(tail, absi(v))
	check(peak > 3000 and peak < 16000, "audible but soft (peak %d)" % peak)
	check(tail < 200, "no click at the end (%d)" % tail)
	check(Sfx.hurt().data == w.data, "deterministic")


func test_client_wires_the_bar() -> void:
	var src := FileAccess.get_file_as_string("res://client/client.gd")
	check(src.contains("net.vitals_changed.connect(_on_vitals)"), "client listens for s2c_vitals")
	check(src.contains("net.attack_refused.connect(_on_attack_refused)"), "and for refused swings")
	check(src.contains("vitals_bar.step(delta)"), "the bar steps every frame")
	check(src.contains("vitals_bar.hide_all()"), "and is cleared on disconnect")

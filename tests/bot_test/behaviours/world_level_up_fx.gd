extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (world): the level-up burst plays cleanly on a real avatar wherever the
## player is.
##
## Skills and XP are not on the server yet, so the bot stands in for a level-up: at every
## login and every few seconds it plays LevelUpFx on its own avatar (built like the client
## builds it, no renderer needed) and runs the burst frame by frame. Every spark must stay
## round the avatar and above its feet, the light must come up and go out, and the burst
## must end with nothing showing. A second burst in the middle of one must restart it, not
## stack a second on the avatar. When gameplay sends real level-ups, hook them in here.
## Bursts alternate between full day and night: by day the sky beam must shoot past 20 m
## and be gone again before the burst ends.

const BURST_EVERY := 9.0
const FRAME := 1.0 / 30.0

var _avatar: Node3D
var bursts := 0
var restarts := 0
var frames := 0
var day_beams := 0
var _since := 0.0


func setup(_net: Node) -> void:
	_avatar = AvatarBuilder.rig()


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_burst()


func on_play(delta: float) -> void:
	_since += delta
	if _since >= BURST_EVERY:
		_since = 0.0
		_burst()


func _burst() -> void:
	_avatar.position = bot.my_pos
	bursts += 1
	var day := 1.0 if bursts % 2 == 1 else 0.0
	var fx := LevelUpFx.play(_avatar, bursts, day)
	var lit := false
	var beam_top := 0.0
	var restarted := false
	var done := false
	for i in int(LevelUpFx.DURATION / FRAME) + 30:
		done = fx.advance(FRAME)
		frames += 1
		var light := fx.get_node("Light") as OmniLight3D
		if light.visible and light.light_energy > 1.0:
			lit = true
		beam_top = maxf(beam_top, fx.beam_now.height)
		if fx.age >= LevelUpFx.BEAM_TIME and fx.beam_now.strength > 0.0:
			fail("level-up sky beam still showing at %.2f s" % fx.age)
			return
		var mm := (fx.get_node("Sparks") as MultiMeshInstance3D).multimesh
		for j in mm.instance_count:
			var xf := mm.get_instance_transform(j)
			if xf.basis.get_scale().is_zero_approx():
				continue
			if xf.origin.y < 0.0 or Vector2(xf.origin.x, xf.origin.z).length() > 2.0:
				fail("level-up spark strays to %s at %.2f s" % [xf.origin, fx.age])
				return
		if not restarted and bursts % 2 == 0 and fx.age > 0.6:
			# Two skills levelling on one gather: the second restarts the first.
			restarted = true
			if LevelUpFx.play(_avatar, bursts + 1000) != fx or fx.age != 0.0:
				fail("a second level-up did not restart the burst")
				return
			restarts += 1
		if done:
			break
	if not lit:
		fail("level-up light never came on")
	if day > 0.5 and not restarted:
		if beam_top < 20.0:
			fail("daytime level-up beam only reached %.1f m" % beam_top)
		day_beams += 1
	if not done or fx.visible or (fx.get_node("Light") as OmniLight3D).visible:
		fail("level-up burst did not finish cleanly")
	var count := 0
	for ch in _avatar.get_children():
		if ch is LevelUpFx:
			count += 1
	if count != 1:
		fail("%d level-up bursts on one avatar" % count)


func on_finish() -> void:
	stat("bursts_played", bursts)
	stat("bursts_restarted", restarts)
	stat("frames_checked", frames)
	stat("day_beams", day_beams)
	if bursts == 0:
		fail("never played a level-up burst")
	if _avatar != null:
		_avatar.free()

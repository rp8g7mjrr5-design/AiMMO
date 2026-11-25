# Clean fight (owner playtest, 2026-11-25)

Owner: "no silly text when a zombie chases you and you knock it down", "cleaner animations",
"I shouldn't be able to run backwards".

- Removed every centre notice from a fight: the first-grab hint, "Zombai down.", the winded/tired
  swing refusal (the stamina bar flash and nope stay), and the knocked-down sentence. The
  knock-down is now a dark shade that lifts on you lying there, then AvatarAnimator.get_up()
  (new `lie_down()`; getting up is cut short if you walk off after GETUP_MIN).
- Movement.limit_for_facing caps a move by its angle to the facing: 1.0 ahead, 0.75 sideways,
  0.38 straight back (2.3 m/s, inside the gait's walk band). Client caps before predicting and
  sending; the server caps every c2s_input again (idempotent, so prediction agrees).
- AvatarAnimator: smoothed velocity gives the line of travel; past ~110 deg off the facing the
  stride phase runs backwards (a backpedal, no moonwalk), with hysteresis; strafing turns the
  Hips toward the travel and the Spine/Chest back so the shoulders stay square.
  Your body also turns into a swing at once (it used to swing at the old heading).
- ZombaiView: position blend is linear (smoothstep pulsed the pace 5x a second); facing keeps
  the eased blend. A late s2c_gloam that says "hunt" within STAGGER_HOLD of a heavy blow no
  longer cancels and restarts the stagger.
- ZombaiFigures: stride phase per metre now comes from the gait's cadence at the leg speed
  (ZombaiBody.strides_per_metre), so feet no longer skate at day (1.8) or night (3.4) pace.
- anim_strips.gd: new `backpedal` and `strafe` clips and a checker floor.

Didn't do: a hit-pause / camera kick on blows, a side view in the real-client recording (free
look didn't hold the camera from a script). Next: walkers grab every ~1.3 s and can chain a
knock-down quickly; worth a look at GRAB_RECOVER with the owner's feel in mind.
- CI: the image test's play container now runs with AIMMO_GLOAM=0 like the bot test's --gloam=0; a walker rising on its own grabbed an image-test bot mid-check and failed gameplay_vitals' '/hurt 30 from full' (55/100 = 100 - 30 - 15).

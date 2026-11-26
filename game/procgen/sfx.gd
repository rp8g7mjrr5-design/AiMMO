class_name Sfx
## Procedural sound effects, synthesised into 16-bit PCM at startup.

const RATE := 22050


## A soft two-note chime, used when chat arrives.
static func chime() -> AudioStreamWAV:
	return _tones([[880.0, 0.08], [1320.0, 0.14]], 0.25)


## A rising three-note arpeggio, played when you arrive in the world.
static func arrive() -> AudioStreamWAV:
	return _tones([[523.25, 0.12], [659.25, 0.12], [783.99, 0.3]], 0.3)


## A refusal ("that line wasn't sent", "this ash is spent"): a soft, low falling pair, quiet
## and short (about 0.3 s), so a "no" is heard without sounding like an error box.
const NOPE_NOTES := [[0.0, 293.66], [0.11, 233.08]] ## D4 then B-flat 3


static func nope() -> AudioStreamWAV:
	var data := PackedByteArray()
	var length := 0.34
	for i in int(RATE * length):
		var t := float(i) / RATE
		var v := 0.0
		for n in NOPE_NOTES:
			var d: float = t - float(n[0])
			if d >= 0.0:
				var f: float = n[1]
				v += (sin(TAU * f * d) * 0.85 + sin(TAU * f * 2.0 * d) * 0.12) * minf(1.0, d * 120.0) * exp(-d * 16.0)
		var s16 := int(clampf(v * 0.22, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## A crafted item: two soft wooden knocks on the bench, then a bright rising pair.
static func craft() -> AudioStreamWAV:
	var data := PackedByteArray()
	var knocks := [[0.0, 180.0], [0.11, 150.0]]
	var length := 0.62
	for i in int(RATE * length):
		var t := float(i) / RATE
		var v := 0.0
		for k in knocks:
			var dt: float = t - float(k[0])
			if dt >= 0.0:
				v += sin(TAU * float(k[1]) * dt) * exp(-dt * 38.0) * 0.9
		for n in [[0.24, 659.25], [0.34, 987.77]]:
			var dn: float = t - float(n[0])
			if dn >= 0.0:
				v += (sin(TAU * float(n[1]) * dn) * 0.8 + sin(TAU * float(n[1]) * 2.0 * dn) * 0.2) * minf(1.0, dn * 80.0) * exp(-dn * 7.0) * 0.5
		var s16 := int(clampf(v * 0.32, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## One gather paying out, by node kind: the hit itself (a wooden chop for ash and pine, a
## bright stone clink for an outcrop, a soft slosh for a sap seep), then a little pickup chime
## as the haul lands in your pack. Under half a second, so a held E never stacks them up.
static func haul(kind: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var data := PackedByteArray()
	var length := 0.46
	var lp := 0.0 # one-pole low-pass state for the noise
	var lp2 := 0.0
	for i in int(RATE * length):
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match kind:
			"stone":
				# A hard tick of noise and two inharmonic ringing partials.
				lp += (noise - lp) * 0.6
				v = lp * exp(-t * 90.0) * 0.6
				v += (sin(TAU * 1870.0 * t) * 0.5 + sin(TAU * 2960.0 * t) * 0.35) * exp(-t * 26.0) * 0.55
			"ember_sap":
				# Dark noise swelling and falling, with a wobbling pitch: a scoop of thick sap.
				lp += (noise - lp) * 0.08
				lp2 += (lp - lp2) * 0.15
				var env := sin(PI * clampf(t / 0.22, 0.0, 1.0))
				v = lp2 * env * 3.2 + sin(TAU * (240.0 + 90.0 * sin(TAU * 9.0 * t)) * t) * env * 0.18
			_:
				# Wood: a low thunk with a burst of mid noise for the bite of the blade.
				lp += (noise - lp) * 0.3
				v = sin(TAU * 150.0 * t) * exp(-t * 32.0) * 0.8 + lp * exp(-t * 60.0) * 0.7
		var dn := t - 0.16
		if dn >= 0.0:
			for f in [1318.5, 1975.5]:
				var start: float = 0.0 if f < 1500.0 else 0.06
				var d: float = dn - start
				if d >= 0.0:
					v += (sin(TAU * f * d) * 0.8 + sin(TAU * f * 2.0 * d) * 0.15) * minf(1.0, d * 120.0) * exp(-d * 14.0) * 0.32
		var s16 := int(clampf(v * 0.4, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## A grazer bolting: a short breathy snort through the nose (two quick bursts of dark, filtered
## noise with a low rasp under them), then two soft hoof thuds as it pushes off. About 0.5 s.
const SNORT_LENGTH := 0.5


static func snort() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var data := PackedByteArray()
	var lp := 0.0
	var lp2 := 0.0
	for i in int(RATE * SNORT_LENGTH):
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.22
		lp2 += (lp - lp2) * 0.35
		var v := 0.0
		for b in [[0.0, 0.09], [0.1, 0.16]]: # two bursts, the second longer
			var d: float = t - float(b[0])
			if d >= 0.0 and d < float(b[1]):
				var env := sin(PI * d / float(b[1]))
				v += lp2 * env * 2.6 + sin(TAU * 95.0 * d) * env * 0.25 * signf(sin(TAU * 31.0 * d))
		for h in [0.3, 0.38]: # hooves on turf
			var dh: float = t - h
			if dh >= 0.0:
				v += sin(TAU * 70.0 * dh) * exp(-dh * 45.0) * 0.7
		var s16 := int(clampf(v * 0.4, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## A footstep on meadow turf: a soft low thud of the heel, then a short brush of dark,
## filtered noise as the grass gives under the foot. Quiet and about 0.15 s, so a steady walk
## (about three steps a second) is a gentle patter under everything else. Each variant has
## its own noise and a slightly different heel pitch, so steps never sound copy-pasted.
const FOOTSTEP_VARIANTS := 4
const FOOTSTEP_LENGTH := 0.15


static func footstep(variant: int) -> AudioStreamWAV:
	var v_i := posmod(variant, FOOTSTEP_VARIANTS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + v_i
	var heel := 82.0 + 9.0 * v_i # Hz
	var brush_at := 0.018 + 0.006 * (v_i % 2)
	var data := PackedByteArray()
	var lp := 0.0
	var lp2 := 0.0
	var n := int(RATE * FOOTSTEP_LENGTH)
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.18
		lp2 += (lp - lp2) * 0.3
		var v := sin(TAU * heel * t) * minf(1.0, t * 400.0) * exp(-t * 55.0) * 0.8
		var d := t - brush_at
		if d >= 0.0:
			v += lp2 * sin(PI * clampf(d / 0.09, 0.0, 1.0)) * 2.4
		var fade := clampf((FOOTSTEP_LENGTH - t) / 0.02, 0.0, 1.0) # no click at the end
		var s16 := int(clampf(v * fade * 0.3, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## A left-click that hit nothing (the sky, a spent node, a tree out of reach): a dry, quiet
## tick, a 40 ms brush of bright noise over a fast-dying 640 Hz blip. It is much shorter and
## softer than nope() (a refusal from the server), so a missed swing reads as "nothing
## there", not "no". Peak about 0.18 full scale, under -12 dB on top of that in client.gd.
const MISS_LENGTH := 0.06


static func miss() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6400
	var data := PackedByteArray()
	var hp_prev := 0.0
	var hp := 0.0
	var n := int(RATE * MISS_LENGTH)
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		hp = 0.6 * (hp + noise - hp_prev) # one-pole high-pass: an airy tick, not a thud
		hp_prev = noise
		var v := hp * minf(1.0, t * 900.0) * exp(-t * 110.0) * 0.9
		v += sin(TAU * 640.0 * t) * minf(1.0, t * 600.0) * exp(-t * 70.0) * 0.5
		var fade := clampf((MISS_LENGTH - t) / 0.01, 0.0, 1.0) # no click at the end
		var s16 := int(clampf(v * fade * 0.2, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## Taking a hit (VitalsBar, on an s2c_vitals that lost health): a soft, low, muffled thump
## (about 0.2 s), a body blow rather than a crash, so it reads under footsteps and hauls
## without startling. A pitch that falls from about 110 Hz to 60 Hz plus a short burst of
## low-passed noise for the impact. Peak about 0.3 full scale, -8 dB on top in client.gd.
const HURT_LENGTH := 0.2


static func hurt() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7100
	var data := PackedByteArray()
	var lp := 0.0
	var phase := 0.0
	var n := int(RATE * HURT_LENGTH)
	for i in n:
		var t := float(i) / RATE
		var f := 60.0 + 50.0 * exp(-t * 25.0)
		phase += TAU * f / RATE
		var body := sin(phase) * minf(1.0, t * 500.0) * exp(-t * 18.0)
		lp += 0.12 * (rng.randf_range(-1.0, 1.0) - lp) # one-pole low-pass: a dull thud
		var hit := lp * 2.2 * exp(-t * 60.0)
		var fade := clampf((HURT_LENGTH - t) / 0.02, 0.0, 1.0) # no click at the end
		var s16 := int(clampf((body * 0.8 + hit) * fade * 0.32, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## A swing cutting the air (s2c_swing, played when the blow lands): band-passed noise that
## swells and falls, its centre sweeping down as the arm comes through. The heavy swing is
## longer, lower and a little louder, so you hear which one came. Peak about 0.3 full scale.
const WHOOSH_LIGHT := 0.16
const WHOOSH_HEAVY := 0.26


static func whoosh(heavy: bool) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8800 if heavy else 8700
	var length := WHOOSH_HEAVY if heavy else WHOOSH_LIGHT
	var top := 1700.0 if heavy else 2600.0
	var bottom := 450.0 if heavy else 800.0
	var gain := 0.32 if heavy else 0.26
	var data := PackedByteArray()
	var low := 0.0
	var band := 0.0
	var n := int(RATE * length)
	for i in n:
		var t := float(i) / RATE
		var u := t / length
		var f := lerpf(top, bottom, u)
		var a := clampf(TAU * f / RATE, 0.0, 1.0)
		var noise := rng.randf_range(-1.0, 1.0)
		low += a * (noise - low) # low-pass at the sweeping centre...
		band += 0.35 * (low - band) # ...minus a slower one: a soft band of air, not hiss
		var env := sin(PI * pow(u, 0.7)) # swells in, falls away
		var s16 := int(clampf((low - band) * 2.6 * env * gain, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## Your swing connecting (s2c_swing_hits with someone in it): a short dull smack, a low
## knock under a tight burst of noise, about 0.12 s. Duller than nope() and shorter than
## hurt(), so landing a blow and taking one never sound alike. Peak about 0.35 full scale.
const THWACK_LENGTH := 0.12


static func thwack() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100
	var data := PackedByteArray()
	var lp := 0.0
	var phase := 0.0
	var n := int(RATE * THWACK_LENGTH)
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (140.0 + 80.0 * exp(-t * 40.0)) / RATE
		var knock := sin(phase) * minf(1.0, t * 800.0) * exp(-t * 35.0)
		lp += 0.3 * (rng.randf_range(-1.0, 1.0) - lp)
		var smack := lp * 1.8 * exp(-t * 90.0)
		var fade := clampf((THWACK_LENGTH - t) / 0.015, 0.0, 1.0) # no click at the end
		var s16 := int(clampf((knock * 0.7 + smack) * fade * 0.35, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


static func _tones(notes: Array, volume: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for n in notes:
		var freq: float = n[0]
		var length: float = n[1]
		var samples := int(RATE * length)
		for i in samples:
			var t := float(i) / RATE
			var env := minf(1.0, t * 80.0) * exp(-t * 6.0 / length)
			var v := sin(TAU * freq * t) * 0.8 + sin(TAU * freq * 2.0 * t) * 0.2
			var s := int(clampf(v * env * volume, -1.0, 1.0) * 32767.0)
			data.append(s & 0xFF)
			data.append((s >> 8) & 0xFF)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## A Zombai's groan: a low, wet throat moan that sags in pitch, breathy noise riding a rough
## voiced buzz (about 70 Hz falling to 55), swelling in and dying away. Each variant has its
## own pitch and length, so a pack never moans in unison. Quiet on purpose: you hear the
## nearest one before you see it, never a wall of noise (art bible: restrained).
const GROAN_VARIANTS := 3
const GROAN_LENGTH := 1.3


static func groan(variant: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7100 + variant
	var f0 := 72.0 - 6.0 * float(variant)
	var length := GROAN_LENGTH - 0.15 * float(variant)
	var data := PackedByteArray()
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in int(RATE * length):
		var t := float(i) / RATE
		var k := t / length
		var env := sin(PI * pow(k, 0.7)) * (0.85 + 0.15 * sin(TAU * 5.0 * t))
		var f := f0 * (1.0 - 0.25 * k) * (1.0 + 0.03 * sin(TAU * 3.1 * t))
		ph += f / RATE
		var buzz := fposmod(ph, 1.0) * 2.0 - 1.0 # a sawtooth: the rasp of a dry throat
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.12
		lp2 += (buzz * 0.6 + lp * 1.8 - lp2) * 0.18
		var v := lp2 * env
		var s16 := int(clampf(v * 0.55, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	return _wav(data)


## The arms-up rasp before a grab: a short, rising hiss of breath through the teeth with a
## catch of voice under it. It is the grab's sound cue (the telegraph you hear), so it starts
## with the windup and is done well before the grab closes.
const RASP_LENGTH := 0.45


static func rasp() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7200
	var data := PackedByteArray()
	var lp := 0.0
	var hp_prev := 0.0
	var ph := 0.0
	for i in int(RATE * RASP_LENGTH):
		var t := float(i) / RATE
		var k := t / RASP_LENGTH
		var env := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.7, 1.0, k))
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.45
		var hiss := lp - hp_prev # a little brighter than the groan: breath, not voice
		hp_prev = lp
		ph += (90.0 + 60.0 * k) / RATE
		var voice := (fposmod(ph, 1.0) * 2.0 - 1.0) * 0.25
		var v := (hiss * 1.6 + voice) * env
		var s16 := int(clampf(v * 0.5, -1.0, 1.0) * 32767.0)
		data.append(s16 & 0xFF)
		data.append((s16 >> 8) & 0xFF)
	return _wav(data)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

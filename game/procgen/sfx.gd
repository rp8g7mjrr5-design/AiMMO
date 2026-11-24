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


## A level-up: a quick rising arpeggio (C, E, G, C) that lands on a warm held major chord
## with a soft shimmer on top, the loudest moment in the game but over in about 1.5 s.
const LEVEL_UP_SECONDS := 1.5
const LEVEL_UP_NOTES := [[0.0, 523.25], [0.07, 659.25], [0.14, 783.99], [0.21, 1046.5]]


static func level_up() -> AudioStreamWAV:
	var data := PackedByteArray()
	for i in int(RATE * LEVEL_UP_SECONDS):
		var t := float(i) / RATE
		var v := 0.0
		# The climb: each note plucks and rings, the top one longest.
		for n in LEVEL_UP_NOTES:
			var d: float = t - float(n[0])
			if d >= 0.0:
				var f: float = n[1]
				v += (sin(TAU * f * d) * 0.75 + sin(TAU * f * 2.0 * d) * 0.18) * minf(1.0, d * 150.0) * exp(-d * 4.5) * 0.42
		# The chord it lands on: C major an octave down, swelling in and fading out slowly.
		var dc := t - 0.21
		if dc >= 0.0:
			var env := minf(1.0, dc * 12.0) * exp(-dc * 2.2)
			for f in [261.63, 329.63, 392.0, 523.25]:
				v += (sin(TAU * f * dc) * 0.7 + sin(TAU * f * 3.0 * dc) * 0.08) * env * 0.22
			# A shimmer: a high G with a slow tremolo, like sparks in the air.
			v += sin(TAU * 1567.98 * dc) * (0.5 + 0.5 * sin(TAU * 7.0 * dc)) * env * 0.08
		var fade := clampf((LEVEL_UP_SECONDS - t) / 0.12, 0.0, 1.0) # no click at the end
		var s16 := int(clampf(v * fade * 0.34, -1.0, 1.0) * 32767.0)
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

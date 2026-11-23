class_name Sfx
## Procedural sound effects, synthesised into 16-bit PCM at startup.

const RATE := 22050


## A soft two-note chime, used when chat arrives.
static func chime() -> AudioStreamWAV:
	return _tones([[880.0, 0.08], [1320.0, 0.14]], 0.25)


## A rising three-note arpeggio, played when you arrive in the world.
static func arrive() -> AudioStreamWAV:
	return _tones([[523.25, 0.12], [659.25, 0.12], [783.99, 0.3]], 0.3)


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

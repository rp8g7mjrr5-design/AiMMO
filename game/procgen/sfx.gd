class_name Sfx
## Procedural sound effects, synthesised into 16-bit PCM at startup.

const RATE := 22050


## A soft two-note chime, used when chat arrives.
static func chime() -> AudioStreamWAV:
	return _tones([[880.0, 0.08], [1320.0, 0.14]], 0.25)


## A rising three-note arpeggio, played when you arrive in the world.
static func arrive() -> AudioStreamWAV:
	return _tones([[523.25, 0.12], [659.25, 0.12], [783.99, 0.3]], 0.3)


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

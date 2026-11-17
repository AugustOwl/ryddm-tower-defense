class_name DrumLoop
## Procedurally generates a looping test drum track (kick, snare, hats) so the game needs no audio assets.
## Its tempo only matters for generating the audio; the visuals never use it (they listen to the sound).
## Replace with real music by setting the Main node's Music property, or calling Conductor.play_track().

const MIX_RATE := 44100


static func make(bpm := 120.0, beats := 4) -> AudioStreamWAV:
	var beat_len := 60.0 / bpm
	var total := int(beat_len * beats * MIX_RATE)
	var buf := PackedFloat32Array()
	buf.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	for b in beats:
		var t0 := int(b * beat_len * MIX_RATE)
		_kick(buf, t0)                                     # four on the floor
		if b % 2 == 1:
			_snare(buf, t0, rng)                           # backbeat on 2 and 4
		_hat(buf, t0, rng, 0.35)                           # on the beat
		_hat(buf, t0 + int(beat_len * 0.5 * MIX_RATE), rng, 0.6)   # off-beat

	var bytes := PackedByteArray()
	bytes.resize(total * 2)
	for i in total:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total
	return wav


static func _add(buf: PackedFloat32Array, i: int, v: float) -> void:
	if i < buf.size():
		buf[i] += v


static func _kick(buf: PackedFloat32Array, start: int) -> void:
	var n := int(0.28 * MIX_RATE)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var freq := 45.0 + 110.0 * exp(-t * 28.0)          # pitch drops fast: the "thump"
		phase += TAU * freq / MIX_RATE
		_add(buf, start + i, sin(phase) * exp(-t * 11.0) * 0.9)


static func _snare(buf: PackedFloat32Array, start: int, rng: RandomNumberGenerator) -> void:
	var n := int(0.18 * MIX_RATE)
	for i in n:
		var t := float(i) / MIX_RATE
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 20.0) * 0.45
		var tone := sin(TAU * 190.0 * t) * exp(-t * 26.0) * 0.3
		_add(buf, start + i, noise + tone)


static func _hat(buf: PackedFloat32Array, start: int, rng: RandomNumberGenerator, level: float) -> void:
	var n := int(0.05 * MIX_RATE)
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var x := rng.randf_range(-1.0, 1.0)
		var hp := x - prev                                  # crude high-pass
		prev = x
		_add(buf, start + i, hp * exp(-t * 90.0) * 0.18 * level)

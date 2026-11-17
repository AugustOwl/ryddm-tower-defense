extends Node
## Autoload "Conductor": listens to the music and publishes what it hears.
##
## There is no BPM and no beat clock. A spectrum analyzer on the master bus measures the actual audio every frame
## and turns it into a few smoothed 0..1 values. Each value is auto-normalized against a slowly decaying peak, so any
## song works regardless of how loud or quiet it is. The values go to every shader as global shader parameters,
## so all reactive visuals share one language:
##
##   audio_bass     low end (30-150 Hz): kicks and bass lines
##   audio_mid      body of the music (150 Hz - 2 kHz)
##   audio_treble   highs (2-12 kHz): hats, cymbals, sparkle
##   audio_texture  how much the sound is changing right now (spectral flux): busy / rough vs. smooth / sustained
##   beat_pulse     jumps up when a bass hit lands (onset detection on the real audio), then decays
##   beat_phase     0..1 flowing clock whose speed follows the loudness of the music (for travelling waves)
##   event_pulse    decaying accent that gameplay events trigger via accent()
##   beat_color     the shared reactive tint
## In shaders:  global uniform float audio_bass;   (etc.)

signal onset(strength: float)      ## a bass hit was detected

const ACCENT_DECAY := 3.0          ## event_pulse units per second

## Frequency bands (Hz) for the three headline values.
const BASS_RANGE := Vector2(30.0, 150.0)
const MID_RANGE := Vector2(150.0, 2000.0)
const TREBLE_RANGE := Vector2(2000.0, 12000.0)
## Edges (Hz) of the narrow bands used to measure spectral change ("texture").
const FLUX_EDGES: Array[float] = [40.0, 100.0, 200.0, 400.0, 800.0, 1600.0, 3200.0, 6400.0, 12800.0]

const PEAK_HALF_LIFE := 6.0        ## seconds for the auto-gain peak to halve (how fast it adapts to quiet passages)
const ONSET_RISE := 0.18           ## how far bass must jump above its recent average to count as a hit
const ONSET_COOLDOWN := 0.09       ## seconds between detected hits
const PULSE_DECAY := 6.0           ## beat_pulse decays like exp(-PULSE_DECAY * t)

## "Setting a card" slow-motion: game speed, music pitch/volume and a low-pass ("underwater") filter ease together.
const SLOW_TIME_SCALE := 0.25
const SLOW_VOLUME_DB := -7.0
const SLOW_CUTOFF_HZ := 650.0
const SLOW_EASE := 7.0             ## higher = snappier transition (per real second)
const BASE_VOLUME_DB := -8.0
const FADE_SECONDS := 0.7          ## crossfade time when switching tracks

# What the music is doing right now (all 0..1).
var bass := 0.0
var mid := 0.0
var treble := 0.0
var texture := 0.0
var pulse := 0.0
var flow := 0.0
var event_pulse := 0.0

var slow_amount := 0.0             ## 0 = normal, 1 = fully slowed
var drain_amount := 0.0            ## 0..1: how much color the reactive shaders have lost (only while deploying)
var _slow_action := false          ## slowed because the player is deploying a card / placing the rally flag
var _slow_manual := false          ## slowed because the player pressed Space

var _player: AudioStreamPlayer
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _lowpass: AudioEffectLowPassFilter
var _mute_gain: AudioEffectAmplify
var _peaks := {"bass": 0.0004, "mid": 0.0004, "treble": 0.0004, "flux": 0.0004, "total": 0.0004}
var _flux_prev := PackedFloat32Array()
var _current: AudioStream                       ## the stream that is playing (or fading in)
var _pending: AudioStream                       ## the stream waiting for the current one to fade out
var _default_stream: AudioStreamWAV
var _fade_gain := 1.0
var _fade_target := 1.0
var _bass_avg := 0.0
var _onset_cooldown := 0.0


func _init() -> void:
	# Registered here too (not only in project.godot) so shaders always find them.
	var existing := RenderingServer.global_shader_parameter_get_list()
	for entry in [
		[&"beat_pulse", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"beat_phase", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"event_pulse", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"audio_bass", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"audio_mid", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"audio_treble", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"audio_texture", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"color_drain", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0],
		[&"beat_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.35, 0.85, 1.0)],
	]:
		if not existing.has(entry[0]):
			RenderingServer.global_shader_parameter_add(entry[0], entry[1], entry[2])


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = BASE_VOLUME_DB
	add_child(_player)

	# Master bus chain: analyzer first (so the visuals ignore slow-mo muffling and muting), then the
	# "underwater" low-pass, then the mute switch.
	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.buffer_length = 0.1
	analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(0, analyzer, 0)
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20500.0
	AudioServer.add_bus_effect(0, _lowpass)
	_mute_gain = AudioEffectAmplify.new()
	AudioServer.add_bus_effect(0, _mute_gain)
	_analyzer = AudioServer.get_bus_effect_instance(0, 0)

	_flux_prev.resize(FLUX_EDGES.size() - 1)
	play_default()


## The built-in generated drum loop (used when no track is set).
func play_default(fade := false) -> void:
	if _default_stream == null:
		_default_stream = DrumLoop.make()
	play_track(_default_stream, fade)


## Play a looping track (an imported .mp3 / .ogg / .wav). Nothing about its tempo is needed.
## With `fade`, the current track fades out and the new one fades in. Asking for the track that is already
## playing does nothing.
func play_track(stream: AudioStream, fade := false) -> void:
	if stream == _current and (_player.playing or _pending != null):
		_pending = null
		_fade_target = 1.0
		return
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	if fade and _player.playing:
		_pending = stream
		_fade_target = 0.0
	else:
		_pending = null
		_start(stream)


func _start(stream: AudioStream) -> void:
	_current = stream
	_player.stream = stream
	_player.play()


## Gameplay events call this to add a decaying accent on top of the music (0..1).
func accent(amount: float) -> void:
	event_pulse = maxf(event_pulse, amount)


## Mute the speakers only; the visuals keep reacting to the music.
func toggle_mute() -> void:
	_mute_gain.volume_db = 0.0 if _mute_gain.volume_db < -40.0 else -80.0


## Slow the whole game and muffle the music (true), or return to normal speed (false).
## Used while deploying a card or placing the rally flag. This kind of slow-motion also drains the color from the
## reactive shaders, so the towers and highlights pop.
func set_slow(on: bool) -> void:
	_slow_action = on


## The Space-bar slow-motion (same speed, but the shaders keep their color).
func set_manual_slow(on: bool) -> void:
	_slow_manual = on


func toggle_manual_slow() -> void:
	_slow_manual = not _slow_manual


func is_manual_slow() -> bool:
	return _slow_manual


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toggle_mute()


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)       # smoothing runs in real time, like the audio
	_update_fade(real_dt)
	_update_slow(delta)
	event_pulse = maxf(0.0, event_pulse - ACCENT_DECAY * delta)
	_analyze(real_dt)

	RenderingServer.global_shader_parameter_set(&"beat_pulse", pulse)
	RenderingServer.global_shader_parameter_set(&"beat_phase", flow)
	RenderingServer.global_shader_parameter_set(&"event_pulse", event_pulse)
	RenderingServer.global_shader_parameter_set(&"audio_bass", bass)
	RenderingServer.global_shader_parameter_set(&"audio_mid", mid)
	RenderingServer.global_shader_parameter_set(&"audio_treble", treble)
	RenderingServer.global_shader_parameter_set(&"audio_texture", texture)


# ---------- Listening ----------

func _analyze(dt: float) -> void:
	if _analyzer == null:
		_analyzer = AudioServer.get_bus_effect_instance(0, 0)
		return

	var bass_now := _normalize("bass", _band(BASS_RANGE.x, BASS_RANGE.y), dt)
	var mid_now := _normalize("mid", _band(MID_RANGE.x, MID_RANGE.y), dt)
	var treble_now := _normalize("treble", _band(TREBLE_RANGE.x, TREBLE_RANGE.y), dt)

	# Texture: how much the spectrum changed since the last frame, summed over narrow bands.
	var flux := 0.0
	var total := 0.0
	for i in FLUX_EDGES.size() - 1:
		var v := _band(FLUX_EDGES[i], FLUX_EDGES[i + 1])
		flux += maxf(v - _flux_prev[i], 0.0)
		_flux_prev[i] = v
		total += v
	var texture_now := _normalize("flux", flux, dt)
	var level_now := _normalize("total", total, dt)

	# Smooth: fast attack, slower release, so hits snap in and fade out gracefully.
	bass = _smooth(bass, pow(bass_now, 0.8), 45.0, 7.0, dt)
	mid = _smooth(mid, pow(mid_now, 0.8), 30.0, 5.0, dt)
	treble = _smooth(treble, pow(treble_now, 0.8), 40.0, 8.0, dt)
	texture = _smooth(texture, texture_now, 18.0, 3.0, dt)

	# Bass hit detection on the real signal: a sudden jump above the recent average.
	_onset_cooldown -= dt
	_bass_avg = lerpf(_bass_avg, bass_now, 1.0 - exp(-3.0 * dt))
	if _onset_cooldown <= 0.0 and bass_now - _bass_avg > ONSET_RISE and bass_now > 0.35:
		pulse = clampf(0.5 + (bass_now - _bass_avg) * 1.5, 0.5, 1.0)
		_onset_cooldown = ONSET_COOLDOWN
		onset.emit(pulse)
	pulse *= exp(-PULSE_DECAY * dt)

	# A flowing clock for travelling waves: louder music flows faster. Not a beat; no tempo involved.
	flow = fposmod(flow + dt * (0.12 + 0.7 * level_now + 0.5 * bass), 1.0)


## Average magnitude (both channels) between two frequencies.
func _band(low_hz: float, high_hz: float) -> float:
	var m := _analyzer.get_magnitude_for_frequency_range(low_hz, high_hz, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE)
	return (m.x + m.y) * 0.5


## Auto-gain: divide by a peak that slowly decays, giving 0..1 whatever the song's loudness.
func _normalize(key: String, value: float, dt: float) -> float:
	var peak: float = maxf(_peaks[key] * pow(0.5, dt / PEAK_HALF_LIFE), 0.0004)
	peak = maxf(peak, value)
	_peaks[key] = peak
	return clampf(value / peak, 0.0, 1.0)


func _smooth(current: float, target: float, attack: float, release: float, dt: float) -> float:
	var rate := attack if target > current else release
	return lerpf(current, target, 1.0 - exp(-rate * dt))


# ---------- Crossfade ----------

func _update_fade(real_dt: float) -> void:
	_fade_gain = move_toward(_fade_gain, _fade_target, real_dt / FADE_SECONDS)
	if _pending != null and _fade_gain <= 0.001:
		_start(_pending)                           # the old track is silent now: swap and fade the new one in
		_pending = null
		_fade_target = 1.0


# ---------- Slow motion ----------

func _update_slow(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.01)    # delta is scaled by time_scale; undo that
	var slow_target := 1.0 if (_slow_action or _slow_manual) else 0.0
	slow_amount = move_toward(slow_amount, slow_target, SLOW_EASE * real_delta)
	drain_amount = move_toward(drain_amount, 1.0 if _slow_action else 0.0, SLOW_EASE * real_delta)
	RenderingServer.global_shader_parameter_set(&"color_drain", smoothstep(0.0, 1.0, drain_amount))
	var eased := smoothstep(0.0, 1.0, slow_amount)
	Engine.time_scale = lerpf(1.0, SLOW_TIME_SCALE, eased)
	_player.pitch_scale = Engine.time_scale                    # music slows with the game
	_player.volume_db = lerpf(BASE_VOLUME_DB, SLOW_VOLUME_DB, eased) + linear_to_db(maxf(_fade_gain, 0.0001))
	_lowpass.cutoff_hz = 20500.0 * pow(SLOW_CUTOFF_HZ / 20500.0, eased)

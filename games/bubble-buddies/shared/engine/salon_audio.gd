class_name SalonAudio
extends Node
## Original procedural sound bank and two synchronized music arrangements.
## Activity follows actual work; warnings must be fired once on a gameplay edge.

const SAMPLE_RATE := 22050
const VOICE_COUNT := 6
const SAMPLE_PEAK := 0.18
const VOICE_GAIN := 0.42
const LOOP_GAIN := 0.12
const MUSIC_GAIN := 0.24
const MUSIC_BPM := 112.0
const ACTIVITY_KEYS := ["washing", "drying", "grooming", "toweling"]
const LOOP_RELEASE := 0.09
const PAN_STEPS := 4
const VARIANTS := 3
const CATALOG := {
	"step_dry": {"seconds": 0.075, "priority": -1, "cooldown": 0.065, "gain": 0.24},
	"step_wet": {"seconds": 0.11, "priority": -1, "cooldown": 0.065, "gain": 0.32},
	"pickup": {"seconds": 0.13, "priority": 0, "cooldown": 0.045},
	"place": {"seconds": 0.14, "priority": 0, "cooldown": 0.045},
	"towel": {"seconds": 0.23, "priority": 0, "cooldown": 0.16},
	"wash": {"seconds": 0.20, "priority": 0, "cooldown": 0.16},
	"treatment_start": {"seconds": 0.32, "priority": 1, "cooldown": 0.25},
	"treatment_ready": {"seconds": 0.40, "priority": 2, "cooldown": 0.50},
	"bath_ready": {"seconds": 0.30, "priority": 2, "cooldown": 0.16},
	"dried": {"seconds": 0.34, "priority": 2, "cooldown": 0.16},
	"brush": {"seconds": 0.22, "priority": 0, "cooldown": 0.15},
	"shake": {"seconds": 0.42, "priority": 3, "cooldown": 0.30},
	"shake_warning": {"seconds": 0.27, "priority": 3, "cooldown": 0.40},
	"escape_warning": {"seconds": 0.31, "priority": 3, "cooldown": 0.40},
	"escaped": {"seconds": 0.38, "priority": 3, "cooldown": 0.30},
	"caught": {"seconds": 0.22, "priority": 2, "cooldown": 0.12},
	"help": {"seconds": 0.24, "priority": 3, "cooldown": 0.75},
	"success": {"seconds": 0.42, "priority": 2, "cooldown": 0.12},
	"missed": {"seconds": 0.30, "priority": 2, "cooldown": 0.15},
	"order_waiting": {"seconds": 0.18, "priority": 1, "cooldown": 2.50, "gain": 0.65},
	"queue_loss": {"seconds": 0.32, "priority": 2, "cooldown": 1.50, "gain": 0.85},
	"laundry_start": {"seconds": 0.23, "priority": 1, "cooldown": 0.25},
	"laundry_ready": {"seconds": 0.34, "priority": 2, "cooldown": 0.25},
	"tick": {"seconds": 0.075, "priority": 1, "cooldown": 0.85},
	"comic_warning": {"seconds": 0.24, "priority": 3, "cooldown": 0.40},
	"frizzed": {"seconds": 0.40, "priority": 3, "cooldown": 0.30},
	"crooked": {"seconds": 0.32, "priority": 3, "cooldown": 0.30},
	"cosmetic_repaired": {"seconds": 0.38, "priority": 2, "cooldown": 0.20},
	"imperfect_delivery": {"seconds": 0.42, "priority": 2, "cooldown": 0.20},
}
const ALIASES := {"soak": "wash", "ready": "dried", "washed": "bath_ready", "brushed": "brush", "trimmed": "brush", "treatment_started": "treatment_start", "laundry_started": "laundry_start"}

var muted := false
var music_muted := false
var paused := true
var urgency := 0
var _clock := 0.0
var _serial := 0
var _voices: Array[AudioStreamPlayer] = []
var _voice_priority: Array[int] = []
var _voice_serial: Array[int] = []
var _cooldowns: Dictionary = {}
var _bank: Dictionary = {}
var _mono_bank: Dictionary = {}
var _loops: Dictionary = {}
var _loop_levels := {}
var _wanted := {}
var _music: Array[AudioStreamPlayer] = []
var _pressure := 0.0
var _music_blend := 0.0
var _music_level := 0.0
var _duck_until := 0.0


func _ready() -> void:
	# Independent of SceneTree pause so explicit pause/reset always closes sound.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "EventVoice%d" % index
		player.max_polyphony = 1
		player.volume_linear = VOICE_GAIN
		add_child(player)
		_voices.append(player)
		_voice_priority.append(-1)
		_voice_serial.append(-1)
	for key: String in ACTIVITY_KEYS:
		_loop_levels[key] = 0.0
		_wanted[key] = false
		var player := AudioStreamPlayer.new()
		player.name = key.capitalize() + "Activity"
		player.max_polyphony = 1
		player.volume_linear = 0.0
		player.stream = _make_loop(key)
		add_child(player)
		_loops[key] = player
	for arrangement in 2:
		var player := AudioStreamPlayer.new()
		player.name = "MusicCalm" if arrangement == 0 else "MusicRush"
		player.volume_linear = 0.0
		player.stream = _make_music(arrangement == 1)
		add_child(player)
		_music.append(player)
	# Build all timbres once at load, avoiding synthesis during a first rescue.
	for key: String in CATALOG:
		for variation in VARIANTS:
			_mono_bank[_mono_key(key, variation)] = _synthesize(key, variation)


func _process(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	if paused or muted:
		return
	for key: String in _loops:
		var player: AudioStreamPlayer = _loops[key]
		var target := 1.0 if bool(_wanted[key]) else 0.0
		var level := move_toward(float(_loop_levels[key]), target, delta / LOOP_RELEASE)
		_loop_levels[key] = level
		player.volume_linear = LOOP_GAIN * level
		if level <= 0.0:
			player.stop()
		elif not player.playing:
			player.play()
	if not music_muted:
		_music_blend = move_toward(_music_blend, _pressure, delta * 0.65)
		var target := 0.28 if _clock < _duck_until else 1.0
		_music_level = move_toward(_music_level, target, delta * (18.0 if target < _music_level else 2.0))
		# Both arrangements run together, so changing pressure never resets the beat.
		for index in _music.size():
			_music[index].volume_linear = MUSIC_GAIN * _music_level * (1.0 - _music_blend if index == 0 else _music_blend)
			if not _music[index].playing:
				_music[index].play()


func play_event(key: String, pan: float = 0.0, variation: int = 0) -> bool:
	key = str(ALIASES.get(key, key))
	if paused or muted or not CATALOG.has(key) or _voices.is_empty():
		return false
	if float(_cooldowns.get(key, -1.0)) > _clock:
		return false
	var priority: int = CATALOG[key]["priority"]
	var index := _available_voice(priority)
	if index < 0:
		return false
	var player := _voices[index]
	player.stop()
	player.stream = get_event_stream(key, pan, variation)
	player.volume_linear = VOICE_GAIN * clampf(float(CATALOG[key].get("gain", 1.0)), 0.0, 1.0)
	player.play()
	_serial += 1
	_voice_priority[index] = priority
	_voice_serial[index] = _serial
	_cooldowns[key] = _clock + float(CATALOG[key]["cooldown"])
	if priority >= 2:
		_duck_until = _clock + 0.45
	return true


func set_activity(washing: bool, drying: bool, next_urgency: int, is_paused: bool, grooming: bool = false, toweling: bool = false, pressure: float = 0.0) -> void:
	paused = is_paused
	urgency = clampi(next_urgency, 0, 3)
	_wanted["washing"] = washing and not paused
	_wanted["drying"] = drying and not paused
	_wanted["grooming"] = grooming and not paused
	_wanted["toweling"] = toweling and not paused
	_pressure = clampf(pressure, 0.0, 1.0)
	if paused or muted:
		_stop_all()
	# Urgency is retained for callers/QA; it deliberately adds no alarm loop.
	# Final-second ticks are discrete caller events, never an automatic sound bed.


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		_stop_all()


func set_music_muted(value: bool) -> void:
	music_muted = value
	if music_muted:
		for player in _music:
			player.stop()
		_music_level = 0.0


func reset() -> void:
	_stop_all()
	paused = true
	urgency = 0
	for key: String in _wanted:
		_wanted[key] = false
	_pressure = 0.0
	_music_blend = 0.0
	_duck_until = 0.0
	_cooldowns.clear()
	_clock = 0.0
	_serial = 0
	# Keep the user's mute preference and bounded immutable sample cache.


func get_event_stream(key: String, pan: float = 0.0, variation: int = 0) -> AudioStreamWAV:
	key = str(ALIASES.get(key, key))
	if not CATALOG.has(key):
		return null
	variation = posmod(variation, VARIANTS)
	# Completion location is useful even when a caller omits a position.
	if is_zero_approx(pan):
		if key in ["bath_ready", "treatment_start", "treatment_ready"]:
			pan = -0.65
		elif key == "dried":
			pan = 0.65
	var pan_index := roundi(clampf(pan, -1.0, 1.0) * PAN_STEPS)
	var cache_key := "%s:%d:%d" % [key, variation, pan_index]
	if not _bank.has(cache_key):
		var mono_key := _mono_key(key, variation)
		if not _mono_bank.has(mono_key):
			_mono_bank[mono_key] = _synthesize(key, variation)
		_bank[cache_key] = _stereo_stream(_mono_bank[mono_key], float(pan_index) / PAN_STEPS)
	return _bank[cache_key]


func debug_state() -> Dictionary:
	var count := 0
	for player in _voices:
		if player.playing:
			count += 1
	return {"voices": _voices.size(), "active_voices": count, "children": get_child_count(),
		"washing": _loops.has("washing") and _loops["washing"].playing,
		"drying": _loops.has("drying") and _loops["drying"].playing,
		"grooming": _loops.has("grooming") and _loops["grooming"].playing,
		"toweling": _loops.has("toweling") and _loops["toweling"].playing,
		"music": not _music.is_empty() and _music[0].playing, "music_muted": music_muted,
		"music_blend": _music_blend, "music_level": _music_level,
		"muted": muted, "paused": paused, "cached_streams": _bank.size()}


func _available_voice(priority: int) -> int:
	var candidate := -1
	for index in _voices.size():
		if not _voices[index].playing:
			return index
		if _voice_priority[index] > priority:
			continue
		if candidate < 0 or _voice_priority[index] < _voice_priority[candidate] or (
			_voice_priority[index] == _voice_priority[candidate] and _voice_serial[index] < _voice_serial[candidate]):
			candidate = index
	return candidate


func _stop_all() -> void:
	for player in _music:
		player.stop()
		player.volume_linear = 0.0
	_music_level = 0.0
	for player in _voices:
		player.stop()
	for key: String in _loops:
		_loops[key].stop()
		_loops[key].volume_linear = 0.0
		_loop_levels[key] = 0.0


func _mono_key(key: String, variation: int) -> String:
	return "%s:%d" % [key, variation]


func _synthesize(key: String, variation: int) -> PackedFloat32Array:
	var duration: float = CATALOG[key]["seconds"]
	var count := ceili(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var pitch: float = [1.0, 1.045, 0.965][variation]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5791 + key.hash() + variation * 103
	var soft_noise := 0.0
	var previous_noise := 0.0
	for index in count:
		var t := float(index) / SAMPLE_RATE
		var u := float(index) / maxf(count - 1, 1)
		soft_noise = lerpf(soft_noise, rng.randf_range(-1.0, 1.0), 0.20)
		var airy_noise := soft_noise - previous_noise * 0.55
		previous_noise = soft_noise
		var value := 0.0
		match key:
			"step_dry":
				value = sin(TAU * 105.0 * pitch * t) * exp(-t * 65.0) * 0.4 + soft_noise * exp(-t * 42.0)
			"step_wet":
				value = soft_noise * exp(-t * 24.0) + _chirp(t, duration, 160.0 * pitch, 70.0 * pitch) * exp(-t * 38.0) * 0.25
			"pickup":
				value = _chirp(t, duration, 420.0 * pitch, 205.0 * pitch) * exp(-t * 27.0) + soft_noise * exp(-t * 50.0) * 0.12
			"place":
				value = (sin(TAU * 145.0 * pitch * t) + 0.28 * sin(TAU * 347.0 * pitch * t)) * exp(-t * 39.0) + soft_noise * exp(-t * 60.0) * 0.36
			"towel":
				value = soft_noise * (0.35 + 0.65 * pow(sin(PI * 3.0 * u), 2.0)) + sin(TAU * 80.0 * t) * 0.08 * exp(-8.0 * t)
			"wash":
				value = soft_noise * 0.3 + _note(t, 0.015, 0.10, 560.0 * pitch, 0.5) + _note(t, 0.09, 0.09, 840.0 * pitch, 0.4)
			"treatment_start":
				# A short bubble pump: distinct from the open bath, never a distress cry.
				value = soft_noise * 0.16 + _note(t, 0.0, 0.12, 260.0 * pitch, 0.5) + _note(t, 0.09, 0.13, 390.0 * pitch, 0.45) + _note(t, 0.19, 0.13, 520.0 * pitch, 0.35)
			"treatment_ready":
				# Three hollow notes identify the separate hood, then the pet needs rinsing.
				value = _note(t, 0.0, 0.14, 330.0 * pitch, 0.6) + _note(t, 0.12, 0.14, 440.0 * pitch, 0.55) + _note(t, 0.24, 0.16, 660.0 * pitch, 0.5)
			"bath_ready":
				value = _note(t, 0.0, 0.16, 440.0 * pitch, 0.7) + _note(t, 0.12, 0.18, 660.0 * pitch, 0.7)
			"dried":
				value = _bell(t, 880.0 * pitch) * 0.65 + _bell(maxf(t - 0.09, 0.0), 1320.0 * pitch) * 0.23 * float(t >= 0.09)
			"brush":
				# Two soft snips preserve the original short-care cue for the upgraded table.
				var snips := exp(-t * 65.0) + float(t >= 0.11) * exp(-maxf(t - 0.11, 0.0) * 65.0)
				value = airy_noise * (0.15 + snips * 1.2) + sin(TAU * 1100.0 * pitch * t) * snips * 0.08
			"shake":
				value = (sin(TAU * 95.0 * pitch * t + 1.3 * sin(TAU * 15.0 * t)) * 0.45 + soft_noise * 0.8) * (0.38 + 0.62 * pow(sin(TAU * 9.0 * t), 2.0))
			"shake_warning":
				value = sin(TAU * 215.0 * pitch * t + 0.8 * sin(TAU * 12.0 * t)) * 0.3 * pow(sin(PI * u), 2.0) + _note(t, 0.03, 0.10, 470.0 * pitch, 0.3) + _note(t, 0.15, 0.10, 520.0 * pitch, 0.24)
			"escape_warning":
				value = _note(t, 0.0, 0.12, 620.0 * pitch, 0.6) + _note(t, 0.17, 0.13, 740.0 * pitch, 0.6)
			"escaped":
				value = sin(TAU * pitch * (170.0 * t + 7.0 * (1.0 - exp(-t * 9.0))) + 1.1 * sin(TAU * 16.0 * t)) * exp(-t * 5.0)
			"caught":
				value = _chirp(t, duration, 190.0 * pitch, 390.0 * pitch) * exp(-t * 12.0) + _note(t, 0.09, 0.12, 587.0 * pitch, 0.26)
			"help":
				value = sin(TAU * 920.0 * pitch * t + 0.5 * sin(TAU * 6.0 * t)) * pow(sin(PI * u), 2.0) + airy_noise * 0.10
			"success":
				value = _note(t, 0.0, 0.27, 523.25 * pitch, 0.48) + _note(t, 0.075, 0.28, 659.25 * pitch, 0.42) + _note(t, 0.15, 0.27, 783.99 * pitch, 0.38)
			"missed":
				value = _note(t, 0.0, 0.18, 392.0 * pitch, 0.55) + _note(t, 0.12, 0.18, 293.66 * pitch, 0.55)
			"order_waiting":
				value = _bell(t, 660.0 * pitch) * 0.35 + _note(t, 0.0, 0.15, 330.0 * pitch, 0.3)
			"queue_loss":
				value = _note(t, 0.0, 0.16, 294.0 * pitch, 0.5) + _note(t, 0.17, 0.15, 220.0 * pitch, 0.45) + soft_noise * 0.08 * exp(-t * 16.0)
			"laundry_start":
				value = _chirp(t, duration, 115.0, 220.0) * 0.5 + soft_noise * 0.25 + _note(t, 0.0, 0.06, 420.0, 0.4)
			"laundry_ready":
				value = _note(t, 0.0, 0.18, 587.33 * pitch, 0.6) + _note(t, 0.14, 0.20, 880.0 * pitch, 0.6)
			"comic_warning":
				# Two rising woodblock pips: stop holding, rather than a continuous siren.
				value = _note(t, 0.0, 0.09, 690.0 * pitch, 0.65) + _note(t, 0.13, 0.10, 920.0 * pitch, 0.65)
			"frizzed":
				# A springy puff, no animal distress sample.
				value = _chirp(t, duration, 160.0 * pitch, 540.0 * pitch) * exp(-t * 6.0) + airy_noise * exp(-t * 10.0) * 0.9 + sin(TAU * 75.0 * t + 3.0 * sin(TAU * 16.0 * t)) * exp(-t * 8.0) * 0.3
			"crooked":
				value = _note(t, 0.0, 0.11, 780.0 * pitch, 0.65) + _chirp(maxf(t - 0.10, 0.0), duration, 440.0 * pitch, 160.0 * pitch) * exp(-maxf(t - 0.10, 0.0) * 12.0) * float(t >= 0.10)
			"cosmetic_repaired":
				value = _note(t, 0.0, 0.16, 587.0 * pitch, 0.6) + _note(t, 0.11, 0.17, 740.0 * pitch, 0.55) + _bell(maxf(t - 0.21, 0.0), 1174.0 * pitch) * float(t >= 0.21) * 0.3
			"imperfect_delivery":
				# Playful acceptance keeps the imperfect order from sounding like failure.
				value = _note(t, 0.0, 0.20, 523.0 * pitch, 0.5) + _note(t, 0.12, 0.16, 622.0 * pitch, 0.5) + _note(t, 0.24, 0.16, 784.0 * pitch, 0.45)
			"tick":
				value = sin(TAU * 700.0 * pitch * t) * exp(-t * 70.0) * 0.7 + soft_noise * exp(-t * 100.0) * 0.25
		var fade := minf(minf(t / 0.007, (duration - t - 1.0 / SAMPLE_RATE) / 0.026), 1.0)
		samples[index] = value * maxf(fade, 0.0)
	return _normalize(samples, SAMPLE_PEAK)


func _make_loop(key: String) -> AudioStreamWAV:
	var count := SAMPLE_RATE
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1341 + key.hash()
	var noise := 0.0
	for index in count:
		var t := float(index) / SAMPLE_RATE
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.12 if key == "washing" else 0.045)
		var value := noise * (0.55 + 0.15 * sin(TAU * 3.0 * t))
		if key == "washing":
			value += sin(TAU * 560.0 * t + 0.2 * sin(TAU * 7.0 * t)) * 0.025 * pow(sin(TAU * 4.0 * t), 8.0)
		elif key == "drying":
			value += sin(TAU * 110.0 * t) * 0.13 + sin(TAU * 220.0 * t) * 0.025
		elif key == "grooming":
			# Soft clipper buzz with short scissor snips; no warning-like melody.
			value = sin(TAU * 165.0 * t) * 0.035 + noise * pow(maxf(sin(TAU * 4.0 * t), 0.0), 10.0) * 2.0
		elif key == "toweling":
			value = noise * (0.10 + 1.8 * pow(sin(TAU * 2.0 * t), 4.0))
		var fade := minf(minf(t / 0.03, (1.0 - t - 1.0 / SAMPLE_RATE) / 0.03), 1.0)
		samples[index] = value * maxf(fade, 0.0)
	var stream := _stereo_stream(_normalize(samples, SAMPLE_PEAK), -0.55 if key == "washing" else 0.55)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream


func _make_music(rush: bool) -> AudioStreamWAV:
	# Eight bars, original C / F / Am / G pizzicato phrase; 112 BPM is our tuning.
	var beat := 60.0 / MUSIC_BPM
	var count := roundi(32.0 * beat * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var roots := [130.813, 174.614, 220.0, 195.998]
	var melody := [0, 4, 7, 9, 7, 4, 2, 7, 9, 7, 4, 2, 4, 7, 2, 0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8257
	for index in count:
		var t := float(index) / SAMPLE_RATE
		var b := int(t / beat)
		var local := fmod(t, beat)
		var root_hz: float = roots[(b / 8) % 4]
		var bass_hz := root_hz * (1.0 if b % 2 == 0 else 1.5)
		var value := _note(local, 0.0, beat * 0.8, bass_hz, 0.38)
		var offbeat := fmod(t + beat * 0.5, beat)
		value += _note(offbeat, 0.0, beat * 0.36, root_hz * 2.0, 0.10)
		value += _note(offbeat, 0.0, beat * 0.36, root_hz * (2.3784 if b / 8 == 2 else 2.5198), 0.07)
		var melody_step := int(t / (beat * 0.5))
		if melody_step % 4 != 3:
			var melody_hz := 523.251 * pow(2.0, float(melody[(melody_step / 2 + (8 if b >= 16 else 0)) % 16]) / 12.0)
			value += _note(fmod(t, beat * 0.5), 0.0, beat * 0.42, melody_hz, 0.16)
		if rush:
			var eighth := fmod(t, beat * 0.5)
			value += rng.randf_range(-1.0, 1.0) * exp(-eighth * 85.0) * 0.12
			value += sin(TAU * 70.0 * local) * exp(-local * 28.0) * 0.15
		var fade := clampf(minf(t, float(count - 1 - index) / SAMPLE_RATE) / 0.012, 0.0, 1.0)
		samples[index] = value * fade
	var stream := _stereo_stream(_normalize(samples, SAMPLE_PEAK), 0.0)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream


func _stereo_stream(samples: PackedFloat32Array, pan: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 4)
	var angle := (clampf(pan, -1.0, 1.0) + 1.0) * PI / 4.0
	var left := cos(angle)
	var right := sin(angle)
	for index in samples.size():
		bytes.encode_s16(index * 4, roundi(samples[index] * left * 32767.0))
		bytes.encode_s16(index * 4 + 2, roundi(samples[index] * right * 32767.0))
	stream.data = bytes
	return stream


func _normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var largest := 0.000001
	for sample in samples:
		largest = maxf(largest, absf(sample))
	var gain := peak / largest
	for index in samples.size():
		samples[index] *= gain
	samples[0] = 0.0
	samples[samples.size() - 1] = 0.0
	return samples


func _chirp(t: float, duration: float, start_hz: float, end_hz: float) -> float:
	return sin(TAU * (start_hz * t + (end_hz - start_hz) * t * t / (2.0 * duration)))


func _note(t: float, start: float, duration: float, frequency: float, gain: float) -> float:
	var local := t - start
	if local < 0.0 or local >= duration:
		return 0.0
	var envelope := sin(PI * local / duration) * exp(-local * 4.0)
	return gain * envelope * (sin(TAU * frequency * local) + 0.17 * sin(TAU * frequency * 2.0 * local))


func _bell(t: float, frequency: float) -> float:
	return (sin(TAU * frequency * t) + 0.18 * sin(TAU * frequency * 2.75 * t)) * exp(-t * 12.0)

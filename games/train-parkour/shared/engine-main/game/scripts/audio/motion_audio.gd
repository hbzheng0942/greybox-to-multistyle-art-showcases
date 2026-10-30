extends Node
## Quiet procedural placeholders; no third-party samples or streamed generation.

var session: LabSession
var muted: bool = false
var motor := AudioStreamPlayer.new()
var wind := AudioStreamPlayer.new()
var cue := AudioStreamPlayer.new()
var hit_sound: AudioStreamWAV
var miss_sound: AudioStreamWAV
var launch_sound: AudioStreamWAV
var landing_sound: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for player in [motor, wind, cue]:
		add_child(player)
	if DisplayServer.get_name() == "headless":
		return
	motor.stream = _wave(1.0, 70.0, true, false)
	wind.stream = _wave(1.0, 0.0, true, true)
	hit_sound = _wave(0.18, 740.0, false, false)
	miss_sound = _wave(0.16, 130.0, false, false)
	launch_sound = _wave(0.24, 420.0, false, false)
	landing_sound = _wave(0.22, 95.0, false, false)
	motor.volume_db = -35.0
	wind.volume_db = -40.0
	cue.volume_db = -24.0
	motor.play()
	wind.play()


func _process(delta: float) -> void:
	if session == null:
		return
	var quiet := muted or get_tree().paused or session.finished or session.failed
	var speed := clampf(session.train.speed / 90.0, 0.0, 1.0)
	motor.pitch_scale = 0.65 + speed * 1.25
	wind.pitch_scale = 0.8 + speed * 0.35
	motor.volume_db = lerpf(motor.volume_db, -60.0 if quiet else -30.0 + speed * 9.0, 1.0 - exp(-8.0 * delta))
	wind.volume_db = lerpf(wind.volume_db, -60.0 if quiet else -38.0 + speed * 14.0, 1.0 - exp(-8.0 * delta))
	if session.train.state == TrainController.State.AIR and not quiet:
		motor.volume_db = -38.0


func reset_feedback() -> void:
	cue.stop()


func _exit_tree() -> void:
	for player in [motor, wind, cue]:
		player.stop()
		player.stream = null


func play_gate(hit: bool, combo: int) -> void:
	if muted or DisplayServer.get_name() == "headless":
		return
	cue.stream = hit_sound if hit else miss_sound
	cue.pitch_scale = 1.0 + minf(combo * 0.03, 0.3) if hit else 1.0
	cue.play()


func play_stunt(kind: String) -> void:
	if muted or DisplayServer.get_name() == "headless":
		return
	cue.pitch_scale = 1.0
	if kind in ["TAKEOFF", "DRIFT BOOST"]:
		cue.stream = launch_sound
	elif kind in ["PERFECT LANDING", "LANDED", "ROUGH LANDING"]:
		cue.stream = landing_sound
	elif kind == "CRASH":
		cue.stream = miss_sound
	elif kind in ["ROLL", "SPIN"]:
		cue.stream = hit_sound
		cue.pitch_scale = 1.25 if kind == "SPIN" else 1.0
	else:
		return
	cue.play()


func _wave(seconds: float, frequency: float, loop: bool, noise: bool) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(rate * seconds)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var smoothed := 0.0
	for i in samples:
		var t := float(i) / rate
		var value := sin(TAU * frequency * t) * 0.65 + sin(TAU * frequency * 2.0 * t) * 0.2
		if noise:
			smoothed = lerpf(smoothed, rng.randf_range(-1.0, 1.0), 0.25)
			value = smoothed
		if not loop:
			value *= minf(t * 100.0, 1.0) * pow(1.0 - float(i) / samples, 2.0)
		bytes.encode_s16(i * 2, int(value * 15000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples
	return stream

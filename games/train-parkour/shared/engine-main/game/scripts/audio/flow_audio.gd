extends "res://scripts/audio/motion_audio.gd"
## Synthesized local stems: wheel pulse, drift grit, percussion and impact.

var scrub := AudioStreamPlayer.new()
var rhythm := AudioStreamPlayer.new()
var impact := AudioStreamPlayer.new()
var whoosh: AudioStreamWAV
var scrape: AudioStreamWAV


func _ready() -> void:
	super._ready()
	for player in [scrub, rhythm, impact]: add_child(player)
	if DisplayServer.get_name() == "headless": return
	scrub.stream = _wave(1, 0, true, true)
	rhythm.stream = _beat()
	whoosh = _wave(0.23, 0, false, true)
	scrape = _wave(0.3, 140, false, true)
	landing_sound = _wave(0.34, 63, false, false)
	scrub.volume_db = -60
	rhythm.volume_db = -60
	impact.volume_db = -14
	cue.volume_db = -17
	scrub.play()
	rhythm.play()


func _process(delta: float) -> void:
	super._process(delta)
	if session == null or DisplayServer.get_name() == "headless": return
	var quiet := muted or get_tree().paused or session.finished or session.failed
	var train := session.train
	var drift := train.state == TrainController.State.DRIFT
	scrub.volume_db = lerpf(scrub.volume_db, -60.0 if quiet or not drift else -23.0 + train.drift_charge * 8.0, 1.0 - exp(-18 * delta))
	scrub.pitch_scale = 0.7 + train.drift_charge * 1.4
	rhythm.volume_db = lerpf(rhythm.volume_db, -60.0 if quiet else -27.0 + minf(train.boost_time, 1.0) * 4.0, 1.0 - exp(-12 * delta))
	if not quiet and train.state != TrainController.State.AIR:
		motor.volume_db += sin(train.distance * 1.5) * 1.4
	if quiet:
		cue.stop()
		impact.stop()


func play_stunt(kind: String) -> void:
	if muted or DisplayServer.get_name() == "headless": return
	if kind in ["TRANSFER", "WALL SCRAPE", "FAST RIGHT"]:
		impact.stream = scrape if kind == "WALL SCRAPE" else whoosh
		impact.pitch_scale = 0.8 if kind == "WALL SCRAPE" else 1.3
		impact.play()
	elif kind == "CLEAR":
		play_gate(true, session.combo)
	else:
		super.play_stunt(kind)


func reset_feedback() -> void:
	super.reset_feedback()
	impact.stop()


func _exit_tree() -> void:
	super._exit_tree()
	for player in [scrub, rhythm, impact]:
		player.stop()
		player.stream = null


func _beat() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 3.2) # Eight beats at 150 BPM.
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in count:
		var t := float(i) / rate
		var beat := fmod(t, 0.4)
		var hat := fmod(t, 0.2)
		var value := sin(TAU * (54.0 * beat + 1.2 * (1.0 - exp(-35.0 * beat)))) * exp(-23.0 * beat) * 0.6
		value += rng.randf_range(-1, 1) * exp(-100 * hat) * 0.16
		if int(t / 0.4) % 2 == 1:
			value += rng.randf_range(-1, 1) * exp(-28 * beat) * 0.22
		bytes.encode_s16(i * 2, int(clampf(value, -1, 1) * 22000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream

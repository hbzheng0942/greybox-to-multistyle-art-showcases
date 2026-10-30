extends "res://scripts/audio/flow_audio.gd"
## Reuses the project's generated stems, replaces the old 90m/s-normalized mix.
var pulse_sound: AudioStreamWAV
var clamp_sound: AudioStreamWAV
var warning_sound: AudioStreamWAV
var last_warning_key := ""

func _ready() -> void:
	super._ready()
	if DisplayServer.get_name() == "headless": return
	pulse_sound = _wave(0.25, 48, false, false)
	clamp_sound = _wave(0.15, 310, false, true)
	warning_sound = _wave(0.28, 180, false, true)

func _process(delta: float) -> void:
	if session == null or DisplayServer.get_name() == "headless": return
	var train := session.train as SpatialTrain
	var m := train.motion
	var quiet := muted or get_tree().paused or session.finished or session.failed
	var v := m.world_velocity.length()
	var response := 1 - exp(-12 * delta)
	var air := m.phase == SpatialMotionSolver.AIR
	var rail := m.route.current.kind
	var grip := rail in ["grind", "wall", "inverted", "loop", "clip"] or m.phase == SpatialMotionSolver.DRIFT
	motor.pitch_scale = clampf(0.55 + v * 0.0065, 0.55, 1.70)
	wind.pitch_scale = clampf(0.6 + v * 0.005, 0.6, 1.5)
	motor.volume_db = lerpf(motor.volume_db, -60.0 if quiet else (-38.0 if air else -27.0 + clampf((v - 70) / 80, 0, 1) * 5), response)
	wind.volume_db = lerpf(wind.volume_db, -60.0 if quiet else -33.0 + clampf(v / 150, 0, 1.2) * 10 + (3.0 if air else 0.0), response)
	scrub.pitch_scale = 0.7 + v / (110 if rail == "grind" else 160)
	scrub.volume_db = lerpf(scrub.volume_db, -60.0 if quiet or air or not grip else -24.0 + m.drift_quality * 3, response)
	rhythm.volume_db = lerpf(rhythm.volume_db, -60.0 if quiet else -31.0 + m.pulse * 4, response)
	if quiet:
		cue.stop()
		impact.stop()
		last_warning_key = ""
	elif not air:
		var warning_key := ""
		for obstacle in m.route.current.obstacles:
			if obstacle.get("kind", "block") not in ["block", "beam"]: continue
			if obstacle.s > m.s and obstacle.s - m.s <= v * 2.1:
				warning_key = m.route.obstacle_key(m.route.current, obstacle)
				break
		if not warning_key.is_empty() and warning_key != last_warning_key:
			cue.stream = warning_sound
			cue.volume_db = -15
			cue.pitch_scale = 0.8
			cue.play()
		last_warning_key = warning_key

func play_motion(kind: String, data: Dictionary) -> void:
	if muted or DisplayServer.get_name() == "headless": return
	if kind == "PULSE":
		impact.stream = pulse_sound
		impact.volume_db = -10
		impact.pitch_scale = 1
		impact.play()
		super.play_stunt("DRIFT BOOST")
	elif kind == "CAPTURE":
		impact.stream = landing_sound
		impact.volume_db = lerpf(-22, -11, clampf(float(data.normal_speed) / 35, 0, 1))
		impact.pitch_scale = 0.85
		impact.play()
	elif kind in ["TAKEOFF", "EDGE"]:
		var impulse: Array = data.get("impulse", [0, 0, 0])
		var strength := Vector3(impulse[0], impulse[1], impulse[2]).length()
		if strength > 1:
			impact.stream = pulse_sound
			impact.volume_db = lerpf(-18, -10, clampf(strength / 40, 0, 1))
			impact.pitch_scale = 1.1
			impact.play()
		super.play_stunt("TAKEOFF")
	elif kind in ["TRANSFER", "GUARD CONTACT", "SOFT CONTACT"]: super.play_stunt("TRANSFER" if kind == "TRANSFER" else "WALL SCRAPE")
	elif kind == "CRASH": super.play_stunt("CRASH")
	elif kind == "CLEAR": play_gate(true, session.combo)
	elif kind == "ENTER" and data.support in ["wall", "inverted", "loop"]:
		cue.stream = clamp_sound
		cue.pitch_scale = 1.1
		cue.play()

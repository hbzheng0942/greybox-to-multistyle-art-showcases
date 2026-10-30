extends "res://scripts/audio/flow_audio.gd"
## Opt-in grind stem reuses the existing synthesized grit, without changing Flow audio.

var burst: AudioStreamWAV

func _ready() -> void:
	super._ready()
	if DisplayServer.get_name() != "headless": burst = _wave(0.22, 48, false, false)

func _process(delta: float) -> void:
	super._process(delta)
	if session == null or DisplayServer.get_name() == "headless": return
	var train := session.train as NetworkTrain
	if train.support_kind == "grind" and train.active and not muted and not get_tree().paused:
		scrub.volume_db = -23.0
		scrub.pitch_scale = 1.0 + train.speed / 150.0

func play_stunt(kind: String) -> void:
	if kind == "BOOST IMPULSE" and not muted and DisplayServer.get_name() != "headless":
		impact.stream = burst
		impact.volume_db = -10
		impact.pitch_scale = 1
		impact.play()
	else:
		impact.volume_db = -14
	super.play_stunt("DRIFT BOOST" if kind in ["BOOST IMPULSE", "POWER KICK"] else ("TRANSFER" if kind == "GRIND" else kind))

extends Node
## Shipped original PCM clips. No network, no Python and no synth work in the game loop.
## Audio is feedback only: it never modifies growth, capture timing or rewards.
const CLIPS = {
	"small_a": preload("res://assets/audio/bite_small_a.wav"),
	"small_b": preload("res://assets/audio/bite_small_b.wav"),
	"medium": preload("res://assets/audio/bite_medium.wav"),
	"large": preload("res://assets/audio/bite_large.wav"),
	"capture": preload("res://assets/audio/capture_suction.wav"),
	"release": preload("res://assets/audio/release_clatter.wav"),
	"growth": preload("res://assets/audio/growth_chime.wav"),
	"landmark": preload("res://assets/audio/landmark_impact.wav"),
	"finish": preload("res://assets/audio/round_end.wav"),
	"countdown": preload("res://assets/audio/countdown.wav"),
}
const MOTION = preload("res://assets/audio/motion_loop.wav")
var voices: Array = []
var priority_voice: AudioStreamPlayer
var motion_voice: AudioStreamPlayer
var next_voice: int = 0
var enabled: bool = true
var volume: float = 0.8
var bus_index: int = -1
var cooldowns: Dictionary = {}
var wall_time: float = 0.0
var last_bite: float = -10.0
var chain: int = 0
var variant: int = 0
var test_generation: int = 0

func _ready() -> void:
	bus_index = AudioServer.get_bus_index("HoleSFX")
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "HoleSFX")
		AudioServer.set_bus_send(bus_index, "Master")
		var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.5
		limiter.release = 0.10
		AudioServer.add_bus_effect(bus_index, limiter)
	for i in range(10):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.bus = "HoleSFX"
		add_child(voice)
		voices.append(voice)
	priority_voice = AudioStreamPlayer.new()
	priority_voice.bus = "HoleSFX"
	add_child(priority_voice)
	motion_voice = AudioStreamPlayer.new()
	motion_voice.bus = "HoleSFX"
	var loop: AudioStreamWAV = MOTION.duplicate()
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	motion_voice.stream = loop
	motion_voice.volume_db = -48.0
	add_child(motion_voice)
	configure(enabled, volume)

func configure(sound_on: bool, gain: float) -> void:
	enabled = sound_on
	volume = clampf(gain, 0.0, 1.0)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, not enabled or volume <= 0.0)
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(volume, 0.0001)))
	if not enabled and motion_voice != null:
		motion_voice.stop()

func _process(delta: float) -> void:
	wall_time += delta

func update_motion(speed_fraction: float, captured_units: float, active: bool) -> void:
	if motion_voice == null:
		return
	if not active or not enabled:
		motion_voice.stop()
		return
	var energy: float = clampf(speed_fraction * 0.65 + minf(captured_units, 5.0) * 0.09, 0.0, 1.0)
	if energy < 0.02:
		motion_voice.stop()
		return
	if not motion_voice.playing:
		motion_voice.play()
	motion_voice.volume_db = lerpf(-40.0, -27.0, energy)
	motion_voice.pitch_scale = 0.95 + energy * 0.12

func _play(key: String, db: float, pitch: float = 1.0, priority: bool = false) -> void:
	if not enabled or voices.is_empty():
		return
	var voice: AudioStreamPlayer = priority_voice if priority else voices[next_voice]
	voice.stream = CLIPS[key]
	voice.volume_db = db
	voice.pitch_scale = pitch
	voice.play()
	if not priority:
		next_voice = (next_voice + 1) % voices.size()

func play_event(kind: String, object_tier: int = 0) -> void:
	if not enabled:
		return
	var interval: float = 0.0
	if kind == "CAPTURE": interval = 0.09
	elif kind == "RELEASE": interval = 0.16
	elif kind == "CONSUME": interval = 0.04
	if wall_time - float(cooldowns.get(kind, -100.0)) < interval:
		return
	cooldowns[kind] = wall_time
	match kind:
		"CAPTURE":
			_play("capture", -19.0 if object_tier < 2 else -14.0, 1.12 - minf(object_tier, 5) * 0.065)
		"RELEASE":
			_play("release", -9.0)
		"CONSUME":
			chain = mini(chain + 1, 6) if wall_time - last_bite < 0.35 else 0
			last_bite = wall_time
			variant += 1
			if object_tier <= 1:
				_play("small_a" if variant % 2 == 0 else "small_b", -6.0, 1.0 + float(chain) * 0.028)
			elif object_tier == 2:
				_play("medium", -4.0, 1.0 + float(chain) * 0.016)
			else:
				_play("large", -4.0, 1.08 - float(object_tier - 3) * 0.09)
		"LEVEL_UP":
			_play("growth", -5.0, 1.0 + minf(object_tier, 5) * 0.025, true)
		"LANDMARK":
			_play("landmark", -2.0, 1.0, true)
		"COUNTDOWN":
			_play("countdown", -13.0)
		"FINISHED":
			motion_voice.stop()
			_play("finish", -5.0, 1.0, true)

func stop_all() -> void:
	test_generation += 1
	for voice in voices:
		voice.stop()
	if priority_voice != null: priority_voice.stop()
	if motion_voice != null: motion_voice.stop()
	cooldowns.clear()
	last_bite = -10.0
	chain = 0

func test_sequence() -> void:
	stop_all()
	var generation: int = test_generation
	for key in ["small_a", "medium", "large", "growth", "landmark"]:
		if generation != test_generation or not enabled:
			return
		_play(key, -5.0, 1.0, true)
		await get_tree().create_timer(0.80).timeout

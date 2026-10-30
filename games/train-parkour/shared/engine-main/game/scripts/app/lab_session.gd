class_name LabSession
extends Node3D

const TUNING: MotionTuning = preload("res://resources/tuning/motion_default.tres")
@export var wait_for_start: bool = false
var waiting_for_start: bool = false
var failed: bool = false
var stunt_score: int = 0
var landings: int = 0
var drift_boosts: int = 0
var next_gate: int = 0
var cleared: int = 0
var perfects: int = 0
var combo: int = 0
var best_combo: int = 0
var session_best: int = 0
var finished: bool = false
var feedback: String = "FIND YOUR LINE"
var feedback_time: float = 1.5
var feedback_positive: bool = true
@onready var lab: Node3D = $ControllerLab
@onready var train: TrainController = $Actors/Train
@onready var camera: RailCamera = $RailCamera
@onready var sound: Node = $MotionAudio
@onready var hud: Control = $HUD/LabHUD


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	train.configure(lab.route, TUNING)
	camera.configure(train, lab.route, TUNING)
	train.advanced.connect(_on_advanced)
	train.completed.connect(_on_completed)
	train.stunt_event.connect(_on_stunt_event)
	hud.session = self
	sound.session = self
	_update_gate_visibility()
	waiting_for_start = wait_for_start
	if waiting_for_start:
		get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if waiting_for_start and (event.is_action_pressed("jump") or event.is_action_pressed("pause")):
		restart_run()
		return
	if event.is_action_pressed("restart"):
		restart_run()
	elif event.is_action_pressed("pause") and not finished:
		get_tree().paused = not get_tree().paused
	elif event.is_action_pressed("comfort"):
		camera.comfort = not camera.comfort
	elif event.is_action_pressed("mute"):
		sound.muted = not sound.muted
	else:
		for mode in range(3):
			if event.is_action_pressed("pace_%d" % (mode + 1)):
				train.speed_mode = mode
				restart_run()


func _physics_process(delta: float) -> void:
	if train == null or get_tree().paused:
		return
	feedback_time = maxf(0.0, feedback_time - delta)
	_update_gate_visibility()


func restart_run() -> void:
	get_tree().paused = false
	finished = false
	failed = false
	waiting_for_start = false
	stunt_score = 0
	landings = 0
	drift_boosts = 0
	next_gate = 0
	cleared = 0
	perfects = 0
	combo = 0
	best_combo = 0
	feedback = "FIND YOUR LINE"
	feedback_time = 1.5
	feedback_positive = true
	for gate: LaneGate in lab.gates:
		gate.reset_gate()
	train.reset_run()
	camera.reset_camera()
	sound.reset_feedback()
	_update_gate_visibility()


func _on_advanced(previous: float, current: float, previous_lateral: float, current_lateral: float) -> void:
	# Sweep the entire distance interval. Never miss thin gates at high speed.
	while next_gate < lab.gates.size() and lab.gates[next_gate].distance <= current:
		var gate: LaneGate = lab.gates[next_gate]
		var fraction := clampf((gate.distance - previous) / maxf(current - previous, 0.00001), 0.0, 1.0)
		var lateral_at_crossing := lerpf(previous_lateral, current_lateral, fraction)
		var error := absf(lateral_at_crossing - gate.lane * TUNING.lane_spacing)
		var hit := error <= TUNING.gate_half_width and train.state != TrainController.State.AIR
		var perfect := hit and error <= TUNING.perfect_half_width
		gate.resolve(hit)
		if hit:
			cleared += 1
			perfects += int(perfect)
			combo += 1
			best_combo = maxi(best_combo, combo)
			feedback = "PERFECT LINE" if perfect else "GATE CLEAR"
		else:
			combo = 0
			feedback = "MISSED / KEEP MOVING"
		feedback_positive = hit
		feedback_time = 0.8
		train.register_gate(perfect, hit)
		sound.play_gate(hit, combo)
		next_gate += 1


func _on_completed() -> void:
	finished = true
	session_best = maxi(session_best, stunt_score if lab.route.stunts != null else cleared)
	feedback_time = 0.0


func _on_stunt_event(kind: String, value: float) -> void:
	feedback = kind
	feedback_time = 0.9
	feedback_positive = true
	if kind == "DRIFT BOOST":
		drift_boosts += 1
		stunt_score += int(value * 150.0)
		combo += 1
	elif kind in ["PERFECT LANDING", "LANDED", "ROUGH LANDING"]:
		landings += 1
		stunt_score += int(value)
		combo += train.air_tricks + 1
		feedback_positive = kind != "ROUGH LANDING"
	elif kind == "CRASH":
		failed = true
		feedback = train.crash_reason
		feedback_positive = false
		combo = 0
	best_combo = maxi(best_combo, combo)
	sound.play_stunt(kind)


func _update_gate_visibility() -> void:
	for gate: LaneGate in lab.gates:
		var ahead := gate.distance - train.distance
		gate.visible = ahead > -30.0 and ahead < 750.0


func next_gate_data() -> Dictionary:
	if next_gate >= lab.gates.size():
		return {"lane": 0, "distance": 0.0, "remaining": 0}
	var gate: LaneGate = lab.gates[next_gate]
	return {"lane": gate.lane, "distance": maxf(0.0, gate.distance - train.distance), "remaining": lab.gates.size() - next_gate}

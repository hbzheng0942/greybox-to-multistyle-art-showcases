class_name SpatialTrain
extends FlowTrain
## Presentation/input adapter. No legacy rail/air/landing integration is called.
signal motion_event(kind: String, payload: Dictionary)
var motion := SpatialMotionSolver.new()
@export var settings: SpatialTuning = preload("res://resources/tuning/spatial_default.tres")
var spatial: SpatialRoute
var _reported_finish := false

func configure(new_route: RailRoute, new_tuning: MotionTuning) -> void:
	route = new_route
	spatial = new_route as SpatialRoute
	tuning = new_tuning.duplicate()
	tuning.speed_presets = settings.cruise.duplicate()
	speed_mode = 2
	motion.event.connect(_motion_event)
	motion.configure(spatial, settings)
	_reset_presentation()
	_sync()

func reset_run() -> void:
	motion.reset(speed_mode)
	_reset_presentation()
	_sync()
	reset_physics_interpolation()

func _reset_presentation() -> void:
	_reported_finish = false
	transfer_pulse = 0
	scrape_time = 0
	style_axis = 0
	style_angle = 0
	style_progress = 0
	styles_completed = 0
	trick_axis = 0
	trick_angle = 0
	air_tricks = 0
	air_points = 0
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	visual.scale = Vector3.ONE
	trick_pivot.rotation = Vector3.ZERO

func _sync() -> void:
	state = motion.phase as State
	distance = motion.s
	speed = motion.speed
	lateral = motion.side
	target_lane = motion.lane
	lane_elapsed = motion.lane_elapsed
	elapsed = motion.clock
	active = motion.active
	braking_now = motion.braking
	drift_direction = motion.drift_side
	drift_charge = motion.drift_quality
	landing_impact = motion.impact
	boost_time = motion.pulse * 0.85
	boost_amount = 0
	velocity = motion.world_velocity
	vertical_velocity = velocity.y
	launch_speed = Vector2(velocity.x, velocity.z).length()
	air_forward = velocity.normalized() if velocity.length_squared() > 1 else -motion.world_pose.basis.z
	air_right = motion.world_pose.basis.x
	air_time = motion.air_time
	crash_reason = motion.crash_reason
	global_transform = motion.world_pose

func _physics_process(delta: float) -> void:
	if spatial == null: return
	previous_world = global_position
	transfer_pulse = move_toward(transfer_pulse, 0, delta * 3)
	scrape_time = maxf(0, scrape_time - delta)
	var old_s := distance
	var old_side := lateral
	var camera := get_viewport().get_camera_3d()
	var control_right := camera.global_basis.x if camera != null else global_basis.x
	var controls := {"axis": Input.get_axis("steer_left", "steer_right"), "left": Input.is_action_just_pressed("steer_left"), "right": Input.is_action_just_pressed("steer_right"), "shift": Input.is_action_pressed("brake_drift"), "jump": Input.is_action_just_pressed("jump")}
	motion.step(delta, controls, control_right)
	_sync()
	if state == State.AIR:
		air_side_speed = float(controls.axis) * signf(control_right.dot(global_basis.x)) * 6.0
		_step_trick(delta)
	_update_visual(delta, (lateral - old_side) / maxf(delta, 0.001))
	advanced.emit(old_s, distance, old_side, lateral)
	if motion.finished and not _reported_finish:
		_reported_finish = true
		completed.emit()

func _motion_event(kind: String, payload: Dictionary) -> void:
	_sync()
	motion_event.emit(kind, payload)
	var legacy_kind := kind
	if kind == "TRANSFER":
		transfer_pulse = 1
		transfer_direction = int(payload.screen_direction)
	elif kind in ["TAKEOFF", "EDGE"]:
		style_progress = 0
		style_angle = 0
		# Don't double-spin a physically flipping ceiling or wall departure.
		style_axis = 0 if motion.air_source in ["wall", "inverted"] else (2 if motion.air_source == "grind" else 1)
		style_duration = 0.65
		legacy_kind = "TAKEOFF"
	elif kind == "CAPTURE":
		style_axis = 0
		style_angle = 0
		trick_pivot.rotation = Vector3.ZERO
		legacy_kind = "ROUGH LANDING" if payload.rough else "PERFECT LANDING"
	elif kind == "GUARD CONTACT":
		scrape_time = 0.35
		legacy_kind = "WALL SCRAPE"
	stunt_event.emit(legacy_kind, 0)

func landing_eta() -> float:
	var prediction := motion.predict()
	return prediction.get("eta", 0.4)

func landing_target() -> Vector3:
	var prediction := motion.predict()
	return prediction.get("target", global_position + air_forward * 30)

func landing_steering_error() -> float:
	var prediction := motion.predict()
	if prediction.is_empty(): return 0
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x if camera != null else motion.world_pose.basis.x
	return right.dot(prediction.target - prediction.point)

func _crash(reason: String) -> void:
	motion.crash(reason)
	_sync()

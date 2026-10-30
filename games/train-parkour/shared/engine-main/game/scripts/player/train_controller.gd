class_name TrainController
extends CharacterBody3D

signal advanced(previous_distance: float, distance: float, previous_lateral: float, lateral: float)
signal completed
signal stunt_event(kind: String, value: float)

enum State { RAIL, DRIFT, AIR, RECOVER, CRASHED }
var state: State = State.RAIL
var route: RailRoute
var tuning: MotionTuning
var distance: float = 0.0
var speed: float = 0.0
var lateral: float = 0.0
var target_lane: int = 0
var speed_mode: int = 1
var elapsed: float = 0.0
var flow: int = 0
var active: bool = false
var braking_now: bool = false
var lane_from: float = 0.0
var lane_elapsed: float = 0.0
var hit_pulse: float = 0.0
var lean: float = 0.0
var drift_direction: float = 0.0
var drift_charge: float = 0.0
var boost_time: float = 0.0
var boost_amount: float = 0.0
var jump_buffer: float = 0.0
var jump_cooldown: float = 0.0
var recovery_time: float = 0.0
var landing_impact: float = 0.0
var air_time: float = 0.0
var air_forward: Vector3 = Vector3.FORWARD
var air_right: Vector3 = Vector3.RIGHT
var launch_speed: float = 0.0
var vertical_velocity: float = 0.0
var air_side_speed: float = 0.0
var air_points: int = 0
var air_tricks: int = 0
var trick_axis: int = 0
var trick_time: float = 0.0
var trick_angle: float = 0.0
var trick_queued: int = 0
var airborne_from_jump: bool = false
var crash_reason: String = ""
@onready var visual: Node3D = $VisualRoot
@onready var trick_pivot: Node3D = $VisualRoot/TrickPivot


func configure(new_route: RailRoute, new_tuning: MotionTuning) -> void:
	route = new_route
	tuning = new_tuning
	reset_run()


func reset_run() -> void:
	state = State.RAIL
	distance = tuning.start_distance
	speed = tuning.speed_presets[speed_mode] * 0.65
	lateral = 0.0
	target_lane = 0
	lane_from = 0.0
	lane_elapsed = tuning.lane_change_seconds
	elapsed = 0.0
	flow = 0
	hit_pulse = 0.0
	lean = 0.0
	drift_direction = 0.0
	drift_charge = 0.0
	boost_time = 0.0
	boost_amount = 0.0
	jump_buffer = 0.0
	jump_cooldown = 0.18
	recovery_time = 0.0
	landing_impact = 0.0
	air_time = 0.0
	air_side_speed = 0.0
	vertical_velocity = 0.0
	air_forward = Vector3.FORWARD
	air_right = Vector3.RIGHT
	launch_speed = 0.0
	air_points = 0
	air_tricks = 0
	trick_axis = 0
	trick_time = 0.0
	trick_angle = 0.0
	trick_queued = 0
	airborne_from_jump = false
	crash_reason = ""
	velocity = Vector3.ZERO
	braking_now = false
	visual.rotation = Vector3.ZERO
	visual.position = Vector3.ZERO
	trick_pivot.rotation = Vector3.ZERO
	global_transform = route.pose_at(distance)
	reset_physics_interpolation()
	active = true


func switch_lane(direction: int) -> void:
	if not active or state == State.AIR:
		return
	var next := clampi(target_lane + direction, -1, 1)
	if next == target_lane:
		return
	lane_from = lateral
	lane_elapsed = 0.0
	target_lane = next


func _physics_process(delta: float) -> void:
	if not active or route == null:
		return
	var old_distance := distance
	var old_lateral := lateral
	var old_position := global_position
	elapsed += delta
	boost_time = maxf(0.0, boost_time - delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	jump_cooldown = maxf(0.0, jump_cooldown - delta)
	landing_impact = move_toward(landing_impact, 0.0, delta * 5.0)
	if route.stunts != null and Input.is_action_just_pressed("jump"):
		jump_buffer = tuning.jump_buffer_seconds
	if state != State.AIR:
		_ground_input(delta)
	if state == State.AIR:
		_step_air(delta)
	elif state != State.CRASHED:
		_step_rail(delta)
	velocity = (global_position - old_position) / delta
	_update_visual(delta, (lateral - old_lateral) / delta)
	advanced.emit(old_distance, distance, old_lateral, lateral)
	if state != State.AIR and state != State.CRASHED and _at_finish():
		active = false
		completed.emit()


func _ground_input(delta: float) -> void:
	var axis := Input.get_axis("steer_left", "steer_right")
	var shift := Input.is_action_pressed("brake_drift")
	if route.stunts != null and shift and absf(axis) > 0.5 and state != State.DRIFT:
		state = State.DRIFT
		drift_direction = axis
		drift_charge = 0.0
		stunt_event.emit("DRIFT", 0.0)
	if state == State.DRIFT:
		if not shift:
			_release_drift()
		else:
			if absf(axis) > 0.5:
				drift_direction = axis
			var turn := route.turn_direction(distance)
			var matching := absf(turn) > 0.035 and signf(turn) == signf(axis)
			drift_charge = clampf(drift_charge + delta * (0.55 if matching else -0.18), 0.0, 1.0)
	else:
		if Input.is_action_just_pressed("steer_left"):
			switch_lane(-1)
		if Input.is_action_just_pressed("steer_right"):
			switch_lane(1)
	if jump_buffer > 0.0 and jump_cooldown <= 0.0:
		if state == State.DRIFT:
			_release_drift()
		_launch(true)


func _release_drift() -> void:
	state = State.RAIL
	if drift_charge >= 0.25:
		boost_amount = 8.0 + drift_charge * 14.0
		boost_time = 2.0
		speed += boost_amount * 0.65
		stunt_event.emit("DRIFT BOOST", drift_charge)
	else:
		stunt_event.emit("DRIFT RELEASE", 0.0)
	lane_from = lateral
	lane_elapsed = 0.0
	drift_charge = 0.0


func _step_rail(delta: float) -> void:
	_step_speed(delta)
	_step_support_motion(delta)


func _step_speed(delta: float) -> void:
	braking_now = Input.is_action_pressed("brake_drift") and state != State.DRIFT
	var desired := tuning.brake_speed if braking_now else tuning.speed_presets[speed_mode] + minf(flow * 1.5, 10.0)
	if boost_time > 0.0 and not braking_now:
		desired += boost_amount
	if state == State.DRIFT:
		desired *= 0.94
		var turn := route.turn_direction(distance)
		if absf(turn) > 0.035 and signf(turn) != signf(drift_direction):
			# Penalize the target speed so normal acceleration cannot undo the penalty.
			desired = maxf(tuning.brake_speed, desired - 18.0)
	speed = move_toward(speed, desired, (tuning.braking if braking_now else tuning.acceleration) * delta)


func _step_support_motion(delta: float) -> void:
	if state == State.DRIFT:
		lateral = lerpf(lateral, target_lane * tuning.lane_spacing + drift_direction * 1.8, 1.0 - exp(-7.0 * delta))
	else:
		lane_elapsed = minf(lane_elapsed + delta, tuning.lane_change_seconds)
		var t := lane_elapsed / tuning.lane_change_seconds
		lateral = lerpf(lane_from, target_lane * tuning.lane_spacing, t * t * (3.0 - 2.0 * t))
	if state == State.RECOVER:
		recovery_time -= delta
		if recovery_time <= 0.0:
			state = State.RAIL
	_advance_rail(delta)


func _at_finish() -> bool:
	return distance >= route.length - 16.0


func _advance_rail(delta: float) -> void:
	distance = minf(distance + speed * delta, route.length - 16.0)
	global_transform = route.pose_at(distance, lateral)
	_check_rail_support()


func _check_rail_support() -> void:
	if not route.has_track(distance):
		_launch(false)
	elif route.stunts != null and distance >= route.stunts.gap_end and distance < route.stunts.landing_end:
		if absf(lateral - route.stunts.landing_lane * tuning.lane_spacing) > 2.1:
			_launch(false)


func _launch(intentional: bool) -> void:
	var pose := route.pose_at(distance)
	air_forward = -pose.basis.z
	air_forward.y = 0.0
	air_forward = air_forward.normalized()
	air_right = air_forward.cross(Vector3.UP).normalized()
	launch_speed = speed
	vertical_velocity = tuning.ollie_velocity if intentional else 0.0
	_apply_launch_assist(intentional)
	air_side_speed = 0.0
	air_time = 0.0
	air_points = 0
	air_tricks = 0
	trick_axis = 0
	trick_time = 0.0
	trick_angle = 0.0
	trick_queued = 0
	jump_buffer = 0.0
	airborne_from_jump = intentional
	braking_now = false
	global_position += Vector3.UP * 0.05
	state = State.AIR
	stunt_event.emit("TAKEOFF" if intentional else "FALL", launch_speed)


func _apply_launch_assist(intentional: bool) -> void:
	var profile := route.stunts
	if intentional and profile != null and distance >= profile.gap_start - profile.launch_window and distance <= profile.gap_start + 4.0:
		launch_speed = maxf(speed, 60.0)
		var flight_range := profile.gap_end - profile.gap_start + 64.0
		vertical_velocity = clampf(flight_range * tuning.gravity / (2.0 * launch_speed), 27.0, 46.0)


func _step_air(delta: float) -> void:
	var previous_position := global_position
	var previous_height := previous_position.y - route.pose_at(distance).origin.y
	air_time += delta
	var axis := Input.get_axis("steer_left", "steer_right")
	if absf(axis) > 0.1:
		air_side_speed = clampf(air_side_speed + axis * tuning.air_acceleration * delta, -tuning.air_lateral_limit, tuning.air_lateral_limit)
	else:
		air_side_speed *= exp(-tuning.air_drag * delta)
	vertical_velocity -= tuning.gravity * delta
	global_position += (air_forward * launch_speed + air_right * air_side_speed + Vector3.UP * vertical_velocity) * delta
	global_basis = Basis(air_right, Vector3.UP, -air_forward)
	distance = clampf(route.closest_distance(global_position), 0.0, route.length)
	var pose := route.pose_at(distance)
	lateral = pose.basis.x.dot(global_position - pose.origin)
	speed = launch_speed
	_step_trick(delta)
	var height := global_position.y - pose.origin.y
	if vertical_velocity < 0.0 and previous_height > 0.0 and height <= 0.0:
		var fraction := previous_height / maxf(previous_height - height, 0.0001)
		var contact := previous_position.lerp(global_position, fraction)
		var contact_distance := route.closest_distance(contact)
		if route.has_track(contact_distance):
			_land(contact, contact_distance)
	if state == State.AIR:
		if height < -24.0 or air_time > 6.0:
			_crash("MISSED LANDING")
		elif route.has_track(distance) and height < -0.5:
			_crash("BELOW THE RAIL")


func _step_trick(delta: float) -> void:
	var requested := 0
	if Input.is_action_just_pressed("trick_roll"):
		requested = 1
	elif Input.is_action_just_pressed("trick_spin"):
		requested = 2
	if requested != 0:
		if trick_axis == 0:
			trick_axis = requested
			trick_time = 0.0
		elif tuning.trick_duration - trick_time < 0.14:
			trick_queued = requested
	if trick_axis != 0:
		trick_time += delta
		var t := clampf(trick_time / tuning.trick_duration, 0.0, 1.0)
		trick_angle = TAU * (t * t * (3.0 - 2.0 * t))
		if t >= 1.0:
			air_tricks += 1
			air_points += 100 if trick_axis == 1 else 150
			stunt_event.emit("ROLL" if trick_axis == 1 else "SPIN", air_points)
			trick_axis = trick_queued
			trick_queued = 0
			trick_time = 0.0
			trick_angle = 0.0


func _land(contact: Vector3, contact_distance: float) -> void:
	var pose := route.pose_at(contact_distance)
	var offset := pose.basis.x.dot(contact - pose.origin)
	var best_lane := 0
	var error := INF
	for lane in route.lanes_at(contact_distance):
		var candidate := absf(offset - lane * tuning.lane_spacing)
		if candidate < error:
			error = candidate
			best_lane = lane
	var heading_error := rad_to_deg(acos(clampf(air_forward.dot(-pose.basis.z), -1.0, 1.0)))
	var rotation_error := absf(wrapf(trick_angle, -PI, PI))
	var past_endpoint := absf((-pose.basis.z).dot(contact - pose.origin)) > 5.0
	if error > tuning.landing_capture_width or heading_error > 28.0 or rotation_error > deg_to_rad(65.0) or past_endpoint:
		_crash("UNFINISHED TRICK" if rotation_error > deg_to_rad(65.0) else "MISALIGNED LANDING")
		return
	var rough := rotation_error > deg_to_rad(24.0) or error > 1.1
	var perfect := not rough and error < 0.55 and heading_error < 12.0
	distance = contact_distance
	lateral = offset
	target_lane = best_lane
	lane_from = lateral
	lane_elapsed = 0.0
	state = State.RECOVER
	recovery_time = 0.22
	jump_cooldown = 0.12
	landing_impact = 1.0
	speed = launch_speed * (0.72 if rough else 0.98)
	if not rough:
		boost_time = 1.4
		boost_amount = minf(6.0 + air_tricks * 3.0, 15.0)
		flow += 1
	var points := (air_points / 2 + 50) if rough else air_points + (200 if perfect else 100)
	stunt_event.emit("ROUGH LANDING" if rough else ("PERFECT LANDING" if perfect else "LANDED"), points)
	air_points = 0
	trick_axis = 0
	trick_angle = 0.0
	trick_queued = 0
	trick_pivot.rotation = Vector3.ZERO
	global_transform = route.pose_at(distance, lateral)


func _crash(reason: String) -> void:
	state = State.CRASHED
	active = false
	crash_reason = reason
	air_points = 0
	trick_queued = 0
	stunt_event.emit("CRASH", 0.0)


func _update_visual(delta: float, side_speed: float) -> void:
	var bend := route.turn_direction(distance)
	var wanted_lean := clampf(-side_speed * 0.016 + bend * 1.0, -0.24, 0.24)
	var wanted_yaw := -drift_direction * 0.62 if state == State.DRIFT else 0.0
	var wanted_pitch := 0.035 if braking_now else -0.012
	if state == State.AIR:
		wanted_lean = -air_side_speed * 0.015
		wanted_pitch = clampf(-atan2(vertical_velocity, maxf(speed, 1.0)) * 0.5, -0.35, 0.35)
	lean = lerpf(lean, wanted_lean, 1.0 - exp(-15.0 * delta))
	hit_pulse = move_toward(hit_pulse, 0.0, delta * 4.0)
	visual.rotation.z = lean
	visual.rotation.y = lerp_angle(visual.rotation.y, wanted_yaw, 1.0 - exp(-10.0 * delta))
	visual.rotation.x = lerpf(visual.rotation.x, wanted_pitch, 1.0 - exp(-8.0 * delta))
	visual.position.y = -landing_impact * 0.18 + (0.0 if state == State.AIR else sin(distance * 0.36) * 0.018) + hit_pulse * 0.07
	if state == State.AIR:
		trick_pivot.rotation = Vector3(0, trick_angle, 0) if trick_axis == 2 else Vector3(0, 0, trick_angle)


func landing_target() -> Vector3:
	if route.stunts == null:
		return route.pose_at(distance + 100.0).origin
	return route.pose_at(clampf(distance + 70.0, route.stunts.gap_end + 24.0, route.stunts.landing_end - 12.0), route.stunts.landing_lane * tuning.lane_spacing).origin


func landing_eta() -> float:
	var height := maxf(0.0, global_position.y - route.pose_at(distance).origin.y)
	return (vertical_velocity + sqrt(vertical_velocity * vertical_velocity + 2.0 * tuning.gravity * height)) / tuning.gravity


func landing_steering_error() -> float:
	# Predict where releasing A/D now would carry the train on this flat landing zone.
	# This only informs the HUD; it never attracts the train to the rail.
	var eta := landing_eta()
	var drift_distance := air_side_speed * (1.0 - exp(-tuning.air_drag * eta)) / tuning.air_drag
	var predicted := global_position + air_forward * launch_speed * eta + air_right * drift_distance
	var pose := route.pose_at(route.closest_distance(predicted))
	var offset := pose.basis.x.dot(predicted - pose.origin)
	return route.stunts.landing_lane * tuning.lane_spacing - offset


func register_gate(perfect: bool, hit: bool) -> void:
	if hit:
		flow += 1
		hit_pulse = 0.65 if perfect else 0.3
	else:
		flow = 0
		speed = maxf(tuning.brake_speed, speed - tuning.miss_speed_loss)
		hit_pulse = 1.0

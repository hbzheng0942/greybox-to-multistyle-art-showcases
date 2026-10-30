class_name FlowTrain
extends TrainController
## Flow-specific assistance stays separate from the preserved stunt baseline.

var course: FlowCourse
var previous_world := Vector3.ZERO
var active_jump: Dictionary = {}
var edge_grace := 0.0
var transfer_pulse := 0.0
var transfer_direction := 0
var auto_roll := 0.0
var scrape_time := 0.0
var scrape_count := 0
var style_axis := 0
var style_angle := 0.0
var style_duration := 0.0
var style_progress := 0.0
var styles_completed := 0


func configure(new_route: RailRoute, new_tuning: MotionTuning) -> void:
	course = (new_route as FlowRoute).course
	speed_mode = 2
	super.configure(new_route, new_tuning)


func reset_run() -> void:
	super.reset_run()
	active_jump = {}
	edge_grace = 0
	transfer_pulse = 0
	auto_roll = 0
	scrape_time = 0
	scrape_count = 0
	style_axis = 0
	style_angle = 0
	style_duration = 0
	style_progress = 0
	styles_completed = 0
	visual.scale = Vector3.ONE
	previous_world = global_position


func resume_at(s: float, lane: int) -> void:
	var clock := elapsed
	reset_run()
	elapsed = clock
	distance = s
	target_lane = lane
	lateral = lane * tuning.lane_spacing
	lane_from = lateral
	speed = tuning.speed_presets[speed_mode] * 0.88
	global_transform = route.pose_at(s, lateral)
	previous_world = global_position
	reset_physics_interpolation()


func switch_lane(direction: int) -> void:
	var before := target_lane
	super.switch_lane(direction)
	if before != target_lane:
		transfer_pulse = 1.0
		transfer_direction = direction
		stunt_event.emit("TRANSFER", direction)


func _physics_process(delta: float) -> void:
	previous_world = global_position
	transfer_pulse = move_toward(transfer_pulse, 0, delta * 3.0)
	scrape_time = maxf(0, scrape_time - delta)
	# A deliberate jump just after the edge is accepted; falling is still real.
	if active and state == State.AIR and not airborne_from_jump and edge_grace > 0:
		edge_grace -= delta
		if Input.is_action_just_pressed("jump"):
			_launch(true)
	super._physics_process(delta)


func _ground_input(delta: float) -> void:
	# Early presses immediately outside the coloured takeoff strip wait up to 240 ms.
	var saved_buffer := jump_buffer
	var jump := course.jump_near(distance)
	var waiting: bool = not jump.is_empty() and distance < jump.start - jump.window and jump.start - jump.window - distance <= speed * 0.24
	if Input.is_action_just_pressed("jump"):
		saved_buffer = 0.24
	if waiting:
		jump_buffer = 0
	var was_drifting := state == State.DRIFT
	super._ground_input(delta)
	if was_drifting and state == State.RAIL and not Input.is_action_pressed("brake_drift"):
		if Input.is_action_just_pressed("steer_left"): switch_lane(-1)
		elif Input.is_action_just_pressed("steer_right"): switch_lane(1)
	if waiting:
		jump_buffer = saved_buffer


func _step_rail(delta: float) -> void:
	# Same canonical rail movement, with authored acute-turn consequences.
	var turn := course.turn_at(distance)
	var correct: bool = not turn.is_empty() and state == State.DRIFT and signf(drift_direction) == turn.direction
	if not turn.is_empty() and (distance < turn.start + 8.0 or distance > turn.end - 8.0):
		correct = true # Entry/exit forgiveness; release timing need not be pixel exact.
	if not turn.is_empty() and not correct and speed > 43.0:
		speed = maxf(40, speed - 48.0 * delta)
		if scrape_time <= 0:
			scrape_time = 0.8
			scrape_count += 1
			flow = 0
			stunt_event.emit("WALL SCRAPE", 0)
	super._step_rail(delta)


func _check_rail_support() -> void:
	var lanes := route.lanes_at(distance)
	if lanes.size() == 3:
		return
	var supported := false
	for lane in lanes:
		supported = supported or absf(lateral - lane * tuning.lane_spacing) <= course.support_width(distance, lane)
	if not supported:
		_launch(false)


func _land(contact: Vector3, contact_distance: float) -> void:
	if contact_distance >= course.fork_start and contact_distance < course.fork_end:
		var pose := route.pose_at(contact_distance)
		var offset := pose.basis.x.dot(contact - pose.origin)
		var supported := false
		for lane in route.lanes_at(contact_distance):
			supported = supported or absf(offset - lane * tuning.lane_spacing) <= course.support_width(contact_distance, lane)
		if not supported:
			_crash("MISSED THE NARROW RAIL")
			return
	super._land(contact, contact_distance)
	# Reward the successful long connection, independent of visual rotations.
	if state == State.RECOVER and speed > launch_speed * 0.9 and not active_jump.is_empty():
		boost_amount = 12.0
	style_axis = 0
	style_angle = 0
	style_progress = 0


func _apply_launch_assist(intentional: bool) -> void:
	active_jump = course.jump_near(distance)
	if intentional and not active_jump.is_empty() and distance >= active_jump.start - active_jump.window and distance <= active_jump.start + speed * 0.14:
		launch_speed = maxf(speed, 56.0)
		var reach: float = active_jump.end + 20.0 - distance
		var flight_time := reach / launch_speed
		var height_change: float = route.pose_at(active_jump.end + 20.0).origin.y - global_position.y
		vertical_velocity = height_change / flight_time + tuning.gravity * flight_time * 0.5 + 0.2
	else:
		active_jump = {}
	edge_grace = 0.14 if not intentional else 0.0
	auto_roll = 1.0 if intentional else 0.0
	style_axis = 0
	style_angle = 0
	style_progress = 0
	style_duration = 0
	if intentional and not active_jump.is_empty():
		# Select a readable contextual accent; complete before the capture approach.
		style_axis = 1 if active_jump.land_lane == 0 else 2
		var flight_time: float = (active_jump.end + 20.0 - distance) / launch_speed
		style_duration = clampf(flight_time * 0.60, 0.45, 1.10)


func _step_trick(_delta: float) -> void:
	# Flow has no manual trick input. Presentation cannot cause a failed landing.
	if style_axis == 0 or style_progress >= 1.0:
		return
	var remaining := landing_eta()
	var end_time := minf(style_duration, air_time + maxf(0.0, remaining - 0.18))
	style_progress = maxf(style_progress, clampf((air_time - 0.05) / maxf(end_time - 0.05, 0.10), 0.0, 1.0))
	style_angle = TAU * smoothstep(0, 1, style_progress)
	if style_progress >= 1.0:
		styles_completed += 1
		stunt_event.emit("ROLL" if style_axis == 1 else "SPIN", 0)


func _update_visual(delta: float, side_speed: float) -> void:
	super._update_visual(delta, side_speed)
	# Automatic accents never affect physical orientation or landing validity.
	var hop := sin((1.0 - transfer_pulse) * PI) * transfer_pulse
	visual.position.y += hop * 0.7
	visual.rotation.z += hop * transfer_direction * -0.30
	visual.scale = Vector3(1.0 + landing_impact * 0.11, 1.0 - landing_impact * 0.16, 1.0 + landing_impact * 0.04)
	if state == State.AIR and style_axis != 0:
		trick_pivot.rotation = Vector3(0, style_angle, 0) if style_axis == 2 else Vector3(0, 0, style_angle)
	elif state == State.AIR:
		var duration := air_time + landing_eta()
		var phase := clampf(air_time / maxf(duration, 0.01), 0, 1)
		trick_pivot.rotation.z = sin(phase * TAU) * 0.24 * auto_roll


func landing_target() -> Vector3:
	if active_jump.is_empty():
		return route.pose_at(distance + speed * landing_eta(), target_lane * tuning.lane_spacing).origin
	var lane: int = active_jump.land_lane if active_jump.land_lane != 0 else target_lane
	return route.pose_at(active_jump.end + 20.0, lane * tuning.lane_spacing).origin


func landing_steering_error() -> float:
	var eta := landing_eta()
	var predicted := global_position + air_forward * launch_speed * eta + air_right * air_side_speed * (1.0 - exp(-tuning.air_drag * eta)) / tuning.air_drag
	var pose := route.pose_at(route.closest_distance(predicted))
	var lane: int = active_jump.get("land_lane", target_lane)
	if lane == 0: lane = target_lane
	return lane * tuning.lane_spacing - pose.basis.x.dot(predicted - pose.origin)

class_name NetworkTrain
extends FlowTrain
## Opt-in network extension: original lane easing, drift, body, audio and input survive.

signal segment_entered(id: String)
var network: NetworkRoute
var settings: NetworkTuning = preload("res://resources/tuning/network_default.tres")
var support_kind := "wide"
var triggered: Dictionary = {}
var pad_pulse := 0.0
var air_source := ""
var air_source_distance := 0.0
var legal_targets: Array[Dictionary] = []
var preferred_target := ""
var metres := 0.0
var grade_delta_v := 0.0
var boost_delta_v := 0.0
var peak_speed := 0.0
var history: Array[Dictionary] = []
var last_rejection := "NO SUPPORT CONTACT"
var _frame_position := Vector3.ZERO
var _support_side_before_step := 0.0


func configure(new_route: RailRoute, new_tuning: MotionTuning) -> void:
	network = new_route as NetworkRoute
	if "--candidate-100" in OS.get_cmdline_user_args() and network.layout in ["ramp", "sentence", "integration"]:
		settings = preload("res://resources/tuning/network_100.tres")
	# New resource instance only; old motion_default is not modified.
	var isolated := new_tuning.duplicate() as MotionTuning
	isolated.speed_presets = new_tuning.speed_presets.duplicate()
	isolated.speed_presets[2] = settings.candidate_speed
	super.configure(new_route, isolated)


func reset_run() -> void:
	network.activate(network.start_id)
	super.reset_run()
	metres = 0
	triggered.clear()
	pad_pulse = 0
	grade_delta_v = 0
	boost_delta_v = 0
	peak_speed = speed
	history.clear()
	legal_targets.clear()
	preferred_target = ""
	support_kind = network.current.support
	_record("START")


func _record(kind: String) -> void:
	history.append({"kind": kind, "segment": network.current.id, "s": distance, "seconds": elapsed, "metres": metres, "speed": speed, "height": network.to_local(global_position).y})


func _physics_process(delta: float) -> void:
	pad_pulse = move_toward(pad_pulse, 0, delta * 2.5)
	_frame_position = global_position
	if network != null and network.current.next.size() > 1:
		network.preview_next = network.current.next[1] if target_lane < 0 else network.current.next[0]
	super._physics_process(delta)
	if active:
		metres += global_position.distance_to(_frame_position)
		peak_speed = maxf(peak_speed, speed)


func _release_drift() -> void:
	super._release_drift()
	speed = minf(speed, settings.max_speed)


func _step_speed(delta: float) -> void:
	_support_side_before_step = lateral
	braking_now = Input.is_action_pressed("brake_drift") and state != State.DRIFT
	var base := tuning.speed_presets[speed_mode]
	var desired := base + (boost_amount if boost_time > 0 else 0.0)
	if state == State.DRIFT: desired *= 0.94
	if braking_now:
		speed = move_toward(speed, tuning.brake_speed, tuning.braking * delta)
	else:
		# Cruise supplies traction below target; coasting does not erase gravity gains.
		speed = move_toward(speed, desired, (tuning.acceleration if speed < desired else settings.coast_drag) * delta)
	var grade := -route.pose_at(distance).basis.z.y
	var contribution := -grade * settings.grade_gravity * delta
	speed += contribution
	grade_delta_v += contribution
	speed = clampf(speed, 18, settings.max_speed)


func _boost_sweep(a: float, b: float, side_a: float, side_b: float) -> float:
	var first := 1.0
	for i in network.current.boosts.size():
		var pad: Dictionary = network.current.boosts[i]
		var key := network.current.id + ":boost:" + str(i)
		if triggered.has(key) or b < pad.start or a > pad.end: continue
		var low := maxf(0, (pad.start - a) / maxf(b - a, 0.00001))
		var high := minf(1, (pad.end - a) / maxf(b - a, 0.00001))
		var center: float = pad.lane * tuning.lane_spacing
		if absf(side_b - side_a) < 0.00001:
			if absf(side_a - center) > 1.8: continue
		else:
			var t1 := (center - 1.8 - side_a) / (side_b - side_a)
			var t2 := (center + 1.8 - side_a) / (side_b - side_a)
			low = maxf(low, minf(t1, t2))
			high = minf(high, maxf(t1, t2))
		if low > high: continue
		triggered[key] = true
		var gain := minf(settings.boost_impulse, settings.max_speed - speed)
		speed += gain
		boost_delta_v += gain
		boost_time = 0.85
		boost_amount = 0
		pad_pulse = 1
		first = minf(first, low)
		_record("BOOST IMPULSE")
		stunt_event.emit("BOOST IMPULSE", gain)
	return first


func _advance_rail(delta: float) -> void:
	var before_speed := speed
	var fraction := _boost_sweep(distance, distance + speed * delta, _support_side_before_step, lateral)
	var remaining := before_speed * delta * fraction + speed * delta * (1.0 - fraction)
	# Consume all continuous boundaries, never discard overshoot or teleport across gaps.
	for boundary in range(12):
		var available := maxf(0, route.length - distance)
		if remaining <= available:
			distance += remaining
			global_transform = route.pose_at(distance, lateral)
			_check_rail_support()
			return
		distance = route.length
		global_transform = route.pose_at(distance, lateral)
		remaining -= available
		if network.current.next.is_empty():
			if network.current.connections.is_empty(): return
			_launch(false)
			_step_air(remaining / maxf(speed, 1))
			return
		var next_id := network.current.next[0]
		if network.current.next.size() > 1:
			next_id = network.current.next[1] if target_lane < 0 else network.current.next[0]
		_enter(next_id, 0)
	_crash("INVALID CYCLIC CONNECTION")


func _enter(id: String, s: float) -> void:
	network.activate(id)
	distance = s
	support_kind = network.current.support
	_record("ENTER")
	segment_entered.emit(id)


func _at_finish() -> bool:
	return network.current.next.is_empty() and network.current.connections.is_empty() and distance >= route.length - 16


func _check_rail_support() -> void:
	if network.current.auto_launcher and launch_permitted() and not triggered.has(network.current.id + ":launcher"):
		_launch(true)
		return
	if absf(lateral) > network.current.half_width:
		_launch(false)


func switch_lane(direction: int) -> void:
	# A/D on a single rail prepares the aerial correction; cannot slide on empty space.
	if network.current.lanes().size() == 1: return
	super.switch_lane(direction)


func launch_permitted() -> bool:
	var segment := network.current
	return segment.launch_at(distance) and (segment.launcher_lane == 99 or absf(lateral - segment.launcher_lane * tuning.lane_spacing) < 1.7)


func _ground_input(delta: float) -> void:
	# Space has no free-flat impulse. Retain the existing short press buffer for a prop.
	var pending := jump_buffer
	if not launch_permitted(): jump_buffer = 0
	super._ground_input(delta)
	if not launch_permitted() and state != State.AIR: jump_buffer = pending


func _launch(intentional: bool) -> void:
	if intentional and not launch_permitted():
		jump_buffer = 0
		return
	super._launch(intentional)


func _apply_launch_assist(intentional: bool) -> void:
	active_jump = {}
	var tangent := -route.pose_at(distance).basis.z
	launch_speed = speed * Vector2(tangent.x, tangent.z).length()
	vertical_velocity = speed * tangent.y + (network.current.launch_impulse if intentional else 0.0)
	if intentional and network.current.launch_impulse > 0:
		triggered[network.current.id + ":launcher"] = true
		stunt_event.emit("POWER KICK", network.current.launch_impulse)
	air_source = network.current.id
	air_source_distance = distance
	legal_targets = []
	for connection in network.current.connections:
		if distance >= connection.from and distance <= connection.until:
			legal_targets.append(connection)
	for next_id in network.current.next:
		legal_targets.append({"target": next_id, "target_from": 0.0, "target_end": minf(350, network.segments[next_id].length), "min_speed": 0.0, "max_speed": 160.0})
	preferred_target = legal_targets[0].target if not network.current.connections.is_empty() and not legal_targets.is_empty() else air_source
	if network.current.choice == "timing" and (distance < network.current.length * 0.65 or speed < 85):
		preferred_target = "arc_low"
	support_kind = "none"
	edge_grace = 0.14 if not intentional else 0.0
	auto_roll = 1
	style_axis = 1 if preferred_target == air_source or legal_targets.size() < 2 else 2
	style_duration = 0.65
	style_progress = 0
	style_angle = 0
	_record("JUMP" if intentional else "EDGE")


func _step_air(delta: float) -> void:
	var before := global_position
	air_time += delta
	var axis := Input.get_axis("steer_left", "steer_right")
	if network.segments[air_source].choice == "rescue" and axis < -0.5:
		preferred_target = "rescue"
	if absf(axis) > 0.1:
		air_side_speed = clampf(air_side_speed + axis * tuning.air_acceleration * delta, -tuning.air_lateral_limit, tuning.air_lateral_limit)
	else:
		air_side_speed *= exp(-tuning.air_drag * delta)
	# Analytic vertical step removes the 60/120 Hz Euler fall bias.
	global_position += (air_forward * launch_speed + air_right * air_side_speed + Vector3.UP * (vertical_velocity - tuning.gravity * delta * 0.5)) * delta
	vertical_velocity -= tuning.gravity * delta
	global_basis = Basis(air_right, Vector3.UP, -air_forward)
	distance = route.closest_distance(global_position)
	lateral = route.pose_at(distance).basis.x.dot(global_position - route.pose_at(distance).origin)
	speed = launch_speed
	_step_trick(delta)
	var candidates: Array[Dictionary] = [{"target": air_source, "target_from": 0.0, "target_end": network.segments[air_source].length, "min_speed": 0.0, "max_speed": 160.0}]
	candidates.append_array(legal_targets)
	var best: Dictionary = {}
	for candidate in candidates:
		var hit := sweep_capture(before, global_position, candidate)
		if not hit.is_empty() and (best.is_empty() or hit.fraction < best.fraction): best = hit
	if not best.is_empty():
		_enter(best.target, best.s)
		_land(best.point, best.s)
		if state != State.CRASHED:
			support_kind = network.current.support
			_record("CAPTURE")
		return
	if air_time > 7 or global_position.y < network.segment_pose(air_source, air_source_distance).origin.y - 95:
		_crash("MISSED / " + last_rejection)


func sweep_capture(a: Vector3, b: Vector3, connection: Dictionary) -> Dictionary:
	var segment: RoadSegment = network.segments[connection.target]
	var sa := segment.curve.get_closest_offset(network.to_local(a))
	var sb := segment.curve.get_closest_offset(network.to_local(b))
	var pa := network.segment_pose(segment.id, sa)
	var pb := network.segment_pose(segment.id, sb)
	var ha := pa.basis.y.dot(a - pa.origin)
	var hb := pb.basis.y.dot(b - pb.origin)
	if ha <= 0 or hb > 0: return {}
	var fraction := ha / maxf(ha - hb, 0.000001)
	var point := a.lerp(b, fraction)
	var s := segment.curve.get_closest_offset(network.to_local(point))
	var pose := network.segment_pose(segment.id, s)
	var offset := pose.basis.x.dot(point - pose.origin)
	var longitudinal := absf(pose.basis.z.dot(point - pose.origin))
	if longitudinal > 0.8 or s < connection.target_from or s > connection.target_end:
		last_rejection = "OUTSIDE CAPTURE WINDOW"
		return {}
	var heading := rad_to_deg(acos(clampf(air_forward.dot(Vector3(-pose.basis.z.x, 0, -pose.basis.z.z).normalized()), -1, 1)))
	if heading > settings.heading_limit_degrees or speed < connection.min_speed or speed > connection.max_speed:
		last_rejection = "DIRECTION / SPEED"
		return {}
	var lane_error := INF
	for lane in segment.lanes(): lane_error = minf(lane_error, absf(offset - lane * tuning.lane_spacing))
	if absf(offset) > segment.half_width or lane_error > tuning.landing_capture_width:
		last_rejection = "LATERAL MISS / A-D TO CORRECT"
		return {}
	return {"target": segment.id, "s": s, "point": point, "fraction": fraction}


func _land(point: Vector3, s: float) -> void:
	super._land(point, s)
	# Independent grind identity; existing RECOVER/RAIL locomotion remains reusable.
	if state != State.CRASHED and network.current.support == "grind":
		target_lane = 0
		stunt_event.emit("GRIND", 0)


func landing_eta() -> float:
	if network == null or preferred_target.is_empty(): return super.landing_eta()
	var target_y := network.segment_pose(preferred_target, 20).origin.y
	var discriminant := vertical_velocity * vertical_velocity + 2 * tuning.gravity * (global_position.y - target_y)
	return maxf(0, (vertical_velocity + sqrt(maxf(0, discriminant))) / tuning.gravity)


func landing_target() -> Vector3:
	if preferred_target.is_empty(): return super.landing_target()
	var prediction := global_position + air_forward * launch_speed * landing_eta()
	var segment: RoadSegment = network.segments[preferred_target]
	var s := segment.curve.get_closest_offset(network.to_local(prediction))
	return network.segment_pose(preferred_target, s).origin


func landing_steering_error() -> float:
	var eta := landing_eta()
	var prediction := global_position + air_forward * launch_speed * eta + air_right * air_side_speed * (1 - exp(-tuning.air_drag * eta)) / tuning.air_drag
	return air_right.dot(landing_target() - prediction)

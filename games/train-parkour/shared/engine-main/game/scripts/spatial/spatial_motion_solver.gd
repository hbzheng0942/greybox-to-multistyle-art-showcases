class_name SpatialMotionSolver
extends RefCounted
## Sole integrator for the new lab. Legacy fields are outputs, never an alternate solver.
signal event(kind: String, payload: Dictionary)

const RAIL := 0
const DRIFT := 1
const AIR := 2
const RECOVER := 3
const CRASHED := 4
var route: SpatialRoute
var tuning: SpatialTuning
var phase := RAIL
var active := true
var finished := false
var mode := 2
var s := 24.0
var side := 0.0
var lane := 0
var lane_from := 0.0
var lane_elapsed := 0.24
var slip_speed := 0.0
var _side_velocity := 0.0
var slip := 0.0
var speed := 100.0
var world_velocity := Vector3.ZERO
var world_pose := Transform3D.IDENTITY
var clock := 0.0
var metres := 0.0
var peak_speed := 0.0
var braking := false
var drift_side := 0.0
var drift_quality := 0.0
var impact := 0.0
var pulse := 0.0
var jump_buffer := 0.0
var jump_cooldown := 0.0
var recovery_left := 0.0
var contact_cooldown := 0.0
var air_time := 0.0
var air_source := ""
var air_source_s := 0.0
var air_source_pose := Transform3D.IDENTITY
var air_source_impulse := Vector3.ZERO
var air_intentional := false
var air_candidates: Array[Dictionary] = []
var preferred_target := ""
var assist_engaged := false
var assist_disqualified := false
var wrong_direction_time := 0.0
var steering_used := 0.0 # Current deviation inside a 15-degree cone, NOT an invisible consumable.
var steering_reference_velocity := Vector3.ZERO
var steering_launch_velocity := Vector3.ZERO
var control_sign := 1.0
var pending_lane_command := 0
var pending_lane_time := 0.0
var crash_reason := ""
var triggered: Dictionary = {}
var cleared: Dictionary = {}
var history: Array[Dictionary] = []
var step_spans: Array[Dictionary] = []
var energy := {"traction_dv": 0.0, "brake_dv": 0.0, "grade_dv": 0.0, "device_dv": 0.0, "scrape_dv": 0.0, "landing_dv": 0.0, "cap_dv": 0.0}
var support_seconds: Dictionary = {}
var source_base_y := 0.0

func configure(new_route: SpatialRoute, new_tuning: SpatialTuning) -> void:
	route = new_route
	tuning = new_tuning
	reset(2)

func reset(pace: int = 2, emit_start := true) -> void:
	mode = pace
	route.activate(route.start_id)
	phase = RAIL
	active = true
	finished = false
	s = 24
	side = 0
	lane = 0
	lane_from = 0
	lane_elapsed = tuning.lane_seconds
	slip_speed = 0
	_side_velocity = 0
	slip = 0
	speed = tuning.cruise[mode]
	world_pose = route.pose_at(s)
	world_velocity = -world_pose.basis.z * speed
	clock = 0
	metres = 0
	peak_speed = speed
	braking = false
	drift_side = 0
	drift_quality = 0
	impact = 0
	pulse = 0
	jump_buffer = 0
	jump_cooldown = 0.18
	recovery_left = 0
	contact_cooldown = 0
	air_time = 0
	air_intentional = false
	assist_engaged = false
	assist_disqualified = false
	wrong_direction_time = 0
	steering_used = 0
	steering_reference_velocity = Vector3.ZERO
	steering_launch_velocity = Vector3.ZERO
	control_sign = 1
	pending_lane_command = 0
	pending_lane_time = 0
	crash_reason = ""
	preferred_target = ""
	triggered.clear()
	cleared.clear()
	history.clear()
	support_seconds.clear()
	step_spans.clear()
	energy = {"traction_dv": 0.0, "brake_dv": 0.0, "grade_dv": 0.0, "device_dv": 0.0, "scrape_dv": 0.0, "landing_dv": 0.0, "cap_dv": 0.0}
	if emit_start: _emit("START")

func _emit(kind: String, extra: Dictionary = {}) -> void:
	var row := {"kind": kind, "segment": route.current.id, "s": s, "side": side, "seconds": clock, "speed": speed, "metres": metres, "support": route.current.kind if phase != AIR else "none", "position": [world_pose.origin.x, world_pose.origin.y, world_pose.origin.z], "velocity": [world_velocity.x, world_velocity.y, world_velocity.z]}
	row.merge(extra, true)
	history.append(row)
	event.emit(kind, row)

func step(delta: float, input: Dictionary, camera_right: Vector3) -> void:
	var remaining := maxf(delta, 0)
	var controls := input.duplicate()
	# Bounded integration also makes stall frames consume every boundary/event.
	while active and remaining > 0.000001:
		var dt := minf(remaining, 1.0 / 120.0)
		_step_internal(dt, controls, camera_right)
		controls["jump"] = false
		controls["left"] = false
		controls["right"] = false
		remaining -= dt

func _step_internal(delta: float, input: Dictionary, camera_right: Vector3) -> void:
	if not active: return
	var before := world_pose.origin
	clock += delta
	jump_buffer = maxf(0, jump_buffer - delta)
	pending_lane_time = maxf(0, pending_lane_time - delta)
	if pending_lane_time == 0: pending_lane_command = 0
	jump_cooldown = maxf(0, jump_cooldown - delta)
	contact_cooldown = maxf(0, contact_cooldown - delta)
	impact = move_toward(impact, 0, delta * 5)
	pulse = move_toward(pulse, 0, delta * 2.5)
	step_spans.clear()
	if input.get("jump", false): jump_buffer = tuning.jump_buffer
	if phase == AIR:
		_step_air(delta, float(input.get("axis", 0)), camera_right)
	else:
		_step_supported(delta, input, camera_right)
	metres += world_pose.origin.distance_to(before)
	peak_speed = maxf(peak_speed, speed)
	if phase != AIR and phase != CRASHED:
		support_seconds[route.current.kind] = float(support_seconds.get(route.current.kind, 0)) + delta

func _step_supported(delta: float, input: Dictionary, camera_right: Vector3) -> void:
	var track := route.current
	var frame := route.pose_at(s)
	var projection := frame.basis.x.dot(camera_right)
	if absf(projection) > 0.20: control_sign = signf(projection)
	var axis: float = input.get("axis", 0.0)
	var local_axis := axis * control_sign
	var shift: bool = input.get("shift", false)
	var curvature := track.curvature(s)
	var curve_active := absf(curvature.x) > 0.0004 and speed * speed * absf(curvature.x) > 4.0
	var drifting := shift and absf(axis) > 0.5 and curve_active and not track.single_lane and absf(projection) > 0.20
	var stabilized_support := track.single_lane or track.kind in ["wall", "inverted", "loop", "grind", "clip"]
	var was_drifting := phase == DRIFT
	braking = shift and not drifting and not stabilized_support
	if drifting:
		phase = DRIFT
		drift_side = local_axis
		drift_quality = clampf(drift_quality + delta * (0.7 if signf(local_axis) == signf(curvature.x) else -1.5), 0, 1)
		if not was_drifting: _emit("DRIFT")
	else:
		if was_drifting:
			# Continue from the current contact, never snap the offset into an old lane tween.
			lane_from = side - slip
			lane_elapsed = 0
			_emit("CARVE EXIT", {"quality": drift_quality})
		drift_quality = 0
		if phase == RECOVER:
			recovery_left -= delta
			if recovery_left <= 0: phase = RAIL
		else: phase = RAIL
		if not shift and not track.single_lane:
			if input.get("left", false) or input.get("right", false):
				pending_lane_command = -1 if input.get("left", false) else 1
				pending_lane_time = tuning.jump_buffer
			# Near an edge-on view, do not turn screen-right into a remembered left.
			# Retain the short tap until the camera establishes a readable direction.
			if pending_lane_command != 0 and absf(projection) > 0.20:
				var command := pending_lane_command
				pending_lane_command = 0
				pending_lane_time = 0
				var target := clampi(lane + int(command * control_sign), -1, 1)
				if target != lane:
					lane_from = side - slip
					lane_elapsed = 0
					lane = target
					_emit("TRANSFER", {"screen_direction": command})
	var prior_speed := speed
	if braking:
		# A floor is not a target: this expression can NEVER increase speed.
		speed = minf(speed, maxf(tuning.brake_floor, speed - tuning.brake * delta))
		energy.brake_dv += speed - prior_speed
	else:
		speed = move_toward(speed, tuning.cruise[mode], (tuning.traction if speed < tuning.cruise[mode] else tuning.coast_drag) * delta)
		energy.traction_dv += speed - prior_speed
	var grade_dv := -frame.basis.z.y * -tuning.grade_gravity * delta
	speed += grade_dv
	energy.grade_dv += grade_dv
	energy.cap_dv -= maxf(0, speed - tuning.speed_cap)
	speed = clampf(speed, 0, tuning.speed_cap)
	var old_side := side
	var grip := tuning.drift_grip if drifting and signf(local_axis) == signf(curvature.x) else tuning.lateral_grip
	var excess := maxf(0, speed * speed * absf(curvature.x) - grip)
	if track.single_lane: excess = 0 # Positive clamp; no three-lane sliding on a wall/grind.
	slip_speed += -signf(curvature.x) * excess * delta
	slip_speed *= exp(-5 * delta)
	slip += slip_speed * delta
	if excess == 0: slip = move_toward(slip, 0, delta * 2.5)
	if drifting:
		side = lerpf(side, lane * tuning.lane_spacing + drift_side * 0.6 + slip, 1 - exp(-10 * delta))
	else:
		lane_elapsed = minf(lane_elapsed + delta, tuning.lane_seconds)
		var t := lane_elapsed / tuning.lane_seconds
		side = lerpf(lane_from, lane * tuning.lane_spacing, t * t * (3 - 2 * t)) + slip
	_side_velocity = (side - old_side) / delta
	world_velocity = -frame.basis.z * speed + frame.basis.x * _side_velocity
	if jump_buffer > 0 and jump_cooldown <= 0:
		var release_at := s if track.can_release(s) else INF
		for window in track.release_windows:
			if window.x >= s and window.x <= s + speed * minf(delta, jump_buffer): release_at = minf(release_at, window.x)
		if is_finite(release_at):
			var approach_time := (release_at - s) / maxf(speed, 1)
			if approach_time > 0:
				side = lerpf(old_side, side, approach_time / maxf(delta, 0.00001))
				_advance(release_at - s, old_side, approach_time)
			if not active: return
			_launch(true, axis)
			_step_air(maxf(0, delta - approach_time), axis, camera_right)
			return
	var old_speed := speed
	var fraction := _pads(s, s + speed * delta, old_side, side)
	_advance(old_speed * delta * fraction + speed * delta * (1 - fraction), old_side, delta)

func _pads(a: float, b: float, side_a: float, side_b: float) -> float:
	var earliest := 1.0
	for i in route.current.pads.size():
		var pad: Dictionary = route.current.pads[i]
		var key := route.current.id + ":pad:" + str(i)
		if triggered.has(key) or b < pad.a or a > pad.b: continue
		var lo := maxf(0, (pad.a - a) / maxf(b - a, 0.0001))
		var hi := minf(1, (pad.b - a) / maxf(b - a, 0.0001))
		var center: float = pad.lane * tuning.lane_spacing
		if absf(side_b - side_a) < 0.00001:
			if absf(side_a - center) > 1.8: continue
		else:
			var t1 := (center - 1.8 - side_a) / (side_b - side_a)
			var t2 := (center + 1.8 - side_a) / (side_b - side_a)
			lo = maxf(lo, minf(t1, t2))
			hi = minf(hi, maxf(t1, t2))
		if lo > hi: continue
		triggered[key] = true
		var gain := minf(tuning.pad_impulse, tuning.speed_cap - speed)
		speed += gain
		energy.device_dv += gain
		pulse = 1
		earliest = minf(earliest, lo)
		if route.experience_revision == 2:
			_emit("PULSE", {"delta_v": gain, "contact_s": lerpf(a, b, lo), "zone_id": str(pad.get("id", key))})
		else:
			_emit("PULSE", {"delta_v": gain, "contact_s": lerpf(a, b, lo)})
	return earliest

func _advance(remaining: float, old_side: float, delta: float) -> void:
	for boundary in 16:
		var track := route.current
		var available := maxf(0, track.length - s)
		var step_length := minf(remaining, available)
		var a := s
		var before := world_pose.origin
		s += step_length
		world_pose = route.pose_at(s, side)
		step_spans.append({"segment": track.id, "a": a, "b": s})
		_check_obstacles(track, a, s, before, world_pose.origin)
		if not active: return
		if absf(side) > track.width_at(s) - (1.35 if not track.single_lane else 0.0):
			if track.single_lane:
				world_velocity = -world_pose.basis.z * speed + world_pose.basis.x * slip_speed
				_launch(false, 0)
				return
			# This is actual contact with the rendered edge guard, not an authored turn tax.
			side = clampf(side, -track.width_at(s) + 1.35, track.width_at(s) - 1.35)
			world_pose = route.pose_at(s, side)
			slip_speed = 0
			if contact_cooldown <= 0:
				var loss := minf(12, speed * 0.10)
				speed -= loss
				energy.scrape_dv -= loss
				contact_cooldown = 0.5
				_emit("GUARD CONTACT", {"delta_v": -loss})
		remaining -= step_length
		world_velocity = -world_pose.basis.z * speed + world_pose.basis.x * _side_velocity
		if remaining <= 0.00001: return
		if track.next.is_empty():
			if track.connections.is_empty():
				finished = true
				active = false
				_emit("FINISH")
				return
			_launch(false, 0)
			_step_air(remaining / maxf(speed, 1), 0, world_pose.basis.x)
			return
		var next_id := track.next[0]
		var previous_point := world_pose.origin
		route.activate(next_id)
		s = 0
		var next_pose := route.pose_at(0)
		side = next_pose.basis.x.dot(previous_point - next_pose.origin)
		if route.current.single_lane: lane = 0
		lane_from = side
		lane_elapsed = 0
		slip = 0
		slip_speed = 0
		world_pose = route.pose_at(0, side)
		_emit("ENTER")
		# A newly entered segment has its own swept device domain.
		var prior := speed
		var time_left := remaining / maxf(prior, 0.0001)
		var fraction := _pads(0, remaining, side, side)
		remaining = prior * time_left * fraction + speed * time_left * (1 - fraction)
	crash("INVALID CONNECTION CYCLE")

func _check_obstacles(track: SpatialTrack, a: float, b: float, p0: Vector3, p1: Vector3) -> void:
	for i in track.obstacles.size():
		var ob: Dictionary = track.obstacles[i]
		var key := route.obstacle_key(track, ob)
		var at: float = ob.s - 6.0
		if cleared.has(key) or a > at or b < at: continue
		var f := clampf((at - a) / maxf(b - a, 0.00001), 0, 1)
		var point := p0.lerp(p1, f)
		var frame := route.track_pose(track.id, at)
		var offset := frame.basis.x.dot(point - frame.origin)
		var altitude := frame.basis.y.dot(point - frame.origin)
		var hit := false
		for l in ob.lanes:
			if absf(offset - l * tuning.lane_spacing) < 2.6:
				hit = hit or (altitude + 3.4 > float(ob.get("bottom", INF)) and altitude < float(ob.height) + 0.2 if ob.get("kind", "block") == "beam" else altitude < ob.height + 0.2 and altitude > -0.8)
		cleared[key] = true
		if hit:
			if ob.get("kind", "block") == "soft":
				_soft_contact(key, ob)
			else:
				crash("LOW BEAM" if ob.get("kind", "block") == "beam" else "BLOCK / PICK THE OPEN LINE")
			return
		_emit("CLEAR", {"obstacle_key": key, "obstacle_kind": ob.get("kind", "block"), "lanes": ob.lanes})

func _soft_contact(key: String, ob: Dictionary) -> void:
	cleared[key] = true
	var loss := 0.0
	var group: String = str(ob.get("group", ""))
	var group_key := "soft-group:" + group
	var already_penalized := not group.is_empty() and triggered.has(group_key)
	if contact_cooldown <= 0 and not already_penalized:
		loss = minf(float(ob.get("loss", tuning.soft_contact_loss)), speed * 0.08)
		speed = maxf(0, speed - loss)
		if phase == AIR and world_velocity.length_squared() > 0.01:
			world_velocity = world_velocity.normalized() * speed
		energy.scrape_dv -= loss
		contact_cooldown = 0.45
		if not group.is_empty(): triggered[group_key] = true
	_emit("SOFT CONTACT", {"delta_v": -loss, "group": ob.get("group", ""), "obstacle_key": key})

func _link_matches_intent(link: Dictionary, intentional: bool) -> bool:
	var intent: String = link.get("intent", "any")
	return intent == "any" or (intent == "intentional") == intentional

func _choose_preferred(axis: float) -> void:
	if air_candidates.is_empty():
		preferred_target = air_source
		return
	var wanted := signi(axis)
	var best_score := -INF
	var best := air_candidates[0]
	for link: Dictionary in air_candidates:
		var minimum: float = link.get("preferred_minimum_speed", link.get("minimum_speed", -INF))
		var maximum: float = link.get("preferred_maximum_speed", link.get("maximum_speed", INF))
		var direction: int = int(link.get("screen_direction", 0))
		if (speed < minimum or speed > maximum) and not (wanted != 0 and direction == wanted): continue
		var score := float(link.get("priority", 0))
		if wanted != 0:
			score += 100 if direction == wanted else (-40 if direction != 0 else 0)
		elif link.get("default", false):
			score += 20
		if score > best_score:
			best_score = score
			best = link
	preferred_target = best.target

func _launch(intentional: bool, axis: float) -> void:
	air_source = route.current.id
	air_source_s = s
	air_source_pose = world_pose
	air_intentional = intentional
	air_source_impulse = route.global_basis * route.current.impulse if intentional else Vector3.ZERO
	world_velocity += air_source_impulse
	if air_source_impulse.length() > 0.1: pulse = maxf(pulse, 0.65)
	world_pose.origin += world_pose.basis.y * 0.08
	source_base_y = world_pose.origin.y
	air_candidates.clear()
	for link: Dictionary in route.current.connections:
		if s >= link.from and s <= link.until and _link_matches_intent(link, intentional):
			air_candidates.append(link.duplicate())
	for id in route.current.next:
		air_candidates.append({"target": id, "a": 0.0, "b": minf(350, route.tracks[id].length), "minimum_speed": 15.0, "screen_direction": 0, "priority": -10, "assist": false})
	_choose_preferred(axis)
	air_time = 0
	assist_engaged = false
	assist_disqualified = false
	wrong_direction_time = 0
	steering_used = 0
	steering_reference_velocity = world_velocity
	steering_launch_velocity = world_velocity
	pending_lane_command = 0
	pending_lane_time = 0
	jump_buffer = 0
	jump_cooldown = 0.12
	phase = AIR
	braking = false
	drift_quality = 0
	_emit("TAKEOFF" if intentional else "EDGE", {"impulse": [air_source_impulse.x, air_source_impulse.y, air_source_impulse.z], "v": [world_velocity.x, world_velocity.y, world_velocity.z]})

func _step_air(delta: float, axis: float, camera_right: Vector3) -> void:
	if delta <= 0: return
	if absf(axis) > 0.5 and air_time < 0.8: _choose_preferred(axis)
	var choice := _preferred_link()
	var expected_direction: int = int(choice.get("screen_direction", 0))
	if expected_direction != 0 and absf(axis) > 0.5 and signi(axis) != expected_direction:
		wrong_direction_time += delta
		if wrong_direction_time >= 0.25: assist_disqualified = true
	elif absf(axis) > 0.5:
		wrong_direction_time = maxf(0, wrong_direction_time - delta * 0.5)
	var before := world_pose.origin
	var start_velocity := world_velocity
	var gravity := Vector3.DOWN * tuning.gravity
	# Reference is a constraint only; actual velocity is the sole integrated motion.
	if air_time == 0: steering_launch_velocity = start_velocity
	var reference_start := steering_launch_velocity + gravity * air_time
	var assist := _assist_state()
	var steering_axis := axis
	if not assist.is_empty() and absf(assist.error) <= tuning.assist_settle_error:
		steering_axis *= 0.2
	# Steering is an instantaneous rotation (zero work), followed by exact gravity drift.
	if absf(steering_axis) > 0.1:
		var direction := start_velocity.normalized()
		var lateral_axis := camera_right.slide(direction).normalized()
		if lateral_axis.length_squared() > 0.5:
			var amount := tuning.steering_rate * delta
			start_velocity = Quaternion(direction.cross(lateral_axis).normalized(), deg_to_rad(amount) * steering_axis) * start_velocity
	if not assist.is_empty():
		var frame: Transform3D = assist.frame
		var current_lateral := start_velocity.dot(frame.basis.x)
		var desired_lateral := clampf(-assist.error / maxf(assist.eta, 0.2), -18.0, 18.0)
		var next_lateral := move_toward(current_lateral, desired_lateral, tuning.assist_accel * delta)
		var magnitude := start_velocity.length()
		start_velocity += frame.basis.x * (next_lateral - current_lateral)
		if start_velocity.length_squared() > 0.001: start_velocity = start_velocity.normalized() * magnitude
		assist_engaged = true
		_emit_once("assist:" + air_source + ":" + preferred_target, "LANDING ASSIST", {"target": preferred_target, "eta": assist.eta, "lateral_error": assist.error, "source": air_source})
	start_velocity = _limit_steering_cone(start_velocity, reference_start)
	var after := before + start_velocity * delta + gravity * (0.5 * delta * delta)
	var end_velocity := start_velocity + gravity * delta
	var candidates: Array[Dictionary] = air_candidates.duplicate()
	candidates.append({"target": air_source, "a": maxf(0, air_source_s - 4), "b": minf(route.tracks[air_source].length, air_source_s + tuning.speed_cap * (air_time + delta) + 16), "minimum_speed": 15.0})
	var local_a := route.to_local(before)
	var local_b := route.to_local(after)
	var swept_bounds := AABB(local_a, Vector3.ZERO).expand(local_b).grow(7)
	var best: Dictionary = {}
	var clears_to_commit: Array[Dictionary] = []
	var softs_to_commit: Array[Dictionary] = []
	# An assisted mouth is still a finite plane event. Resolve the analytically
	# predicted crossing when it falls inside this substep so sampled nearest-point
	# changes on a curved receiver cannot skip a valid contact by one frame.
	if not assist.is_empty() and assist.eta <= delta:
		var link := _preferred_link()
		var prediction: Dictionary = assist.prediction
		var frame: Transform3D = route.track_pose(preferred_target, prediction.s)
		var hit_velocity: Vector3 = start_velocity + gravity * float(assist.eta)
		var planar: Vector3 = hit_velocity.slide(frame.basis.y)
		var offset: float = frame.basis.x.dot(prediction.point - frame.origin)
		var error: float = absf(offset)
		var heading: float = rad_to_deg(planar.normalized().angle_to(-frame.basis.z))
		var closing: float = -hit_velocity.dot(frame.basis.y)
		var target_track: SpatialTrack = route.tracks[preferred_target]
		var width := float(link.get("capture_width", target_track.width_at(prediction.s)))
		var forward_speed: float = planar.dot(-frame.basis.z)
		var legal_window: bool = prediction.s >= float(link.get("a", 0)) and prediction.s <= float(link.get("b", target_track.length))
		var legal_speed: bool = forward_speed >= float(link.get("minimum_speed", 15)) and forward_speed <= float(link.get("maximum_speed", INF))
		if legal_window and legal_speed and error <= width and heading <= float(link.get("capture_heading", tuning.capture_heading)) and closing >= 0 and closing <= tuning.capture_normal_speed:
			var best_lane := 0
			var lane_error := INF
			for candidate_lane in target_track.lanes():
				var candidate_error := absf(offset - candidate_lane * tuning.lane_spacing)
				if candidate_error < lane_error:
					lane_error = candidate_error
					best_lane = candidate_lane
			best = {"target": preferred_target, "s": prediction.s, "point": prediction.point, "side": offset, "lane": best_lane, "fraction": assist.eta / delta, "forward_speed": forward_speed, "incoming_speed": hit_velocity.length(), "closing": closing, "heading": heading, "error": lane_error, "assisted": true}
	# Capture topology is NOT the collision domain. Unlinked solids still obstruct.
	for track: SpatialTrack in route.tracks.values():
		var padding := maxf(track.half_width + 1, 16 if track.kind == "wall" or track.enclosure == "tunnel" else 6)
		if not track.bounds.grow(padding).intersects(swept_bounds): continue
		# A powered departure must clear its own support before it can land on it.
		# Keep the support's obstacles and structure active during this short window.
		var source_clearance := air_intentional and track.id == air_source and air_time < 0.25 and air_source_s < track.length - 2.0 and start_velocity.dot(air_source_pose.basis.y) > 1.0
		var hit: Dictionary = {}
		if not source_clearance:
			var full := {"target": track.id, "a": 0.0, "b": track.length, "minimum_speed": 0.0, "capture_width": track.width_at(track.nearest(route.to_local(after)))}
			hit = sweep_contact(before, after, end_velocity, full)
		if not hit.is_empty():
			if not hit.get("blocked", false):
				var legal := false
				for link in candidates:
					var capture_width := float(link.get("capture_width", track.width_at(hit.s) if link.get("assist", false) else tuning.capture_lane_width))
					if link.target == track.id and hit.s >= link.a and hit.s <= link.b and hit.forward_speed >= float(link.get("minimum_speed", 15)) and hit.forward_speed <= float(link.get("maximum_speed", INF)) and hit.error <= capture_width:
						legal = true
						hit.assisted = link.get("assist", false) and assist_engaged
						break
				if not legal: hit = {"blocked": true, "fraction": hit.fraction, "reason": "SOLID TRACK / OUTSIDE LEGAL CAPTURE", "physical_track": track.id, "contact_s": hit.s}
			if best.is_empty() or hit.fraction < best.fraction: best = hit
		var structural := _structural_hit(track, before, after)
		if not structural.is_empty() and (best.is_empty() or structural.fraction < best.fraction): best = structural
		for ob_hit in _obstacle_queries(track, before, after):
			if ob_hit.blocked:
				if best.is_empty() or ob_hit.fraction < best.fraction: best = ob_hit
			else:
				clears_to_commit.append(ob_hit)
	for solid in route.camera_solids:
		if not solid.get("actor_block", false) or not (solid.bounds as AABB).intersects(swept_bounds): continue
		var inverse: Transform3D = solid.inverse
		var half: Vector3 = solid.half
		var fraction := _box_fraction(inverse * local_a, inverse * local_b, AABB(-half, half * 2))
		if is_finite(fraction) and (best.is_empty() or fraction < best.fraction): best = {"blocked": true, "fraction": fraction, "reason": "CANYON CONTACT / MISSED THE CLEAR GAP"}
	var fraction: float = best.get("fraction", 1.0)
	# No event after the earliest physical transition is allowed to contaminate state.
	for clear in clears_to_commit:
		if clear.fraction <= fraction and not cleared.has(clear.key):
			if clear.get("soft", false):
				cleared[clear.key] = true
				softs_to_commit.append(clear)
			else:
				cleared[clear.key] = true
				_emit("CLEAR", {"obstacle_segment": clear.segment, "obstacle_key": clear.key, "obstacle_kind": clear.obstacle.get("kind", "block"), "lanes": clear.obstacle.lanes})
	var used := delta * fraction
	world_pose.origin = before.lerp(after, fraction)
	steering_reference_velocity = steering_launch_velocity + gravity * (air_time + used)
	world_velocity = _limit_steering_cone(start_velocity + gravity * used, steering_reference_velocity)
	steering_used = rad_to_deg(world_velocity.angle_to(_cone_reference(steering_reference_velocity)))
	air_time += used
	speed = world_velocity.length()
	for soft in softs_to_commit: _soft_contact(soft.key, soft.obstacle)
	var preferred_link := _preferred_link()
	if not preferred_link.is_empty() and preferred_link.has("fallback_target"):
		var plane := route.track_pose(preferred_target, maxf(10, float(preferred_link.get("a", 0))))
		if (world_pose.origin - plane.origin).dot(plane.basis.y) < -0.2:
			preferred_target = preferred_link.fallback_target
			_emit_once("rescue_offer", "RESCUE WINDOW")
	var target_basis := route.track_pose(preferred_target, 0).basis if route.tracks.has(preferred_target) else Basis.IDENTITY
	var forward := world_velocity.normalized()
	var source_q := air_source_pose.basis.get_rotation_quaternion()
	var target_q := target_basis.get_rotation_quaternion()
	var orient_blend := smoothstep(0, 0.45, air_time)
	if air_source_pose.basis.y.y < -0.9:
		# Drop clear of the ceiling before turning the whole 3.4m body upright.
		# A time-only turn could rotate the body/camera focus back through the deck.
		var separation := (world_pose.origin - air_source_pose.origin).dot(air_source_pose.basis.y)
		orient_blend = smoothstep(4, 8, separation)
	var up := Basis(source_q.slerp(target_q, orient_blend)).y
	if up.slide(forward).length_squared() < 0.001: up = air_source_pose.basis.x.cross(forward)
	var right := forward.cross(up).normalized()
	world_pose.basis = Basis(right, right.cross(forward).normalized(), -forward)
	if not best.is_empty():
		if best.get("blocked", false):
			_emit("CONTACT REJECTED", best)
			crash(best.get("reason", "TRACK BACK FACE / INVALID CONTACT"))
			return
		_capture(best)
		_side_velocity = 0
		var remaining := delta - used
		if remaining > 0.000001: _advance(speed * remaining, side, remaining)
		return
	var imminent := false
	var next_contact := predict()
	if not next_contact.is_empty() and next_contact.eta < 0.8:
		var next_track: SpatialTrack = route.tracks[preferred_target]
		var next_frame := route.track_pose(preferred_target, next_contact.s)
		var next_error := absf(next_frame.basis.x.dot(next_contact.point - next_frame.origin))
		imminent = next_error <= next_track.width_at(next_contact.s)
	var assisted_route: bool = not _preferred_link().is_empty() and _preferred_link().get("assist", false)
	if air_time > 0.35 and not assisted_route and not imminent and not air_candidates.is_empty() and _all_target_heights_unreachable():
		crash("MISSED COIL / NO UPWARD POWER" if air_source == "wall" else "MISSED LAST CATCH / CORRECT EARLIER")
	elif air_time > 6.0 or world_pose.origin.y < source_base_y - 100:
		crash("MISSED CONTACT / AIM AT A LEGAL RAIL")

func _cone_reference(reference: Vector3) -> Vector3:
	# Exactly at a vertical ballistic apex there is no direction. Use the outgoing
	# gravity direction for that instant, without ever rebasing on steered momentum.
	if reference.length_squared() > 0.00000001: return reference.normalized()
	return Vector3.DOWN if tuning.gravity > 0 else Vector3.FORWARD

func _preferred_link() -> Dictionary:
	for link: Dictionary in air_candidates:
		if link.target == preferred_target: return link
	return {}

func _assist_state() -> Dictionary:
	if assist_disqualified or tuning.assist_time <= 0 or tuning.assist_accel <= 0: return {}
	var link := _preferred_link()
	if link.is_empty() or not link.get("assist", false): return {}
	var prediction := predict(preferred_target)
	var assist_time: float = minf(float(link.get("assist_time", tuning.assist_time)), tuning.assist_time)
	var assist_error: float = minf(float(link.get("assist_max_error", tuning.assist_max_error)), tuning.assist_max_error)
	if prediction.is_empty() or prediction.eta > assist_time or prediction.longitudinal_error > 6.0: return {}
	var frame := route.track_pose(preferred_target, prediction.s)
	var error := frame.basis.x.dot(prediction.point - frame.origin)
	if absf(error) > assist_error: return {}
	if route.experience_revision == 2 and absf(error) <= 0.6 and prediction.longitudinal_error <= 0.8:
		var arriving := world_velocity + Vector3.DOWN * tuning.gravity * float(prediction.eta)
		var planar := arriving.slide(frame.basis.y)
		if planar.length_squared() > 0.1 and rad_to_deg(planar.normalized().angle_to(-frame.basis.z)) <= 8.0:
			return {} # A naturally precise entry must remain player-owned.
	return {"eta": prediction.eta, "error": error, "frame": frame, "prediction": prediction}

func _limit_steering_cone(value: Vector3, reference: Vector3) -> Vector3:
	if value.length_squared() < 0.00000001: return value
	var a := _cone_reference(reference)
	var b := value.normalized()
	var angle := acos(clampf(a.dot(b), -1, 1))
	var limit := deg_to_rad(tuning.steering_limit)
	if angle <= limit: return value
	var tangent := b.slide(a)
	if tangent.length_squared() < 0.00000001:
		tangent = (Vector3.RIGHT if absf(a.x) < 0.9 else Vector3.FORWARD).slide(a)
	return (a * cos(limit) + tangent.normalized() * sin(limit)).normalized() * value.length()

func _all_target_heights_unreachable() -> bool:
	# Conservative cone bound: grants the remaining steering angle instantly.
	# Failing even this generous bound means no last-second correction can save a flat catch.
	var reference := steering_reference_velocity if steering_reference_velocity.length_squared() > 0.001 else world_velocity
	var horizontal := Vector2(reference.x, reference.z).length()
	var max_pitch := minf(PI * 0.5, atan2(reference.y, horizontal) + deg_to_rad(tuning.steering_limit))
	var best_up_speed := maxf(0, world_velocity.length() * sin(max_pitch))
	var highest := world_pose.origin.y + best_up_speed * best_up_speed / maxf(2 * tuning.gravity, 0.0001)
	for link in air_candidates:
		var pose := route.track_pose(link.target, link.a)
		if absf(pose.basis.y.y) < 0.98: return false
		if pose.basis.y.y < 0:
			if highest >= pose.origin.y: return false
		elif world_pose.origin.y >= pose.origin.y - 0.3 or highest >= pose.origin.y:
			return false
	return true

func _obstacle_queries(track: SpatialTrack, a: Vector3, b: Vector3) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i in track.obstacles.size():
		var key := route.obstacle_key(track, track.obstacles[i])
		if cleared.has(key): continue
		var ob: Dictionary = track.obstacles[i]
		var pose := route.track_pose(track.id, ob.s)
		var forward := -pose.basis.z
		var travel := (b - a).dot(forward)
		if absf(travel) < 0.00001: continue
		var sign := signf(travel)
		var face := pose.origin - forward * (6.0 * sign)
		var da := (a - face).dot(forward) * sign
		var db := (b - face).dot(forward) * sign
		if da > 0 or db < 0: continue
		var f := clampf(-da / maxf(db - da, 0.00001), 0, 1)
		var point := a.lerp(b, f)
		var offset := pose.basis.x.dot(point - pose.origin)
		var altitude := pose.basis.y.dot(point - pose.origin)
		if absf(offset) > track.width_at(track.nearest(route.to_local(point))) + 2.6: continue
		var hit := false
		for lane_index in ob.lanes:
			if absf(offset - lane_index * tuning.lane_spacing) < 2.6:
				hit = hit or (altitude + 3.4 > float(ob.get("bottom", INF)) and altitude < float(ob.height) + 0.2 if ob.get("kind", "block") == "beam" else altitude < ob.height + 0.2 and altitude + 3.4 > 0)
		var soft: bool = hit and ob.get("kind", "block") == "soft"
		results.append({"blocked": hit and not soft, "soft": soft, "obstacle": ob, "fraction": f, "key": key, "segment": track.id, "reason": "LOW BEAM" if ob.get("kind", "block") == "beam" else "BLOCK / PICK THE OPEN LINE"})
	return results

func _box_fraction(a: Vector3, b: Vector3, box: AABB) -> float:
	var lo := 0.0
	var hi := 1.0
	var d := b - a
	for axis in 3:
		if absf(d[axis]) < 0.00001:
			if a[axis] < box.position[axis] or a[axis] > box.end[axis]: return INF
		else:
			var u := (box.position[axis] - a[axis]) / d[axis]
			var v := (box.end[axis] - a[axis]) / d[axis]
			lo = maxf(lo, minf(u, v))
			hi = minf(hi, maxf(u, v))
			if lo > hi: return INF
	return lo

func _structural_hit(track: SpatialTrack, a: Vector3, b: Vector3) -> Dictionary:
	if track.kind != "wall" and track.enclosure != "tunnel": return {}
	# A curved tunnel must use the local support frame at the swept contact;
	# a single box fixed at its entrance diverges from the visible wall.
	var at := 0.0 if track.kind == "wall" else track.nearest(route.to_local((a + b) * 0.5))
	var frame := route.track_pose(track.id, at)
	var inverse := frame.affine_inverse()
	var ca := inverse * a
	var cb := inverse * b
	var boxes: Array[AABB] = []
	if track.kind == "wall":
		boxes.append(AABB(Vector3(-15, -1.5, -track.length), Vector3(30, 1, track.length)))
	else:
		var width := track.enclosure_half_width
		var span := maxf(6.0, a.distance_to(b) * 2.0 + 2.0)
		boxes.append(AABB(Vector3(-width - 0.1, -0.5, -span), Vector3(1.2, 14, span * 2)))
		boxes.append(AABB(Vector3(width - 1.1, -0.5, -span), Vector3(1.2, 14, span * 2)))
		boxes.append(AABB(Vector3(-width, track.ceiling - 4.5, -span), Vector3(width * 2, 1, span * 2)))
		boxes.append(AABB(Vector3(-width, -1.4, -span), Vector3(width * 2, 1, span * 2)))
	var earliest := INF
	for box in boxes: earliest = minf(earliest, _box_fraction(ca, cb, box))
	return {"blocked": true, "fraction": earliest, "reason": "TUNNEL / WALL STRUCTURE"} if is_finite(earliest) else {}

func _emit_once(key: String, kind: String, extra: Dictionary = {}) -> void:
	if triggered.has(key): return
	triggered[key] = true
	_emit(kind, extra)

func sweep_contact(a: Vector3, b: Vector3, velocity_at_contact: Vector3, link: Dictionary) -> Dictionary:
	var track: SpatialTrack = route.tracks[link.target]
	var sa := track.nearest(route.to_local(a), link.a, link.b)
	var sb := track.nearest(route.to_local(b), link.a, link.b)
	var pa := route.track_pose(track.id, sa)
	var pb := route.track_pose(track.id, sb)
	var ha := (a - pa.origin).dot(pa.basis.y)
	var hb := (b - pb.origin).dot(pb.basis.y)
	var front := ha > 0 and hb <= 0
	var back := ha < -0.6 and hb >= -0.6
	if not front and not back: return {}
	var fraction := clampf((ha + (0.6 if back else 0.0)) / (ha - hb), 0, 1)
	var point := a.lerp(b, fraction)
	var at := track.nearest(route.to_local(point), link.a, link.b)
	var pose := route.track_pose(track.id, at)
	var offset := pose.basis.x.dot(point - pose.origin)
	var long_error := absf(pose.basis.z.dot(point - pose.origin))
	if long_error > 0.65 or absf(offset) > track.width_at(at): return {}
	if back: return {"blocked": true, "fraction": fraction}
	var planar := velocity_at_contact.slide(pose.basis.y)
	var forward_speed := planar.dot(-pose.basis.z)
	var alignment := rad_to_deg(acos(clampf(planar.normalized().dot(-pose.basis.z), -1, 1)))
	var closing := -velocity_at_contact.dot(pose.basis.y)
	var error := INF
	var best_lane := 0
	for l in track.lanes():
		var e := absf(offset - l * tuning.lane_spacing)
		if e < error: error = e; best_lane = l
	var allowed_error := float(link.get("capture_width", tuning.capture_lane_width))
	if forward_speed < float(link.get("minimum_speed", 15)) or alignment > float(link.get("capture_heading", tuning.capture_heading)) or closing < 0 or closing > tuning.capture_normal_speed or error > allowed_error:
		return {"blocked": true, "fraction": fraction}
	return {"target": track.id, "s": at, "point": point, "side": offset, "lane": best_lane, "fraction": fraction, "forward_speed": forward_speed, "incoming_speed": velocity_at_contact.length(), "closing": closing, "heading": alignment, "error": error}

func _capture(hit: Dictionary) -> void:
	route.activate(hit.target)
	s = hit.s
	side = hit.side
	lane = hit.lane
	lane_from = side
	lane_elapsed = 0
	slip = 0
	slip_speed = 0
	var assisted: bool = hit.get("assisted", false)
	var rough: bool = (not assisted and hit.error > minf(1.1, route.current.half_width * 0.8)) or hit.heading > (24 if assisted else 16)
	var before := speed
	var retention := tuning.rough_capture_retention if rough else (tuning.assisted_capture_retention if assisted else tuning.clean_capture_retention)
	var incoming_speed: float = hit.get("incoming_speed", hit.forward_speed)
	var retained_speed := incoming_speed * retention
	energy.cap_dv -= maxf(0, retained_speed - tuning.speed_cap)
	speed = minf(tuning.speed_cap, retained_speed)
	energy.landing_dv += retained_speed - before
	phase = RECOVER
	recovery_left = 0.0
	jump_cooldown = 0.12
	impact = clampf(hit.closing / 35.0, 0.3, 1.0)
	world_pose = route.pose_at(s, side)
	world_velocity = -world_pose.basis.z * speed
	preferred_target = ""
	var capture_data := {"normal_speed": hit.closing, "heading": hit.heading, "lateral_error": hit.error, "rough": rough, "assisted": assisted, "retention": retention}
	if route.experience_revision == 2:
		capture_data.merge({"zone_id": "capture:" + route.current.id, "source": air_source, "target": route.current.id, "release_s": air_source_s, "capture_s": s, "incoming_speed": incoming_speed, "retained_speed": speed})
	_emit("CAPTURE", capture_data)

func predict(id: String = "", trial_velocity := Vector3.INF, trial_position := Vector3.INF) -> Dictionary:
	if id.is_empty(): id = preferred_target
	if id.is_empty() or not route.tracks.has(id): return {}
	var track: SpatialTrack = route.tracks[id]
	var predicted_velocity := world_velocity if not trial_velocity.is_finite() else trial_velocity
	var predicted_position := world_pose.origin if not trial_position.is_finite() else trial_position
	var pose := route.track_pose(id, 20)
	var eta := -1.0
	var point := predicted_position
	for iteration in 3:
		var h := (predicted_position - pose.origin).dot(pose.basis.y)
		var v := predicted_velocity.dot(pose.basis.y)
		var g := Vector3.DOWN.dot(pose.basis.y) * tuning.gravity
		var candidates: Array[float] = []
		if absf(g) < 0.0001:
			if v < -0.0001: candidates.append(-h / v)
		else:
			var disc := v * v - 2 * g * h
			if disc < 0: return {}
			candidates.append((-v - sqrt(disc)) / g)
			candidates.append((-v + sqrt(disc)) / g)
		eta = INF
		for t in candidates:
			if t > 0.005 and t < 6 and v + g * t < 0: eta = minf(eta, t)
		if not is_finite(eta): return {}
		point = predicted_position + predicted_velocity * eta + Vector3.DOWN * tuning.gravity * eta * eta * 0.5
		pose = route.track_pose(id, track.nearest(route.to_local(point)))
	return {"eta": eta, "point": point, "target": pose.origin, "s": track.nearest(route.to_local(point)), "id": id, "longitudinal_error": absf(pose.basis.z.dot(point - pose.origin))}

func crash(reason: String) -> void:
	phase = CRASHED
	active = false
	crash_reason = reason
	_emit("CRASH", {"reason": reason})

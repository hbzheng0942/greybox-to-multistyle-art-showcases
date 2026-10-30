extends "res://tests/behavior/stunt_driver.gd"
## Real key events only. Reads motion to choose a strategy; never writes movement state.
var high_route := false
var safe_rollout := false
var rescue := false
var rescue_control := 0 # 0 correct, 1 none, 2 wrong; identical initial miss.
var omit_wall := false
var relaxed_precision := false
var natural_grind := false
var input_log: Array[Dictionary] = []
var observation: Dictionary = {}

func tick(train: TrainController) -> void:
	var p := train as SpatialTrain
	var m := p.motion
	var track := p.spatial.current
	observation = {"seconds": m.clock, "segment": track.id, "s": m.s}
	var air := m.phase == SpatialMotionSolver.AIR
	var direction := 0
	var jump := false
	var shift := false
	if air:
		var prediction := m.predict("rescue") if rescue and p.spatial.full_course and m.air_source == "cliff_lip" else m.predict()
		if not prediction.is_empty():
			var target: Vector3 = prediction.target
			if rescue and not p.spatial.full_course and m.air_source == "cliff_lip" and m.preferred_target == "upper":
				target -= p.spatial.track_pose("upper", prediction.s).basis.x * 6.8
			var camera := p.get_viewport().get_camera_3d()
			var error := camera.global_basis.x.dot(target - prediction.point)
			if absf(error) > 0.38: direction = 1 if error > 0 else -1
			if p.spatial.experience_revision == 2 and m.air_source == "cliff_lip" and not rescue and m.air_time < 0.8:
				direction = 0 # Early opposite input deliberately chooses the lower rescue.
			if rescue and m.air_source == "cliff_lip":
				if p.spatial.full_course:
					if rescue_control == 1: direction = 0
					elif rescue_control == 2: direction = -direction if direction != 0 else 1
				elif m.preferred_target == "rescue":
					if rescue_control == 1: direction = 0
					elif rescue_control == 2: direction = 1
			if relaxed_precision and p.spatial.experience_revision == 2 and m.air_source != "cliff_lip" and absf(error) < 1.8:
				direction = 0
	else:
		var desired_lane := 1 if track.id == "rush" and m.s < 158 else 0
		if track.id == "drop" or (track.id == "loop_entry" and m.s < 74): desired_lane = 1
		var hazard_imminent := false
		for ob in track.obstacles:
			if ob.s > m.s and ob.s - m.s < m.speed * 2.6:
				hazard_imminent = true
				var best := INF
				for candidate in [-1, 0, 1]:
					if not ob.lanes.has(candidate) and absf(candidate - m.lane) < best:
						best = absf(candidate - m.lane)
						desired_lane = candidate
				break
		if track.id == "rush" and m.s < 154: desired_lane = 1
		var camera := p.get_viewport().get_camera_3d()
		var screen_sign := signf(camera.global_basis.x.dot(m.world_pose.basis.x))
		if absf(screen_sign) < 0.1: screen_sign = m.control_sign
		if not track.single_lane and m.lane_elapsed >= m.tuning.lane_seconds:
			direction = signi(desired_lane - m.lane) * int(screen_sign)
			if held.get(KEY_A if direction < 0 else KEY_D, false): direction = 0
		var curvature := track.curvature(m.s)
		if p.spatial.experience_revision == 2 and track.id == "landmark_return" and m.s < 925.0 and absf(curvature.x) > 0.0004 and m.speed * m.speed * absf(curvature.x) > 4:
			shift = true
		var carve_exit_margin := 95.0 if p.spatial.experience_revision == 2 and track.id == "carve" else maxf(25, m.speed * 0.24)
		if not hazard_imminent and not track.single_lane and absf(curvature.x) > 0.0004 and m.speed * m.speed * absf(curvature.x) > 4 and track.length - m.s > carve_exit_margin:
			shift = true
			direction = int(signf(curvature.x) * screen_sign)
		if track.id == "wall" and not omit_wall:
			jump = track.length - m.s <= clampf(m.speed * 0.50 - 22, 4, 38)
		elif track.id == "inverted" and not safe_rollout:
			var release_margin := 25 if p.spatial.experience_revision == 2 and m.speed > 165 and (p.get_viewport().get_camera_3d() as SpatialCamera).comfort else (30 if p.spatial.experience_revision == 2 and m.speed > 165 else 35)
			jump = track.length - m.s < release_margin
		elif track.id == "exit_ramp" and high_route:
			jump = m.s > 8
			if jump: direction = -1 # Visible SPACE + A high-line choice.
		elif track.id == "grind" and not natural_grind: jump = track.length - m.s < minf(48, m.speed * 1.61 - 22)
		elif track.id == "upper": jump = track.length - m.s < clampf((m.speed + 12) * (78.0 / 24.0) - 320 - 8, 5, 30)
	set_key(KEY_SHIFT, shift)
	set_key(KEY_A, direction < 0)
	set_key(KEY_D, direction > 0)
	set_key(KEY_SPACE, jump)

func set_key(code: Key, pressed: bool) -> void:
	if held.get(code, false) != pressed:
		var record := observation.duplicate()
		record.key = int(code)
		record.pressed = pressed
		input_log.append(record)
	super.set_key(code, pressed)

func longest_idle(end_time: float) -> float:
	var keys: Dictionary = {}
	var idle_from := 0.0
	var maximum := 0.0
	for row in input_log:
		if not row.key in [KEY_A, KEY_D, KEY_SHIFT, KEY_SPACE]: continue
		var was_idle := not keys.values().has(true)
		keys[row.key] = row.pressed
		var idle := not keys.values().has(true)
		var at: float = row.get("seconds", 0.0)
		if was_idle and not idle: maximum = maxf(maximum, at - idle_from)
		if not was_idle and idle: idle_from = at
	if not keys.values().has(true): maximum = maxf(maximum, end_time - idle_from)
	return maximum

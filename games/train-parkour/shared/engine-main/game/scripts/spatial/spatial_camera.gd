class_name SpatialCamera
extends RailCamera
## Physical support roll, never the TrickPivot. Every phase has a deliberate composition.
@export var station_art_camera := false
var player: SpatialTrain
var previous_mode := ""
var rendered_control_right := Vector3.RIGHT
var intent: Dictionary = {}
var last_focus := Vector3.ZERO
var max_physics_step_degrees := 0.0
var largest_step_context: Dictionary = {}

func configure(target: TrainController, new_route: RailRoute, new_tuning: MotionTuning) -> void:
	train = target
	player = target as SpatialTrain
	route = new_route
	tuning = new_tuning
	reset_camera()

func _update_pose(delta: float, snap: bool) -> void:
	if player == null: return
	var motion := player.motion
	var track := player.spatial.current
	var frame := motion.world_pose
	if not snap:
		var travelled := frame.origin - last_focus
		global_position += travelled
		aim += travelled
	last_focus = frame.origin
	var forward := -frame.basis.z
	var up := frame.basis.y
	var right := frame.basis.x
	var phase_name := "flight" if motion.phase == SpatialMotionSolver.AIR else track.camera_phase
	camera_mode = phase_name.to_upper()
	var full := player.spatial.full_course
	# The opening station and canyon need the actual hub bridge silhouette in
	# view; the remaining chapters retain the shorter depth range.
	far = 4400.0 if full and (track.chapter.begins_with("01") or track.chapter.begins_with("02")) else 1800.0
	var distance_back := 18.0 if full else 12.0
	var height := 7.5 if full else 3.8
	var side_offset := 0.0
	var look_ahead := 38.0 if full else 24.0
	if phase_name == "carve":
		distance_back = 18 if full else 14
		height = 7.0 if full else 4.4
		side_offset = -signf(track.curvature(motion.s).x) * 5.0 + (motion.side * 0.4 if full else 0.0)
	elif phase_name in ["grind", "wall", "inverted", "rescue"]:
		distance_back = 17 if full else 13
		height = 6.5 if full else 4.5
		side_offset = -7.0 if phase_name != "rescue" else 6.0
		if phase_name == "grind": side_offset = 5.0 if full else 8.0
		if phase_name == "inverted": side_offset = 14.0
	elif phase_name == "loop":
		distance_back = 13
		height = 5.0
		look_ahead = 16
	elif phase_name == "crest":
		distance_back = 18 if full else 15
		height = 7.5 if full else 5.0
		look_ahead = 38 if full else 26
	elif phase_name == "tunnel":
		distance_back = 18.0
		height = 7.5
		look_ahead = 68
	elif phase_name == "landing":
		distance_back = 18 if full else 12
		height = 6.5 if full else 3.3
	elif phase_name == "flight":
		distance_back = 21
		height = 12
		side_offset = -4.0
		look_ahead = 20
		if motion.air_source == "cliff_lip": height = 18; side_offset = -7
		elif motion.air_source in ["wall", "inverted"]: height = 6; distance_back = 16; side_offset = 14
		elif motion.air_source == "grind": side_offset = 8
	if full and player.spatial.experience_revision == 2:
		if phase_name == "rush": height = 5.8; distance_back = 17.0; look_ahead = 34.0
		elif phase_name == "carve": height = 6.2; distance_back = 17.0
		elif phase_name == "landing": height = 6.2
	if full and phase_name == "rush": side_offset = motion.side * 0.65
	var desired := frame.origin - forward * distance_back + up * height + right * side_offset
	var target := frame.origin + forward * look_ahead + up * 1.5
	if motion.phase != SpatialMotionSolver.AIR:
		var curvature := track.curvature(motion.s).length()
		var along := minf(look_ahead, 0.50 / maxf(curvature, 0.001))
		target = route.pose_at(motion.s + along, motion.side * 0.25).origin + up * 1.3
		if full and player.spatial.experience_revision == 2 and track.id == "inverted":
			# Reveal the lower rail before SPACE is pressed. The old inverted
			# camera stared along the ceiling until the train had already left it.
			var lower_mouth: Vector3 = route.track_pose("drop", 52.0).origin + Vector3.UP * 3.0
			var lower_blend := smoothstep(0.0, 1.0, clampf((motion.s - 70.0) / 60.0, 0.0, 1.0)) * 0.68
			target = target.lerp(lower_mouth, lower_blend)
	else:
		# Aim near enough to expose the fall, not always at a tiny distant vanishing point.
		var goal := motion.predict()
		if not goal.is_empty():
			if full and player.spatial.experience_revision == 2 and motion.air_source in ["wall", "inverted", "grind"]:
				# These flights can finish before the old 0.6 s delay. Sight the
				# actual receiver from takeoff so the action has a visible destination.
				var catch_frame: Transform3D = route.track_pose(goal.id, goal.s)
				target = target.lerp(goal.target + catch_frame.basis.y * 4.0, 0.78)
			elif motion.air_time > 0.6:
				var adjustment: Vector3 = goal.target - target
				target += adjustment.limit_length(28) * 0.35
	if comfort:
		var world_up := Vector3.UP
		var flat_forward := Vector3(forward.x, 0, forward.z)
		if flat_forward.length_squared() < 0.05:
			flat_forward = -player.spatial.global_basis.z
		flat_forward = flat_forward.normalized()
		var stable_side := flat_forward.cross(world_up)
		# Position stays on the train's side of the support, even when upside down.
		# World-up is an orientation choice, not permission to look through a deck.
		desired = frame.origin - forward * 19 + frame.basis.y * 8 + stable_side * 14
		# A loop has two nearby limbs. Move to its outside BEFORE the ordinary
		# arm reaches the return deck; reactive candidate switching teleports
		# across that deck. The loop's entrance side also stays defined at the
		# vertical tangent, where projecting forward onto the ground flips sign.
		var loop_view := _comfort_loop_view(track, motion.s)
		if not loop_view.is_empty():
			var outside: Vector3 = loop_view.right
			var loop_desired := frame.origin - forward * 19 + frame.basis.y * 8 - outside * 18
			desired = desired.lerp(loop_desired, float(loop_view.blend))
		up = world_up
		if (target - desired).normalized().cross(up).length_squared() < 0.02: up = frame.basis.x
	# Optional art-scene profile: ordinary station architecture uses a level horizon.
	# The short canyon fade preserves the previous stunt/loop camera contract.
	var station_weight:=0.0
	if station_art_camera:
		if track.id.begins_with("station_") or (motion.phase==SpatialMotionSolver.AIR and motion.air_source.begins_with("station_")):station_weight=1.0
		elif track.id in ["canyon_safe","canyon_fast"]:station_weight=1.0-smoothstep(0.0,140.0,motion.s)
		var level_weight:=1.0 if track.id=="station_start" else 0.0
		if track.id=="station_carve":level_weight=1.0-smoothstep(track.length-100.0,track.length-20.0,motion.s)
		# Air steering is camera-relative: restore the original roll before takeoff.
		up=up.slerp(Vector3.UP,level_weight)
	var tunnel_blend := 1.0 if track.enclosure == "tunnel" else 0.0
	if tunnel_blend == 0 and motion.phase != SpatialMotionSolver.AIR and not track.next.is_empty():
		var next_track: SpatialTrack = player.spatial.tracks[track.next[0]]
		if next_track.enclosure == "tunnel":
			tunnel_blend = smoothstep(0, 1, clampf(1.0 - (track.length - motion.s) / maxf(motion.speed, 1), 0, 1))
	if tunnel_blend > 0 and motion.phase != SpatialMotionSolver.AIR:
		var anchor := route.pose_at(motion.s - distance_back)
		var ceiling := track.ceiling if track.enclosure == "tunnel" else (player.spatial.tracks[track.next[0]] as SpatialTrack).ceiling
		var tunnel_desired := anchor.origin + anchor.basis.y * minf(7.5, ceiling - 4.2) + anchor.basis.x * motion.side * (0.8 if full else 0.25)
		desired = desired.lerp(tunnel_desired, tunnel_blend)
		target = target.lerp(route.pose_at(motion.s + 68).origin + anchor.basis.y * 0.8, tunnel_blend)
	var response := 1.0 if snap else 1 - exp(-14 * delta)
	var body: MeshInstance3D = player.get_node("VisualRoot/TrickPivot/Geometry/Body")
	var focus := body.global_position
	desired = _clear_view(focus, desired, frame)
	global_position = desired if snap else global_position.lerp(desired, response)
	global_position = _clear_view(focus, global_position, frame)
	aim = target if snap else aim.lerp(target, response)
	var looking := aim - global_position
	if looking.length_squared() < 0.01: looking = forward
	if looking.normalized().cross(up).length_squared() < 0.0001: up = right.cross(looking).normalized()
	var wanted := Basis.looking_at(looking, up).get_rotation_quaternion()
	var before_rotation := global_basis.get_rotation_quaternion()
	var rotation := wanted if snap else before_rotation.slerp(wanted, 1 - exp(-18 * delta))
	if not snap:
		var angle := before_rotation.angle_to(rotation)
		var allowed := deg_to_rad(600) * delta
		if angle > allowed: rotation = before_rotation.slerp(rotation, allowed / angle)
		var equivalent_step := rad_to_deg(before_rotation.angle_to(rotation)) / maxf(delta * 60, 0.0001)
		if equivalent_step > max_physics_step_degrees:
			max_physics_step_degrees = equivalent_step
			largest_step_context = {"seconds": motion.clock, "phase": phase_name, "degrees_per_60hz_step": equivalent_step}
	else:
		max_physics_step_degrees = 0
		largest_step_context = {}
	global_basis = Basis(rotation)
	rendered_control_right = global_basis.x
	var v := motion.world_velocity.length()
	var target_fov := 82.0
	if v <= 100: target_fov = lerpf(70, 82, clampf((v - 28) / 72, 0, 1))
	elif v <= 130: target_fov = lerpf(82, 90, (v - 100) / 30)
	else: target_fov = lerpf(90, 94, clampf((v - 130) / 20, 0, 1))
	if comfort: target_fov = 78
	else: target_fov += motion.pulse * 3
	target_fov=lerpf(target_fov,68.0,station_weight)
	fov = target_fov if snap else lerpf(fov, target_fov, 1 - exp(-12 * delta))
	intent = {"phase": phase_name, "target": target, "support_up": frame.basis.y, "comfort": comfort, "expected_roll": not comfort and track.kind in ["wall", "inverted", "loop", "clip"]}

func _comfort_loop_view(track: SpatialTrack, s: float) -> Dictionary:
	var candidate := track
	var distance := -s
	for i in 3:
		if candidate.kind == "loop":
			var entrance: Transform3D = route.track_pose(candidate.id, 0.0)
			return {"right": entrance.basis.x, "blend": 1.0 if i == 0 else 1.0 - smoothstep(80.0, 200.0, distance)}
		distance += candidate.length
		if candidate.next.is_empty(): break
		candidate = player.spatial.tracks[candidate.next[0]]
	# Release the established side gradually after leaving a loop.
	for previous: SpatialTrack in player.spatial.tracks.values():
		if previous.kind == "loop" and track.id in previous.next:
			return {"right": route.track_pose(previous.id, 0.0).basis.x, "blend": 1.0 - smoothstep(0.0, track.length, s)}
	return {}


func solid_fraction(from: Vector3, to: Vector3, padding := 0.35) -> float:
	var a := player.spatial.to_local(from)
	var b := player.spatial.to_local(to)
	var query := AABB(a, Vector3.ZERO).expand(b).grow(padding)
	var nearest := 1.0
	for solid in player.spatial.solids_near(query):
		if not (solid.bounds as AABB).grow(padding).intersects(query): continue
		var inverse: Transform3D = solid.inverse
		var half: Vector3 = solid.half + Vector3.ONE * padding
		var hit := player.motion._box_fraction(inverse * a, inverse * b, AABB(-half, half * 2))
		# Zero is a real start-inside hit, not "no collision".
		if hit >= 0 and hit < nearest: nearest = hit
	return nearest

func sight_clear(point: Vector3) -> bool:
	return solid_fraction(global_position, point, 0.05) > 0.995

func body_clearance(point: Vector3) -> bool:
	var body: MeshInstance3D = player.get_node("VisualRoot/TrickPivot/Geometry/Body")
	return point.distance_to(body.global_position) >= 9.0 and not body.get_aabb().grow(0.65).has_point(body.to_local(point))

func _clear_view(focus: Vector3, wanted: Vector3, frame: Transform3D) -> Vector3:
	if body_clearance(wanted) and solid_fraction(focus, wanted) >= 0.999: return wanted
	var candidates: Array[Vector3] = []
	var forward := -frame.basis.z
	var right := frame.basis.x
	var up := frame.basis.y
	for side in [1.0, -1.0]:
		for height in [5.0, 10.0]:
			candidates.append(focus - forward * 17 + right * side * 16 + up * height)
			candidates.append(focus - forward * 21 + right * side * 23 + up * height)
	# A short unobstructed arm is acceptable only outside the whole car + near plane.
	var hit := solid_fraction(focus, wanted)
	var shortened := focus.lerp(wanted, maxf(0, hit - 0.04))
	if body_clearance(shortened): candidates.append(shortened)
	var best := wanted
	var best_cost := INF
	for candidate in candidates:
		if not body_clearance(candidate) or solid_fraction(focus, candidate) < 0.999: continue
		var cost := candidate.distance_squared_to(wanted) + candidate.distance_squared_to(global_position) * 0.6
		if cost < best_cost: best = candidate; best_cost = cost
	if not is_finite(best_cost) and not body_clearance(best):
		var away := (wanted - focus).normalized()
		if away.length_squared() < 0.5: away = frame.basis.z
		best = focus + away * 9.5
	return best

func decision_target() -> Dictionary:
	var m := player.motion
	if m.phase == SpatialMotionSolver.AIR: return m.predict()
	var track := player.spatial.current
	if track.connections.is_empty() or track.length - m.s > m.speed * 1.4: return {}
	var target_id: String = track.connections[0].target
	return m.predict(target_id, m.world_velocity + player.spatial.global_basis * track.impulse, m.world_pose.origin + m.world_pose.basis.y * 0.08)

func target_sight_point(prediction: Dictionary) -> Vector3:
	var id: String = prediction.id
	# Sight the landing-mouth gantry above rail furniture; the receiver bed can
	# otherwise hide a point placed at wheel height during the final approach.
	return prediction.target + player.spatial.track_pose(id, prediction.s).basis.y * (5.5 if player.spatial.full_course else 1.4)

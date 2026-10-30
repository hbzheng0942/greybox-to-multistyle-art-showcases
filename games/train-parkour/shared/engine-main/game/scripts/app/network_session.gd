class_name NetworkSession
extends LabSession

var recoveries := 0
var recovery_left := 0.0
var checkpoint: Dictionary = {}
var resolved: Dictionary = {}
var event_log: Array[Dictionary] = []
var branches: Array[String] = []
var clears := 0
var last_segment := ""


func restart_run() -> void:
	resolved.clear()
	event_log.clear()
	branches.clear()
	checkpoint.clear()
	recoveries = 0
	recovery_left = 0
	clears = 0
	super.restart_run()
	last_segment = ""
	_save_checkpoint()


func _ready() -> void:
	super._ready()
	_save_checkpoint()


func _save_checkpoint() -> void:
	var player := train as NetworkTrain
	checkpoint = {"segment": player.network.current.id, "s": player.network.current.checkpoint_s, "lane": 0, "speed": minf(train.speed, train.tuning.speed_presets[train.speed_mode] * 0.88), "score": stunt_score, "combo": combo, "resolved": resolved.duplicate(), "branches": branches.duplicate(), "clears": clears, "flow": train.flow, "boost_time": 0.0, "boost_amount": 0.0, "triggered": player.triggered.duplicate()}


func _restore() -> void:
	var player := train as NetworkTrain
	var clock := train.elapsed
	var travel := player.metres
	var old_history := player.history.duplicate()
	var peak := player.peak_speed
	var grade := player.grade_delta_v
	var boost := player.boost_delta_v
	train.reset_run()
	player.network.activate(checkpoint.segment)
	train.distance = checkpoint.s
	train.speed = checkpoint.speed
	train.target_lane = checkpoint.lane
	train.lateral = checkpoint.lane * train.tuning.lane_spacing
	train.lane_from = train.lateral
	train.elapsed = clock
	train.flow = checkpoint.flow
	train.boost_time = checkpoint.boost_time
	train.boost_amount = checkpoint.boost_amount
	player.triggered = checkpoint.triggered.duplicate()
	player.metres = travel
	player.history.assign(old_history)
	player.peak_speed = peak
	player.grade_delta_v = grade
	player.boost_delta_v = boost
	player.support_kind = player.network.current.support
	train.global_transform = train.route.pose_at(train.distance, train.lateral)
	train.reset_physics_interpolation()
	resolved = checkpoint.resolved.duplicate()
	branches.assign(checkpoint.branches)
	clears = checkpoint.clears
	stunt_score = checkpoint.score
	combo = checkpoint.combo
	failed = false
	camera.reset_camera()
	sound.reset_feedback()
	feedback = "CHECKPOINT / READ THE NEXT CONNECTION"
	feedback_time = 1.2
	player._record("CHECKPOINT")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if get_tree().paused: return
	if recovery_left > 0:
		recovery_left -= delta
		train.elapsed += delta
		if recovery_left <= 0: _restore()


func _on_advanced(previous: float, current: float, old_side: float, side: float) -> void:
	var player := train as NetworkTrain
	if not train.active: return
	var segment := player.network.current
	if last_segment != segment.id:
		last_segment = segment.id
		previous = train.route.closest_distance(player.previous_world)
		branches.append(segment.id)
	var surface := train.route.pose_at(train.distance)
	if surface.basis.y.dot(train.global_position - surface.origin) + 3.4 > segment.ceiling:
		train._crash("TUNNEL ROOF / STAY ON THE RAIL")
		return
	# Captured rail must first stabilize. Checkpoint keeps actual segment and lane.
	if segment.checkpoint and train.state != TrainController.State.AIR and current >= segment.checkpoint_s and current < segment.length - 20 and checkpoint.get("segment", "") != segment.id:
		_save_checkpoint()
	for i in segment.obstacles.size():
		var obstacle: Dictionary = segment.obstacles[i]
		var key := segment.id + ":" + str(i)
		var trigger: float = obstacle.s - 6
		if resolved.has(key) or current < trigger or previous > trigger: continue
		var t := clampf((trigger - previous) / maxf(current - previous, 0.00001), 0, 1)
		var lateral_at := lerpf(old_side, side, t)
		var point := player.previous_world.lerp(train.global_position, t)
		var pose := train.route.pose_at(trigger)
		var altitude := pose.basis.y.dot(point - pose.origin)
		var collision := false
		for lane in obstacle.lanes:
			if absf(lateral_at - lane * train.tuning.lane_spacing) < 2.55:
				collision = collision or (altitude + 3.4 > obstacle.bottom if obstacle.get("kind", "block") == "beam" else altitude < obstacle.height + 0.2)
		resolved[key] = true
		if collision:
			train._crash("LOW BEAM / STAY ON RAIL" if obstacle.get("kind", "block") == "beam" else "BARRIER / CHANGE RAIL OR HOP GOLD")
			return
		clears += 1
		stunt_score += 100
		combo += 1
		best_combo = maxi(best_combo, combo)
		train.stunt_event.emit("CLEAR", 100)


func _on_stunt_event(kind: String, value: float) -> void:
	var player := train as NetworkTrain
	event_log.append({"kind": kind, "segment": player.network.current.id, "s": train.distance, "seconds": train.elapsed, "speed": train.speed, "reason": train.crash_reason})
	if kind == "CRASH":
		recoveries += 1
		recovery_left = player.settings.checkpoint_seconds
	if kind == "GRIND": feedback = "GRIND / SPACE TO LEAVE - A/D IN AIR"
	super._on_stunt_event(kind, value)
	if kind == "BOOST IMPULSE": feedback = "+%d M/S / READ THE EXIT" % int(value)


func next_task() -> String:
	var player := train as NetworkTrain
	var segment := player.network.current
	if train.state == TrainController.State.AIR:
		var error := train.landing_steering_error()
		return "D / AIM RIGHT" if error > 0.65 else ("A / AIM LEFT" if error < -0.65 else "ON COURSE / RELEASE A-D")
	if segment.auto_launcher and train.distance < segment.launch_end:
		return "CENTRE KICKER + LOW BEAM / A-D TO BYPASS"
	for obstacle in segment.obstacles:
		if obstacle.s > train.distance and obstacle.s - train.distance < train.speed * 2.8:
			if obstacle.get("kind", "block") == "beam": return "LOW BEAM / STAY LOW - DO NOT JUMP"
			if obstacle.height < 2: return "LOW BLOCK / TAKE OPEN RAIL - NO FLAT JUMP"
			var safe := ""
			for lane in [-1, 0, 1]:
				if not obstacle.lanes.has(lane): safe += "LEFT " if lane == -1 else ("RIGHT " if lane == 1 else "CENTRE ")
			return "OPEN: " + safe
	if not segment.turns.is_empty():
		var turn := segment.turns[0]
		if train.distance > turn.start - train.speed * 2.5 and train.distance < turn.end:
			return "SHIFT + D / CARVE RIGHT" if turn.direction > 0 else "SHIFT + A / CARVE LEFT"
	if segment.id == "arc":
		if train.distance < 160: return "VIOLET AHEAD: EARLY LOW EXIT / GOLD LATER: HIGH EXIT"
		if train.distance < 200: return "VIOLET KICKER / SPACE + A: LOW - OR WAIT FOR GOLD"
		if train.distance < segment.length - 65: return "WAIT FOR GOLD / HIGH EXIT"
		return "SPACE NOW / HIGH EXIT"
	return segment.title

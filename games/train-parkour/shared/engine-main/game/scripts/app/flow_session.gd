class_name FlowSession
extends LabSession

var resolved: Dictionary = {}
var recoveries := 0
var recovery_left := 0.0
var checkpoint := 24.0
var checkpoint_lane := 0
var checkpoint_score := 0
var decisions := 0
var obstacle_clears := 0
var branch := ""
var event_log: Array[Dictionary] = []


func restart_run() -> void:
	resolved.clear()
	recoveries = 0
	recovery_left = 0
	checkpoint = 24
	checkpoint_lane = 0
	checkpoint_score = 0
	decisions = 0
	obstacle_clears = 0
	branch = ""
	event_log.clear()
	super.restart_run()
	feedback = "READ THE ROAD"


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if get_tree().paused or recovery_left <= 0:
		return
	recovery_left -= delta
	train.elapsed += delta
	if recovery_left <= 0:
		failed = false
		stunt_score = checkpoint_score
		(train as FlowTrain).resume_at(checkpoint, checkpoint_lane)
		for key in resolved.keys():
			if float(resolved[key]) >= checkpoint:
				resolved.erase(key)
		camera.reset_camera()
		feedback = "BACK IN MOTION"
		feedback_time = 0.6
		feedback_positive = true


func _on_advanced(previous: float, current: float, previous_lateral: float, current_lateral: float) -> void:
	if not train.active:
		return
	var course := (lab.route as FlowRoute).course
	# Nose sweep plus height interpolation prevents tunnelling at every pace.
	for i in course.obstacles.size():
		var obstacle: Dictionary = course.obstacles[i]
		var key := "obstacle_%d" % i
		var trigger: float = obstacle.s - 6.0
		if resolved.has(key) or current < trigger or previous > trigger:
			continue
		var t := clampf((trigger - previous) / maxf(current - previous, 0.00001), 0, 1)
		var side := lerpf(previous_lateral, current_lateral, t)
		var point := (train as FlowTrain).previous_world.lerp(train.global_position, t)
		var altitude: float = point.y - lab.route.pose_at(trigger).origin.y
		var collision := false
		for lane in obstacle.lanes:
			collision = collision or (absf(side - lane * TUNING.lane_spacing) < 2.55 and altitude < obstacle.height + 0.2)
		resolved[key] = obstacle.s
		if collision:
			train._crash("BARRIER HIT / PICK AN OPEN RAIL")
			return
		obstacle_clears += 1
		decisions += 1
		train.flow += 1
		combo += 1
		best_combo = maxi(combo, best_combo)
		stunt_score += 100
		feedback = "HOP CLEAR" if altitude > 2.0 else "CLEAN TRANSFER"
		feedback_time = 0.55
		feedback_positive = true
		train.stunt_event.emit("CLEAR", 100)
	if current >= course.fork_start + 15 and current < course.fork_end and not resolved.has("branch"):
		if train.state != TrainController.State.AIR:
			resolved.branch = course.fork_start
			branch = "FAST RIGHT" if train.target_lane == 1 else "WIDE LEFT"
			decisions += 1
			if train.target_lane == 1:
				train.boost_amount = 19
				train.boost_time = 2.0
				train.speed += 9.0
				stunt_score += 150
			train.stunt_event.emit(branch, 0)
	for cp in course.checkpoints:
		if cp > checkpoint and current >= cp and train.state != TrainController.State.AIR:
			checkpoint = cp
			checkpoint_lane = train.target_lane
			checkpoint_score = stunt_score


func _on_stunt_event(kind: String, value: float) -> void:
	event_log.append({"kind": kind, "distance": train.distance, "time": train.elapsed, "value": value})
	if event_log.size() > 800:
		event_log.pop_front()
	if kind == "CRASH":
		recoveries += 1
		recovery_left = 0.65
		failed = true
		combo = 0
		feedback = train.crash_reason
		feedback_positive = false
		feedback_time = 0.65
		sound.play_stunt(kind)
		return
	if kind == "TRANSFER":
		sound.play_stunt(kind)
		return
	if kind == "CLEAR":
		sound.play_stunt(kind)
		return
	if kind == "WALL SCRAPE":
		combo = 0
		feedback = "SCRAPING / SHIFT + TURN OR BRAKE"
		feedback_time = 0.65
		feedback_positive = false
		sound.play_stunt(kind)
		return
	if kind == "DRIFT BOOST" or kind in ["PERFECT LANDING", "LANDED", "ROUGH LANDING"]:
		decisions += 1
	super._on_stunt_event(kind, value)


func next_task() -> Dictionary:
	var course := (lab.route as FlowRoute).course
	var s := train.distance
	if train.state != TrainController.State.AIR and lab.route.lanes_at(s).size() == 1:
		return {"distance": 0.0, "kind": "capture", "label": "HOLD RIGHT / TRANSFER WHEN TRACK OPENS", "lanes": [1]}
	var best := {"distance": INF, "kind": "finish", "label": "CARRY THE SPEED", "lanes": [-1, 0, 1]}
	for i in course.obstacles.size():
		var obstacle: Dictionary = course.obstacles[i]
		if obstacle.s > s and not resolved.has("obstacle_%d" % i) and obstacle.s - s < best.distance:
			var safe: Array = []
			for lane in [-1, 0, 1]:
				if not obstacle.lanes.has(lane): safe.append(lane)
			best = {"distance": obstacle.s - s, "kind": "barrier", "label": "SPACE / HOP  OR  TAKE OPEN RAIL" if obstacle.height < 2 else "A / D  /  TAKE OPEN RAIL", "lanes": safe}
	for turn in course.turns:
		if s < turn.end and maxf(0, turn.start - s) < best.distance:
			best = {"distance": maxf(0, turn.start - s), "kind": "turn", "label": "SHIFT + D / CARVE RIGHT" if turn.direction > 0 else "SHIFT + A / CARVE LEFT", "lanes": [-1, 0, 1]}
	for jump in course.jumps:
		if s < jump.start and maxf(0, jump.start - jump.window - s) < best.distance:
			best = {"distance": maxf(0, jump.start - jump.window - s), "kind": "jump", "label": "SPACE / JUMP NOW" if s >= jump.start - jump.window else "GOLD STRIP / PREPARE TO JUMP", "lanes": [-1, 0, 1]}
	if not resolved.has("branch") and s < course.fork_end and maxf(0, course.fork_start - s) < best.distance:
		best = {"distance": maxf(0, course.fork_start - s), "kind": "fork", "label": "LEFT: WIDE   /   RIGHT: NARROW + BOOST", "lanes": [-1, 1]}
	return best

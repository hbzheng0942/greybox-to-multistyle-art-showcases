extends "res://scripts/ui/lab_hud.gd"


func _draw() -> void:
	if session == null: return
	var flow_session := session as FlowSession
	var train := session.train as FlowTrain
	var width := size.x
	var height := size.y
	var middle := width * 0.5
	var paused := get_tree().paused
	draw_rect(Rect2(0, 0, width, 112), Color(0.018, 0.04, 0.058, 0.87))
	_text(Vector2(34, 44), "FLOW / 03", 26, CYAN)
	_text(Vector2(34, 80), train.route.section_at(train.distance), 18, WHITE)
	_text(Vector2(width - 265, 64), "%03d" % int(train.speed * 3.6), 58, WHITE)
	_text(Vector2(width - 103, 64), "KM/H", 18, CYAN)
	_text(Vector2(width - 261, 91), "PACE %d / %.2f S" % [train.speed_mode + 1, train.elapsed], 17, MUTED)
	_center(Vector2(middle, 46), "STYLE %04d     CHAIN x%d" % [session.stunt_score, session.combo], 24, GOLD)
	_center(Vector2(middle, 79), "%02d ROAD ACTIONS   /   %d RECOVERIES" % [flow_session.decisions, flow_session.recoveries], 17, WHITE)
	draw_rect(Rect2(width * 0.3, 95, width * 0.4, 3), MUTED * Color(1, 1, 1, 0.3))
	draw_rect(Rect2(width * 0.3, 95, width * 0.4 * train.distance / train.route.length, 3), CYAN)
	if train.active and not paused:
		var task := flow_session.next_task()
		var label: String = task.label
		var color := GOLD if task.kind in ["turn", "jump"] else WHITE
		if train.state == TrainController.State.AIR:
			label = "A / D / AIM RIGHT" if train.landing_steering_error() > 0.8 else ("A / D / AIM LEFT" if train.landing_steering_error() < -0.8 else "ON COURSE / RELEASE A + D")
			_center(Vector2(middle, 188), "LAND %.1f S  /  KEEP YOUR LANDING LINE" % train.landing_eta(), 19, CYAN)
			var target := train.landing_target() + Vector3.UP
			if not session.camera.is_position_behind(target):
				var screen := session.camera.unproject_position(target) * size / session.camera.get_viewport().get_visible_rect().size
				if screen.y > 245 and screen.y < height - 150 and screen.x > 30 and screen.x < width - 30:
					draw_arc(screen, 19, 0, TAU, 28, CYAN, 2, true)
		elif train.state == TrainController.State.DRIFT:
			label = "CARVE / %d%%  -  RELEASE SHIFT AT EXIT" % int(train.drift_charge * 100)
			draw_rect(Rect2(middle - 160, 174, 320, 6), Color(0.05, 0.12, 0.17, 0.8))
			draw_rect(Rect2(middle - 160, 174, 320 * train.drift_charge, 6), GOLD)
		elif task.kind == "barrier" and task.distance < train.speed * 2.8:
			for lane in [-1, 0, 1]:
				var safe: bool = task.lanes.has(lane)
				var at := Vector2(middle + lane * 52, 190)
				draw_rect(Rect2(at - Vector2(17, 12), Vector2(34, 8)), CYAN if safe else Color(1, 0.23, 0.17))
			_center(Vector2(middle, 221), "OPEN RAILS / %.1f S" % (task.distance / maxf(train.speed, 1)), 17, MUTED)
		if task.distance < train.speed * 2.8 or train.state in [TrainController.State.AIR, TrainController.State.DRIFT]:
			_center(Vector2(middle, 154), label, 25, color)
		if session.feedback_time > 0:
			_center(Vector2(middle, height * 0.79), session.feedback, 31, CYAN if session.feedback_positive else GOLD)
		if not session.camera.comfort:
			_speed_edges(train)
	draw_rect(Rect2(0, height - 66, width, 66), Color(0.018, 0.04, 0.058, 0.86))
	_center(Vector2(middle, height - 39), "A / D  TRANSFER    SHIFT + A / D  DRIFT    SPACE  JUMP    R  RETRY", 19, WHITE)
	_center(Vector2(middle, height - 13), "ESC PAUSE    1 / 2 / 3 PACE    V COMFORT: %s    M SOUND: %s" % ["ON" if session.camera.comfort else "OFF", "OFF" if session.sound.muted else "ON"], 15, MUTED)
	if flow_session.recovery_left > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.03, 0.02, 0.28))
		_center(Vector2(middle, height * 0.4), session.feedback, 32, GOLD)
		_center(Vector2(middle, height * 0.46), "REJOINING CHECKPOINT...", 22, WHITE)
	if paused or session.finished:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.02, 0.033, 0.86))
		if session.waiting_for_start:
			_center(Vector2(middle, height * 0.27), "MAKE EVERY METRE COUNT", 55, CYAN)
			_center(Vector2(middle, height * 0.39), "RED BLOCKS: CHANGE RAIL.  LOW GOLD BLOCKS: JUMP OR DODGE.", 24, WHITE)
			_center(Vector2(middle, height * 0.47), "SHIFT + TURN: DRIFT.  RELEASE AT THE EXIT TO BOOST.", 24, WHITE)
			_center(Vector2(middle, height * 0.55), "GOLD STRIP: SPACE TO FLY.  A / D TO AIM.  TRICKS FOLLOW YOUR MOVES.", 24, WHITE)
			_center(Vector2(middle, height * 0.66), "SPACE / START", 34, GOLD)
			_center(Vector2(middle, height * 0.75), "STARTS AT PACE 3  /  1 + 2 FOR PRACTICE  /  R RESTARTS", 19, MUTED)
		elif session.finished:
			_center(Vector2(middle, height * 0.36), "FLOW COMPLETE", 58, CYAN)
			_center(Vector2(middle, height * 0.47), "%.2f S    STYLE %d    BEST CHAIN x%d" % [train.elapsed, session.stunt_score, session.best_combo], 28, WHITE)
			_center(Vector2(middle, height * 0.55), "%d RECOVERIES / %s" % [flow_session.recoveries, flow_session.branch], 24, GOLD)
			_center(Vector2(middle, height * 0.69), "R / AGAIN     1 / 2 / 3 / PACE", 27, WHITE)
		else:
			_center(Vector2(middle, height * 0.42), "PAUSED", 58, CYAN)
			_center(Vector2(middle, height * 0.62), "ESC / RESUME    R / RESTART", 28, WHITE)


func _speed_edges(train: FlowTrain) -> void:
	var strength := clampf(train.boost_time, 0, 1) * 0.27 + train.landing_impact * 0.3
	if strength <= 0.01: return
	for i in range(14):
		var phase := fmod(train.elapsed * 2.0 + i * 0.37, 1.0)
		var y := size.y * (0.22 + i / 14.0 * 0.6)
		for side in [-1, 1]:
			var edge := Vector2(size.x * 0.5 + side * size.x * (0.40 + phase * 0.12), y)
			draw_line(edge, edge + Vector2(side * (35 + phase * 95), (y - size.y * 0.5) * 0.1), Color(0.55, 0.98, 1.0, strength * (1.0 - phase)), 2.0, true)

extends "res://scripts/ui/lab_hud.gd"

func _draw() -> void:
	if session == null: return
	var run := session as SpatialSession
	var player := run.train as SpatialTrain
	var m := player.motion
	var mastery_standard := run.speed_mastery() and player.speed_mode == 2
	var debug_hud := "--debug-hud" in OS.get_cmdline_user_args()
	var middle := size.x * 0.5
	draw_rect(Rect2(0, 0, size.x, 86), Color(0.018, 0.03, 0.045, 0.80))
	_text(Vector2(28, 38), player.spatial.course_name, 21, CYAN)
	_text(Vector2(28, 65), "%s  /  %s" % [m.route.current.chapter, "AIR" if m.phase == SpatialMotionSolver.AIR else m.route.current.kind.to_upper()], 16, WHITE)
	_center(Vector2(middle, 35), "%.2f S   /   %d PTS" % [m.clock, run.stunt_score], 22, WHITE)
	_center(Vector2(middle, 64), "COMBO %d   /   RECOVERY %d" % [run.combo, run.recoveries], 17, CYAN)
	_text(Vector2(size.x - 245, 59), "%03d" % int(m.speed * 3.6), 50, WHITE)
	_text(Vector2(size.x - 104, 58), "KM/H", 17, CYAN)
	if not get_tree().paused and m.active:
		var cue: Dictionary = run.player_hint_state()
		_center(Vector2(middle, 126), str(cue.message), 25, GOLD)
		if not mastery_standard: _center(Vector2(middle, 158), run.player_action_text(cue), 18, CYAN)
		var decision := {} if mastery_standard else (run.camera as SpatialCamera).decision_target()
		if not decision.is_empty():
			var target := (run.camera as SpatialCamera).target_sight_point(decision)
			if not run.camera.is_position_behind(target):
				var point := run.camera.unproject_position(target) * size / run.camera.get_viewport().get_visible_rect().size
				if point.x > 20 and point.x < size.x - 20 and point.y > 185 and point.y < size.y - 90:
					var clear := (run.camera as SpatialCamera).sight_clear(target)
					if clear: draw_arc(point, 17, 0, TAU, 30, CYAN, 2, true)
					elif not player.spatial.full_course or debug_hud:
						for arc in 4: draw_arc(point, 17, arc * PI * 0.5, arc * PI * 0.5 + PI * 0.25, 8, GOLD, 2, true)
						_center(point + Vector2(0, 34), "OCCLUDED", 13, GOLD)
		if run.feedback_time > 0: _center(Vector2(middle, size.y * 0.81), run.feedback, 25, CYAN if run.feedback_positive else GOLD)
		if m.pulse > 0 and not run.camera.comfort:
			for i in 7:
				for edge in [-1, 1]:
					var x := 20.0 + i * 13 if edge < 0 else size.x - 20 - i * 13
					draw_line(Vector2(x, size.y * 0.25), Vector2(x + edge * 50, size.y * 0.85), Color(0.2, 1, 1, m.pulse * 0.45), 2)
	draw_rect(Rect2(0, size.y - 52, size.x, 52), Color(0.018, 0.03, 0.045, 0.85))
	if not mastery_standard: _center(Vector2(middle, size.y - 29), "A/D CHANGE LINE   SHIFT CARVE / BRAKE   SPACE AT COIL" if player.spatial.full_course else "A/D SCREEN LEFT-RIGHT   SHIFT + DIRECTION CARVE   SHIFT ALONE BRAKE   SPACE AT DEVICE / RELEASE WINDOW", 16, WHITE)
	else: _center(Vector2(middle, size.y - 29), "READ THE SEALED TRACK / CHASE THE CLEAN LINE", 16, WHITE)
	_center(Vector2(middle, size.y - 9), "R RETRY   ESC PAUSE   1/2/3 PACE   V CAMERA: %s   M SOUND" % ["COMFORT" if run.camera.comfort else "FULL ROLL"], 13, MUTED)
	if run.failed:
		_center(Vector2(middle, size.y * 0.43), m.crash_reason, 27, GOLD)
		_center(Vector2(middle, size.y * 0.49), "REJOINING CHECKPOINT", 20, WHITE)
	if get_tree().paused or run.finished:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.02, 0.03, 0.91))
		_center(Vector2(middle, size.y * 0.25), "SPATIAL FLOW" if run.waiting_for_start else ("COURSE COMPLETE" if run.finished and player.spatial.full_course else ("SLICE COMPLETE" if run.finished else "PAUSED")), 50, CYAN)
		if run.waiting_for_start:
			_center(Vector2(middle, size.y * 0.37), "125 M/S / FAST LINE - WALL - CEILING - LOOP - CANYON" if run.speed_mastery() else "100 M/S / WALL - CEILING - FULL LOOP - GRIND - CANYON", 22, WHITE)
			_center(Vector2(middle, size.y * 0.46), "SPACE AT THE WALL COIL. GOLD CEILING WEDGES SEND YOU TO THE CYAN LOWER RAIL; STAY ON TO BYPASS.", 19, WHITE)
			_center(Vector2(middle, size.y * 0.54), "A/D ALWAYS FOLLOWS THE SCREEN. SHIFT CARVES OR BRAKES; IT NEVER BOOSTS.", 19, WHITE)
			_center(Vector2(middle, size.y * 0.64), "DEFAULT CAMERA TURNS WITH THE TRACK / V FOR COMFORT", 20, GOLD)
			_center(Vector2(middle, size.y * 0.76), "SPACE / START", 32, CYAN)
		elif run.finished:
			_center(Vector2(middle, size.y * 0.43), "%.2f S / %.2f KM / %d REJOINS" % [m.clock, m.metres / 1000, run.recoveries], 28, WHITE)
			_center(Vector2(middle, size.y * 0.51), "%d PTS  /  %.0f%% PRECISE  /  BEST SCORE %d" % [run.stunt_score, 100.0 * run.precise_landings / maxf(1, run.scored_landings), run.best_score], 22, CYAN)
			var best_delta := "+%.2f S" % [m.clock - run.best_time_at_start] if is_finite(run.best_time_at_start) else "FIRST CLEAN TIME"
			_center(Vector2(middle, size.y * 0.58), "BEST TIME: %s" % best_delta, 20, GOLD)
			var route_text := ""
			for id in run.branches:
				if id in ["canyon_safe", "canyon_fast", "rollout", "drop", "grind", "high", "upper", "rescue", "final_receiver", "final_upper"]:
					route_text += (" / " if not route_text.is_empty() else "") + id.to_upper()
			_center(Vector2(middle, size.y * 0.65), "ROUTE: " + route_text, 17, WHITE)
			if run.speed_mastery():
				var missed := run.largest_lost_zones(3)
				for i in missed.size():
					var row: Dictionary = missed[i]
					_center(Vector2(middle, size.y * (0.72 + i * 0.045)), "%s / %s / %d PTS LOST" % [row.label, row.reason, row.lost], 16, GOLD)
			_center(Vector2(middle, size.y * (0.89 if run.speed_mastery() else 0.70)), "R / AGAIN", 28, WHITE)
		else: _center(Vector2(middle, size.y * 0.60), "ESC / RESUME     R / RESTART", 28, WHITE)

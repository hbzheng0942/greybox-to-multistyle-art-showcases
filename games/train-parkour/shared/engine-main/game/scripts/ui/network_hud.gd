extends "res://scripts/ui/lab_hud.gd"

func _draw() -> void:
	if session == null: return
	var run := session as NetworkSession
	var train := run.train as NetworkTrain
	var middle := size.x * 0.5
	draw_rect(Rect2(0, 0, size.x, 112), Color(0.018, 0.04, 0.058, 0.9))
	_text(Vector2(32, 43), "NETWORK / 04", 27, CYAN)
	_text(Vector2(32, 79), train.network.current.id.to_upper(), 19, WHITE)
	_center(Vector2(middle, 43), "%.2f S  /  %.2f KM  /  %d RECOVERIES" % [train.elapsed, train.metres / 1000, run.recoveries], 23, WHITE)
	_center(Vector2(middle, 78), "SUPPORT: %s  /  PACE %d" % [train.support_kind.to_upper(), train.speed_mode + 1], 19, GOLD)
	_text(Vector2(size.x - 260, 68), "%03d" % int(train.speed * 3.6), 58, WHITE)
	_text(Vector2(size.x - 102, 68), "KM/H", 18, CYAN)
	if train.active and not get_tree().paused:
		if train.pad_pulse > 0 and not run.camera.comfort:
			for side in [0, 1]:
				for i in 8:
					var x := (28.0 + i * 12) if side == 0 else size.x - 28.0 - i * 12
					draw_line(Vector2(x, size.y * 0.35), Vector2(x + (-45 if side == 0 else 45), size.y * 0.80), Color(0.2, 1, 1, train.pad_pulse * 0.4), 2)
		_center(Vector2(middle, 155), run.next_task(), 26, GOLD)
		if train.state == TrainController.State.AIR:
			_center(Vector2(middle, 189), "TARGET %s / %.1f S - RELEASE STEERING WHEN ALIGNED" % [train.preferred_target.to_upper(), train.landing_eta()], 18, CYAN)
			var target := train.landing_target() + Vector3.UP
			if not run.camera.is_position_behind(target):
				var p := run.camera.unproject_position(target) * size / run.camera.get_viewport().get_visible_rect().size
				if p.y > 235 and p.y < size.y - 100: draw_arc(p, 21, 0, TAU, 28, CYAN, 2, true)
		if run.feedback_time > 0: _center(Vector2(middle, size.y * 0.80), run.feedback, 28, CYAN if run.feedback_positive else GOLD)
	draw_rect(Rect2(0, size.y - 66, size.x, 66), Color(0.018, 0.04, 0.058, 0.9))
	_center(Vector2(middle, size.y - 39), "A/D TRANSFER + AIR AIM   SHIFT+A/D DRIFT   SPACE AT DEVICE   R RETRY", 19, WHITE)
	_center(Vector2(middle, size.y - 13), "1/2/3 PACE   ESC PAUSE   V COMFORT: %s   M SOUND: %s" % ["ON" if run.camera.comfort else "OFF", "OFF" if run.sound.muted else "ON"], 15, MUTED)
	if run.failed: _center(Vector2(middle, size.y * 0.44), train.crash_reason + " / REJOINING", 26, GOLD)
	if get_tree().paused or run.finished:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.02, 0.033, 0.89))
		_center(Vector2(middle, size.y * 0.28), "ROAD NETWORK" if run.waiting_for_start else ("NETWORK COMPLETE" if run.finished else "PAUSED"), 55, CYAN)
		if run.waiting_for_start:
			_center(Vector2(middle, size.y * 0.40), "SHORT CYAN PAD: INSTANT BURST. GOLD RAMP / KICKER: PHYSICAL LAUNCH.", 23, WHITE)
			_center(Vector2(middle, size.y * 0.48), "NO FLAT JUMP. SPACE ONLY AT DEVICES / CURVED EXITS. A/D DODGES + AIMS.", 23, WHITE)
			_center(Vector2(middle, size.y * 0.56), "HIGH / LOW ROUTES REJOIN. VIOLET IS A LONGER, ACTIVE RESCUE ROUTE.", 23, WHITE)
			_center(Vector2(middle, size.y * 0.69), "SPACE / START AT PACE 3 - 100 M/S", 33, GOLD)
		elif run.finished:
			_center(Vector2(middle, size.y * 0.43), "%.2f S / %.2f KM / %d RECOVERIES" % [train.elapsed, train.metres / 1000, run.recoveries], 29, WHITE)
			_center(Vector2(middle, size.y * 0.53), "PEAK %.1f M/S / %d ROAD CLEARS" % [train.peak_speed, run.clears], 23, GOLD)
			_center(Vector2(middle, size.y * 0.68), "R / AGAIN", 30, WHITE)
		else: _center(Vector2(middle, size.y * 0.62), "ESC / RESUME   R / RESTART", 30, WHITE)

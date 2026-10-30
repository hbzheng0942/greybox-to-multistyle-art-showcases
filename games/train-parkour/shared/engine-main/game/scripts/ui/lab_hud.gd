extends Control

const WHITE := Color(0.9, 0.95, 0.98)
const MUTED := Color(0.55, 0.68, 0.75)
const CYAN := Color(0.25, 1.0, 0.86)
const GOLD := Color(1.0, 0.77, 0.32)
var session: LabSession
var font: Font = ThemeDB.fallback_font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if session == null:
		return
	var width := size.x
	var height := size.y
	var train := session.train
	var route := session.lab.route as RailRoute
	var stunts := route.stunts != null
	draw_rect(Rect2(0, 0, width, 142), Color(0.018, 0.04, 0.058, 0.86))
	_text(Vector2(46, 48), "STUNT LAB" if stunts else "VELOCITY LAB", 24, CYAN)
	_text(Vector2(46, 80), "02  /  DRIFT - JUMP - RECONNECT" if stunts else "01  /  MOTION & LINE CONTROL", 17, MUTED)
	_text(Vector2(46, 115), route.section_at(train.distance), 18, WHITE)
	_text(Vector2(width - 310, 76), "%03d" % int(train.speed * 3.6), 62, WHITE)
	_text(Vector2(width - 151, 76), "KM/H", 18, CYAN)
	_text(Vector2(width - 305, 112), "%d M/S  /  PACE %d" % [int(train.speed), train.speed_mode + 1], 17, MUTED)
	var bar := Rect2(width * 0.31, 40, width * 0.38, 4)
	draw_rect(bar, Color(0.2, 0.29, 0.32))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * train.distance / route.length, 4)), CYAN)
	_center(Vector2(width * 0.5, 80), "%04.1f S      %04.2f / %.2f KM" % [train.elapsed, train.distance / 1000.0, route.length / 1000.0], 19, WHITE)
	var score_line := "STYLE %04d    CHAIN x%d    LANDED %d" % [session.stunt_score, session.combo, session.landings] if stunts else "GATES %02d/%02d     FLOW x%d     BEST x%d" % [session.cleared, session.lab.gates.size(), session.combo, session.best_combo]
	_center(Vector2(width * 0.5, 113), score_line, 18, GOLD)
	if stunts and train.active and not get_tree().paused:
		_stunt_guidance()
	var upcoming := session.next_gate_data()
	if not stunts and upcoming.remaining > 0 and not session.finished:
		var names := ["LEFT", "CENTER", "RIGHT"]
		var lane: int = upcoming.lane
		var center := Vector2(width * 0.5, 188)
		for index in range(3):
			var active := index == lane + 1
			draw_rect(Rect2(center.x - 59 + index * 42, center.y - 20, 34, 7), CYAN if active else Color(0.4, 0.5, 0.55, 0.5))
		_center(center + Vector2(0, 22), "%s  /  %d M" % [names[lane + 1], int(upcoming.distance)], 20, WHITE)
	if session.feedback_time > 0.0 and train.active and not get_tree().paused:
		_center(Vector2(width * 0.5, height * 0.69), session.feedback, 29, CYAN if session.feedback_positive else GOLD)
	if train.braking_now and not get_tree().paused:
		_text(Vector2(48, height - 135), "BRAKING", 22, GOLD)
	draw_rect(Rect2(0, height - 93, width, 93), Color(0.018, 0.04, 0.058, 0.88))
	var controls := "SHIFT + A/D  DRIFT    SPACE  JUMP    J / K  ROLL / SPIN    A/D  AIR AIM    R  RETRY" if stunts else "A / D  SWITCH TRACK     SHIFT  BRAKE     R  RETRY     1 / 2 / 3  PACE"
	_center(Vector2(width * 0.5, height - 56), controls, 21, WHITE)
	_center(Vector2(width * 0.5, height - 24), "ESC  PAUSE     V  COMFORT: %s     M  AUDIO: %s     |     KEEP THE FLOW" % ["ON" if session.camera.comfort else "OFF", "OFF" if session.sound.muted else "ON"], 16, MUTED)
	if get_tree().paused or session.finished or session.failed:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.02, 0.033, 0.83))
		if session.waiting_for_start:
			_center(Vector2(width * 0.5, height * 0.28), "MAKE THE CONNECTION", 60, CYAN)
			_center(Vector2(width * 0.5, height * 0.39), "HOLD SHIFT + D THROUGH THE RIGHT TURN. RELEASE TO BOOST.", 25, WHITE)
			_center(Vector2(width * 0.5, height * 0.46), "SPACE ON THE GOLD STRIP. J / K TO ROLL OR SPIN.", 25, WHITE)
			_center(Vector2(width * 0.5, height * 0.53), "A / D TO AIM IN THE AIR. LEVEL OUT ON THE RIGHT-HAND RAIL.", 25, WHITE)
			_center(Vector2(width * 0.5, height * 0.64), "SPACE  /  START", 34, GOLD)
			_center(Vector2(width * 0.5, height * 0.73), "R RETRIES INSTANTLY.  1 / 2 / 3 CHANGES PACE.  V FOR COMFORT CAMERA.", 21, MUTED)
		else:
			var title := session.train.crash_reason if session.failed else ("CHAIN COMPLETE" if session.finished and stunts else ("LINE COMPLETE" if session.finished else "PAUSED"))
			_center(Vector2(width * 0.5, height * 0.4), title, 54, GOLD if session.failed else CYAN)
			if session.finished:
				var result := "%.2f S    STYLE %d    BEST CHAIN x%d" % [train.elapsed, session.stunt_score, session.best_combo] if stunts else "%.2f S    %d / %d GATES    %d PERFECT" % [train.elapsed, session.cleared, session.lab.gates.size(), session.perfects]
				_center(Vector2(width * 0.5, height * 0.5), result, 29, WHITE)
				_center(Vector2(width * 0.5, height * 0.57), "SESSION BEST %d" % session.session_best, 22, GOLD)
			elif session.failed:
				_center(Vector2(width * 0.5, height * 0.52), "JUMP FROM THE GOLD STRIP. AIM FOR THE NARROW RIGHT RAIL.", 23, WHITE)
				_center(Vector2(width * 0.5, height * 0.58), "FINISH ROTATIONS BEFORE TOUCHDOWN.", 23, MUTED)
			_center(Vector2(width * 0.5, height * 0.7), "R  /  RUN IT AGAIN" if session.finished or session.failed else "ESC  RESUME    /    R  RESTART", 27, WHITE)


func _stunt_guidance() -> void:
	var train := session.train
	var profile := train.route.stunts
	var center := Vector2(size.x * 0.5, 195)
	var hint := "SHIFT + D  /  DRIFT THE RIGHT TURN"
	var color := WHITE
	if train.state == TrainController.State.AIR:
		var eta := train.landing_eta()
		hint = "LEVEL OUT  /  LAND IN %.1f S" % eta if eta < 0.8 else "J / K  TRICKS    A / D  AIM    +%d UNBANKED" % train.air_points
		color = GOLD if eta < 0.8 else CYAN
		var error := train.landing_steering_error()
		_center(center + Vector2(0, 34), "AIM RIGHT" if error > 0.7 else ("AIM LEFT" if error < -0.7 else "ON COURSE / RELEASE STEERING"), 23, CYAN)
		var target := train.landing_target() + Vector3.UP
		if not session.camera.is_position_behind(target):
			var screen := session.camera.unproject_position(target) * size / session.camera.get_viewport().get_visible_rect().size
			if screen.x > 50 and screen.x < size.x - 50 and screen.y > 250 and screen.y < size.y - 120:
				draw_arc(screen, 23.0, 0, TAU, 32, CYAN, 3.0, true)
				draw_line(screen - Vector2(32, 0), screen + Vector2(32, 0), CYAN, 2.0, true)
	elif train.state == TrainController.State.DRIFT:
		hint = "DRIFT CHARGE %d%%  /  RELEASE SHIFT TO BOOST" % int(train.drift_charge * 100)
		color = GOLD
		draw_rect(Rect2(center.x - 180, center.y + 18, 360, 7), Color(0.1, 0.2, 0.24, 0.8))
		draw_rect(Rect2(center.x - 180, center.y + 18, 360 * train.drift_charge, 7), GOLD)
	elif train.distance > profile.gap_start - 150 and train.distance < profile.gap_start:
		var ready := train.distance >= profile.gap_start - profile.launch_window
		hint = "SPACE / JUMP NOW" if ready else "GOLD STRIP IN %d M / PREPARE TO JUMP" % int(profile.gap_start - profile.launch_window - train.distance)
		color = GOLD
	elif train.distance >= profile.gap_end and train.distance < profile.landing_end:
		hint = "CONNECTED / STAY ON THE RIGHT RAIL"
		color = CYAN
	elif train.distance >= profile.landing_end:
		hint = "KEEP THE MOMENTUM"
	_center(center, hint, 25, color)


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(font, at + Vector2(1, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.6))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center(at: Vector2, text: String, font_size: int, color: Color) -> void:
	_text(at - Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, 0), text, font_size, color)

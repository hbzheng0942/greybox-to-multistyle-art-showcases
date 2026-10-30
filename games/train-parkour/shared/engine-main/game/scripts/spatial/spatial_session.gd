class_name SpatialSession
extends LabSession
var recoveries := 0
var recovery_left := 0.0
var checkpoint: Dictionary = {}
var branches: Array[String] = []
var event_log: Array[Dictionary] = []
var last_track := ""
const SCORE_REVISION := "m1.7r-2"
var rewarded: Dictionary = {}
var carve_seconds := 0.0
var carve_good_seconds := 0.0
var carve_scraped := false
var precise_landings := 0
var scored_landings := 0
var best_time := INF
var best_score := 0
var best_time_at_start := INF
var last_pulse_at := -INF
var quality_results: Dictionary = {}
var challenge_dirty: Dictionary = {}

func speed_mastery() -> bool:
	return train != null and (train as SpatialTrain).spatial != null and (train as SpatialTrain).spatial.experience_revision == 2

func _ready() -> void:
	super._ready()
	(train as SpatialTrain).motion_event.connect(_on_motion)
	_load_records()
	_save_checkpoint()

func restart_run() -> void:
	recoveries = 0
	recovery_left = 0
	branches.clear()
	event_log.clear()
	last_track = ""
	rewarded.clear()
	carve_seconds = 0
	carve_good_seconds = 0
	carve_scraped = false
	precise_landings = 0
	scored_landings = 0
	last_pulse_at = -INF
	quality_results.clear()
	challenge_dirty.clear()
	super.restart_run()
	if lab.has_method("set_soft_prop_visible"):
		for key in lab.get("soft_props").keys(): lab.set_soft_prop_visible(key, true)
	_load_records()
	_save_checkpoint()

func _save_checkpoint() -> void:
	var m := (train as SpatialTrain).motion
	var track := m.route.current
	checkpoint = {"id": track.id, "s": m.s, "speed": m.speed, "lane": m.lane, "side": m.side, "mode": m.mode, "triggered": m.triggered.duplicate(), "cleared": m.cleared.duplicate(), "branches": branches.duplicate(), "score": stunt_score, "combo": combo, "best_combo": best_combo, "cleared_count": cleared, "preferred_target": m.preferred_target, "rewarded": rewarded.duplicate(), "precise_landings": precise_landings, "scored_landings": scored_landings, "last_pulse_at": last_pulse_at, "quality_results": quality_results.duplicate(true), "challenge_dirty": challenge_dirty.duplicate()}

func _physics_process(delta: float) -> void:
	if train == null or get_tree().paused: return
	feedback_time = maxf(0, feedback_time - delta)
	if recovery_left > 0:
		recovery_left -= delta
		(train as SpatialTrain).motion.clock += delta
		if recovery_left <= 0: _restore()

func _on_advanced(_a: float, _b: float, _side_a: float, _side_b: float) -> void:
	var m := (train as SpatialTrain).motion
	if last_track != m.route.current.id:
		_finish_carve(last_track)
		var previous := last_track
		last_track = m.route.current.id
		branches.append(last_track)
		if (previous == "canyon_fast" and last_track == "canyon_merge") or (previous == "high_merge" and last_track == "tunnel") or (previous == "final_upper" and last_track == "victory_run"):
			var clean_branch := not speed_mastery() or not bool(challenge_dirty.get(_challenge_id(previous), false))
			var earned := _award("branch:" + previous, 150, "CHALLENGE LINE") if clean_branch else 0
			if speed_mastery(): _record_quality("branch:" + previous, "CHALLENGE LINE", 150, earned, "CLEAN MERGE" if clean_branch else "CLIPPED / ROUGH")
	if m.route.current.score_carve and m.phase != SpatialMotionSolver.AIR:
		var bend := m.route.current.curvature(m.s).x
		if absf(bend) > 0.0004:
			var dt := maxf(0, (_b - _a) / maxf(m.speed, 1))
			carve_seconds += dt
			if m.phase == SpatialMotionSolver.DRIFT and signf(m.drift_side) == signf(bend): carve_good_seconds += dt
	if m.active and m.phase != SpatialMotionSolver.AIR and m.route.current.checkpoint and m.s >= m.route.current.checkpoint_s and (checkpoint.get("id", "") != m.route.current.id or float(checkpoint.get("s", -INF)) < m.route.current.checkpoint_s):
		_save_checkpoint()

func _finish_carve(id: String) -> void:
	if id == "" or not (train as SpatialTrain).spatial.tracks.has(id): return
	if (train as SpatialTrain).spatial.tracks[id].score_carve and carve_seconds > 0.1:
		var clean := not carve_scraped and carve_good_seconds / carve_seconds >= 0.9
		var earned := _award("carve:" + id, 100, "CLEAN CARVE") if clean else 0
		if speed_mastery(): _record_quality("carve:" + id, "CARVE " + id.to_upper(), 100, earned, "CLEAN" if clean else "MISSED TIMING")
	carve_seconds = 0
	carve_good_seconds = 0
	carve_scraped = false

func _award(key: String, base: int, label: String, break_combo := false, increments_combo := true) -> int:
	if rewarded.has(key): return 0
	rewarded[key] = true
	if break_combo: combo = 0
	elif increments_combo: combo += 1
	best_combo = maxi(best_combo, combo)
	var points := int(roundi(base * (minf(2.0, 1.0 + floorf(float(combo) / (3.0 if speed_mastery() else 5.0)) * 0.25) if increments_combo else 1.0)))
	stunt_score += points
	feedback = "%s  +%d" % [label, points]
	feedback_positive = true
	feedback_time = 0.9
	return points

func _record_quality(id: String, label: String, possible: int, earned: int, reason: String) -> void:
	quality_results[id] = {"id": id, "label": label, "possible": possible, "earned": earned, "lost": maxi(0, possible - earned), "reason": reason}

func _challenge_id(segment: String) -> String:
	if segment in ["canyon_fast_catch", "canyon_fast"]: return "canyon_fast"
	if segment in ["high", "high_merge"]: return "high_merge"
	if segment in ["final_upper_catch", "final_upper"]: return "final_upper"
	return ""

func largest_lost_zones(limit := 3) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in quality_results.values():
		if int(row.lost) > 0: rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.lost) > int(b.lost))
	return rows.slice(0, mini(limit, rows.size()))

func _on_stunt_event(_kind: String, _value: float) -> void:
	pass # Rich motion events below own feedback; no legacy drift/style speed rewards.

func _on_motion(kind: String, data: Dictionary) -> void:
	event_log.append(data.duplicate(true))
	feedback_time = 0.7
	feedback_positive = true
	feedback = kind
	if kind == "PULSE":
		feedback = "+%d M/S / READ THE EXIT" % int(data.delta_v)
		if speed_mastery():
			var zone_id: String = str(data.get("zone_id", "pulse:" + str(data.segment)))
			var chained := float(data.delta_v) > 0 and float(data.seconds) - last_pulse_at <= 4.0
			if chained:
				var earned := _award("flow:" + zone_id, 75, "FLOW BOOST")
				_record_quality(zone_id, "BOOST " + str(data.segment).to_upper(), 75, earned, "CHAINED")
			last_pulse_at = float(data.seconds)
	elif kind == "CARVE EXIT": feedback = "CARVE / SPEED HELD"
	elif kind == "CAPTURE":
		landings += 1
		scored_landings += 1
		if speed_mastery() and data.rough:
			var challenge := _challenge_id(str(data.segment))
			if not challenge.is_empty(): challenge_dirty[challenge] = true
		var precise: bool = not data.rough and not data.assisted and float(data.lateral_error) <= 0.6 and float(data.heading) <= 8.0
		if precise: precise_landings += 1
		if speed_mastery():
			var zone_id: String = str(data.get("zone_id", "capture:" + str(data.segment)))
			var base := 0 if data.rough else (25 if data.assisted else (200 if precise else 100))
			if data.rough: combo = 0
			var earned := _award("landing:%d" % landings, base, "PRECISE" if precise else ("ROUGH CONTACT" if data.rough else ("ASSISTED" if data.assisted else "CLEAN LANDING")), data.rough, not data.assisted and not data.rough)
			_record_quality(zone_id, "LAND " + str(data.segment).to_upper(), 200, earned, "PRECISE" if precise else ("ROUGH" if data.rough else ("ASSISTED" if data.assisted else "CLEAN")))
			if data.rough: feedback = "ROUGH CONTACT / MOMENTUM LOST"; feedback_positive = false
		else:
			_award("landing:%d" % landings, 25 if data.rough else (75 if data.assisted else (200 if precise else 100)), "PRECISE LANDING" if precise else ("ROUGH CONTACT" if data.rough else "CONNECTED"), data.rough)
	elif kind == "CLEAR":
		cleared += 1
		if data.get("obstacle_kind", "") in ["block", "beam"]:
			var obstacle_id: String = str(data.get("obstacle_key", ""))
			var earned := _award("clear:" + obstacle_id, 15 if speed_mastery() else 50, "SAFE LINE" if speed_mastery() else "CLEAN LINE", false, not speed_mastery())
			if speed_mastery(): _record_quality(obstacle_id, "AVOID " + str(data.segment).to_upper(), 15, earned, "SAFE")
	elif kind == "CRASH":
		recoveries += 1
		recovery_left = (train as SpatialTrain).settings.recovery_seconds
		failed = true
		combo = 0
		last_pulse_at = -INF
		feedback = data.reason
		feedback_positive = false
	elif kind == "GUARD CONTACT":
		feedback = "GUARD CONTACT / CORRECT YOUR LINE"; feedback_positive = false; combo = 0; carve_scraped = true; last_pulse_at = -INF
		if speed_mastery() and not _challenge_id(str(data.segment)).is_empty(): challenge_dirty[_challenge_id(str(data.segment))] = true
	elif kind == "SOFT CONTACT":
		feedback = "CLIPPED / KEEP MOVING"; feedback_positive = false; combo = 0; carve_scraped = true; last_pulse_at = -INF
		if speed_mastery() and not _challenge_id(str(data.segment)).is_empty(): challenge_dirty[_challenge_id(str(data.segment))] = true
		if lab.has_method("set_soft_prop_visible"): lab.set_soft_prop_visible(str(data.get("obstacle_key", "")), false)
	elif kind == "LANDING ASSIST": feedback = "LINE LOCK / HOLD YOUR CHOICE"
	elif kind == "RESCUE WINDOW": feedback = "STILL ALIVE / AIM AT THE VIOLET RAIL"
	sound.play_motion(kind, data)

func _restore() -> void:
	var p := train as SpatialTrain
	var m := p.motion
	var old_clock := m.clock
	var old_travel := m.metres
	var old_history := m.history.duplicate()
	var old_peak := m.peak_speed
	var supports := m.support_seconds.duplicate()
	var energy := m.energy.duplicate()
	m.reset(train.speed_mode, false)
	m.route.activate(checkpoint.id)
	m.s = checkpoint.s
	m.lane = checkpoint.lane
	m.side = checkpoint.side
	m.lane_from = m.side
	m.lane_elapsed = m.tuning.lane_seconds
	m.speed = checkpoint.speed
	m.world_pose = m.route.pose_at(m.s, m.side)
	m.world_velocity = -m.world_pose.basis.z * m.speed
	m.clock = old_clock
	m.metres = old_travel
	m.peak_speed = old_peak
	m.history.assign(old_history)
	m.support_seconds = supports
	m.energy = energy
	m.preferred_target = checkpoint.preferred_target
	m.triggered = checkpoint.triggered.duplicate()
	m.cleared = checkpoint.cleared.duplicate()
	rewarded = checkpoint.rewarded.duplicate()
	last_pulse_at = float(checkpoint.get("last_pulse_at", -INF))
	quality_results = checkpoint.get("quality_results", {}).duplicate(true)
	challenge_dirty = checkpoint.get("challenge_dirty", {}).duplicate()
	precise_landings = checkpoint.precise_landings
	scored_landings = checkpoint.scored_landings
	landings = scored_landings
	carve_seconds = 0
	carve_good_seconds = 0
	carve_scraped = false
	if lab.has_method("set_soft_prop_visible"):
		for key in lab.get("soft_props").keys(): lab.set_soft_prop_visible(key, not m.cleared.has(key))
	branches.assign(checkpoint.branches)
	stunt_score = checkpoint.score
	combo = 0
	best_combo = checkpoint.best_combo
	cleared = checkpoint.cleared_count
	failed = false
	p._reset_presentation()
	p._sync()
	p.reset_physics_interpolation()
	camera.reset_camera()
	sound.reset_feedback()
	feedback = "CHECKPOINT / LOOK AHEAD"
	feedback_positive = true
	feedback_time = 1
	m._emit("CHECKPOINT")

func _on_completed() -> void:
	_finish_carve(last_track)
	super._on_completed()
	if not (train as SpatialTrain).spatial.full_course or DisplayServer.get_name() == "headless" or "--qa-run" in OS.get_cmdline_user_args(): return
	if recoveries == 0: best_time = minf(best_time, (train as SpatialTrain).motion.clock)
	best_score = maxi(best_score, stunt_score)
	var key := _record_key()
	var path := "user://spatial_full_records.json"
	var records := _read_records()
	records[key] = {"best_time": best_time if is_finite(best_time) else -1.0, "best_score": best_score}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(records))

func _record_key() -> String:
	var m := (train as SpatialTrain).motion
	var tuning_hash := FileAccess.get_sha256((train as SpatialTrain).settings.resource_path)
	var route_hash_source := FileAccess.get_sha256("res://scripts/spatial/spatial_route.gd") + FileAccess.get_sha256("res://scripts/spatial/spatial_full_route.gd")
	if speed_mastery(): route_hash_source += FileAccess.get_sha256("res://scripts/spatial/spatial_full_r2_route.gd")
	var route_hash := route_hash_source.sha256_text()
	return "%s:%s:%s:%s:%d" % ["m1.7r2" if speed_mastery() else "m1.7r", "m1.7r2-1" if speed_mastery() else SCORE_REVISION, route_hash, tuning_hash, m.mode]

func _read_records() -> Dictionary:
	if not FileAccess.file_exists("user://spatial_full_records.json"): return {}
	var json := JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string("user://spatial_full_records.json")) == OK and json.data is Dictionary else {}

func _load_records() -> void:
	var record: Dictionary = {} if "--qa-run" in OS.get_cmdline_user_args() else _read_records().get(_record_key(), {})
	best_time = float(record.get("best_time", -1.0))
	if best_time < 0: best_time = INF
	best_time_at_start = best_time
	best_score = int(record.get("best_score", 0))

func instruction() -> String:
	var p := train as SpatialTrain
	var m := p.motion
	if m.phase == SpatialMotionSolver.AIR:
		var prediction := m.predict()
		if prediction.is_empty(): return "NO CONTACT PREDICTED / FIND THE CATCH"
		if prediction.longitudinal_error > 1.0: return "OUTSIDE CATCH LENGTH / WATCH YOUR ENTRY SPEED"
		var error := p.landing_steering_error()
		return "D / CORRECT RIGHT" if error > 0.5 else ("A / CORRECT LEFT" if error < -0.5 else "ON LINE / RELEASE A-D")
	var track := m.route.current
	if m.braking: return "BRAKING / RELEASE SHIFT TO DRIVE"
	if m.phase == SpatialMotionSolver.DRIFT and track.length - m.s > 50: return "CARVE / KEEP YOUR LINE"
	if track.id == "carve" and track.length - m.s < 70: return "RELEASE SHIFT / CENTRE BEFORE THE CLAMP"
	if track.can_release(m.s):
		if track.id == "wall":
			var preview := m.predict("inverted", m.world_velocity + m.route.global_basis * track.impulse, m.world_pose.origin + m.world_pose.basis.y * 0.08)
			return "SPACE NOW / COIL TO CEILING" if not preview.is_empty() and preview.longitudinal_error < 0.5 else "WAIT / COIL WINDOW AHEAD"
		if track.id == "inverted": return "SPACE: DROP NOW / HOLD: SAFE ROLLOUT"
		if track.id == "grind": return "SPACE NOW / THEN D TO THE RIGHT RAIL"
		if track.id == "exit_ramp": return "SPACE + A: HIGH / RIDE: GOLD GRIND"
		if track.id == "upper":
			var preview := m.predict("finish", m.world_velocity + m.route.global_basis * track.impulse, m.world_pose.origin + m.world_pose.basis.y * 0.08)
			return "SPACE NOW / FINAL COIL - AIM LEFT" if not preview.is_empty() and preview.longitudinal_error < 0.5 else "WAIT / FINAL COIL WINDOW AHEAD"
	for ob in track.obstacles:
		if ob.s > m.s and ob.s - m.s < m.speed * 2.6:
			var label := "OPEN: "
			for l in [-1, 0, 1]:
				if not ob.lanes.has(l): label += "LEFT " if l < 0 else ("RIGHT " if l > 0 else "CENTRE ")
			return label
	return track.title

func mastery_hint() -> String:
	var m := (train as SpatialTrain).motion
	if m.phase == SpatialMotionSolver.AIR:
		if m.air_source == "wall": return "CEILING CATCH / NEXT GOLD GATE EJECTS DOWN"
		if m.air_source == "inverted": return "DOWNWARD EJECT / CATCH THE CYAN LOWER RAIL"
		if m.air_source == "grind": return "RELAY HOP / CATCH THE CYAN RAIL"
		if m.air_source == "exit_ramp": return "RIGHT GOLD GRIND / FOLLOW THE LOWER CATCH"
		return "CATCH / ALIGN WITH THE VISIBLE RAIL"
	var track := m.route.current
	if track.id == "wall": return "GOLD COIL / SPACE LAUNCHES TO CEILING"
	if track.id == "inverted":
		var eject_window: Vector2 = track.release_windows[0]
		if m.s < eject_window.x: return "GOLD WEDGES AHEAD / SPACE WHEN ON GOLD"
		if track.can_release(m.s): return "SPACE NOW / GOLD WEDGES DROP TO CYAN RAIL"
		return "STAY ON / SAFE BYPASS"
	if track.id == "grind": return "CYAN RELAY AHEAD / SPACE HOPS; RIDE OFF TO DROP SAFELY"
	if track.id in ["loop_out", "exit_ramp"]: return "RIGHT GOLD GRIND / LEFT HIGH LINE"
	var best: Dictionary = {}
	var nearest := INF
	var priority := 99
	var targets: Array[Dictionary] = [{"track": track, "offset": -m.s}]
	if track.next.size() == 1 and m.route.tracks.has(track.next[0]):
		targets.append({"track": m.route.tracks[track.next[0]], "offset": track.length - m.s})
	for target in targets:
		for zone: Dictionary in (target.track as SpatialTrack).action_zones:
			var distance: float = float(target.offset) + float(zone.s)
			if distance < 0 or distance > m.speed * float(zone.preview_seconds): continue
			var rank := 0 if zone.kind in ["block", "beam"] else (1 if zone.kind == "soft" else 2)
			if rank > priority or (rank == priority and distance >= nearest): continue
			best = zone
			nearest = distance
			priority = rank
	if best.is_empty(): return "HOLD MOMENTUM / READ THE ROAD"
	var lane_names := ["LEFT", "CENTRE", "RIGHT"]
	var kind: String = best.kind
	if kind in ["block", "beam", "soft"]:
		var closed := ""
		for lane in best.lanes:
			closed += (" + " if not closed.is_empty() else "") + lane_names[int(lane) + 1]
		return ("LOW BEAM" if kind == "beam" else ("SOFT CONTACT" if kind == "soft" else "SEALED TRACK")) + " / " + closed
	if kind == "pulse": return "PULSE / " + lane_names[int(best.lane) + 1]
	if kind == "coil": return "COIL / RELEASE WINDOW AHEAD"
	return "BEND / HOLD MOMENTUM"

func player_hint_state() -> Dictionary:
	# Public, deliberately quantized presentation state. A cue-only controller
	# may consume this; exact predicted contact point and solver links stay private.
	var p := train as SpatialTrain
	var m := p.motion
	if speed_mastery() and p.speed_mode == 2:
		return {"message": mastery_hint(), "phase": "air" if m.phase == SpatialMotionSolver.AIR else "rail", "steer": 0, "lane": m.lane, "current_lane": m.lane, "shift": false, "jump_now": false, "prepare": false}
	var message := instruction()
	var cue := {"message": message, "phase": "air" if m.phase == SpatialMotionSolver.AIR else "rail", "steer": 0, "lane": m.lane, "current_lane": m.lane, "shift": false, "jump_now": false, "prepare": false}
	if m.phase == SpatialMotionSolver.AIR:
		cue.steer = 1 if message.begins_with("D /") else (-1 if message.begins_with("A /") else 0)
		return cue
	var track := m.route.current
	var release_now := message.begins_with("SPACE NOW") or message.begins_with("SPACE: DROP NOW")
	var screen_sign := signf(camera.global_basis.x.dot(m.world_pose.basis.x))
	if absf(screen_sign) < 0.1: screen_sign = m.control_sign
	var desired_lane := m.lane
	var nearest := INF
	for ob in track.obstacles:
		var distance: float = ob.s - m.s
		if distance <= 0 or distance > m.speed * 2.6 or distance >= nearest: continue
		nearest = distance
		if not release_now:
			cue.message = "OPEN: "
			for lane in [-1, 0, 1]:
				if not ob.lanes.has(lane): cue.message += "LEFT " if lane < 0 else ("RIGHT " if lane > 0 else "CENTRE ")
		if ob.lanes.has(desired_lane):
			for candidate in [-1, 0, 1]:
				if not ob.lanes.has(candidate): desired_lane = candidate; break
	if nearest == INF:
		for pad in track.pads:
			if pad.a > m.s and pad.a - m.s < m.speed * 1.2:
				desired_lane = int(pad.lane)
				break
		if not release_now and not track.next.is_empty() and (track.camera_phase == "carve" or track.length - m.s < m.speed * 1.5):
			var successor: SpatialTrack = m.route.tracks[track.next[0]]
			if successor.single_lane:
				desired_lane = 0
				cue.message = "CENTRE / NARROW RAIL AHEAD"
	cue.lane = desired_lane
	if not track.single_lane and m.lane_elapsed >= m.tuning.lane_seconds:
		cue.steer = int(signf(desired_lane - m.lane) * screen_sign)
	if track.camera_phase == "carve" and nearest == INF and desired_lane == m.lane and track.length - m.s > m.speed * 0.55 and absf(track.curvature(m.s).x) > 0.0004:
		cue.shift = true
		cue.steer = int(signf(track.curvature(m.s).x) * screen_sign)
	cue.jump_now = release_now
	cue.prepare = track.release_windows.size() > 0 and track.length - m.s < m.speed * 1.5
	return cue

func player_action_text(cue: Dictionary) -> String:
	# The cue-only controller consumes these same public action bits. Keep every
	# requested key visible, including the bend direction and pad-driven lane.
	var action := ""
	if bool(cue.get("shift", false)): action = "SHIFT"
	if bool(cue.get("jump_now", false)): action += (" + " if not action.is_empty() else "") + "SPACE"
	var steer := int(cue.get("steer", 0))
	if steer != 0: action += (" + " if not action.is_empty() else "") + ("A / SCREEN LEFT" if steer < 0 else "D / SCREEN RIGHT")
	if action.is_empty(): return "AIM AT THE VISIBLE CATCH" if cue.get("phase", "rail") == "air" else "HOLD LINE / READ AHEAD"
	return action + (" / PREPARE" if bool(cue.get("prepare", false)) and not bool(cue.get("jump_now", false)) else "")

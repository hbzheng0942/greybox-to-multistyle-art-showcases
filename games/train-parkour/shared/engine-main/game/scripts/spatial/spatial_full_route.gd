class_name SpatialFullRoute
extends SpatialRoute
## M1.7 full course. Reuses the reviewed 3D action core, with authored approach and finale chapters.

func _ready() -> void:
	course_name = "SPATIAL FLOW / FULL GREYBOX"
	full_course = true
	_build_slice()
	# The short entry remains a checkpoint in the legacy 27-second slice, but
	# is too close to the loop's forced decision for a full-course recovery.
	(tracks.loop_entry as SpatialTrack).checkpoint = false
	# At the bottom of the high-line speed envelope the train can meet the
	# upper rail before reaching its legal catch. Route those slow approaches
	# toward the visible lower rescue instead of treating the solid as a death.
	for connection in (tracks.cliff_lip as SpatialTrack).connections:
		if connection.target == "upper": connection.minimum_speed = 110.0
		elif connection.target == "rescue": connection.preferred_maximum_speed = 110.0
	(tracks.grind as SpatialTrack).entry_taper_length = 60.0
	var core_grind: SpatialTrack = tracks.grind
	core_grind.release_windows = [Vector2(core_grind.length - 130.0, core_grind.length - 2.0)]
	for connection in core_grind.connections:
		if connection.target == "relay": connection.from = core_grind.length - 130.0
	(tracks.upper as SpatialTrack).entry_taper_length = 60.0
	(tracks.rescue as SpatialTrack).half_width = 3.0
	var core_wall: SpatialTrack = tracks.wall
	core_wall.release_windows = [Vector2(core_wall.length - 120, core_wall.length - 2)]
	if not core_wall.connections.is_empty():
		core_wall.connections[0].from = core_wall.length - 120
	var core_inverted: SpatialTrack = tracks.inverted
	var inverted_end := core_inverted.pose(core_inverted.length).origin
	var inverted_forward := -core_inverted.pose(0).basis.z
	var inverted_points := PackedVector3Array()
	for i in 131:
		var t := float(i) / 130.0
		inverted_points.append(inverted_end - inverted_forward * 195.0 + inverted_forward * 195.0 * t)
	core_inverted.build(inverted_points, PI, PI)
	core_inverted.release_windows = [Vector2(core_inverted.length - 82.0, core_inverted.length - 1.0)]
	# Rebuilding this rail changes its length; keep the actual airborne link legal
	# throughout the advertised release window.
	for connection in core_inverted.connections:
		if connection.target == "drop": connection.until = core_inverted.length + 2.0
	# At 150 m/s a late legal release lands on the first metres of the
	# physically continuous loop-entry rail. Declare that visible surface as a
	# narrow secondary catch, rather than accepting a collision by proximity.
	air_link("inverted", "loop_entry", core_inverted.length - 30.0, core_inverted.length + 2.0, 40.0,
		{"intent": "intentional", "minimum_speed": 145.0, "priority": -5})
	var late_rollout: SpatialTrack = tracks.rollout
	air_link("inverted", "rollout", core_inverted.length - 30.0, core_inverted.length + 2.0, late_rollout.length,
		{"intent": "intentional", "minimum_speed": 135.0, "preferred_minimum_speed": 145.0, "a": late_rollout.length - 21.0, "capture_width": late_rollout.half_width, "priority": -5})
	if not core_wall.connections.is_empty(): core_wall.connections[0].b = 180.0
	var core_upper: SpatialTrack = tracks.upper
	core_upper.release_windows = [Vector2(core_upper.length - 80, core_upper.length)]
	for connection in core_upper.connections:
		if connection.target == "finish": connection.from = core_upper.length - 80
	var core_tunnel: SpatialTrack = tracks.tunnel
	# A broad mountain spiral adds readable tunnel travel without moving either
	# end of the reviewed wall/valley chain. The 380 m radius keeps curvature
	# gentle enough for the 100-150 m/s envelope.
	var tunnel_start := core_tunnel.pose(0)
	var tunnel_end := core_tunnel.pose(core_tunnel.length)
	var tunnel_forward := -tunnel_start.basis.z
	var tunnel_right := tunnel_start.basis.x
	var tunnel_delta := tunnel_end.origin - tunnel_start.origin
	var tunnel_points := PackedVector3Array()
	for i in 481:
		var t := float(i) / 480.0
		var angle := TAU * t
		var advance := t + sin(angle) / TAU
		# Separate the spiral's early and late passes vertically where their
		# projected paths cross; each tunnel tube retains physical roof clearance.
		var vertical := 45.0 * sin(angle) * smoothstep(0.0, 0.04, t) * smoothstep(0.0, 0.04, 1.0 - t)
		tunnel_points.append(tunnel_start.origin + tunnel_right * 380.0 * (1.0 - cos(angle)) + tunnel_forward * 380.0 * sin(angle) + tunnel_delta * advance + Vector3.UP * vertical)
	core_tunnel.build(tunnel_points)
	core_tunnel.ceiling = 18.0
	core_tunnel.enclosure_half_width = 38.0
	core_tunnel.pads = [{"a": core_tunnel.length * 0.20, "b": core_tunnel.length * 0.20 + 12.0, "lane": 1}]
	core_tunnel.obstacles = [
		{"s": core_tunnel.length * 0.18, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"s": core_tunnel.length * 0.28, "lanes": [0], "height": 5.0, "bottom": 3.2, "kind": "beam"},
		{"s": core_tunnel.length * 0.44, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "core_tunnel_soft"},
		{"s": core_tunnel.length * 0.58, "lanes": [-1, 0], "height": 5.0, "kind": "block"},
		{"s": core_tunnel.length * 0.78, "lanes": [0], "height": 5.0, "bottom": 3.2, "kind": "beam"},
		{"s": core_tunnel.length * 0.91, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	_build_station_and_canyon()
	_build_landmark_finale()
	_label_core_chapters()
	for track: SpatialTrack in tracks.values():
		for connection in track.connections:
			if connection.get("assist", false):
				connection.assist_time = 0.6
				connection.assist_max_error = 8.0
	for seam in [["carve", "wall"], ["rollout", "loop_entry"], ["rescue_merge", "finish"], ["station_carve", "station_ramp"], ["tunnel", "cliff_turn"], ["final_upper", "victory_run"]]:
		_smooth_join_normal(seam[0], seam[1])
	start_id = "station_start"
	activate(start_id)

func _smooth_join_normal(source_id: String, target_id: String) -> void:
	var source: SpatialTrack = tracks[source_id]
	var target: SpatialTrack = tracks[target_id]
	var target_up := target.pose(0).basis.y
	var normals := PackedVector3Array()
	for i in source.points.size():
		var current_up := Basis(source.rotations[i]).y
		var blend := smoothstep(0.0, 1.0, clampf((source.distances[i] - source.length + 120.0) / 120.0, 0.0, 1.0))
		normals.append(current_up.slerp(target_up, blend).normalized())
	source.build(source.points, 0.0, 0.0, normals)

func _label_core_chapters() -> void:
	for id in ["rush", "carve", "wall", "inverted", "drop", "rollout", "loop_entry", "loop", "loop_out", "exit_ramp", "grind", "relay", "high", "high_merge"]:
		(tracks[id] as SpatialTrack).chapter = "03 VERTICAL STATION"
	(tracks.tunnel as SpatialTrack).chapter = "04 TUNNEL"
	for id in ["cliff_turn", "cliff_lip", "upper", "rescue", "rescue_merge", "finish"]:
		(tracks[id] as SpatialTrack).chapter = "05 MULTILEVEL VALLEY"
	(tracks.cliff_turn as SpatialTrack).score_carve = true

func bridge(id: String, start: Vector3, finish: Vector3, right: Vector3, bow: float, bank0 := 0.0, bank1 := 0.0, end_forward := Vector3.ZERO) -> SpatialTrack:
	var points := PackedVector3Array()
	var start_forward := (finish - start).normalized()
	for track: SpatialTrack in tracks.values():
		if track.pose(track.length).origin.distance_to(start) < 0.01:
			start_forward = -track.pose(track.length).basis.z
			break
	if end_forward.length_squared() < 0.5: end_forward = (finish - start).normalized()
	var span := start.distance_to(finish)
	for i in 241:
		var t := float(i) / 240.0
		var t2 := t * t
		var t3 := t2 * t
		points.append(start * (2 * t3 - 3 * t2 + 1) + start_forward * span * (t3 - 2 * t2 + t) + finish * (-2 * t3 + 3 * t2) + end_forward.normalized() * span * (t3 - t2) + right * bow * pow(sin(PI * t), 2))
	return add_track(id, points, bank0, bank1)

func line(id: String, origin: Vector3, forward: Vector3, span: float, rise := 0.0, bank0 := 0.0, bank1 := 0.0) -> SpatialTrack:
	var points := PackedVector3Array()
	var count := ceili(span / 1.5)
	for i in range(count + 1):
		var t := float(i) / count
		var height_fraction := t * t * (2.0 - t) if span <= 50.0 and absf(rise) > 0.01 else t
		points.append(origin + forward * span * t + Vector3.UP * rise * height_fraction)
	return add_track(id, points, bank0, bank1)

func _build_station_and_canyon() -> void:
	var f := Vector3.FORWARD
	var right := f.cross(Vector3.UP).normalized()
	var station := line("station_start", Vector3(0, 140, 3400), f, 1000, -10)
	station.chapter = "01 STATION"
	station.title = "PULSE / READ THE NO-ENTRY SIGNS"
	station.checkpoint = true
	station.checkpoint_s = 30
	station.checkpoint_speed = 100
	station.pads = [{"a": 95.0, "b": 107.0, "lane": 0}, {"a": 465.0, "b": 477.0, "lane": -1}, {"a": 950.0, "b": 962.0, "lane": 0}]
	station.obstacles = [
		{"s": 270.0, "lanes": [0], "height": 2.2, "kind": "soft", "group": "station_cones_a"},
		{"s": 390.0, "lanes": [1], "height": 5.0, "kind": "block"},
		{"s": 540.0, "lanes": [-1, 0], "height": 2.4, "kind": "soft", "group": "station_barriers_b"},
		{"s": 720.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"s": 850.0, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "station_cones_d"},
	]
	station.next = ["station_carve"]
	var carve := shaped("station_carve", station.pose(station.length).origin, f, 600, 50, -30, 0, deg_to_rad(-18))
	carve.chapter = "01 STATION"
	carve.title = "SHIFT + A / DESCEND INTO THE CANYON"
	carve.camera_phase = "carve"
	carve.score_carve = true
	carve.obstacles = [
		{"s": 245.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"s": 420.0, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "station_cones_c"},
	]
	carve.next = ["station_ramp"]
	var ramp := line("station_ramp", carve.pose(carve.length).origin, f, 40, 6, deg_to_rad(-18), 0)
	ramp.chapter = "02 CANYON"
	ramp.kind = "ramp"
	ramp.camera_phase = "crest"
	ramp.title = "RIDE: WIDE CANYON / SPACE + A: FAST RIDGE"
	ramp.release_windows = [Vector2(8, ramp.length)]
	ramp.impulse = Vector3.UP * 12
	var safe_start := ramp.pose(ramp.length).origin + f * 55 + right * 4.4 - Vector3.UP * 12
	var fast_start := ramp.pose(ramp.length).origin + f * 65 - right * 4.4 + Vector3.UP * 6
	var merge_start := Vector3(0, 65, 350)
	var safe := bridge("canyon_safe", safe_start, merge_start, right, 0, 0, 0, f)
	safe.chapter = "02 CANYON"
	safe.title = "WIDE CANYON / PULSES AND OPEN LANES"
	safe.camera_phase = "carve"
	safe.entry_half_width = 5.0
	safe.entry_taper_length = 65
	safe.pads = [{"a": 250.0, "b": 262.0, "lane": 1}, {"a": 820.0, "b": 832.0, "lane": -1}]
	safe.obstacles = [
		{"s": 520.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"s": 620.0, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "canyon_soft_a"},
		{"s": 900.0, "lanes": [-1, 0], "height": 5.0, "kind": "block"},
		{"s": 1110.0, "lanes": [1], "height": 2.4, "kind": "soft", "group": "canyon_soft_b"},
		{"s": 1290.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	safe.next = ["canyon_merge"]
	var fast_catch := line("canyon_fast_catch", fast_start, f, 220, -8)
	fast_catch.chapter = "02 CANYON"
	fast_catch.title = "FAST RIDGE CATCH / STABILIZE"
	fast_catch.kind = "grind"
	fast_catch.single_lane = true
	fast_catch.half_width = 2.2
	fast_catch.entry_half_width = 3.8
	fast_catch.entry_taper_length = 50
	fast_catch.camera_phase = "grind"
	fast_catch.next = ["canyon_fast"]
	var fast := bridge("canyon_fast", fast_catch.pose(fast_catch.length).origin, merge_start, right, -160, 0, 0, f)
	fast.chapter = "02 CANYON"
	fast.title = "FAST RIDGE / STABILIZE WITH SHIFT"
	fast.kind = "clip"
	fast.single_lane = true
	fast.half_width = 2.2
	fast.camera_phase = "grind"
	fast.pads = [{"a": 440.0, "b": 452.0, "lane": 0}]
	fast.next = ["canyon_merge"]
	air_link("station_ramp", "canyon_safe", 0, ramp.length + 2, safe.length - 20, {"intent": "natural", "screen_direction": 1, "assist": true, "default": true, "priority": 5})
	air_link("station_ramp", "canyon_fast_catch", 0, ramp.length + 2, fast_catch.length - 10, {"intent": "intentional", "screen_direction": -1, "assist": true, "priority": 10})
	var merge := line("canyon_merge", merge_start, f, 350)
	merge.chapter = "02 CANYON"
	merge.title = "MERGE / WALL SEQUENCE AHEAD"
	merge.checkpoint = true
	merge.checkpoint_s = 35
	merge.checkpoint_speed = 125
	merge.obstacles = [{"s": 300.0, "lanes": [0], "height": 2.0, "kind": "soft", "group": "merge_soft"}]
	merge.next = ["rush"]
	var rush: SpatialTrack = tracks.rush
	rush.checkpoint_s = 0
	rush.checkpoint_speed = 125
	rush.obstacles = [{"s": 265.0, "lanes": [1], "height": 5.0, "kind": "block"}]
	(tracks.loop_entry as SpatialTrack).checkpoint_speed = 125
	(tracks.relay as SpatialTrack).checkpoint_speed = 125

func _build_landmark_finale() -> void:
	var finish: SpatialTrack = tracks.finish
	var f := -finish.pose(finish.length).basis.z
	var right := finish.pose(finish.length).basis.x
	finish.title = "LANDMARK RETURN / KEEP THE FLOW"
	finish.next = ["landmark_return"]
	var loop_base: Vector3 = (tracks.loop as SpatialTrack).pose(0).origin
	var return_forward := Vector3(loop_base.x - finish.pose(finish.length).origin.x, 0, loop_base.z - finish.pose(finish.length).origin.z).normalized()
	var underpass_start := loop_base - return_forward * 100.0 - Vector3.UP * 18.0
	var turnaround := PackedVector3Array()
	var turnaround_origin := finish.pose(finish.length).origin
	var turn_side := -right
	var turn_radius := 330.0
	for i in 181:
		var angle := PI * float(i) / 180.0
		turnaround.append(turnaround_origin + turn_side * turn_radius * (1.0 - cos(angle)) + f * turn_radius * sin(angle))
	var turn_end := turnaround[-1]
	var turn_span := turn_end.distance_to(underpass_start)
	for i in range(1, 301):
		var t := float(i) / 300.0
		var t2 := t * t
		var t3 := t2 * t
		turnaround.append(turn_end * (2 * t3 - 3 * t2 + 1) - f * turn_span * (t3 - 2 * t2 + t) + underpass_start * (-2 * t3 + 3 * t2) + return_forward * turn_span * (t3 - t2))
	var landmark := add_track("landmark_return", turnaround)
	landmark.chapter = "05 MULTILEVEL VALLEY"
	landmark.title = "SHIFT + DIRECTION / WIDE VALLEY RETURN"
	landmark.camera_phase = "carve"
	landmark.score_carve = true
	landmark.checkpoint = true
	landmark.checkpoint_s = 30
	landmark.pads = [{"a": 120.0, "b": 132.0, "lane": 0}, {"a": 1610.0, "b": 1622.0, "lane": 1}]
	landmark.obstacles = [
		{"s": 1450.0, "lanes": [-1, 0], "height": 5.0, "kind": "block"},
		{"s": 2070.0, "lanes": [1], "height": 2.3, "kind": "soft", "group": "landmark_soft"},
		{"s": 2600.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	landmark.next = ["underpass"]
	var underpass := line("underpass", landmark.pose(landmark.length).origin, return_forward, 900)
	underpass.chapter = "06 LANDMARK RETURN"
	underpass.title = "HIGH CAMERA / READ LEFT-RIGHT-CENTRE"
	underpass.enclosure = "tunnel"
	underpass.ceiling = 18
	underpass.camera_phase = "tunnel"
	underpass.checkpoint = true
	underpass.checkpoint_s = 0
	underpass.checkpoint_speed = 125
	underpass.pads = [{"a": 280.0, "b": 292.0, "lane": -1}, {"a": 515.0, "b": 527.0, "lane": 1}]
	underpass.obstacles = [
		{"s": 330.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"s": 610.0, "lanes": [-1, 0], "height": 5.0, "kind": "block"},
		{"s": 820.0, "lanes": [0], "height": 5.0, "kind": "beam", "bottom": 3.2},
	]
	underpass.next = ["return_switchback"]
	f = return_forward
	right = f.cross(Vector3.UP).normalized()
	var switchback := shaped("return_switchback", underpass.pose(underpass.length).origin, f, 400, 12, -12)
	switchback.chapter = "06 LANDMARK RETURN"
	switchback.title = "VALLEY SWITCHBACK / FINAL YARD AHEAD"
	switchback.camera_phase = "carve"
	switchback.score_carve = true
	switchback.checkpoint = true
	switchback.checkpoint_s = 30
	switchback.pads = [{"a": 40.0, "b": 52.0, "lane": 1}]
	switchback.obstacles = [
		{"s": 350.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	switchback.next = ["final_approach"]
	var approach := line("final_approach", switchback.pose(switchback.length).origin, f, 240)
	approach.chapter = "06 FINAL YARD"
	approach.title = "NO-ENTRY SIGNS / FINAL SPLIT AHEAD"
	approach.checkpoint = false
	approach.checkpoint_s = 30
	approach.checkpoint_speed = 130
	approach.pads = [{"a": 85.0, "b": 97.0, "lane": 1}]
	approach.obstacles = [
		{"s": 205.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	approach.next = ["final_ramp"]
	var ramp := line("final_ramp", approach.pose(approach.length).origin, f, 40, 7)
	ramp.chapter = "06 FINAL YARD"
	ramp.kind = "ramp"
	ramp.camera_phase = "crest"
	ramp.title = "RIDE + D: WIDE CATCH / SPACE + A: UPPER"
	ramp.release_windows = [Vector2(8, ramp.length)]
	ramp.impulse = Vector3.UP * 16 + f * 5
	var common := ramp.pose(ramp.length).origin + f * 720 - Vector3.UP * 18
	var safe_start := ramp.pose(ramp.length).origin + f * 55 + right * 4.4 - Vector3.UP * 13
	var upper_start := ramp.pose(ramp.length).origin + f * 100 - right * 4.4 + Vector3.UP * 6
	var receiver := bridge("final_receiver", safe_start, common, right, 0, 0, 0, f)
	receiver.chapter = "06 FINAL YARD"
	receiver.title = "WIDE CATCH / CENTRE FOR THE FINISH"
	receiver.entry_half_width = 5.0
	receiver.entry_taper_length = 70
	receiver.pads = [{"a": 330.0, "b": 342.0, "lane": 0}]
	receiver.obstacles = [
		{"s": 230.0, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "receiver_soft"},
		{"s": 630.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	receiver.next = ["victory_run"]
	var upper_catch := line("final_upper_catch", upper_start, f, 450, -8)
	upper_catch.chapter = "06 FINAL YARD"
	upper_catch.title = "UPPER CATCH / STABILIZE"
	upper_catch.kind = "grind"
	upper_catch.single_lane = true
	upper_catch.half_width = 1.2
	upper_catch.entry_half_width = 3.2
	upper_catch.entry_taper_length = 45
	upper_catch.camera_phase = "grind"
	upper_catch.next = ["final_upper"]
	var upper := bridge("final_upper", upper_catch.pose(upper_catch.length).origin, common, right, -130, 0, 0, f)
	upper.chapter = "06 FINAL YARD"
	upper.title = "UPPER CHALLENGE / STABILIZE WITH SHIFT"
	upper.kind = "grind"
	upper.single_lane = true
	upper.half_width = 1.2
	upper.entry_half_width = 3.2
	upper.entry_taper_length = 45
	upper.camera_phase = "grind"
	upper.next = ["victory_run"]
	air_link("final_ramp", "final_receiver", 0, ramp.length + 2, receiver.length - 20, {"intent": "natural", "screen_direction": 1, "assist": true, "default": true, "priority": 5})
	air_link("final_ramp", "final_upper_catch", 0, ramp.length + 2, upper_catch.length - 10, {"intent": "intentional", "screen_direction": -1, "assist": true, "priority": 10})
	var victory := line("victory_run", common, f, 500)
	victory.chapter = "06 FINAL YARD"
	victory.title = "CHAIN COMPLETE / CARRY IT HOME"
	victory.camera_phase = "rush"

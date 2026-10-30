class_name SpatialFullR2Route
extends SpatialFullRoute
## The faster score-attack course keeps the M1.7R route playable as a separate scene.

func _ready() -> void:
	super._ready()
	experience_revision = 2
	course_name = "SPATIAL FLOW / SPEED MASTERY"
	_index_action_zones()

func _index_action_zones() -> void:
	for track: SpatialTrack in tracks.values():
		track.action_zones.clear()
		for index in track.obstacles.size():
			var ob: Dictionary = track.obstacles[index]
			if not ob.has("id"): ob.id = "obstacle_%02d" % index
			var kind: String = ob.get("kind", "block")
			track.action_zones.append({"id": obstacle_key(track, ob), "kind": kind, "s": float(ob.s), "lanes": ob.lanes.duplicate(), "preview_seconds": 1.8 if kind != "soft" else 1.3, "safe_result": "CLEAR", "precision": "CLEAN LINE" if kind != "soft" else "NO CONTACT"})
		for index in track.pads.size():
			var pad: Dictionary = track.pads[index]
			pad.id = "%s:pulse:%02d" % [track.id, index]
			track.action_zones.append({"id": pad.id, "kind": "pulse", "s": float(pad.a), "lane": int(pad.lane), "preview_seconds": 1.3, "safe_result": "BYPASS", "precision": "FLOW BOOST"})
		for index in track.release_windows.size():
			var window: Vector2 = track.release_windows[index]
			track.action_zones.append({"id": "%s:coil:%02d" % [track.id, index], "kind": "coil", "s": window.x, "preview_seconds": 1.6, "safe_result": "RIDE", "precision": "PRECISE RELEASE"})
		if track.score_carve:
			track.action_zones.append({"id": "carve:" + track.id, "kind": "carve", "s": track.length * 0.5, "preview_seconds": 1.7, "safe_result": "BRAKE", "precision": "CLEAN CARVE"})
		track.action_zones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.s) < float(b.s))

func _build_station_and_canyon() -> void:
	_open_carve_radius()
	_reshape_tunnel()
	# The ceiling release is a powered downward eject. Without the impulse a
	# 125-175 m/s train overflies the short lower catch and hits the rollout.
	# Its physical gold device and the lower catch now describe the same action.
	var ceiling: SpatialTrack = tracks.inverted
	ceiling.impulse = Vector3.DOWN * 35.0
	ceiling.release_windows = [Vector2(ceiling.length - 90.0, ceiling.length - 1.0)]
	var lower: SpatialTrack = tracks.drop
	var lower_forward := -lower.pose(0).basis.z
	var lower_start := lower.pose(0).origin - lower_forward * 60.0
	var lower_points := PackedVector3Array()
	for index in 161:
		lower_points.append(lower_start + lower_forward * (240.0 * float(index) / 160.0))
	lower.build(lower_points)
	# The rail visibly continues into a lower receiver. Running off its end is
	# therefore a valid safe route; SPACE remains an earlier, scoreable release.
	var core_grind: SpatialTrack = tracks.grind
	# The inherited 60 m taper had already narrowed to 2 m at the actual
	# 165 m/s contact around s=379. Widen the visible deck through that catch.
	core_grind.entry_half_width = 4.0
	core_grind.entry_taper_length = 800.0
	# A clean 173 m/s exit meets the old flat rail, but a modestly slower safe
	# exit falls below it. Shape the physical receiver into a shallow catch
	# trough before its existing endpoint; the high branch remains independent.
	var grind_points := core_grind.points.duplicate()
	for index in grind_points.size():
		var along := core_grind.distances[index]
		var dip := 4.0 * pow(sin(PI * clampf((along - 310.0) / 110.0, 0.0, 1.0)), 2.0)
		var point: Vector3 = grind_points[index]
		point.y -= dip
		grind_points[index] = point
	core_grind.build(grind_points)
	core_grind.impulse = Vector3.UP * 10.0
	air_link("grind", "relay", core_grind.length - 130.0, core_grind.length + 2.0, (tracks.relay as SpatialTrack).length - 10.0,
		{"intent": "natural", "screen_direction": 1, "assist": true, "default": true, "priority": 5})
	var high_coil: SpatialTrack = tracks.exit_ramp
	# The former first metres accepted SPACE before the high trajectory could
	# meet its visible merge. Arm only where both high and safe outcomes exist.
	high_coil.release_windows = [Vector2(11.0, high_coil.length)]
	# The high-speed powered arc reaches the visible front of the continuous
	# high merge instead of the preceding short high rail.
	air_link("exit_ramp", "high_merge", 0.0, high_coil.length + 2.0, 300.0, {"intent": "intentional", "screen_direction": -1, "minimum_speed": 150.0, "priority": 12})
	var f := Vector3.FORWARD
	var right := f.cross(Vector3.UP).normalized()
	var station := line("station_start", Vector3(0, 140, 2300), f, 600, -10)
	station.chapter = "01 STATION"
	station.title = "STATION / FIND YOUR FLOW"
	station.checkpoint = true
	station.checkpoint_s = 20
	station.checkpoint_speed = 125
	station.pads = [{"a": 65.0, "b": 77.0, "lane": 0}, {"a": 305.0, "b": 317.0, "lane": -1}]
	station.obstacles = [
		{"id": "station_soft_a", "s": 145.0, "lanes": [0], "height": 2.2, "kind": "soft", "group": "station_soft_a"},
		{"id": "station_block_a", "s": 230.0, "lanes": [1], "height": 5.0, "kind": "block"},
		{"id": "station_soft_b", "s": 395.0, "lanes": [-1, 0], "height": 2.4, "kind": "soft", "group": "station_soft_b"},
		{"id": "station_block_b", "s": 520.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	station.next = ["station_carve"]
	var carve := shaped("station_carve", station.pose(station.length).origin, f, 420, 40, -30, 0, deg_to_rad(-18))
	carve.chapter = "01 STATION"
	carve.title = "CANYON GATE / HOLD THE BEND"
	carve.camera_phase = "carve"
	carve.score_carve = true
	carve.obstacles = [
		{"id": "station_carve_block", "s": 210.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"id": "station_carve_soft", "s": 310.0, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "station_carve_soft"},
	]
	carve.next = ["station_ramp"]
	var ramp := line("station_ramp", carve.pose(carve.length).origin, f, 40, 6, deg_to_rad(-18), 0)
	ramp.chapter = "02 CANYON"
	ramp.kind = "ramp"
	ramp.camera_phase = "crest"
	ramp.title = "WIDE CATCH / FAST RIDGE"
	ramp.release_windows = [Vector2(8, ramp.length)]
	ramp.impulse = Vector3.UP * 12
	var safe_start := ramp.pose(ramp.length).origin + f * 55 + right * 4.4 - Vector3.UP * 12
	var fast_start := ramp.pose(ramp.length).origin + f * 65 - right * 4.4 + Vector3.UP * 6
	var merge_start := Vector3(0, 65, 350)
	var safe := bridge("canyon_safe", safe_start, merge_start, right, 0, 0, 0, f)
	safe.chapter = "02 CANYON"
	safe.title = "CANYON / KEEP THE MOMENTUM"
	safe.camera_phase = "carve"
	safe.entry_half_width = 5.0
	safe.entry_taper_length = 65
	safe.pads = [{"a": safe.length * 0.42, "b": safe.length * 0.42 + 12.0, "lane": 1}, {"a": safe.length * 0.74, "b": safe.length * 0.74 + 12.0, "lane": -1}]
	safe.obstacles = [
		{"id": "canyon_soft_a", "s": safe.length * 0.62, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "canyon_soft_a"},
		{"id": "canyon_soft_b", "s": safe.length * 0.71, "lanes": [1], "height": 2.4, "kind": "soft", "group": "canyon_soft_b"},
		{"id": "canyon_block_a", "s": safe.length - 60.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	safe.next = ["canyon_merge"]
	var fast_catch := line("canyon_fast_catch", fast_start, f, 185, -8)
	fast_catch.chapter = "02 CANYON"
	fast_catch.title = "FAST CATCH / STABILIZE"
	fast_catch.kind = "grind"
	fast_catch.single_lane = true
	fast_catch.half_width = 2.2
	fast_catch.entry_half_width = 3.8
	fast_catch.entry_taper_length = 50
	fast_catch.camera_phase = "grind"
	fast_catch.next = ["canyon_fast"]
	var fast := bridge("canyon_fast", fast_catch.pose(fast_catch.length).origin, merge_start, right, -110, 0, 0, f)
	fast.chapter = "02 CANYON"
	fast.title = "FAST RIDGE / CLEAN MERGE"
	fast.kind = "clip"
	fast.single_lane = true
	fast.half_width = 2.2
	fast.camera_phase = "grind"
	fast.pads = [{"a": fast.length * 0.56, "b": fast.length * 0.56 + 12.0, "lane": 0}]
	fast.next = ["canyon_merge"]
	air_link("station_ramp", "canyon_safe", 0, ramp.length + 2, safe.length - 20, {"intent": "natural", "screen_direction": 1, "assist": true, "default": true, "priority": 5})
	air_link("station_ramp", "canyon_fast_catch", 0, ramp.length + 2, fast_catch.length - 10, {"intent": "intentional", "screen_direction": -1, "assist": true, "priority": 10})
	var merge := line("canyon_merge", merge_start, f, 350)
	merge.chapter = "02 CANYON"
	merge.title = "MERGE / WALL AHEAD"
	merge.checkpoint = true
	merge.checkpoint_s = 35
	merge.checkpoint_speed = 150
	merge.obstacles = [{"id": "merge_soft", "s": 85.0, "lanes": [0], "height": 2.0, "kind": "soft", "group": "merge_soft"}]
	merge.next = ["rush"]
	var rush: SpatialTrack = tracks.rush
	rush.checkpoint = false
	rush.checkpoint_speed = 150
	rush.obstacles = [{"id": "rush_block", "s": 265.0, "lanes": [-1, 0], "height": 5.0, "kind": "block"}]
	(tracks.loop_entry as SpatialTrack).checkpoint_speed = 150
	(tracks.relay as SpatialTrack).checkpoint_speed = 150

func _open_carve_radius() -> void:
	var carve: SpatialTrack = tracks.carve
	var old_end := carve.pose(carve.length).origin
	var origin := carve.pose(0).origin
	var angle := deg_to_rad(75.0)
	var radius := 260.0
	var points := PackedVector3Array()
	for index in 241:
		var t := float(index) / 240.0
		points.append(origin + Vector3(radius * (1.0 - cos(angle * t)), 8.0 * smoothstep(0, 1, t), -radius * sin(angle * t)))
	carve.build(points, 0, PI * 0.5)
	var shift := carve.pose(carve.length).origin - old_end
	for id in ["wall", "inverted", "drop", "rollout", "loop_entry", "loop", "loop_out", "exit_ramp", "grind", "relay", "high", "high_merge", "tunnel", "cliff_turn", "cliff_lip", "upper", "rescue", "rescue_merge", "finish"]:
		var track: SpatialTrack = tracks[id]
		for index in track.points.size(): track.points[index] += shift
		track.bounds.position += shift

func _reshape_tunnel() -> void:
	var tunnel: SpatialTrack = tracks.tunnel
	var start := tunnel.pose(0)
	var old_end := tunnel.pose(tunnel.length).origin
	var forward := -start.basis.z
	var right := start.basis.x
	var points := PackedVector3Array()
	for i in 481:
		var t := float(i) / 480.0
		var bend := pow(sin(PI * t), 2)
		points.append(start.origin + forward * 1400.0 * t + right * 125.0 * bend + Vector3.UP * 14.0 * bend)
	tunnel.build(points)
	tunnel.ceiling = 18.0
	tunnel.enclosure_half_width = 38.0
	tunnel.pads = [{"a": tunnel.length * 0.27, "b": tunnel.length * 0.27 + 12.0, "lane": 1}, {"a": tunnel.length * 0.72, "b": tunnel.length * 0.72 + 12.0, "lane": -1}]
	tunnel.obstacles = [
		{"id": "tunnel_block_a", "s": tunnel.length * 0.18, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"id": "tunnel_beam_a", "s": tunnel.length * 0.34, "lanes": [0], "height": 5.0, "bottom": 3.2, "kind": "beam"},
		{"id": "tunnel_soft", "s": tunnel.length * 0.46, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "tunnel_soft"},
		{"id": "tunnel_block_b", "s": tunnel.length * 0.61, "lanes": [-1, 0], "height": 5.0, "kind": "block"},
		{"id": "tunnel_beam_b", "s": tunnel.length * 0.78, "lanes": [0], "height": 5.0, "bottom": 3.2, "kind": "beam"},
		{"id": "tunnel_block_c", "s": tunnel.length * 0.91, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	var shift := tunnel.pose(tunnel.length).origin - old_end
	for id in ["cliff_turn", "cliff_lip", "upper", "rescue", "rescue_merge", "finish"]:
		var track: SpatialTrack = tracks[id]
		for index in track.points.size(): track.points[index] += shift
		track.bounds.position += shift
	# At 175 m/s the unassisted lower-error trajectory reaches beyond the old
	# 220 m upper rail. Lengthen the visible physical receiver, not its hitbox.
	var upper: SpatialTrack = tracks.upper
	var upper_origin := upper.pose(0).origin
	var upper_forward := -upper.pose(0).basis.z
	var upper_points := PackedVector3Array()
	for index in 229:
		upper_points.append(upper_origin + upper_forward * (340.0 * float(index) / 228.0))
	upper.build(upper_points)
	upper.release_windows = [Vector2(upper.length - 80.0, upper.length)]
	for link in upper.connections:
		if link.target == "finish": link.from = upper.length - 80.0; link.until = upper.length + 2.0
	for link in (tracks.cliff_lip as SpatialTrack).connections:
		if link.target == "upper": link.b = upper.length - 10.0
	var finish: SpatialTrack = tracks.finish
	var finish_origin := finish.pose(0).origin + upper_forward * 140.0
	var finish_forward := -finish.pose(0).basis.z
	var finish_points := PackedVector3Array()
	for index in 321:
		finish_points.append(finish_origin + finish_forward * (480.0 * float(index) / 320.0))
	finish.build(finish_points)
	for link in upper.connections:
		if link.target == "finish": link.b = finish.length - 10.0
	var rescue: SpatialTrack = tracks.rescue
	var rescue_origin := rescue.pose(0).origin
	var rescue_forward := -rescue.pose(0).basis.z
	var rescue_points := PackedVector3Array()
	for index in 349:
		rescue_points.append(rescue_origin + rescue_forward * (520.0 * float(index) / 348.0))
	rescue.build(rescue_points)
	var rescue_merge: SpatialTrack = tracks.rescue_merge
	for index in rescue_merge.points.size(): rescue_merge.points[index] += rescue_forward * 140.0
	rescue_merge.bounds.position += rescue_forward * 140.0
	for link in (tracks.cliff_lip as SpatialTrack).connections:
		if link.target == "rescue": link.b = rescue.length - 10.0

func _build_landmark_finale() -> void:
	var finish: SpatialTrack = tracks.finish
	var f := -finish.pose(finish.length).basis.z
	var right := finish.pose(finish.length).basis.x
	finish.title = "VALLEY EXIT / RETURN THROUGH THE BRIDGE"
	finish.next = ["landmark_return"]
	var bridge_track: SpatialTrack = tracks.cliff_turn
	var bridge_frame := bridge_track.pose(bridge_track.length * 0.52)
	var return_forward := bridge_frame.basis.x
	return_forward.y = 0
	return_forward = return_forward.normalized()
	var underpass_mid := bridge_frame.origin - Vector3.UP * 19.0
	var underpass_start := underpass_mid - return_forward * 300.0
	var turnaround := PackedVector3Array()
	var origin := finish.pose(finish.length).origin
	var turn_side := -right
	var radius := 300.0
	for i in 181:
		var angle := PI * float(i) / 180.0
		turnaround.append(origin + turn_side * radius * (1.0 - cos(angle)) + f * radius * sin(angle))
	var turn_end := turnaround[-1]
	var span := turn_end.distance_to(underpass_start)
	for i in range(1, 301):
		var t := float(i) / 300.0
		var t2 := t * t
		var t3 := t2 * t
		turnaround.append(turn_end * (2 * t3 - 3 * t2 + 1) - f * span * (t3 - 2 * t2 + t) + underpass_start * (-2 * t3 + 3 * t2) + return_forward * span * (t3 - t2))
	var landmark := add_track("landmark_return", turnaround)
	landmark.chapter = "05 MULTILEVEL VALLEY"
	landmark.title = "RETURN BEND / HOLD SPEED OR BRAKE"
	landmark.camera_phase = "carve"
	landmark.score_carve = true
	landmark.checkpoint = true
	landmark.checkpoint_s = 30
	landmark.pads = [{"a": landmark.length * 0.24, "b": landmark.length * 0.24 + 12.0, "lane": 0}, {"a": landmark.length * 0.67, "b": landmark.length * 0.67 + 12.0, "lane": 1}]
	landmark.obstacles = [
		{"id": "return_block_a", "s": landmark.length * 0.65, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"id": "return_soft", "s": landmark.length * 0.73, "lanes": [-1], "height": 2.3, "kind": "soft", "group": "return_soft"},
		{"id": "return_block_b", "s": landmark.length * 0.80, "lanes": [0, 1], "height": 5.0, "kind": "block"},
	]
	landmark.next = ["underpass"]
	var underpass := line("underpass", underpass_start, return_forward, 520)
	underpass.chapter = "06 LANDMARK RETURN"
	underpass.title = "UNDER THE SAME BRIDGE / HOLD YOUR LINE"
	underpass.enclosure = "tunnel"
	underpass.ceiling = 18
	underpass.camera_phase = "tunnel"
	underpass.checkpoint = true
	underpass.checkpoint_s = 110
	underpass.checkpoint_speed = 150
	underpass.pads = [{"a": 85.0, "b": 97.0, "lane": -1}, {"a": 215.0, "b": 227.0, "lane": 1}]
	underpass.obstacles = [
		{"id": "underpass_block_a", "s": 90.0, "lanes": [0, 1], "height": 5.0, "kind": "block"},
		{"id": "underpass_block_b", "s": 485.0, "lanes": [-1, 0], "height": 5.0, "kind": "block"},
	]
	underpass.next = ["return_switchback"]
	f = return_forward
	right = f.cross(Vector3.UP).normalized()
	var switchback := shaped("return_switchback", underpass.pose(underpass.length).origin, f, 250, 10, -12)
	switchback.chapter = "06 LANDMARK RETURN"
	switchback.title = "FINAL SWITCH / KEEP THE COMBO"
	switchback.camera_phase = "carve"
	switchback.score_carve = true
	switchback.checkpoint = false
	switchback.pads = [{"a": 35.0, "b": 47.0, "lane": 1}]
	switchback.obstacles = [{"id": "switch_block", "s": 220.0, "lanes": [0, 1], "height": 5.0, "kind": "block"}]
	switchback.next = ["final_approach"]
	var approach := line("final_approach", switchback.pose(switchback.length).origin, f, 175)
	approach.chapter = "06 FINAL YARD"
	approach.title = "FINAL SPLIT / SAFE OR PRECISE"
	approach.pads = [{"a": 45.0, "b": 57.0, "lane": 1}]
	approach.obstacles = [{"id": "final_block", "s": 135.0, "lanes": [0, 1], "height": 5.0, "kind": "block"}]
	approach.next = ["final_ramp"]
	var ramp := line("final_ramp", approach.pose(approach.length).origin, f, 40, 7)
	ramp.chapter = "06 FINAL YARD"
	ramp.kind = "ramp"
	ramp.camera_phase = "crest"
	ramp.title = "WIDE CATCH / UPPER CHALLENGE"
	ramp.release_windows = [Vector2(8, ramp.length)]
	ramp.impulse = Vector3.UP * 16 + f * 5
	var common := ramp.pose(ramp.length).origin + f * 950 - Vector3.UP * 18
	var safe_start := ramp.pose(ramp.length).origin + f * 55 + right * 4.4 - Vector3.UP * 13
	var upper_start := ramp.pose(ramp.length).origin + f * 300 - right * 4.4 + Vector3.UP * 6
	var receiver := bridge("final_receiver", safe_start, common, right, 0, 0, 0, f)
	receiver.chapter = "06 FINAL YARD"
	receiver.title = "WIDE CATCH / HOLD THE FINISH"
	receiver.entry_half_width = 5.0
	receiver.entry_taper_length = 70
	receiver.pads = [{"a": 260.0, "b": 272.0, "lane": 0}]
	receiver.obstacles = [{"id": "receiver_soft", "s": 210.0, "lanes": [-1], "height": 2.2, "kind": "soft", "group": "receiver_soft"}, {"id": "receiver_block", "s": 820.0, "lanes": [0, 1], "height": 5.0, "kind": "block"}]
	receiver.next = ["victory_run"]
	var upper_catch := line("final_upper_catch", upper_start, f, 420, -8)
	upper_catch.chapter = "06 FINAL YARD"
	upper_catch.title = "UPPER CATCH / NO ASSIST BONUS"
	upper_catch.kind = "grind"
	upper_catch.single_lane = true
	upper_catch.half_width = 1.2
	upper_catch.entry_half_width = 3.2
	upper_catch.entry_taper_length = 45
	upper_catch.camera_phase = "grind"
	upper_catch.next = ["final_upper"]
	var upper := bridge("final_upper", upper_catch.pose(upper_catch.length).origin, common, right, -90, 0, 0, f)
	upper.chapter = "06 FINAL YARD"
	upper.title = "UPPER CHALLENGE / CLEAN MERGE"
	upper.kind = "grind"
	upper.single_lane = true
	upper.half_width = 1.2
	upper.entry_half_width = 3.2
	upper.entry_taper_length = 45
	upper.camera_phase = "grind"
	upper.next = ["victory_run"]
	air_link("final_ramp", "final_receiver", 0, ramp.length + 2, receiver.length - 20, {"intent": "natural", "screen_direction": 1, "assist": true, "default": true, "priority": 5})
	air_link("final_ramp", "final_upper_catch", 0, ramp.length + 2, upper_catch.length - 10, {"intent": "intentional", "screen_direction": -1, "assist": true, "priority": 10})
	var victory := line("victory_run", common, f, 220)
	victory.chapter = "06 FINAL YARD"
	victory.title = "COURSE COMPLETE / CARRY THE SPEED"
	victory.camera_phase = "rush"
	victory.checkpoint = false

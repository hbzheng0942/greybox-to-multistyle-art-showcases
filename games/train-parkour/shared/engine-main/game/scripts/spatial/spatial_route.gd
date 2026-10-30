class_name SpatialRoute
extends RailRoute
## Compatibility facade only. The solver owns track identity and world velocity.

var tracks: Dictionary = {}
var current: SpatialTrack
var start_id := "rush"
var preview_id := ""
var camera_solids: Array[Dictionary] = []
var camera_solid_cells: Dictionary = {}
var camera_solid_large: Array[int] = []
const SOLID_CELL := 128.0
var course_name := "SPATIAL FLOW / HUMAN-GATE SLICE"
var full_course := false
var experience_revision := 1

func _ready() -> void:
	_build_slice()
	activate(start_id)

func activate(id: String) -> void:
	current = tracks[id]
	length = current.length
	preview_id = current.next[0] if not current.next.is_empty() else ""

func pose_at(s: float, side := 0.0) -> Transform3D:
	return global_transform * current.pose(s, side)

func track_pose(id: String, s: float, side := 0.0) -> Transform3D:
	return global_transform * (tracks[id] as SpatialTrack).pose(s, side)

func closest_distance(p: Vector3) -> float:
	return current.nearest(to_local(p))

func has_track(s: float) -> bool:
	return s >= 0 and s <= current.length

func index_camera_solids() -> void:
	camera_solid_cells.clear()
	camera_solid_large.clear()
	for index in camera_solids.size():
		var bounds: AABB = camera_solids[index].bounds
		var low := Vector2i(floori(bounds.position.x / SOLID_CELL), floori(bounds.position.z / SOLID_CELL))
		var high := Vector2i(floori(bounds.end.x / SOLID_CELL), floori(bounds.end.z / SOLID_CELL))
		if (high.x - low.x + 1) * (high.y - low.y + 1) > 32:
			camera_solid_large.append(index)
			continue
		for x in range(low.x, high.x + 1):
			for z in range(low.y, high.y + 1):
				var key := Vector2i(x, z)
				if not camera_solid_cells.has(key): camera_solid_cells[key] = []
				camera_solid_cells[key].append(index)

func solids_near(bounds: AABB) -> Array[Dictionary]:
	if camera_solid_cells.is_empty(): return camera_solids
	var low := Vector2i(floori(bounds.position.x / SOLID_CELL), floori(bounds.position.z / SOLID_CELL))
	var high := Vector2i(floori(bounds.end.x / SOLID_CELL), floori(bounds.end.z / SOLID_CELL))
	var found: Dictionary = {}
	for index in camera_solid_large: found[index] = true
	for x in range(low.x, high.x + 1):
		for z in range(low.y, high.y + 1):
			for index in camera_solid_cells.get(Vector2i(x, z), []): found[index] = true
	var result: Array[Dictionary] = []
	for index in found: result.append(camera_solids[index])
	return result

func lanes_at(_s: float) -> Array[int]:
	return current.lanes()

func section_at(_s: float) -> String:
	return current.title

func obstacle_key(track: SpatialTrack, obstacle: Dictionary) -> String:
	var identity: String = str(obstacle.get("id", "%s-%d-%s" % [obstacle.get("kind", "block"), roundi(float(obstacle.s) * 100.0), str(obstacle.lanes)]))
	return track.id + ":" + identity

func turn_direction(s: float) -> float:
	return current.curvature(s).x * 35.0

func add_track(id: String, points: PackedVector3Array, bank0 := 0.0, bank1 := 0.0, normals := PackedVector3Array()) -> SpatialTrack:
	var track := SpatialTrack.new()
	track.id = id
	track.build(points, bank0, bank1, normals)
	tracks[id] = track
	return track

func line(id: String, origin: Vector3, forward: Vector3, span: float, rise := 0.0, bank0 := 0.0, bank1 := 0.0) -> SpatialTrack:
	var points := PackedVector3Array()
	var count := ceili(span / 1.5)
	for i in range(count + 1):
		var t := float(i) / count
		points.append(origin + forward * span * t + Vector3.UP * rise * t)
	return add_track(id, points, bank0, bank1)

func shaped(id: String, origin: Vector3, forward: Vector3, span: float, side: float, rise: float, bank0 := 0.0, bank1 := 0.0) -> SpatialTrack:
	var right := forward.cross(Vector3.UP).normalized()
	var points := PackedVector3Array()
	for i in 201:
		var t := float(i) / 200
		points.append(origin + forward * span * t + right * side * pow(sin(PI * t), 2) + Vector3.UP * rise * smoothstep(0, 1, t))
	return add_track(id, points, bank0, bank1)

func air_link(source: String, target: String, from_s: float, end_s: float, capture_end := INF, options: Dictionary = {}) -> void:
	var track: SpatialTrack = tracks[source]
	var link := {"source": source, "target": target, "from": from_s, "until": end_s, "a": 0.0, "b": minf(capture_end, tracks[target].length), "minimum_speed": 15.0, "intent": "any", "screen_direction": 0, "priority": 0, "assist": false}
	link.merge(options, true)
	track.connections.append(link)

func _build_slice() -> void:
	var rush := shaped("rush", Vector3(0, 65, 0), Vector3.FORWARD, 280, 0, -20)
	rush.title = "RIGHT PULSE / CENTRE EXIT"
	rush.camera_phase = "rush"
	rush.checkpoint = true
	rush.pads = [{"a": 140.0, "b": 152.0, "lane": 1}]
	rush.obstacles = [{"s": 240.0, "lanes": [1], "height": 5.0}]
	rush.next = ["carve"]
	var origin := rush.pose(rush.length).origin
	var points := PackedVector3Array()
	var angle := deg_to_rad(75)
	var radius := 150.0
	for i in 141:
		var t := float(i) / 140
		points.append(origin + Vector3(radius * (1 - cos(angle * t)), 8 * smoothstep(0, 1, t), -radius * sin(angle * t)))
	var carve := add_track("carve", points, 0, PI * 0.5)
	carve.title = "SHIFT + D / CARVE INTO THE WALL"
	carve.camera_phase = "carve"
	carve.kind = "clip"
	carve.next = ["wall"]
	var f := Vector3(sin(angle), 0, -cos(angle))
	var right := f.cross(Vector3.UP).normalized()
	var wall := line("wall", carve.pose(carve.length).origin, f, 160, 0, PI * 0.5, PI * 0.5)
	wall.kind = "wall"
	wall.single_lane = true
	wall.half_width = 2.2
	wall.camera_phase = "wall"
	wall.title = "SPACE AT COIL / CATCH THE CEILING"
	wall.release_windows = [Vector2(wall.length - 50, wall.length - 2)]
	wall.impulse = Vector3.UP * 30 + right * 12
	origin = wall.pose(wall.length).origin
	var inverted := line("inverted", origin + f * 10 + right * 6 + Vector3.UP * 12, f, 165, 0, PI, PI)
	inverted.kind = "inverted"
	inverted.single_lane = true
	inverted.half_width = 3.0
	inverted.camera_phase = "inverted"
	inverted.title = "SPACE: DROP / HOLD: SAFE ROLLOUT"
	inverted.release_windows = [Vector2(inverted.length - 55, inverted.length - 1)]
	air_link("wall", "inverted", 90, wall.length + 2, 145, {"intent": "intentional", "assist": true, "assist_time": 1.2, "assist_max_error": 14.0, "priority": 10})
	origin = inverted.pose(inverted.length).origin
	var drop := line("drop", origin + f * 15 - Vector3.UP * 22, f, 180)
	drop.title = "D: RIGHT PULSE AHEAD / THEN CENTRE FOR LOOP"
	drop.camera_phase = "landing"
	drop.next = ["loop_entry"]
	air_link("inverted", "drop", 95, inverted.length + 2, 175, {"intent": "intentional", "assist": true, "assist_time": 1.4, "assist_max_error": 14.0, "priority": 10})
	var rollout := shaped("rollout", origin, f, 195, -90, -22, PI, 0)
	rollout.title = "SAFE ROLLOUT / LONGER ROUTE"
	rollout.kind = "clip"
	rollout.single_lane = true
	rollout.half_width = 3
	rollout.camera_phase = "inverted"
	rollout.next = ["loop_entry"]
	inverted.next = ["rollout"]
	var entry := line("loop_entry", drop.pose(drop.length).origin, f, 140)
	entry.title = "RIGHT PULSE / RETURN CENTRE BEFORE THE CLAMP"
	entry.pads = [{"a": 60.0, "b": 72.0, "lane": 1}]
	entry.camera_phase = "crest"
	entry.checkpoint = true
	entry.next = ["loop"]
	origin = entry.pose(entry.length).origin
	points = PackedVector3Array()
	var normals := PackedVector3Array()
	radius = 38
	for i in 481:
		var t := float(i) / 480
		var theta := TAU * t
		points.append(origin + f * radius * sin(theta) + Vector3.UP * radius * (1 - cos(theta)) + right * 20 * smoothstep(0, 1, t))
		normals.append(Vector3.UP * cos(theta) - f * sin(theta))
	var loop := add_track("loop", points, 0, 0, normals)
	loop.kind = "loop"
	loop.single_lane = true
	loop.half_width = 2.5
	loop.camera_phase = "loop"
	loop.title = "RIDE THE FULL LOOP / PREPARE EXIT"
	loop.next = ["loop_out"]
	var loop_out := line("loop_out", loop.pose(loop.length).origin, f, 90)
	loop_out.title = "RIDE + D: RIGHT GRIND / SPACE + A: HIGH"
	loop_out.camera_phase = "crest"
	loop_out.next = ["exit_ramp"]
	var ramp := line("exit_ramp", loop_out.pose(loop_out.length).origin, f, 30, 4.5)
	ramp.kind = "ramp"
	ramp.camera_phase = "crest"
	ramp.title = "SPACE + A: HIGH / RIDE + D: RIGHT GRIND"
	ramp.release_windows = [Vector2(4, ramp.length)]
	ramp.impulse = Vector3.UP * 8
	origin = ramp.pose(ramp.length).origin
	var grind := line("grind", origin + f * 15 + right * 6.8 - Vector3.UP * 4, f, 480)
	grind.kind = "grind"
	grind.single_lane = true
	grind.half_width = 2.0
	grind.entry_half_width = 4.0
	grind.entry_taper_length = 500.0
	grind.camera_phase = "grind"
	grind.title = "SPACE AT COIL / AIM RIGHT"
	grind.release_windows = [Vector2(grind.length - 65, grind.length - 5)]
	grind.impulse = Vector3.UP * 15
	var relay := line("relay", grind.pose(grind.length).origin + f * 12 + right * 6.8 - Vector3.UP * 7, f, 330)
	relay.title = "RECONNECT / TUNNEL LEFT-RIGHT-CENTRE"
	relay.camera_phase = "landing"
	relay.checkpoint = true
	relay.next = ["tunnel"]
	var high := line("high", origin + f * 100 - right * 6.8 + Vector3.UP * 10, f, 260)
	high.title = "HIGH BYPASS / CARRY HEIGHT INTO SPEED"
	high.single_lane = true
	high.half_width = 2.5
	high.kind = "clip"
	high.camera_phase = "grind"
	high.next = ["high_merge"]
	var high_merge := shaped("high_merge", high.pose(high.length).origin, f, 477, -90, -21)
	# Offset shifts continuously to the common relay endpoint; endpoints stay coincident.
	for i in high_merge.points.size():
		var t := float(i) / (high_merge.points.size() - 1)
		high_merge.points[i] += right * 20.4 * smoothstep(0, 1, t)
	high_merge.build(high_merge.points)
	high_merge.title = "HIGH ROUTE / MERGE AT THE TUNNEL"
	high_merge.camera_phase = "carve"
	high_merge.next = ["tunnel"]
	air_link("exit_ramp", "grind", 0, ramp.length + 2, 465, {"intent": "natural", "screen_direction": 1, "assist": true, "assist_time": 3.0, "assist_max_error": 40.0, "priority": 5})
	air_link("exit_ramp", "high", 0, ramp.length + 2, 285, {"intent": "intentional", "screen_direction": -1, "assist": false, "priority": 10})
	air_link("grind", "relay", grind.length - 75, grind.length + 2, 280, {"intent": "intentional", "screen_direction": 1, "assist": true, "assist_time": 1.5, "assist_max_error": 14.0, "priority": 10})
	var tunnel := line("tunnel", relay.pose(relay.length).origin, f, 340)
	tunnel.title = "TUNNEL / LEFT - RIGHT - CENTRE"
	tunnel.enclosure = "tunnel"
	tunnel.ceiling = 13.5
	tunnel.camera_phase = "tunnel"
	tunnel.obstacles = [{"s": 100.0, "lanes": [0, 1], "height": 5.0}, {"s": 210.0, "lanes": [-1, 0], "height": 5.0}, {"s": 300.0, "lanes": [-1, 1], "height": 5.0}]
	tunnel.next = ["cliff_turn"]
	origin = tunnel.pose(tunnel.length).origin
	points = PackedVector3Array()
	for i in 121:
		var t := float(i) / 120
		var theta := deg_to_rad(45) * t
		points.append(origin + f * 210 * sin(theta) - right * 210 * (1 - cos(theta)) - Vector3.UP * 10 * smoothstep(0, 1, t))
	var cliff := add_track("cliff_turn", points, 0, deg_to_rad(-25))
	cliff.title = "SHIFT + A / OPEN THE CANYON"
	cliff.camera_phase = "carve"
	cliff.enclosure = "canyon"
	cliff.next = ["cliff_lip"]
	f = f.rotated(Vector3.UP, deg_to_rad(45))
	right = f.cross(Vector3.UP).normalized()
	var lip := line("cliff_lip", cliff.pose(cliff.length).origin, f, 26, 3.64, deg_to_rad(-25), 0)
	lip.title = "95+ M/S: D HIGH / A LOW - MISSES CAN BE SAVED"
	lip.kind = "ramp"
	lip.camera_phase = "crest"
	origin = lip.pose(lip.length).origin
	var upper := line("upper", origin + f * 120 + right * 6.8 - Vector3.UP * 6, f, 220)
	upper.kind = "grind"
	upper.single_lane = true
	upper.half_width = 2.0
	upper.entry_half_width = 4.0
	upper.entry_taper_length = 160.0
	upper.title = "UPPER LINE / SPACE AT FINAL COIL - AIM LEFT"
	upper.camera_phase = "grind"
	upper.release_windows = [Vector2(upper.length - 50, upper.length)]
	upper.impulse = Vector3.UP * 39 + f * 12
	var rescue := line("rescue", origin + f * 20 - right * 6.8 - Vector3.UP * 30, f, 380)
	rescue.single_lane = true
	rescue.half_width = 1.6
	rescue.entry_half_width = 4.0
	rescue.entry_taper_length = 48.0
	rescue.kind = "rescue"
	rescue.title = "SAVED / LOWER LINE HAS A COST"
	rescue.camera_phase = "rescue"
	rescue.next = ["rescue_merge"]
	var detour := shaped("rescue_merge", rescue.pose(rescue.length).origin, f, 260, -100, 24)
	for i in detour.points.size():
		var t := float(i) / (detour.points.size() - 1)
		detour.points[i] += right * 6.8 * smoothstep(0, 1, t)
	detour.build(detour.points)
	detour.title = "LOW ROUTE / CLIMB BACK TO THE MERGE"
	detour.kind = "clip"
	detour.single_lane = true
	detour.half_width = 2.5
	detour.camera_phase = "carve"
	detour.next = ["finish"]
	air_link("cliff_lip", "upper", 0, lip.length + 2, 215, {"intent": "natural", "screen_direction": 1, "minimum_speed": 95.0, "assist": true, "assist_time": 1.5, "assist_max_error": 14.0, "priority": 10, "fallback_target": "rescue"})
	air_link("cliff_lip", "rescue", 0, lip.length + 2, 375, {"intent": "natural", "screen_direction": -1, "preferred_maximum_speed": 95.0, "assist": true, "assist_time": 2.5, "assist_max_error": 16.0, "priority": 5})
	var finish := line("finish", origin + f * 660 - Vector3.UP * 6, f, 240)
	air_link("upper", "finish", upper.length - 50, upper.length + 2, 235, {"intent": "intentional", "screen_direction": -1, "assist": true, "assist_time": 4.0, "assist_max_error": 100.0, "priority": 10})
	finish.title = "CHAIN COMPLETE / CARRY IT HOME"
	finish.camera_phase = "rush"

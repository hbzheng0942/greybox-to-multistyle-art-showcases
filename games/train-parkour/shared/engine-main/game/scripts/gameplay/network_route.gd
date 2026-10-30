class_name NetworkRoute
extends FlowRoute
## Flow-compatible facade; distance is segment-local, not a fictitious global rail.

@export_enum("ramp", "sentence", "integration", "full") var layout := "ramp"
@export var mirror := 1.0
var segments: Dictionary = {}
var current: RoadSegment
var start_id := "approach"
var preview_next := ""


func _ready() -> void:
	course = FlowCourse.new()
	course.obstacles = []
	course.jumps = []
	course.turns = []
	course.fork_start = INF
	course.fork_end = INF
	stunts = StuntProfile.new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--layout=") and argument.get_slice("=", 1) in ["ramp", "sentence", "integration", "full"]:
			layout = argument.get_slice("=", 1)
	build()
	activate(start_id)


func activate(id: String) -> void:
	current = segments[id]
	curve = current.curve
	length = current.length
	course.turns = current.turns
	preview_next = current.next[0] if not current.next.is_empty() else ""


func pose_at(s: float, side: float = 0.0) -> Transform3D:
	if current == null: return Transform3D.IDENTITY
	if s > length and not preview_next.is_empty():
		return segment_pose(preview_next, s - length, side)
	var pose := segment_pose(current.id, clampf(s, 0, length), side)
	if s < 0 or s > length:
		pose.origin += -pose.basis.z * (s if s < 0 else s - length)
	return pose


func segment_pose(id: String, s: float, side: float = 0.0) -> Transform3D:
	return global_transform * (segments[id] as RoadSegment).pose(s, side)


func has_track(s: float) -> bool:
	return s >= 0 and s <= length


func lanes_at(_s: float) -> Array[int]:
	return current.lanes()


func section_at(_s: float) -> String:
	return current.title


func add_segment(id: String, points: PackedVector3Array, support := "wide", width := 6.5) -> RoadSegment:
	var segment := RoadSegment.new()
	segment.id = id
	segment.support = support
	segment.half_width = width
	segment.order = segments.size()
	segment.curve.bake_interval = 1.0
	for p in points: segment.curve.add_point(p)
	segment.length = segment.curve.get_baked_length()
	segments[id] = segment
	return segment


func line(id: String, origin: Vector3, forward: Vector3, span: float, rise := 0.0, support := "wide", width := 6.5) -> RoadSegment:
	var points := PackedVector3Array()
	var steps := ceili(span / 4.0)
	for i in range(steps + 1):
		var t := float(i) / steps
		points.append(origin + forward * (span * t) + Vector3.UP * rise * t)
	return add_segment(id, points, support, width)


func connect_air(source: String, target: String, from_s: float = 0.0, target_end: float = 280.0) -> void:
	var segment: RoadSegment = segments[source]
	segment.connections.append({"source": source, "target": target, "from": from_s, "until": segment.length + 2, "target_from": 0.0, "target_end": minf(target_end, segments[target].length), "min_speed": 15.0, "max_speed": 160.0})


func build() -> void:
	if layout == "sentence":
		_build_sentence()
		return
	if layout in ["integration", "full"]:
		_build_integration()
		if layout == "full": _expand_full()
		return
	_build_ramp()


func _build_ramp() -> void:
	var approach := line("approach", Vector3(0, 90, 0), Vector3.FORWARD, 500)
	approach.title = "B / CYAN BOOST - GOLD RAMP / SPACE CHANGES YOUR ARC"
	approach.mechanism = "B01"
	approach.boosts = [{"start": 250.0, "end": 262.0, "lane": 0}]
	approach.next = ["ramp"]
	var ramp := line("ramp", approach.pose(approach.length).origin, Vector3.FORWARD, 32, 5.76)
	ramp.title = "R01 / NATURAL EXIT OR SPACE - NO TARGET ASSIST"
	ramp.mechanism = "R01"
	ramp.launch_start = 0
	ramp.launch_end = ramp.length
	ramp.launch_impulse = 8.0
	ramp.checkpoint = false
	var catch := line("catch", ramp.pose(ramp.length).origin + Vector3(0, -4, -12), Vector3.FORWARD, 520)
	catch.title = "B / WIDE RECONNECT"
	connect_air("ramp", "catch", 0, 420)


func _build_sentence() -> void:
	var approach := line("approach", Vector3(0, 90, 0), Vector3.FORWARD, 280)
	approach.title = "B01 / CENTRE CYAN BOOST"
	approach.boosts = [{"start": 140.0, "end": 152.0, "lane": 0}]
	approach.next = ["ramp"]
	var ramp := line("ramp", approach.pose(approach.length).origin, Vector3.FORWARD, 28, 5.04)
	ramp.title = "R01 / RIDE THE RAMP - LAND ON GOLD"
	ramp.mechanism = "R01"
	ramp.launch_start = 0
	ramp.launch_end = ramp.length
	ramp.launch_impulse = 8.0
	ramp.checkpoint = false
	var grind := line("grind", ramp.pose(ramp.length).origin + Vector3(0, -4, -10), Vector3.FORWARD, 480, 0, "grind", 0.9)
	grind.title = "G01 / SPACE NEAR END - AIM RIGHT" if mirror > 0 else "G01 / SPACE NEAR END - AIM LEFT"
	grind.mechanism = "G01"
	grind.checkpoint = false
	grind.launch_start = grind.length - 54
	grind.launch_end = grind.length - 38
	grind.launch_impulse = 15
	connect_air("ramp", "grind", 0, 355)
	var catch := line("relay", grind.pose(grind.length).origin + Vector3(6.8 * mirror, -7, -12), Vector3.FORWARD, 320)
	catch.title = "T01 / RECONNECT - KEEP MOVING"
	catch.mechanism = "T01"
	connect_air("grind", "relay", grind.length - 100, 250)


func _build_integration() -> void:
	_build_sentence()
	var entry: RoadSegment = segments.relay
	entry.title = "H01 / LEFT: DIVE FOR ENERGY / CENTRE: SHORT HIGH LINE"
	entry.next = ["high", "dive"]
	var origin := entry.pose(entry.length).origin
	var high := line("high", origin, Vector3.FORWARD, 480, -20, "wide", 3.0)
	high.title = "H01 / SHORT HIGH LINE - LOW BEAM: STAY DOWN"
	high.obstacles = [{"s": 250.0, "lanes": [0], "kind": "beam", "bottom": 4.6, "height": 1.2}]
	high.next = ["arc"]
	var points := PackedVector3Array()
	for i in 161:
		var t := float(i) / 160
		points.append(origin + Vector3(-100 * sin(PI * t), -20 * t - 78 * sin(PI * t), -480 * t))
	var dive := add_segment("dive", points)
	dive.title = "X2 / FAST DIVE - LEFT PULSE THEN RIGHT GAP"
	dive.obstacles = [{"s": 120.0, "lanes": [0, 1], "height": 5.0}, {"s": 315.0, "lanes": [-1, 0], "height": 5.0}]
	dive.mechanism = "H01"
	dive.checkpoint_s = 350.0
	dive.boosts = [{"start": 210.0, "end": 222.0, "lane": -1}]
	dive.next = ["arc"]
	origin = high.pose(high.length).origin
	points = PackedVector3Array()
	for i in 86:
		var s := i * 4.0
		points.append(origin + Vector3(0, 0.00055 * pow(maxf(0, s - 120), 2), -s))
	var arc := add_segment("arc", points, "wide", 3.0)
	arc.title = "X1 / VIOLET SPACE + A: LOW / GOLD SPACE: HIGH"
	arc.mechanism = "R01"
	arc.choice = "timing"
	arc.launch_start = 145
	arc.launch_end = arc.length
	arc.launch_impulse = 13.0
	arc.launch_intervals = [Vector2(175, 189), Vector2(arc.length - 49, arc.length - 35)]
	arc.checkpoint = false
	var high_catch := line("arc_high", origin + Vector3(0, 24, -352), Vector3.FORWARD, 500)
	high_catch.title = "X1 / HIGH EXIT - PREPARE NEXT CONNECTION"
	high_catch.next = ["precision"]
	points = PackedVector3Array()
	for i in 132:
		var t := float(i) / 131
		var blend := smoothstep(0.45, 1.0, t)
		points.append(origin + Vector3(-8 * (1 - blend), -16 + blend * 40, -170 - 682 * t))
	var low_catch := add_segment("arc_low", points)
	low_catch.title = "X1 / EARLY LOW EXIT - CLIMB BACK TO MERGE"
	low_catch.next = ["precision"]
	connect_air("arc", "arc_high", 200, 480)
	connect_air("arc", "arc_low", 100, 600)
	var precision := line("precision", high_catch.pose(high_catch.length).origin, Vector3.FORWARD, 260)
	precision.title = "T01 / SPACE AT GOLD + D: HIGH / A: VIOLET RESCUE"
	precision.mechanism = "T01"
	precision.choice = "rescue"
	precision.launch_start = precision.length - 34
	precision.launch_end = precision.length - 18
	precision.launch_impulse = 13
	origin = precision.pose(precision.length).origin
	var upper := line("upper", origin + Vector3(6.8, -5, -12), Vector3.FORWARD, 340, 0, "grind", 0.9)
	upper.title = "G01 / PRECISE UPPER RAIL - MERGE AHEAD"
	upper.mechanism = "G01"
	upper.checkpoint = false
	upper.next = ["merge"]
	points = PackedVector3Array()
	for i in 161:
		var t := float(i) / 160
		var blend := smoothstep(0.60, 1, t)
		var u := clampf((t - 0.60) / 0.40, 0, 1)
		points.append(origin + Vector3(-8 - 85 * pow(sin(PI * u), 2) + 14.8 * blend, -32 + 27 * blend, -12 - 340 * t))
	var rescue := add_segment("rescue", points, "wide", 3.0)
	rescue.title = "X3 / SAVED - LONGER LOW ROUTE / CLIMB TO MERGE"
	rescue.mechanism = "H01"
	connect_air("precision", "upper", precision.length - 90, 220)
	connect_air("precision", "rescue", precision.length - 90, 260)
	rescue.next = ["merge"]
	var merge := line("merge", upper.pose(upper.length).origin, Vector3.FORWARD, 280)
	merge.title = "VISIBLE MERGE / KEEP THE RUN ALIVE"
	merge.checkpoint = false
	merge.obstacles = [{"s": 155.0, "lanes": [0], "height": 1.4}]


func transform_segments(ids: Array, transform: Transform3D) -> void:
	for id: String in ids:
		var segment: RoadSegment = segments[id]
		for i in segment.curve.point_count:
			segment.curve.set_point_position(i, transform * segment.curve.get_point_position(i))
		segment.length = segment.curve.get_baked_length()


func bezier(id: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> RoadSegment:
	var points := PackedVector3Array()
	for i in 301:
		var t := float(i) / 300
		points.append(a.bezier_interpolate(b, c, d, t))
	return add_segment(id, points)


func _expand_full() -> void:
	var old_ids := segments.keys()
	var intro := line("intro", Vector3(0, 90, 0), Vector3.FORWARD, 820)
	intro.title = "A / READ GAPS - CHANGE RAIL / NO FLAT JUMP"
	intro.obstacles = [{"s": 240.0, "lanes": [0, 1], "height": 5.0}, {"s": 390.0, "lanes": [-1, 0], "height": 1.4}, {"s": 610.0, "lanes": [0, 1], "height": 5.0}]
	intro.next = ["boost_intro"]
	var boost := line("boost_intro", intro.pose(intro.length).origin, Vector3.FORWARD, 320)
	boost.title = "B01 / RIGHT PULSE PAD - MOVE LEFT OF THE RED EXIT"
	boost.obstacles = [{"s": 235.0, "lanes": [1], "height": 5.0}]
	boost.mechanism = "B01"
	boost.boosts = [{"start": 110.0, "end": 122.0, "lane": 1}]
	boost.next = ["launch_intro"]
	var ramp := line("launch_intro", boost.pose(boost.length).origin, Vector3.FORWARD, 28, 5.04)
	ramp.title = "R01 / RIDE OFF OR SPACE / WIDE CYAN LANDING"
	ramp.mechanism = "R01"
	ramp.launch_start = 0
	ramp.launch_end = ramp.length
	ramp.launch_impulse = 8.0
	ramp.checkpoint = false
	var landing := line("landing_intro", ramp.pose(ramp.length).origin + Vector3(0, -4, -12), Vector3.FORWARD, 580)
	landing.title = "B / STABILIZE - LOW BLOCK THEN BEAM"
	landing.obstacles = [{"s": 410.0, "lanes": [0], "height": 1.4}, {"s": 510.0, "lanes": [-1, 0, 1], "kind": "beam", "bottom": 4.6, "height": 1.2}]
	landing.next = ["approach"]
	connect_air("launch_intro", "landing_intro", 0, 500)
	var shift := landing.pose(landing.length).origin - (segments.approach as RoadSegment).pose(0).origin
	transform_segments(old_ids, Transform3D(Basis.IDENTITY, shift))
	start_id = "intro"
	# Real 1.1 km hairpin; the second half returns toward the familiar landmark.
	var old_pivot := (segments.arc as RoadSegment).pose(0).origin
	var canyon := bezier("canyon", old_pivot, old_pivot + Vector3(0, -15, -250), old_pivot + Vector3(160, -45, -450), old_pivot + Vector3(100, -45, -700))
	canyon.title = "CANYON / CARVE - PULSE - LEFT GAP - RIGHT GAP"
	canyon.enclosure = "canyon"
	canyon.checkpoint_s = 600.0
	canyon.turns = [{"start": 45.0, "end": 165.0, "direction": 1}, {"start": 335.0, "end": 450.0, "direction": -1}]
	canyon.boosts = [{"start": 188.0, "end": 200.0, "lane": 0}]
	canyon.obstacles = [{"s": 290.0, "lanes": [0, 1], "height": 5.0}, {"s": 565.0, "lanes": [-1, 0], "height": 5.0}]
	canyon.next = ["tunnel"]
	var tunnel := line("tunnel", canyon.pose(canyon.length).origin, Vector3.FORWARD, 420)
	tunnel.title = "TUNNEL / LEFT - RIGHT - CENTRE / BRIGHT EXIT AHEAD"
	tunnel.enclosure = "tunnel"
	tunnel.ceiling = 15.0
	tunnel.obstacles = [{"s": 115.0, "lanes": [0, 1], "height": 5.0}, {"s": 235.0, "lanes": [-1, 0], "height": 5.0}, {"s": 355.0, "lanes": [-1, 1], "height": 5.0}]
	tunnel.checkpoint = false
	tunnel.next = ["return_bend"]
	var pivot := tunnel.pose(tunnel.length).origin
	var points := PackedVector3Array()
	var radius := 350.0
	for i in 361:
		var angle := PI * float(i) / 360
		points.append(pivot + Vector3(radius * (1 - cos(angle)), 0, -radius * sin(angle)))
	var bend := add_segment("return_bend", points)
	bend.title = "D01 / THREE RIGHT CARVES / RELEASE BETWEEN CHEVRONS"
	bend.turns = [{"start": 220.0, "end": 350.0, "direction": 1}, {"start": 460.0, "end": 730.0, "direction": 1}, {"start": 850.0, "end": 1080.0, "direction": 1}]
	bend.obstacles = [{"s": 420.0, "lanes": [-1, 0], "height": 5.0}, {"s": 790.0, "lanes": [0, 1], "height": 5.0}]
	bend.next = ["arc"]
	(segments.high as RoadSegment).next = ["canyon"]
	(segments.dive as RoadSegment).next = ["canyon"]
	var rotation := Basis(Vector3.UP, PI)
	var turn_transform := Transform3D(rotation, bend.pose(bend.length).origin - rotation * old_pivot)
	transform_segments(["arc", "arc_high", "arc_low", "precision", "upper", "rescue", "merge"], turn_transform)
	var merge: RoadSegment = segments.merge
	merge.next = ["landmark_approach"]
	var origin := merge.pose(merge.length).origin
	var destination := Vector3(280, 35, -600)
	var approach := bezier("landmark_approach", origin, origin + Vector3(0, -10, 500), destination + Vector3(450, 0, 0), destination)
	approach.title = "G / DESCEND TOWARD THE TWIN TOWER - CARVE RIGHT"
	approach.enclosure = "gallery"
	approach.title = "G / CLIFF GALLERY - CARVE / LEFT-RIGHT / REPEAT TO BRIDGE"
	approach.turns = [{"start": 240.0, "end": 400.0, "direction": 1}, {"start": 730.0, "end": 930.0, "direction": 1}, {"start": 1290.0, "end": 1510.0, "direction": 1}, {"start": 1860.0, "end": approach.length - 70, "direction": 1}]
	approach.obstacles = [{"s": 495.0, "lanes": [0, 1], "height": 5.0}, {"s": 620.0, "lanes": [-1, 0], "height": 5.0}, {"s": 1040.0, "lanes": [0, 1], "height": 5.0}, {"s": 1160.0, "lanes": [-1, 0], "height": 5.0}, {"s": 1620.0, "lanes": [0, 1], "height": 5.0}, {"s": 1740.0, "lanes": [-1, 0], "height": 5.0}]
	approach.boosts = [{"start": 442.0, "end": 454.0, "lane": 0}, {"start": 985.0, "end": 997.0, "lane": 0}, {"start": 1550.0, "end": 1562.0, "lane": 0}]
	approach.next = ["under_bridge"]
	var under := line("under_bridge", destination, Vector3.LEFT, 600)
	under.title = "C01 / UNDER THE SAME BRIDGE / BEAM THEN LOW BLOCK"
	under.mechanism = "C01"
	under.launch_start = 230
	under.launch_end = 244
	under.launch_impulse = 13
	under.launcher_lane = 0
	under.auto_launcher = true
	under.title = "C01 / CENTRE KICKER + LOW BEAM / TAKE A SIDE RAIL"
	under.obstacles = [{"s": 310.0, "lanes": [-1, 0, 1], "kind": "beam", "bottom": 4.6, "height": 1.2}, {"s": 435.0, "lanes": [-1, 0], "height": 1.4}, {"s": 520.0, "lanes": [-1, 0], "height": 5.0}]
	under.next = ["final_boost"]
	var final_boost := line("final_boost", under.pose(under.length).origin, Vector3.LEFT, 1340)
	final_boost.title = "H / CENTRE CYAN BOOST - FINAL LAUNCH"
	final_boost.boosts = [{"start": 160.0, "end": 172.0, "lane": 0}]
	final_boost.obstacles = [{"s": 355.0, "lanes": [-1, 1], "height": 5.0}, {"s": 550.0, "lanes": [0], "height": 1.4}, {"s": 730.0, "lanes": [0, 1], "height": 5.0}, {"s": 950.0, "lanes": [-1, 0, 1], "kind": "beam", "bottom": 4.6, "height": 1.2}, {"s": 1110.0, "lanes": [0], "height": 1.4}]
	final_boost.next = ["final_ramp"]
	var final_ramp := line("final_ramp", final_boost.pose(final_boost.length).origin, Vector3.LEFT, 30, 5.4)
	final_ramp.title = "R01 / FINAL FLIGHT - AIM LEFT FOR CYAN"
	final_ramp.checkpoint = false
	final_ramp.launch_start = 0
	final_ramp.launch_end = final_ramp.length
	var finish := line("finish", final_ramp.pose(final_ramp.length).origin + Vector3(-12, -4, 6.8), Vector3.LEFT, 420)
	finish.title = "H / RECONNECTED - CARRY SPEED TO FINISH"
	connect_air("final_ramp", "finish", 0, 330)

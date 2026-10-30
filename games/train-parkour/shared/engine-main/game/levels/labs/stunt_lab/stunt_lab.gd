extends "res://levels/labs/controller_lab/controller_lab.gd"


func _ready() -> void:
	super._ready()
	var gold := _material(Color(1.0, 0.64, 0.15))
	var cyan := _material(Color(0.12, 0.92, 0.83))
	var takeoff: Array[Transform3D] = []
	var landing: Array[Transform3D] = []
	var drift: Array[Transform3D] = []
	var profile := route.stunts
	var s := profile.gap_start - profile.launch_window
	while s < profile.gap_start:
		takeoff.append(_level_pose(s).translated_local(Vector3(0, 0.16, 0)))
		s += 5.0
	s = profile.gap_end + 3.0
	while s < profile.landing_end:
		landing.append(_level_pose(s).translated_local(Vector3(profile.landing_lane * TUNING.lane_spacing, 0.16, 0)))
		s += 10.0
	s = profile.drift_start
	while s < profile.drift_end:
		drift.append(_level_pose(s).translated_local(Vector3(7.3, 0.18, 0)))
		s += 8.0
	_batch(presentation, "LaunchStripes", Vector3(15.0, 0.08, 1.7), gold, takeoff)
	_batch(presentation, "LandingStripes", Vector3(4.5, 0.06, 1.0), cyan, landing)
	_batch(presentation, "DriftStripes", Vector3(0.5, 0.08, 3.0), gold, drift)
	_sign("HOLD SHIFT + D", profile.drift_start + 12.0, Vector3(9, 5, 0), Color(1.0, 0.75, 0.3))
	_sign("SPACE / JUMP", profile.gap_start - 10.0, Vector3(0, 7, 0), Color(1.0, 0.75, 0.3))
	_sign("LAND HERE", profile.gap_end + 26.0, Vector3(profile.landing_lane * TUNING.lane_spacing, 5.5, 0), Color(0.2, 1.0, 0.85))


func _build_gates() -> void:
	for data in [Vector2(130, 0), Vector2(1150, 1)]:
		var gate := LaneGate.new()
		$GameplayRoot.add_child(gate)
		gate.build(data.x, int(data.y), route.pose_at(data.x, data.y * TUNING.lane_spacing))
		gates.append(gate)


func _sign(text: String, distance: float, offset: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.022
	label.modulate = color
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	# Retire teaching signs before the chase camera passes through their text plane.
	label.visibility_range_begin = 18.0
	label.visibility_range_end = 350.0
	presentation.add_child(label)
	label.transform = _level_pose(distance).translated_local(offset)

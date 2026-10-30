class_name FlowRoute
extends RailRoute

@export var course: FlowCourse


func _ready() -> void:
	# Arc-length construction keeps authored gameplay metres close to curve metres.
	curve = Curve3D.new()
	curve.bake_interval = 1.0
	var point := Vector3(0, 45, 100)
	for i in range(971):
		var s := i * 2.0
		if i > 0:
			var heading := _smooth(s, 300, 465) * 1.45 - _smooth(s, 1250, 1405) * 1.1
			point += Vector3(sin(heading), 0, -cos(heading)) * 2.0
		point.y = 45.0 + _smooth(s, 910, 1030) * 18.0 - _smooth(s, 1408, 1510) * 32.0
		curve.add_point(point)
	stunts = StuntProfile.new() # Enables the shared jump/drift input vocabulary.
	super._ready()


func _smooth(s: float, a: float, b: float) -> float:
	var t := clampf((s - a) / (b - a), 0, 1)
	return t * t * (3.0 - 2.0 * t)


func has_track(s: float) -> bool:
	if s < 0.0 or s > length:
		return false
	for jump in course.jumps:
		if s >= jump.start and s < jump.end:
			return false
	return true


func lanes_at(s: float) -> Array[int]:
	if not has_track(s):
		return []
	if s >= course.fork_start and s < course.fork_end:
		return [-1, 1]
	if s >= 1640.0 and s < 1680.0:
		return [1]
	return [-1, 0, 1]


func section_at(s: float) -> String:
	if s < 285: return "01 / THREAD THE BLOCKS"
	if s < 680: return "02 / CARVE - BOOST - HOP"
	if s < 1000: return "03 / LAUNCH - RECONNECT"
	if s < 1210: return "04 / WIDE LEFT - FAST RIGHT"
	if s < 1470: return "05 / CARVE INTO THE DROP"
	if s < 1700: return "06 / FLY TO THE RIGHT RAIL"
	return "07 / LEFT - RIGHT - FINISH"

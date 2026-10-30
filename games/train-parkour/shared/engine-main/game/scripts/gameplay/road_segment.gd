class_name RoadSegment
extends RefCounted
## Level-local metres. Geometry, support, capture and previews share this curve.

var id: String
var curve := Curve3D.new()
var length := 0.0
var support := "wide"
var half_width := 6.5
var mechanism := "D01"
var title := "READ THE ROAD"
var next: Array[String] = []
var connections: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
var boosts: Array[Dictionary] = []
var turns: Array[Dictionary] = []
var checkpoint := true
var checkpoint_s := 24.0
var order := 0
var choice := ""


func pose(s: float, side: float = 0.0) -> Transform3D:
	var t := clampf(s, 0, length)
	var a := curve.sample_baked(maxf(0, t - 0.5), true)
	var b := curve.sample_baked(minf(length, t + 0.5), true)
	var forward := (b - a).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	return Transform3D(Basis(right, up, -forward), curve.sample_baked(t, true) + right * side)


func lanes() -> Array[int]:
	return [0] if support == "grind" or half_width < 5.0 else [-1, 0, 1]

var launch_start := -1.0
var launch_end := -1.0
var launch_impulse := 0.0
var launcher_lane := 99
var auto_launcher := false
var enclosure := "open"
var ceiling := INF

var launch_intervals: Array[Vector2] = []

func launch_at(s: float) -> bool:
	if not launch_intervals.is_empty():
		for interval in launch_intervals:
			if s >= interval.x and s <= interval.y: return true
		return false
	return launch_start >= 0 and s >= launch_start and s <= launch_end

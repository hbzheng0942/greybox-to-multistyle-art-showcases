class_name RailRoute
extends Path3D
## The Curve3D is authoritative. Its baked distance is independent of render meshes.

@export var stunts: StuntProfile
var length: float = 0.0


func _ready() -> void:
	length = curve.get_baked_length()


func pose_at(distance: float, lateral: float = 0.0) -> Transform3D:
	var along := clampf(distance, 0.0, length)
	var center := curve.sample_baked(along, true)
	var a := curve.sample_baked(maxf(0.0, along - 1.0), true)
	var b := curve.sample_baked(minf(length, along + 1.0), true)
	var forward := (b - a).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	return global_transform * Transform3D(Basis(right, up, -forward), center + right * lateral)


func section_at(distance: float) -> String:
	if stunts != null:
		if distance < stunts.drift_start:
			return "01 / APPROACH"
		if distance < stunts.drift_end:
			return "02 / DRIFT"
		if distance < stunts.gap_start:
			return "03 / LAUNCH"
		if distance < stunts.gap_end:
			return "04 / FLIGHT"
		if distance < stunts.landing_end:
			return "05 / RECONNECT"
		return "06 / KEEP THE SPEED"
	var ratio := distance / length
	if ratio < 0.13:
		return "01 / LAUNCH"
	if ratio < 0.32:
		return "02 / CLIMB"
	if ratio < 0.52:
		return "03 / SWEEP"
	if ratio < 0.72:
		return "04 / SKYLINE"
	if ratio < 0.92:
		return "05 / DESCENT"
	return "06 / HOME STRAIGHT"


func closest_distance(world_position: Vector3) -> float:
	return curve.get_closest_offset(to_local(world_position))


func has_track(distance: float) -> bool:
	return distance >= 0.0 and distance <= length and (stunts == null or distance < stunts.gap_start or distance >= stunts.gap_end)


func lanes_at(distance: float) -> Array[int]:
	if not has_track(distance):
		return []
	if stunts != null and distance >= stunts.gap_end and distance < stunts.landing_end:
		return [stunts.landing_lane]
	return [-1, 0, 1]


func turn_direction(distance: float) -> float:
	var pose := pose_at(distance)
	return pose.basis.x.dot(-pose_at(distance + 35.0).basis.z)

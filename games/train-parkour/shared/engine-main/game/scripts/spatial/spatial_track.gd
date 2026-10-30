class_name SpatialTrack
extends RefCounted
## Arc-length geometry + continuous contact frames. No WORLD_UP cross at verticals.

var id := ""
var points := PackedVector3Array()
var distances := PackedFloat64Array()
var rotations: Array[Quaternion] = []
var length := 0.0
var bounds := AABB()
var half_width := 6.5
var entry_half_width := 0.0
var entry_taper_length := 0.0
var single_lane := false
var kind := "wide"
var title := "READ THE LINE"
var next: Array[String] = []
var connections: Array[Dictionary] = []
var pads: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []
var release_windows: Array[Vector2] = []
var impulse := Vector3.ZERO # Level-local physical device impulse, not a target solver.
var ceiling := INF
var enclosure := "open"
var enclosure_half_width := 11.0
var checkpoint := false
var checkpoint_s := 24.0
var checkpoint_speed := -1.0
var checkpoint_lane := 0
var camera_phase := "rush"
var chapter := ""
var score_carve := false
var action_zones: Array[Dictionary] = []


func build(path: PackedVector3Array, bank_from := 0.0, bank_to := 0.0, normals := PackedVector3Array(), seed_up := Vector3.UP) -> void:
	assert(path.size() >= 2)
	points = path
	bounds = AABB(points[0], Vector3.ZERO)
	for point in points: bounds = bounds.expand(point)
	distances.resize(path.size())
	for i in range(1, points.size()):
		distances[i] = distances[i - 1] + points[i].distance_to(points[i - 1])
	length = distances[-1]
	assert(length > 0.01)
	var previous_forward := (points[1] - points[0]).normalized()
	var transported_up := seed_up.slide(previous_forward)
	if transported_up.length_squared() < 0.0001:
		transported_up = Vector3.RIGHT.slide(previous_forward)
	if transported_up.length_squared() < 0.0001:
		transported_up = Vector3.FORWARD.slide(previous_forward)
	transported_up = transported_up.normalized()
	rotations.clear()
	for i in points.size():
		var forward := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		assert(forward.length_squared() > 0.99)
		if i > 0:
			transported_up = (Quaternion(previous_forward, forward) * transported_up).slide(forward).normalized()
		var up := transported_up
		if normals.size() == points.size():
			up = normals[i].slide(forward).normalized()
		else:
			up = Quaternion(forward, lerpf(bank_from, bank_to, smoothstep(0, 1, distances[i] / length))) * up
		var right := forward.cross(up).normalized()
		up = right.cross(forward).normalized()
		var q := Basis(right, up, -forward).get_rotation_quaternion().normalized()
		if not rotations.is_empty() and rotations.back().dot(q) < 0: q = -q
		rotations.append(q)
		previous_forward = forward


func index_at(s: float) -> int:
	var lo := 0
	var hi := distances.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) / 2
		if distances[mid] <= s: lo = mid
		else: hi = mid
	return mini(lo, points.size() - 2)


func pose(s: float, side := 0.0) -> Transform3D:
	var at := clampf(s, 0, length)
	var i := index_at(at)
	var t := (at - distances[i]) / maxf(0.00001, distances[i + 1] - distances[i])
	var basis := Basis(rotations[i].slerp(rotations[i + 1], t)).orthonormalized()
	var p := points[i].lerp(points[i + 1], t) + basis.x * side
	if s < 0: p += -basis.z * s
	elif s > length: p += -basis.z * (s - length)
	return Transform3D(basis, p)


func curvature(s: float) -> Vector2:
	var a := clampf(s - 2, 0, length)
	var b := clampf(s + 2, 0, length)
	var frame := pose(s)
	var change := (-pose(b).basis.z + pose(a).basis.z) / maxf(b - a, 0.001)
	return Vector2(change.dot(frame.basis.x), change.dot(frame.basis.y))


func width_at(s: float) -> float:
	if entry_half_width <= 0 or entry_taper_length <= 0: return half_width
	var t := smoothstep(0, 1, clampf(s / entry_taper_length, 0, 1))
	return lerpf(entry_half_width, half_width, t)


func nearest(point: Vector3, from_s := 0.0, to_s := INF) -> float:
	var a := clampf(from_s, 0, length)
	var b := clampf(to_s, a, length)
	var best := a
	var error := INF
	for i in range(index_at(a), mini(index_at(b) + 1, points.size() - 1)):
		var edge := points[i + 1] - points[i]
		var span := distances[i + 1] - distances[i]
		var t := clampf(edge.dot(point - points[i]) / maxf(edge.length_squared(), 0.0001), maxf(0, (a - distances[i]) / span), minf(1, (b - distances[i]) / span))
		var e := point.distance_squared_to(points[i] + edge * t)
		if e < error:
			error = e
			best = distances[i] + span * t
	return best


func can_release(s: float) -> bool:
	for window in release_windows:
		if s >= window.x and s <= window.y: return true
	return false


func lanes() -> Array[int]:
	return [0] if single_lane else [-1, 0, 1]

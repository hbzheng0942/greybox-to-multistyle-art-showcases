extends RefCounted
## Shared authoritative horizontal collision for PLAYER + AI.
## The ENTIRE physical hole disk must remain on dry land, including after growth.
## Uses analytic swept movement (not a visual-only fence, not a point clamp).
## Radius-aware navigation is a separate convenience; collision never trusts a path.

var polygon: PackedVector2Array = PackedVector2Array()
var minimum: Vector2 = Vector2(-22.0, -18.0)
var maximum: Vector2 = Vector2(22.0, 18.0)
var shore_margin: float = 0.18
var cell_size: float = 0.75
var grids: Dictionary = {}
var winding: float = 1.0

func setup(map: Dictionary, margin: float = 0.18) -> void:
	polygon.clear()
	for v in map["land_polygon_xz"]:
		polygon.append(Vector2(float(v[0]), float(v[1])))
	shore_margin = margin
	cell_size = float(map.get("navigation_cell_size", 0.75))
	minimum = polygon[0]
	maximum = polygon[0]
	var area: float = 0.0
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		minimum = minimum.min(a)
		maximum = maximum.max(a)
		area += a.cross(b)
	winding = 1.0 if area > 0.0 else -1.0
	grids.clear()

func nearest_edge(p: Vector2) -> Dictionary:
	var best: float = INF
	var q: Vector2 = Vector2.ZERO
	var normal: Vector2 = Vector2.UP
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		var point: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
		var distance: float = p.distance_to(point)
		if distance < best:
			best = distance
			q = point
			var edge: Vector2 = (b - a).normalized()
			normal = Vector2(-edge.y, edge.x) * winding
	return {"point": q, "distance": best, "inward": normal}

func clearance(p: Vector2) -> float:
	var distance: float = float(nearest_edge(p)["distance"])
	return distance if Geometry2D.is_point_in_polygon(p, polygon) else -distance

func valid(p: Vector2, radius: float, extra: float = 0.0) -> bool:
	if not Geometry2D.is_point_in_polygon(p, polygon):
		return false
	return float(nearest_edge(p)["distance"]) + 0.00001 >= radius + shore_margin + extra

func project_inside(p: Vector2, radius: float) -> Vector2:
	if valid(p, radius):
		return p
	var current: Vector2 = p
	var required: float = maxf(0.0, radius) + shore_margin + 0.001
	# Fast alternating projections handles straight banks and ordinary corner growth.
	for _iteration in range(24):
		var edge: Dictionary = nearest_edge(current)
		var q: Vector2 = edge["point"]
		var normal: Vector2 = edge["inward"]
		var is_inside: bool = Geometry2D.is_point_in_polygon(current, polygon)
		if is_inside and float(edge["distance"]) > 0.00001:
			normal = (current - q).normalized()
		current = q + normal * required
		if valid(current, radius):
			return current
	# Rare fallback for debug teleports / strong tuning jumps. No reward is awarded.
	var best: float = INF
	var answer: Vector2 = Vector2.ZERO
	var found: bool = false
	var x: float = minimum.x + required
	while x <= maximum.x - required:
		var y: float = minimum.y + required
		while y <= maximum.y - required:
			var candidate: Vector2 = Vector2(x, y)
			var distance: float = p.distance_squared_to(candidate)
			if distance < best and valid(candidate, radius):
				best = distance
				answer = candidate
				found = true
			y += 0.5
		x += 0.5
	if not found:
		push_error("LandBoundary: this radius has no valid land centre. Restore default tuning.")
		return Vector2.ZERO
	return answer

func move_and_slide_disk(start: Vector2, desired: Vector2, radius: float) -> Dictionary:
	var p: Vector2 = project_inside(start, radius)
	var corrected_start: Vector2 = p
	var path: PackedVector2Array = PackedVector2Array([p])
	# Use the requested displacement, NOT a vector back into the bank after a growth correction.
	var displacement: Vector2 = desired - start
	var steps: int = maxi(1, int(ceil(displacement.length() / 0.18)))
	var step: Vector2 = displacement / float(steps)
	var hits: int = 0
	for _i in range(steps):
		var remaining: Vector2 = step
		for _slide in range(3):
			if remaining.length_squared() < 0.0000001:
				break
			if valid(p + remaining, radius):
				p += remaining
				path.append(p)
				break
			hits += 1
			var low: float = 0.0
			var high: float = 1.0
			for _search in range(12):
				var t: float = (low + high) * 0.5
				if valid(p + remaining * t, radius):
					low = t
				else:
					high = t
			p += remaining * maxf(0.0, low - 0.0005)
			path.append(p)
			var edge: Dictionary = nearest_edge(p)
			var outward_to_land: Vector2 = p - Vector2(edge["point"])
			var normal: Vector2 = outward_to_land.normalized() if outward_to_land.length_squared() > 0.000001 else Vector2(edge["inward"])
			remaining *= 1.0 - low
			var into_bank: float = remaining.dot(normal)
			if into_bank < 0.0:
				remaining -= normal * into_bank
			else:
				break
	if not valid(p, radius):
		p = project_inside(p, radius)
		path.append(p)
	return {"position": p, "start": corrected_start, "path": path, "contacts": hits}

func segment_valid(a: Vector2, b: Vector2, radius: float) -> bool:
	var steps: int = maxi(1, int(ceil(a.distance_to(b) / 0.20)))
	for i in range(steps + 1):
		if not valid(a.lerp(b, float(i) / float(steps)), radius):
			return false
	return true

func _grid_for(radius: float) -> AStarGrid2D:
	# Conservative bucket + cell half-diagonal prevents paths cutting concave banks.
	var bucket: float = ceil(radius * 4.0) / 4.0
	var key: String = "%.2f:%.2f" % [bucket, shore_margin]
	if grids.has(key):
		return grids[key]
	var grid: AStarGrid2D = AStarGrid2D.new()
	var width: int = int(ceil((maximum.x - minimum.x) / cell_size))
	var height: int = int(ceil((maximum.y - minimum.y) / cell_size))
	grid.region = Rect2i(0, 0, width, height)
	grid.cell_size = Vector2.ONE * cell_size
	grid.offset = minimum + Vector2.ONE * cell_size * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(width):
		for y in range(height):
			var pos: Vector2 = grid.offset + Vector2(x, y) * cell_size
			grid.set_point_solid(Vector2i(x, y), not valid(pos, bucket, cell_size * 0.71))
	grids[key] = grid
	return grid

func _closest_cell(grid: AStarGrid2D, p: Vector2, radius: float) -> Vector2i:
	var raw: Vector2i = Vector2i(((p - grid.offset) / cell_size).round())
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = INF
	for x in range(raw.x - 6, raw.x + 7):
		for y in range(raw.y - 6, raw.y + 7):
			var id: Vector2i = Vector2i(x, y)
			if not grid.region.has_point(id) or grid.is_point_solid(id):
				continue
			var point: Vector2 = grid.offset + Vector2(id) * cell_size
			var distance: float = p.distance_squared_to(point)
			if distance < best_distance and segment_valid(p, point, radius):
				best = id
				best_distance = distance
	return best

func navigation_path(start: Vector2, goal: Vector2, radius: float) -> PackedVector2Array:
	var from: Vector2 = project_inside(start, radius)
	var to: Vector2 = project_inside(goal, radius)
	if segment_valid(from, to, radius):
		return PackedVector2Array([from, to])
	var grid: AStarGrid2D = _grid_for(radius)
	var a: Vector2i = _closest_cell(grid, from, radius)
	var b: Vector2i = _closest_cell(grid, to, radius)
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var middle: PackedVector2Array = grid.get_point_path(a, b)
	if middle.is_empty():
		return PackedVector2Array()
	var result: PackedVector2Array = PackedVector2Array([from])
	result.append_array(middle)
	result.append(to)
	return result

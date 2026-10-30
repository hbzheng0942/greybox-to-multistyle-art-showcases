extends RefCounted
## Measure visible horizontal mesh at the frozen positions of supported items.

static func _triangle_y(a: Vector3, b: Vector3, c: Vector3, point: Vector2) -> float:
	var normal: Vector3 = (b - a).cross(c - a)
	if absf(normal.y) < normal.length() * .7:
		return INF
	var denominator: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(denominator) < 0.000001:
		return INF
	var wa: float = ((b.z - c.z) * (point.x - c.x) + (c.x - b.x) * (point.y - c.z)) / denominator
	var wb: float = ((c.z - a.z) * (point.x - c.x) + (a.x - c.x) * (point.y - c.z)) / denominator
	var wc: float = 1.0 - wa - wb
	if minf(wa, minf(wb, wc)) < -0.001:
		return INF
	return wa * a.y + wb * b.y + wc * c.y

static func _scan(node: Node, parent_xf: Transform3D, samples: Array, expected_y: float, best: Array) -> void:
	var xf: Transform3D = parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		if instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var index_data = arrays[Mesh.ARRAY_INDEX]
				var indices: PackedInt32Array = index_data if index_data != null else PackedInt32Array()
				var count: int = indices.size() if not indices.is_empty() else vertices.size()
				for triangle in range(count / 3):
					var offset: int = triangle * 3
					var a: Vector3 = xf * vertices[indices[offset] if not indices.is_empty() else offset]
					var b: Vector3 = xf * vertices[indices[offset + 1] if not indices.is_empty() else offset + 1]
					var c: Vector3 = xf * vertices[indices[offset + 2] if not indices.is_empty() else offset + 2]
					for i in range(samples.size()):
						var y: float = _triangle_y(a, b, c, samples[i])
						if is_finite(y) and absf(y - expected_y) < absf(float(best[i]) - expected_y):
							best[i] = y
	for child in node.get_children():
		_scan(child, xf, samples, expected_y, best)

static func measure(node: Node3D, samples: Array, expected_y: float, tolerance: float = .08) -> Dictionary:
	var heights: Array = []
	for _sample in samples:
		heights.append(INF)
	_scan(node, Transform3D.IDENTITY, samples, expected_y, heights)
	var measured: Array = []
	var passed: bool = samples.size() > 0
	for height in heights:
		var good: bool = is_finite(float(height)) and absf(float(height) - expected_y) <= tolerance
		passed = passed and good
		measured.append(height if is_finite(float(height)) else null)
	return {"expected_y_local": expected_y, "sample_xz": samples.map(func(v: Vector2): return [v.x, v.y]),
		"measured_y_local": measured, "tolerance": tolerance, "contact_pass": passed}

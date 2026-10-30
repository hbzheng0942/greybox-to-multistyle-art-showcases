extends RefCounted
## N02 plus bounded N03 water/cloud effects; imported footprints are authoritative.
## No colliders, routes, camera settings, speed or gameplay nodes are changed.

const WATER_SHADER = preload("paper_water.gdshader")
const CLOUD_SHADER = preload("paper_cloud.gdshader")
const TE04_SHA = "a2f756315ebb5c6901d03724e209088d04dde49ba8142708669b329d6b921d1d"
const TE04_OUTLET = Vector3(0.110, -0.120, 0.068)
const TE04_LIP = Vector3(0.110, -0.122, 0.112)

var _water_triangles: Array = []
var _foundation_triangles: Dictionary = {}
var _transfer_water_triangles: Array = []
var _world_water_triangles: Dictionary = {}
var _report: Dictionary = {}
var _root: Node3D

func install(_session: Node3D, root: Node3D, spec: Dictionary) -> Dictionary:
	_root = root
	_water_triangles.clear()
	_transfer_water_triangles.clear()
	_world_water_triangles.clear()
	_foundation_triangles.clear()
	_report = {"revision": "paper_atmosphere_r7_authored_water_facets", "scope": "visual_only_N02_N03_N04_N06_N07",
		"water_meshes": [], "hidden_old_clouds": [], "waterfall_connections": [],
		"skipped_waterfalls": [], "low_cloud_clusters": 0, "sky_cloud_clusters": 0,
		"new_meshes": 0, "new_triangles": 0, "transfer_water_meshes": [],
		"transfer_water_patches": 0, "transfer_low_cloud_clusters": 0, "transfer_cloud_centers": [], "acceptance": "native_visual_review_required"}
	var previous := root.get_node_or_null("PaperAtmosphere")
	if previous != null:
		previous.free()
	var effects := Node3D.new()
	effects.name = "PaperAtmosphere"
	root.add_child(effects)
	_mark_effect(effects, "paper_atmosphere")
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var label := str(mesh_node.name)
		if label.begins_with("N02_fold_shoulder_") and label.ends_with("_cliff"):
			_foundation_triangles[label.trim_suffix("_cliff")] = _read_triangles(mesh_node)
		if label.begins_with("N02_valley_water_"):
			_read_water_surface(mesh_node)
			_apply_authored_water(mesh_node, Color("48adba"), false, false)
			_mark_effect(mesh_node, "paper_water_basin")
			_report.water_meshes.append(label)
		elif label.begins_with("N03_valley_water_"):
			_transfer_water_triangles.append_array(_read_top_water_triangles(mesh_node))
			_apply_authored_water(mesh_node, Color("48adba"), false, false)
			_mark_effect(mesh_node, "paper_water_basin", "vertical")
			_report.transfer_water_meshes.append(label)
		elif label.begins_with("N04_valley_water_") or label.begins_with("N06_reservoir_water") or label.begins_with("N07_harbor_water"):
			var region := "coaster" if label.begins_with("N04") else ("valley" if label.begins_with("N06") else "finale")
			if not _world_water_triangles.has(region): _world_water_triangles[region] = []
			_world_water_triangles[region].append_array(_read_top_water_triangles(mesh_node))
			_apply_authored_water(mesh_node, Color("48adba"), false, false)
			_mark_effect(mesh_node, "paper_water_basin", region)
			_report.water_meshes.append(label)
		elif label.begins_with("N06_spillway_fall_"):
			_apply_authored_water(mesh_node, Color("78c9cf"), true, true)
			_mark_effect(mesh_node, "paper_waterfall_existing", "valley")
		elif label.begins_with("N06_spillway_upper_water"):
			_apply_authored_water(mesh_node, Color("48adba"), false, false)
			_mark_effect(mesh_node, "paper_water_basin", "valley")
		elif label.begins_with("N06_spillway_foam_"):
			mesh_node.material_override = null
			for index in mesh_node.mesh.get_surface_count():
				var source := mesh_node.mesh.surface_get_material(index) as BaseMaterial3D
				var tint := source.albedo_color if source != null else Color("edf5e7")
				mesh_node.set_surface_override_material(index, _cloud_material(tint, 0.0))
			_mark_effect(mesh_node, "waterfall_foam", "valley")
		elif label.begins_with("CL01_") or label.begins_with("CL02_"):
			mesh_node.visible = false
			_mark_effect(mesh_node, "superseded_cloud")
			_report.hidden_old_clouds.append(label)
		elif label.begins_with("WA02_waterfall_"):
			# Existing exact river mouths are retained if the current geometry has any.
			mesh_node.material_override = _water_material(Color("78c9cf"), true, false)
			_mark_effect(mesh_node, "paper_waterfall_existing")
	if not _water_triangles.is_empty():
		_add_water_layers(effects)
		_add_waterfall_connections(effects, spec)
		_add_clouds(effects)
	if not _transfer_water_triangles.is_empty():
		_add_transfer_atmosphere(effects)
	if _water_triangles.is_empty() and _transfer_water_triangles.is_empty():
		push_warning("Paper atmosphere found no imported water top; no inferred water/falls added.")
		_report["warning"] = "missing_native_water_geometry"
	_add_world_atmosphere(effects)
	_add_world_sky(effects)
	root.set_meta("paper_atmosphere_report", _report)
	return _report

func _mark_effect(node: Node, kind: String, scene_id := "canyon") -> void:
	node.set_meta("scene_id", scene_id)
	node.set_meta("asset_id", "paper_atmosphere")
	node.set_meta("instance_id", str(node.name))
	node.set_meta("visual_effect", true)
	node.set_meta("visual_effect_kind", kind)
	node.set_meta("collision_role", "none")
	node.set_meta("support_role", "none")

func _water_material(tint: Color, falls: bool, colored: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("waterfall", falls)
	material.set_shader_parameter("layer_colors", colored)
	return material

func _apply_authored_water(node: MeshInstance3D, fallback: Color, falls: bool, flow: bool) -> void:
	# Keep the actual authored large color facets. A single mesh override erased
	# all basin and spillway material variation, even when the DCC mesh had it.
	node.material_override = null
	for index in node.mesh.get_surface_count():
		var source := node.mesh.surface_get_material(index) as BaseMaterial3D
		var tint := source.albedo_color if source != null else fallback
		var finish := _water_material(tint, falls, false)
		finish.set_shader_parameter("world_flow",flow)
		node.set_surface_override_material(index,finish)

func _cloud_material(tint: Color, drift: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("drift_amplitude", drift)
	return material

func _read_triangles(node: MeshInstance3D) -> Array:
	var triangles: Array = []
	if node.mesh == null:
		return triangles
	var transform: Transform3D = _root.global_transform.affine_inverse() * node.global_transform
	for surface in node.mesh.get_surface_count():
		var arrays: Array = node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for i in range(0, count - 2, 3):
			var a: Vector3 = transform * vertices[indices[i] if not indices.is_empty() else i]
			var b: Vector3 = transform * vertices[indices[i + 1] if not indices.is_empty() else i + 1]
			var c: Vector3 = transform * vertices[indices[i + 2] if not indices.is_empty() else i + 2]
			triangles.append([a, b, c])
	return triangles

func _read_water_surface(node: MeshInstance3D) -> void:
	_water_triangles.append_array(_read_top_water_triangles(node))

func _read_top_water_triangles(node: MeshInstance3D) -> Array:
	var result := []
	var triangles: Array = _read_triangles(node)
	var top: float = -INF
	for triangle in triangles:
		for vertex: Vector3 in triangle:
			top = maxf(top, vertex.y)
	for triangle in triangles:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		if absf(a.y - b.y) <= 0.03 and absf(a.y - c.y) <= 0.03 and a.y >= top - 0.03:
			result.append(triangle)
	return result

func _water_height_at(point: Vector3) -> float:
	for triangle in _water_triangles:
		var a := Vector2(triangle[0].x, triangle[0].z)
		var b := Vector2(triangle[1].x, triangle[1].z)
		var c := Vector2(triangle[2].x, triangle[2].z)
		if _inside_triangle(Vector2(point.x, point.z), a, b, c):
			return float(triangle[0].y)
	return -INF

func _inside_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab: float = (b - a).cross(point - a)
	var bc: float = (c - b).cross(point - b)
	var ca: float = (a - c).cross(point - c)
	return (ab >= -0.001 and bc >= -0.001 and ca >= -0.001) or (ab <= 0.001 and bc <= 0.001 and ca <= 0.001)

func _new_surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		color := Color.WHITE, uva := Vector2.ZERO, uvb := Vector2.ZERO,
		uvc := Vector2.ZERO) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	for pair in [[a, uva], [b, uvb], [c, uvc]]:
		surface.set_normal(normal)
		surface.set_color(color)
		surface.set_uv(pair[1])
		surface.add_vertex(pair[0])
	_report.new_triangles += 1

func _finish_mesh(surface: SurfaceTool, parent: Node3D, label: String,
		material: Material, kind: String, range_end := 1400.0, scene_id := "canyon") -> void:
	var mesh: ArrayMesh = surface.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = range_end
	parent.add_child(node)
	_mark_effect(node, kind, scene_id)
	_report.new_meshes += 1

func _clip_patch_edge(polygon: Array, a: Vector2, b: Vector2) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Vector3 = polygon[-1]
	var previous_distance: float = (b - a).cross(Vector2(previous.x, previous.z) - a)
	for current: Vector3 in polygon:
		var current_distance: float = (b - a).cross(Vector2(current.x, current.z) - a)
		var previous_in: bool = previous_distance >= 0.0
		var current_in: bool = current_distance >= 0.0
		if previous_in != current_in:
			result.append(previous.lerp(current, previous_distance / (previous_distance - current_distance)))
		if current_in:
			result.append(current)
		previous = current
		previous_distance = current_distance
	return result

func _add_water_layers(parent: Node3D, authored_patches: Array = [], label := "PaperWaterCutLayers", scene_id := "canyon") -> void:
	var surface := _new_surface()
	# Vertex COLOR is linear, unlike a shader source_color uniform. Converting
	# these dyed-paper colors prevents the previous accidental white stripes.
	var palettes: Array[Color] = [Color("50b1bc").srgb_to_linear(),
		Color("46a9b7").srgb_to_linear(), Color("4caebb").srgb_to_linear()]
	# Local overlapping sheets vary in width, length and angle. None spans
	# the valley; every fragment is clipped to the actual imported shoreline.
	var patches := [
		[Vector2(-25, 74), Vector2(29, 40), 0.26],
		[Vector2(38, 126), Vector2(23, 56), -0.31],
		[Vector2(-64, 193), Vector2(38, 44), 0.18],
		[Vector2(3, 238), Vector2(31, 62), -0.41],
		[Vector2(76, 290), Vector2(24, 38), 0.34],
		[Vector2(-25, 345), Vector2(43, 53), -0.22],
		[Vector2(-88, 410), Vector2(29, 36), 0.42],
		[Vector2(48, 452), Vector2(36, 65), 0.14],
		[Vector2(-7, 509), Vector2(24, 43), -0.33],
		[Vector2(72, 568), Vector2(29, 36), 0.29],
		[Vector2(-52, 619), Vector2(39, 58), -0.19],
		[Vector2(17, 686), Vector2(29, 47), 0.38],
		[Vector2(-73, 753), Vector2(26, 38), -0.26],
		[Vector2(62, 801), Vector2(37, 62), 0.11],
		[Vector2(-18, 858), Vector2(32, 48), -0.37],
		[Vector2(39, 913), Vector2(25, 37), 0.23],
		[Vector2(-53, 977), Vector2(42, 59), -0.18],
		[Vector2(18, 1036), Vector2(28, 41), 0.32]
	]
	if not authored_patches.is_empty():
		patches = authored_patches
	for patch_index in patches.size():
		var patch: Array = patches[patch_index]
		var center: Vector2 = patch[0]
		var radius: Vector2 = patch[1]
		var outline: Array[Vector2] = []
		for corner in range(9):
			var angle: float = float(corner) / 9.0 * TAU
			# Convex hand-cut ovals with uneven side lengths, not rectangular bands.
			var radial: float = 1.0 + 0.035 * sin(float(corner * 3 + patch_index))
			var point := Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * radial
			outline.append(center + point.rotated(float(patch[2])))
		for triangle in _water_triangles:
			var polygon: Array = triangle.duplicate()
			for edge in outline.size():
				polygon = _clip_patch_edge(polygon, outline[edge], outline[(edge + 1) % outline.size()])
				if polygon.is_empty():
					break
			if polygon.size() < 3:
				continue
			for index in polygon.size():
				polygon[index].y += 0.035 + float(patch_index) * 0.0015
			for index in range(1, polygon.size() - 1):
				_triangle(surface, polygon[0], polygon[index], polygon[index + 1], palettes[patch_index % 3])
	_finish_mesh(surface, parent, label, _water_material(Color.WHITE, false, true), "water_cut_layers", 1400.0, scene_id)

func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _add_waterfall_connections(parent: Node3D, spec: Dictionary) -> void:
	var ribbons := _new_surface()
	var foam := _new_surface()
	var count := 0
	for item: Dictionary in spec.get("g1_instances", []):
		if str(item.get("asset_id", "")) != "TE04":
			continue
		var identity: String = item.id
		# Only the three exposed, high east-bank mouths face the N02 basin.
		if not ("east_forest_enter" in identity or "east_forest_bridge" in identity or "exit_forest_east" in identity):
			_report.skipped_waterfalls.append({"id": identity, "reason": "no_approved_exposed_high_outlet"})
			continue
		if str(item.get("source_sha256", "")) != TE04_SHA:
			_report.skipped_waterfalls.append({"id": identity, "reason": "source_changed_remeasure_outlet"})
			continue
		var scale_value: float = item.uniform_scale
		var basis := Basis(Vector3.UP, deg_to_rad(float(item.yaw_degrees)))
		var origin := _vec3(item.position_m)
		var outlet: Vector3 = origin + basis * (TE04_OUTLET * scale_value)
		var lip: Vector3 = origin + basis * (TE04_LIP * scale_value)
		var front: Vector3 = basis * Vector3(0, 0, 1)
		var side: Vector3 = basis * Vector3.RIGHT
		var width: float = clampf(scale_value * 0.031, 7.5, 13.0)
		var foundation_id: String = identity.trim_suffix("_TE04")
		var foundation: Array = _foundation_triangles.get(foundation_id, [])
		var profile: Array[Vector3] = []
		var offline: Dictionary = spec.get("waterfall_profiles", {}).get(identity, {})
		if not offline.is_empty():
			if not offline.get("valid", false) or offline.get("mother_sha256", "") != TE04_SHA:
				_report.skipped_waterfalls.append({"id": identity, "reason": offline.get("reason", "offline_profile_invalid")})
				continue
			for point: Array in offline.rows:
				profile.append(_vec3(point))
		else:
			profile = _foundation_profile(foundation, lip, front, side, width)
		if profile.size() < 2:
			_report.skipped_waterfalls.append({"id": identity, "reason": "no_verified_foundation_to_water_profile"})
			continue
		var landing: Vector3 = profile[-1]
		var water_y: float = _water_height_at(landing)
		if not is_finite(water_y) or lip.y - water_y < 8.0 or profile[0].y > lip.y + 0.1:
			_report.skipped_waterfalls.append({"id": identity, "reason": "source_lip_or_landing_profile_conflict"})
			continue
		var rows: Array[Vector3] = [outlet, lip]
		# The exact upper envelope includes every clipped triangle corner and
		# crossing. Across the whole ribbon width it stays above the root, not
		# merely above the center line or a handful of guessed samples.
		for point: Vector3 in profile:
			if point.distance_to(lip) > 0.15:
				rows.append(point)
		var drops: Array[float] = [0.0]
		for row in range(1, rows.size()):
			drops.append(drops[-1] + rows[row - 1].distance_to(rows[row]))
		for row in range(rows.size() - 1):
			for column in range(5):
				var u0: float = float(column) / 5.0
				var u1: float = float(column + 1) / 5.0
				var fold0: float = 0.0 if column % 2 == 0 else 0.55
				var fold1: float = 0.0 if (column + 1) % 2 == 0 else 0.55
				var a: Vector3 = rows[row] + side * ((u0 - 0.5) * width) + Vector3.UP * fold0
				var b: Vector3 = rows[row] + side * ((u1 - 0.5) * width) + Vector3.UP * fold1
				var c: Vector3 = rows[row + 1] + side * ((u1 - 0.5) * width) + Vector3.UP * fold1
				var d: Vector3 = rows[row + 1] + side * ((u0 - 0.5) * width) + Vector3.UP * fold0
				_triangle(ribbons, a, b, c, Color.WHITE, Vector2(u0, drops[row]), Vector2(u1, drops[row]), Vector2(u1, drops[row + 1]))
				_triangle(ribbons, a, c, d, Color.WHITE, Vector2(u0, drops[row]), Vector2(u1, drops[row + 1]), Vector2(u0, drops[row + 1]))
		for lobe in range(5):
			var center: Vector3 = landing + side * ((lobe - 2) * width * 0.20) + front * (1.5 + (lobe % 2) * 0.8)
			center.y = water_y + 0.35
			_add_lobe(foam, center, Vector3(width * 0.20, 2.3 + (lobe % 2) * 0.8, 2.4), Color.WHITE, 8, 3)
		_report.waterfall_connections.append({"instance_id": identity, "source_sha256": TE04_SHA,
			"source_local_outlet": [TE04_OUTLET.x, TE04_OUTLET.y, TE04_OUTLET.z],
			"outlet": [outlet.x, outlet.y, outlet.z], "lip": [lip.x, lip.y, lip.z],
			"landing": [landing.x, landing.y, landing.z], "width_m": width,
			"water_y_m": water_y, "foundation_id": foundation_id,
			"foundation_triangles": foundation.size(), "profile_rows": rows.size(),
			"profile_method": offline.get("method", "exact_procedural_core_upper_envelope"),
			"profile_scope": offline.get("scope", "procedural_foundation_only"),
			"root_clearance_m": 0.38, "native_visual_review_required": true})
		count += 1
	if count > 0:
		_finish_mesh(ribbons, parent, "PaperWaterfallContinuations", _water_material(Color("83cdd2"), true, false), "waterfall_ribbons")
		_finish_mesh(foam, parent, "PaperFoldedSplash", _cloud_material(Color("edf5e7"), 0.0), "waterfall_foam")

func _clip_profile_side(polygon: Array, origin: Vector3, side: Vector3,
		threshold: float, keep_above: bool) -> Array:
	var result: Array = []
	if polygon.is_empty():
		return result
	var previous: Vector3 = polygon[-1]
	var previous_distance: float = (previous - origin).dot(side) - threshold
	for current: Vector3 in polygon:
		var current_distance: float = (current - origin).dot(side) - threshold
		var previous_in: bool = previous_distance >= 0.0 if keep_above else previous_distance <= 0.0
		var current_in: bool = current_distance >= 0.0 if keep_above else current_distance <= 0.0
		if previous_in != current_in:
			result.append(previous.lerp(current, previous_distance / (previous_distance - current_distance)))
		if current_in:
			result.append(current)
		previous = current
		previous_distance = current_distance
	return result

func _foundation_profile(triangles: Array, lip: Vector3, front: Vector3,
		side: Vector3, width: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if triangles.is_empty():
		return result
	var edges: Array = []
	var knots: Array[float] = [0.0]
	for triangle in triangles:
		var polygon: Array = _clip_profile_side(_clip_profile_side(triangle, lip, side,
			-width * 0.5, true), lip, side, width * 0.5, false)
		for index in polygon.size():
			var a: Vector3 = polygon[index]
			var b: Vector3 = polygon[(index + 1) % polygon.size()]
			var ta: float = (a - lip).dot(front)
			var tb: float = (b - lip).dot(front)
			if absf(ta - tb) < 0.0001:
				continue
			var low: float = maxf(0.0, minf(ta, tb))
			var high: float = minf(130.0, maxf(ta, tb))
			if high <= low:
				continue
			var slope: float = (b.y - a.y) / (tb - ta)
			var intercept: float = a.y - slope * ta
			edges.append([low, high, slope, intercept])
			knots.append(low)
			knots.append(high)
	# Upper envelopes can also change where two projected edges intersect.
	for i in edges.size():
		var a: Array = edges[i]
		for j in range(i + 1, edges.size()):
			var b: Array = edges[j]
			if absf(float(a[2]) - float(b[2])) < 0.00001:
				continue
			var crossing: float = (float(b[3]) - float(a[3])) / (float(a[2]) - float(b[2]))
			if crossing > maxf(float(a[0]), float(b[0])) and crossing < minf(float(a[1]), float(b[1])):
				knots.append(crossing)
	if edges.is_empty():
		return result
	knots.sort()
	# Insert the water crossings as well; the last row ends at real water.
	var expanded: Array[float] = []
	for knot: float in knots:
		if expanded.is_empty() or knot - expanded[-1] > 0.002:
			expanded.append(knot)
	var previous_height: float = INF
	var previous_distance: float = 0.0
	for distance: float in expanded:
		var point: Vector3 = lip + front * distance
		var height: float = -INF
		for edge in edges:
			if distance >= float(edge[0]) - 0.002 and distance <= float(edge[1]) + 0.002:
				height = maxf(height, float(edge[2]) * distance + float(edge[3]) + 0.38)
		var water_y: float = _water_height_at(point)
		if not is_finite(height):
			continue
		if is_finite(water_y) and height <= water_y + 0.20 and distance > 2.0:
			if is_finite(previous_height) and previous_height > water_y + 0.20:
				var fraction: float = (previous_height - water_y - 0.20) / (previous_height - height)
				point = lip + front * lerpf(previous_distance, distance, fraction)
			point.y = water_y + 0.20
			result.append(point)
			return result
		point.y = height
		result.append(point)
		previous_height = height
		previous_distance = distance
	# A broad rib can end just above the river after the toe has submerged.
	# Move past the maximum extent of every clipped face before its last drop.
	if not result.is_empty():
		var outside: Vector3 = lip + front * (expanded[-1] + 0.8)
		var water_y: float = _water_height_at(outside)
		if is_finite(water_y):
			outside.y = water_y + 0.20
			result.append(outside)
			return result
	return [] as Array[Vector3]

func _add_lobe(surface: SurfaceTool, center: Vector3, radius: Vector3, color: Color,
		segments := 10, rings := 4, complete := false) -> void:
	# Sky lobes are complete solids; contact foam/low clouds meet the water.
	var ring_count: int = rings * 2 if complete else rings
	for ring in range(ring_count):
		var theta0: float = -PI * 0.5 + float(ring) / ring_count * PI if complete else float(ring) / rings * PI * 0.5
		var theta1: float = -PI * 0.5 + float(ring + 1) / ring_count * PI if complete else float(ring + 1) / rings * PI * 0.5
		for sector in range(segments):
			var phi0: float = float(sector) / segments * TAU
			var phi1: float = float(sector + 1) / segments * TAU
			var a := center + Vector3(cos(phi0) * cos(theta0), sin(theta0), sin(phi0) * cos(theta0)) * radius
			var b := center + Vector3(cos(phi1) * cos(theta0), sin(theta0), sin(phi1) * cos(theta0)) * radius
			var c := center + Vector3(cos(phi1) * cos(theta1), sin(theta1), sin(phi1) * cos(theta1)) * radius
			var d := center + Vector3(cos(phi0) * cos(theta1), sin(theta1), sin(phi0) * cos(theta1)) * radius
			if not (complete and ring == 0):
				_triangle(surface, a, b, c, color)
			if ring < ring_count - 1:
				_triangle(surface, a, c, d, color)
			if ring == 0 and not complete:
				_triangle(surface, center, b, a, color)

func _add_cloud_cluster(surface: SurfaceTool, center: Vector3, size: Vector3,
		seed_value: int, lobes := 5, complete := false) -> void:
	if complete:
		# A broad heart and embedded unequal shoulders form one cloud mass.
		# Deep overlaps hide most individual ellipsoid outlines; the raised
		# off-centre crown gives an irregular upper edge rather than beads.
		var mirror: float = -1.0 if seed_value % 2 == 0 else 1.0
		var crown_shift: float = 0.07 * sin(float(seed_value) * 1.3)
		var masses := [
			[Vector3(-0.06, 0.0, 0.0), Vector3(0.40, 0.78, 0.52)],
			[Vector3(-0.34, -0.16, 0.015), Vector3(0.24, 0.48, 0.37)],
			[Vector3(0.28, -0.10, -0.025), Vector3(0.28, 0.56, 0.41)],
			[Vector3(0.07 + crown_shift, 0.36, -0.025), Vector3(0.25, 0.66, 0.40)],
			[Vector3(-0.22, 0.20, 0.03), Vector3(0.19, 0.44, 0.35)],
			[Vector3(0.02, -0.31, 0.08), Vector3(0.31, 0.37, 0.46)]
		]
		for index in masses.size():
			var offset: Vector3 = masses[index][0] * size
			offset.x *= mirror
			var radius: Vector3 = masses[index][1] * size
			# One tonal family avoids drawing a separate outline around lobes.
			var shade: float = 0.985 + 0.012 * sin(float(index + seed_value))
			_add_lobe(surface, center + offset, radius, Color(shade, shade, shade, 1.0), 10, 4, true)
		return
	for lobe in range(lobes):
		var phase: float = float(lobe + seed_value) * 1.91
		var offset := Vector3((float(lobe) / maxf(float(lobes - 1), 1.0) - 0.5) * size.x,
			(size.y * 0.22 if complete else 0.9) * sin(phase), cos(phase) * size.z * 0.26)
		var radius := Vector3(size.x * (0.25 + 0.035 * sin(phase)), size.y * (0.62 + 0.28 * absf(sin(phase))), size.z * 0.42)
		var shade: float = 0.96 + 0.04 * sin(phase * 0.7)
		_add_lobe(surface, center + offset, radius, Color(shade, shade, shade, 1.0), 10, 4, complete)

func _add_clouds(parent: Node3D) -> void:
	var low := _new_surface()
	# Discontinuous islands leave exposed water and the full track silhouettes.
	var patches := [Vector2(-76, 185), Vector2(107, 350), Vector2(-83, 490),
		Vector2(104, 635), Vector2(-92, 805), Vector2(80, 920), Vector2(6, 80)]
	for index in patches.size():
		var point: Vector2 = patches[index]
		var center := Vector3(point.x, 0, point.y)
		var water_y: float = _water_height_at(center)
		if not is_finite(water_y):
			continue
		center.y = water_y + 1.5
		_add_cloud_cluster(low, center, Vector3(64 + (index % 3) * 12, 10 + (index % 2) * 4, 42), index)
		_report.low_cloud_clusters += 1
	_finish_mesh(low, parent, "PaperLowCloudSea", _cloud_material(Color("eff4eb"), 0.12), "low_cloud_sea", 1700)
	var sky := _new_surface()
	# Three restrained folded clouds behind the canyon skyline, not fog at eye level.
	for item in [[Vector3(-310, 275, -390), Vector3(180, 45, 70)],
		[Vector3(250, 245, -560), Vector3(155, 42, 76)],
		[Vector3(550, 280, -780), Vector3(220, 62, 95)]]:
		_add_cloud_cluster(sky, item[0], item[1], int(_report.sky_cloud_clusters) + 17, 5, true)
		_report.sky_cloud_clusters += 1
	_finish_mesh(sky, parent, "PaperSkyClouds", _cloud_material(Color("fff5e4"), 0.25), "sky_paper_clouds", 3000)

func _add_transfer_atmosphere(parent: Node3D) -> void:
	# Work only from imported N03 top triangles. N02 arrays and authored geometry
	# are restored untouched; no world-Z tiling or invented TE04 connections.
	var canyon_water := _water_triangles
	_water_triangles = _transfer_water_triangles
	var centers: Array[Vector3] = []
	var patches: Array = []
	# Area-weighted triangle centroids provide route-following candidates; minimum
	# separation bounds density regardless of how many mesh chunks were exported.
	var candidates := []
	for triangle in _water_triangles:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var area := (b-a).cross(c-a).length()*0.5
		if area < 40.0: continue
		candidates.append({"center":(a+b+c)/3.0,"area":area})
	candidates.sort_custom(func(a,b): return a.area>b.area)
	for item in candidates:
		var center: Vector3 = item.center
		var separated := true
		for placed: Vector3 in centers:
			if Vector2(center.x-placed.x,center.z-placed.z).length()<90.0:
				separated = false
				break
		if not separated: continue
		centers.append(center)
		var index := centers.size()-1
		patches.append([Vector2(center.x,center.z),Vector2(22+(index%3)*7,32+(index%4)*6),sin(float(index)*1.71)*0.55])
		if centers.size()>=14: break
	if not patches.is_empty():
		_add_water_layers(parent,patches,"N03PaperWaterCutLayers","vertical")
	_report.transfer_water_patches = patches.size()
	var low := _new_surface()
	var cloud_centers: Array[Vector3] = []
	for center: Vector3 in _transfer_edge_candidates():
		var separated := true
		for placed: Vector3 in cloud_centers:
			if Vector2(center.x-placed.x,center.z-placed.z).length()<190.0: separated = false
		if not separated: continue
		# Full connected cloud silhouette, compressed into a low shelf. Its whole
		# conservative XZ rectangle is sampled against actual water, including drift.
		var size := Vector3(105,6,45)
		var fits := false
		for attempt in 3:
			fits = _transfer_cloud_fits(center,size)
			if fits: break
			size.x *= 0.78
			size.z *= 0.78
		if not fits: continue
		center.y = _water_height_at(center)-2.5
		_add_cloud_cluster(low,center,size,41+cloud_centers.size(),5,true)
		cloud_centers.append(center)
		_report.transfer_cloud_centers.append([center.x,center.y,center.z])
		if cloud_centers.size()>=4: break
	if not cloud_centers.is_empty():
		_finish_mesh(low,parent,"N03PaperLowCloudShelves",_cloud_material(Color("eff4eb"),0.08),"low_cloud_sea",1700.0,"vertical")
	_report.transfer_low_cloud_clusters = cloud_centers.size()
	_report["transfer_boundary_method"] = "Water patches exact triangle clipping; cloud conservative rectangles sampled at 7x5 points with drift margin; low shelves below gameplay, no extended TE04 falls."
	_water_triangles = canyon_water

func _transfer_cloud_fits(center: Vector3, size: Vector3) -> bool:
	# Complete-cluster XZ extents are below 0.59*x and 0.55*z.
	for ix in range(7):
		for iz in range(5):
			var point := center+Vector3((float(ix)/6.0*2.0-1.0)*(size.x*0.60+0.1),0,(float(iz)/4.0*2.0-1.0)*(size.z*0.56+0.1))
			if not is_finite(_water_height_at(point)): return false
	return true

func _transfer_edge_candidates() -> Array[Vector3]:
	# Remove shared top-triangle edges, including exported chunk seams. The
	# remaining boundary edges locate shoreline shelves rather than a cloud grid.
	var edges := {}
	for triangle in _water_triangles:
		var triangle_center: Vector3 = (triangle[0]+triangle[1]+triangle[2])/3.0
		for i in 3:
			var a: Vector3 = triangle[i]
			var b: Vector3 = triangle[(i+1)%3]
			var ka := "%d,%d" % [roundi(a.x*100),roundi(a.z*100)]
			var kb := "%d,%d" % [roundi(b.x*100),roundi(b.z*100)]
			var key := ka+"/"+kb if ka<kb else kb+"/"+ka
			if edges.has(key): edges[key].count += 1
			else: edges[key] = {"count":1,"a":a,"b":b,"inside":triangle_center}
	var candidates: Array[Vector3] = []
	for edge in edges.values():
		if edge.count!=1: continue
		var midpoint: Vector3 = (edge.a+edge.b)*0.5
		var inward: Vector3 = edge.inside-midpoint
		inward.y = 0.0
		if inward.length()<1.0: continue
		candidates.append(midpoint+inward.normalized()*minf(72.0,inward.length()*0.8))
	return candidates

func _add_world_atmosphere(parent: Node3D) -> void:
	# Exact imported basin triangles clip the cut-paper layers; no water outside
	# the authored footprint. Reservoir and harbor stay clear; waterfall foam
	# belongs to the authored falls, rather than white flattened islands.
	var original_water := _water_triangles
	_report["world_water_layers"] = {}
	for region in _world_water_triangles:
		_water_triangles = _world_water_triangles[region]
		var patches: Array = []
		for index in range(0, _water_triangles.size(), 17):
			var tri: Array = _water_triangles[index]
			var center: Vector3 = (tri[0]+tri[1]+tri[2])/3.0
			var separated := true
			for patch in patches:
				if Vector2(center.x,center.z).distance_to(patch[0]) < 155.0: separated = false
			if not separated: continue
			patches.append([Vector2(center.x,center.z),Vector2(76,110),sin(float(index))*0.65])
		if not patches.is_empty(): _add_water_layers(parent, patches, "WorldPaperWaterLayers_"+region, region)
		_report.world_water_layers[region] = {"patches":patches.size(),"low_clouds":0,"source_triangles":_water_triangles.size()}
	_water_triangles = original_water

func _add_world_sky(parent: Node3D) -> void:
	var centers := [Vector3(1150,240,-1400),Vector3(1800,270,-1700),
		Vector3(2800,280,-1850),Vector3(4400,250,-2500),Vector3(3900,260,-3500),
		Vector3(4700,260,-1000),Vector3(4600,250,500),Vector3(2400,250,300)]
	for index in centers.size():
		var sky := _new_surface()
		_add_cloud_cluster(sky,centers[index],Vector3(220+float(index%3)*35,105+float(index%2)*16,150),101+index,5,true)
		_finish_mesh(sky,parent,"WorldPaperSky_"+str(index),_cloud_material(Color("fff5e4"),0.20),"sky_paper_clouds",3500,"coaster" if index<2 else "valley")
	_report["world_sky_clouds"] = centers.size()

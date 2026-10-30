extends RefCounted
## S8 calibration overlay. Source GLBs/materials and frozen gameplay stay immutable.
## calibration.json: assets[{id, role, source:{path,sha256}, source_to_normalized:[16],
## result_size_m:[3], source_up, source_front, source_front_vector?:[3]}], placements[{id,asset_id,space_id,
## source_proxy_instance_id,position:[3],yaw_radians,uniform_scale}].
## Matrices are column-major. Placements use WORLD metres; normalization is applied once.
const ProxyWorld = preload("res://../art/train-parkour/shared/tools/proxy_world.gd")
const CASE := "res://../art/train-parkour/"
const TRAIN_PAINT = preload("res://../art/train-parkour/shared/tools/lux_train_paint.gdshader")
const GEOMETRY_PATH := "Actors/Train/VisualRoot/TrickPivot/Geometry"
const AXES := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
const EPS := 0.0001
# Bounded caches: source vertices once per mesh; a few relative bases, never positions.
const MAX_VERTEX_CACHE_MESHES := 32
const MAX_BASIS_CACHE_PER_MESH := 4
var _geometry_cache: Dictionary = {}
var _geometry_tick := 0
var _vertex_reads := 0
var _basis_evaluations := 0
var _basis_hits := 0
var errors: Array[String] = []
var warnings: Array[String] = []
var templates: Dictionary = {}
var asset_reports: Array = []
var instance_reports: Array = []
var added_bounds: Array = []
var replaced_ids: Array[String] = []
var sid := ""

func build_style(session: Node3D, style_id: String) -> Node3D:
	_reset()
	sid = style_id
	var proxy: Node3D = ProxyWorld.new().build_style(session, sid)
	var old_report: Dictionary = proxy.get_meta("construction_report", {}).duplicate(true)
	var old_geometry: Dictionary = proxy.get_meta("proxy_geometry", {}).duplicate(true)
	proxy.set_meta("proxy_construction_report", old_report)
	proxy.set_meta("proxy_geometry_before_calibration", old_geometry)
	var before_collisions := _collision_count(session)
	var config_path := CASE + "styles/" + sid + "/runtime/calibration.json"
	var descriptor: Variant = null
	if FileAccess.file_exists(config_path):
		descriptor = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not descriptor is Dictionary:
		errors.append("Missing or invalid calibration descriptor: " + config_path)
	else:
		_apply_descriptor(session, proxy, descriptor)
	for template: Node in templates.values():
		template.free()
	templates.clear()
	var collision_delta := _collision_count(session) - before_collisions
	if collision_delta != 0:
		errors.append("Collision node count changed: " + str(collision_delta))
	var active := _active_geometry(old_geometry)
	proxy.set_meta("proxy_geometry", active)
	var combined_errors: Array = old_report.get("errors", []).duplicate()
	combined_errors.append_array(errors)
	var report := {"schema": 1, "stage": "S8_LUX_CALIBRATION", "style_id": sid,
		"descriptor_path": "art/train-parkour/styles/" + sid + "/runtime/calibration.json",
		"descriptor_sha256": FileAccess.get_sha256(config_path) if FileAccess.file_exists(config_path) else "",
		"assets": asset_reports, "instances": instance_reports, "loaded_source_count": asset_reports.size(),
		"placed_instance_count": instance_reports.size(), "replaced_proxy_instance_ids": replaced_ids,
		"new_collision_nodes": collision_delta, "errors": errors.duplicate(), "warnings": warnings.duplicate(),
		"passed": combined_errors.is_empty(), "calibration_errors": errors.duplicate(),
		"proxy_errors": old_report.get("errors", []).duplicate(),
		"source_material_policy": "Original PBR textures retained; explicit A1 waist-band shader tints only the declared body strip and preserves source metallic/roughness maps",
		"scope": "Only explicitly configured calibration assets; all remaining world geometry is S6 proxy",
		"limits": "Mesh AABB envelopes are conservative, not mesh-solid clearance or H4/fidelity acceptance. Vehicle local bounds are not a dynamic collision test."}
	proxy.set_meta("lux_calibration_report", report)
	var combined: Dictionary = old_report.duplicate(true)
	combined["errors"] = combined_errors
	combined["stage"] = "S8_LUX_CALIBRATION_OVER_S6_PROXY"
	combined["lux_calibration_source_count"] = asset_reports.size()
	combined["lux_calibration_instance_count"] = instance_reports.size()
	combined["new_collision_nodes"] = collision_delta
	combined["fidelity_acceptance"] = "Not assessed; calibration only, remaining world is proxy"
	proxy.set_meta("construction_report", combined)
	return proxy

func _reset() -> void:
	_clear_geometry_cache()
	errors.clear()
	warnings.clear()
	templates.clear()
	asset_reports.clear()
	instance_reports.clear()
	added_bounds.clear()
	replaced_ids.clear()

func _apply_descriptor(session: Node3D, proxy: Node3D, config: Dictionary) -> void:
	if not config.get("assets") is Array or not config.get("placements", []) is Array:
		errors.append("assets and placements must be arrays")
		return
	var specs := {}
	var player_ids: Array[String] = []
	for value: Variant in config.assets:
		if not value is Dictionary:
			errors.append("Asset must be an object")
			continue
		var spec: Dictionary = value
		var ident := str(spec.get("id", ""))
		if ident.is_empty() or specs.has(ident):
			errors.append("Empty or duplicate asset id: " + ident)
			continue
		specs[ident] = spec
		if str(spec.get("role", "")) == "player_vehicle": player_ids.append(ident)
		var template := load_asset(spec)
		if template != null: templates[ident] = template
	if player_ids.size() > 1:
		errors.append("Only one player_vehicle is allowed")
	elif player_ids.size() == 1 and templates.has(player_ids[0]):
		_mount_vehicle(session, templates[player_ids[0]], specs[player_ids[0]])
	var seen := {}
	for value: Variant in config.get("placements", []):
		if not value is Dictionary:
			errors.append("Placement must be an object")
			continue
		var placement: Dictionary = value
		var ident := str(placement.get("id", ""))
		var asset_id := str(placement.get("asset_id", ""))
		if ident.is_empty() or seen.has(ident):
			errors.append("Empty or duplicate placement id: " + ident)
			continue
		seen[ident] = true
		if not templates.has(asset_id) or str(specs[asset_id].get("role", "")) != "environment":
			errors.append("Placement requires a loaded environment asset: " + ident)
			continue
		_place_environment(proxy, templates[asset_id], specs[asset_id], placement)

## Detached source loader is also usable by the pure-load validation script.
func load_asset(spec: Dictionary) -> Node3D:
	var ident := str(spec.get("id", ""))
	if ident.is_empty() or not str(spec.get("role", "")) in ["player_vehicle", "environment"]:
		errors.append("Asset requires id and supported role: " + ident)
		return null
	var source: Variant = spec.get("source")
	if not source is Dictionary:
		errors.append("Missing source object: " + ident)
		return null
	var path := str(source.get("path", ""))
	var expected := str(source.get("sha256", "")).to_lower()
	if path.is_empty() or path.is_absolute_path() or path.contains(":") or ".." in path.split("/") or not path.ends_with(".glb"):
		errors.append("Source must be a project-relative GLB: " + ident)
		return null
	var absolute := ProjectSettings.globalize_path("res://../" + path)
	if expected.length() != 64 or not FileAccess.file_exists(absolute) or FileAccess.get_sha256(absolute) != expected:
		errors.append("Missing source or SHA256 mismatch: " + ident)
		return null
	var up := str(spec.get("source_up", ""))
	var front := str(spec.get("source_front", ""))
	if not valid_source_axes(up, front, spec.get("source_front_vector")):
		errors.append("Declare perpendicular cardinal axes or a finite unit measured source_front_vector: " + ident)
		return null
	if not _valid_vector(spec.get("result_size_m"), true) or not valid_normalization(spec.get("source_to_normalized")):
		errors.append("Invalid dimensions or nonuniform/non-affine normalization: " + ident)
		return null
	if not normalization_aligns_axes(spec.source_to_normalized, up, front, spec.get("source_front_vector")):
		errors.append("Normalization does not map declared axes to Godot +Y/-Z: " + ident)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var result := doc.append_from_file(absolute, state)
	if result != OK:
		errors.append("GLTF parse failed for " + ident + ": " + error_string(result))
		return null
	var imported := doc.generate_scene(state)
	if imported == null:
		errors.append("GLTF scene generation failed: " + ident)
		return null
	var forbidden := forbidden_nodes(imported)
	if not forbidden.is_empty():
		errors.append("Static visual source contains unsupported nodes: " + ident + " " + str(forbidden))
		imported.free()
		return null
	var normalized := Node3D.new()
	normalized.name = "LuxNormalization"
	normalized.transform = matrix_transform(spec.source_to_normalized)
	normalized.add_child(imported)
	var paint_count := 0
	if spec.get("material_adjustment", "") == "restore_blue_waist_band":
		paint_count = _restore_train_paint(normalized, Transform3D.IDENTITY)
		if paint_count == 0:
			errors.append("Requested train paint could not find a textured PBR surface: " + ident)
			normalized.free()
			return null
	var measured := measure(normalized)
	if int(measured.mesh_count) == 0 or not measured.finite or measured.bounds.size.x <= EPS or measured.bounds.size.y <= EPS or measured.bounds.size.z <= EPS:
		errors.append("Empty or nonfinite model geometry: " + ident)
		normalized.free()
		return null
	var expected_size := vector(spec.result_size_m)
	var actual_size: Vector3 = measured.bounds.size
	for axis_index in 3:
		var tolerance := maxf(EPS if front == "measured_vector" else 0.02, expected_size[axis_index] * 0.01)
		if absf(expected_size[axis_index] - actual_size[axis_index]) > tolerance:
			errors.append("Measured normalized size differs from descriptor: " + ident + " actual=" + str(actual_size))
			normalized.free()
			return null
	if FileAccess.get_sha256(absolute) != expected:
		errors.append("Source changed during load: " + ident)
		normalized.free()
		return null
	asset_reports.append({"id": ident, "role": spec.role, "source": {"path": path, "sha256": expected},
		"source_up": up, "source_front": front, "source_front_vector": spec.get("source_front_vector"), "source_to_normalized": spec.source_to_normalized,
		"normalization_scale": normalized.basis.x.length(), "declared_size_m": spec.result_size_m,
		"measured_size_m": array(actual_size), "normalized_bounds": box_record(measured.bounds),
		"measurement_kind": "transformed_referenced_vertices", "conservative_normalized_bounds": box_record(measured.conservative_bounds),
		"mesh_count": measured.mesh_count, "material_statistics": measured.material_statistics,
		"source_unchanged_after_load": true, "material_overrides_added": paint_count, "material_adjustment": spec.get("material_adjustment", "none")})
	return normalized

func _restore_train_paint(node: Node, parent: Transform3D) -> int:
	var at: Transform3D = parent * node.transform if node is Node3D else parent
	var changed := 0
	if node is MeshInstance3D and node.mesh != null:
		for index in node.mesh.get_surface_count():
			var original := node.get_active_material(index) as StandardMaterial3D
			if original == null or original.albedo_texture == null: continue
			var painted := ShaderMaterial.new()
			painted.resource_name = "A1BlueWaistBandPreservingLuxPBR"
			painted.shader = TRAIN_PAINT
			painted.set_shader_parameter("albedo_tex", original.albedo_texture)
			painted.set_shader_parameter("albedo_factor", original.albedo_color)
			painted.set_shader_parameter("metallic_roughness_tex", original.roughness_texture)
			painted.set_shader_parameter("metallic_factor", original.metallic)
			painted.set_shader_parameter("roughness_factor", original.roughness)
			painted.set_shader_parameter("mesh_to_normalized", at)
			node.set_surface_override_material(index, painted)
			changed += 1
	for child: Node in node.get_children(): changed += _restore_train_paint(child, at)
	return changed

func _mount_vehicle(session: Node3D, template: Node3D, spec: Dictionary) -> void:
	var geometry := session.get_node_or_null(GEOMETRY_PATH) as Node3D
	var body := session.get_node_or_null(GEOMETRY_PATH + "/Body") as MeshInstance3D
	if geometry == null or body == null:
		errors.append("Frozen Geometry/Body nodes missing; vehicle not replaced")
		return
	var measured := measure(template)
	var bounds: AABB = measured.bounds
	var envelope := AABB(Vector3(-1.3, 0.0, -6.0), Vector3(2.6, 3.4, 12.0))
	if absf(bounds.position.y) > 0.02 or not envelope.grow(0.02).encloses(bounds):
		errors.append("Vehicle normalization must have bottom=0 and fit frozen 2.6x3.4x12 envelope: " + str(spec.id))
		return
	if bounds.position.z > -5.75 or bounds.end.z < 5.75:
		warnings.append("Vehicle visual front/rear does not explain full +/-6m interaction extent; native contact review required")
	var original_transform := body.transform
	var original_mesh := body.mesh
	var original_parent_transform := geometry.transform
	var mount := Node3D.new()
	mount.name = "LuxPlayerVehicle"
	var model := template.duplicate() as Node3D
	mount.add_child(model)
	var hidden: Array[String] = []
	for child: Node in geometry.get_children():
		if child is Node3D and child.visible:
			hidden.append(str(child.name))
			child.visible = false
	geometry.add_child(mount)
	_tag_tree(mount, sid + ":lux:player", str(spec.id), "station")
	if body.transform != original_transform or body.mesh != original_mesh or geometry.transform != original_parent_transform:
		errors.append("Frozen vehicle reference unexpectedly changed")
	instance_reports.append({"id": sid + ":lux:player", "asset_id": spec.id, "role": "player_vehicle",
		"parent": GEOMETRY_PATH, "mount_transform": transform_array(Transform3D.IDENTITY),
		"hidden_visual_children": hidden, "frozen_body_retained": body.mesh == original_mesh and body.transform == original_transform,
		"bounds_geometry_local_m": box_record(bounds), "mesh_bounds_geometry_local": measured.meshes,
		"bounds_policy": "Not included as stationary environment geometry; follows frozen TrickPivot and Geometry"})

func _place_environment(proxy: Node3D, template: Node3D, spec: Dictionary, placement: Dictionary) -> void:
	var ident := str(placement.id)
	var old_id := str(placement.get("source_proxy_instance_id", ""))
	var space := str(placement.get("space_id", ""))
	var yaw: Variant = placement.get("yaw_radians", 0.0)
	var scale: Variant = placement.get("uniform_scale", 1.0)
	if not _valid_vector(placement.get("position")) or not _number(yaw) or not _number(scale) or float(scale) <= 0 or space.is_empty():
		errors.append("Invalid placement transform/space: " + ident)
		return
	var matches: Array[Node3D] = []
	_find_instance(proxy, old_id, matches)
	if old_id.is_empty() or matches.size() != 1 or replaced_ids.has(old_id) or not matches[0].is_visible_in_tree():
		errors.append("Replacement requires exactly one visible unused proxy instance: " + ident + " -> " + old_id)
		return
	var old := matches[0]
	if old == proxy or old.get_parent() != proxy:
		errors.append("Replacement must target a direct proxy instance, never the world root or a nested part: " + old_id)
		return
	var scene := str(old.get_meta("scene_id", ""))
	if scene.is_empty():
		errors.append("Replacement proxy lacks scene identity: " + old_id)
		return
	var mount := Node3D.new()
	mount.name = ident.validate_node_name()
	mount.add_child(template.duplicate())
	proxy.add_child(mount)
	mount.global_transform = Transform3D(Basis(Vector3.UP, float(yaw)).scaled(Vector3.ONE * float(scale)), vector(placement.position))
	_tag_tree(mount, ident, str(spec.id), scene)
	var measured := measure(mount, proxy.global_transform)
	if not measured.finite or int(measured.mesh_count) == 0:
		errors.append("Invalid placed geometry: " + ident)
		mount.free()
		return
	old.visible = false
	replaced_ids.append(old_id)
	for i in measured.meshes.size():
		var mesh: Dictionary = measured.meshes[i]
		var box: Dictionary = mesh.bounds
		var center := vector(box.position_m) + vector(box.size_m) * 0.5
		added_bounds.append({"id": ident + ":mesh:" + str(i), "style_id": sid, "space_id": space,
			"category": "background_mass", "center_m": array(center), "size_m": box.size_m,
			"basis_columns": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "protected_route": false,
			"bounds_kind": mesh.get("bounds_kind", "vertex_aabb_conservative_solid"), "mesh_path": mesh.path,
			"mesh_local_aabb": mesh.local_aabb, "mesh_to_world": mesh.transform,
			"source_asset_id": spec.id, "source_sha256": spec.source.sha256})
	instance_reports.append({"id": ident, "asset_id": spec.id, "role": "environment", "space_id": space,
		"scene_id": scene, "source_proxy_instance_id": old_id, "position": placement.position,
		"yaw_radians": yaw, "uniform_scale": scale, "bounds_world_m": box_record(measured.bounds),
		"mesh_count": measured.mesh_count, "source_to_normalized_applied_once": true})

func _active_geometry(original: Dictionary) -> Dictionary:
	var active := original.duplicate(true)
	var items: Array = []
	for item: Dictionary in original.get("items", []):
		var removed := false
		for ident in replaced_ids:
			if str(item.get("id", "")) == ident or str(item.get("id", "")).begins_with(ident + ":"): removed = true
		if not removed: items.append(item)
	items.append_array(added_bounds)
	active["items"] = items
	active["placements"] = original.get("placements", []).filter(func(p): return not str(p.get("id", "")) in replaced_ids)
	active["lux_calibration_placements"] = instance_reports.filter(func(p): return p.role == "environment")
	active["scope"] = "Visible S6 proxy plus explicit S8 calibration replacements; real recursive mesh AABBs, no collision changes"
	return active

func _find_instance(node: Node, ident: String, found: Array[Node3D]) -> void:
	if node is Node3D and str(node.get_meta("instance_id", "")) == ident: found.append(node)
	for child: Node in node.get_children(): _find_instance(child, ident, found)

func _tag_tree(node: Node, ident: String, asset_id: String, scene_id: String) -> void:
	# Imported extras cannot shadow the assembly registration inherited by meshes.
	node.set_meta("instance_id", ident)
	node.set_meta("asset_id", asset_id)
	node.set_meta("scene_id", scene_id)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children(): _tag_tree(child, ident, asset_id, scene_id)

func _collision_count(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D else 0
	for child: Node in node.get_children(): count += _collision_count(child)
	return count

func forbidden_nodes(node: Node) -> Array[String]:
	var found: Array[String] = []
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D or node is Camera3D or node is Light3D or node is AnimationPlayer or node is Skeleton3D or node.get_script() != null:
		found.append(str(node.name) + ":" + node.get_class())
	for child: Node in node.get_children(): found.append_array(forbidden_nodes(child))
	return found

## Accumulate EVERY ancestor, including imported scene and normalization roots.
## Actual vertex AABBs drive dimensions and conservative geometry reports.
## The older transformed local-box envelope is retained separately for audit.
## Neither envelope is a solid/aperture or dynamic collision proof.
func measure(node: Node, parent_transform := Transform3D.IDENTITY) -> Dictionary:
	var meshes: Array = []
	var materials := {}
	var textures := {}
	_collect(node, parent_transform, str(node.name), meshes, materials, textures)
	var merged := AABB()
	var conservative := AABB()
	var finite := not meshes.is_empty()
	var surfaces := 0
	var textured := 0
	for i in meshes.size():
		var row: Dictionary = meshes[i]
		var box := AABB(vector(row.vertex_bounds.position_m), vector(row.vertex_bounds.size_m))
		var envelope := AABB(vector(row.transformed_local_aabb.position_m), vector(row.transformed_local_aabb.size_m))
		merged = box if i == 0 else merged.merge(box)
		conservative = envelope if i == 0 else conservative.merge(envelope)
		finite = finite and bool(row.vertex_bounds_valid) and box.position.is_finite() and box.size.is_finite() and envelope.position.is_finite() and envelope.size.is_finite()
		surfaces += int(row.surface_count)
		textured += int(row.textured_surfaces)
	return {"bounds": merged, "conservative_bounds": conservative, "bounds_kind": "vertex_aabb_conservative_solid",
		"finite": finite, "mesh_count": meshes.size(), "meshes": meshes,
		"material_statistics": {"material_count": materials.size(), "texture_count": textures.size(),
			"surface_count": surfaces, "textured_surface_count": textured, "materials": materials.values()}}

func _collect(node: Node, parent: Transform3D, path: String, rows: Array, materials: Dictionary, textures: Dictionary) -> void:
	var at: Transform3D = parent * node.transform if node is Node3D else parent
	if node is MeshInstance3D and node.mesh != null:
		var local: AABB = node.mesh.get_aabb()
		var box: AABB = at * local
		var vertex_measure := _vertex_bounds(node.mesh, at)
		var textured := 0
		for index in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(index)
			var has_texture := false
			if material != null:
				var key := material.get_instance_id()
				var channels: Array[String] = []
				if material is BaseMaterial3D:
					var available := {}
					for property: Dictionary in material.get_property_list(): available[str(property.name)] = true
					for channel in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "orm_texture", "ao_texture", "emission_texture"]:
						if not available.has(channel): continue
						var texture: Variant = material.get(channel)
						if texture is Texture2D:
							textures[texture.get_instance_id()] = true
							channels.append(channel)
							has_texture = true
				if material is ShaderMaterial:
					for channel in ["albedo_tex", "metallic_roughness_tex"]:
						var texture: Variant = material.get_shader_parameter(channel)
						if texture is Texture2D:
							textures[texture.get_instance_id()] = true
							channels.append(channel)
							has_texture = true
				materials[key] = {"name": material.resource_name, "class": material.get_class(), "texture_channels": channels}
			if has_texture: textured += 1
		rows.append({"path": path, "bounds": box_record(vertex_measure.bounds), "bounds_kind": "vertex_aabb_conservative_solid",
			"bounds_measurement": "transformed_referenced_vertices", "transformed_local_aabb": box_record(box),
			"vertex_bounds": box_record(vertex_measure.bounds), "vertex_bounds_valid": vertex_measure.finite, "local_aabb": box_record(local),
			"transform": transform_array(at), "surface_count": node.mesh.get_surface_count(), "textured_surfaces": textured})
	for child: Node in node.get_children(): _collect(child, at, path + "/" + str(child.name), rows, materials, textures)

func _clear_geometry_cache() -> void:
	for key: int in _geometry_cache.keys(): _drop_geometry_cache(key)
	_geometry_tick = 0
	_vertex_reads = 0
	_basis_evaluations = 0
	_basis_hits = 0

func _drop_geometry_cache(key: int) -> void:
	if not _geometry_cache.has(key): return
	var mesh: Mesh = _geometry_cache[key].weak_mesh.get_ref()
	var callback := Callable(self,"_drop_geometry_cache").bind(key)
	if mesh != null and mesh.changed.is_connected(callback): mesh.changed.disconnect(callback)
	_geometry_cache.erase(key)

func geometry_cache_stats() -> Dictionary:
	var points := 0
	var bases := 0
	for entry: Dictionary in _geometry_cache.values():
		points += entry.vertices.size()
		bases += entry.bases.size()
	return {"mesh_count":_geometry_cache.size(),"vertex_count":points,"basis_count":bases,
		"vertex_reads":_vertex_reads,"basis_evaluations":_basis_evaluations,"basis_hits":_basis_hits}

func _cached_vertices(mesh: Mesh) -> Dictionary:
	var key := mesh.get_instance_id()
	_geometry_tick += 1
	if _geometry_cache.has(key):
		_geometry_cache[key].tick = _geometry_tick
		return _geometry_cache[key]
	# Remove dead resources, then the least recently used entry. No Mesh is retained.
	for old_key: int in _geometry_cache.keys():
		if _geometry_cache[old_key].weak_mesh.get_ref() == null: _drop_geometry_cache(old_key)
	if _geometry_cache.size() >= MAX_VERTEX_CACHE_MESHES:
		var oldest: int = _geometry_cache.keys()[0]
		for old_key: int in _geometry_cache:
			if int(_geometry_cache[old_key].tick) < int(_geometry_cache[oldest].tick): oldest = old_key
		_drop_geometry_cache(oldest)
	var vertices := PackedVector3Array()
	var finite := true
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: continue
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
		if indices is PackedInt32Array and not indices.is_empty():
			# Unreferenced accessor positions are not rendered geometry.
			var seen := PackedByteArray(); seen.resize(points.size())
			for index: int in indices:
				if index < 0 or index >= points.size():
					finite = false
					continue
				if seen[index] != 0: continue
				seen[index] = 1
				finite = finite and points[index].is_finite()
				vertices.append(points[index])
		else:
			for point: Vector3 in points:
				finite = finite and point.is_finite()
				vertices.append(point)
	var entry := {"weak_mesh":weakref(mesh),"vertices":vertices,"finite":finite and not vertices.is_empty(),"bases":[],"tick":_geometry_tick}
	_geometry_cache[key] = entry
	mesh.changed.connect(Callable(self,"_drop_geometry_cache").bind(key))
	_vertex_reads += 1
	return entry

func _vertex_bounds(mesh: Mesh, at: Transform3D) -> Dictionary:
	if not at.is_finite(): return {"bounds":AABB(),"finite":false}
	var entry := _cached_vertices(mesh)
	if not entry.finite: return {"bounds":AABB(),"finite":false}
	# Factor positive uniform magnitude and translation out of the key. Shear and
	# nonuniform imported-node transforms still remain in the relative basis.
	var magnitude := maxf(at.basis.x.length(),maxf(at.basis.y.length(),at.basis.z.length()))
	if not is_finite(magnitude) or magnitude <= 0: return {"bounds":AABB(),"finite":false}
	var relative := at.basis.scaled(Vector3.ONE/magnitude)
	var bounds := AABB()
	var found := false
	for cached: Dictionary in entry.bases:
		if cached.basis == relative:
			bounds = cached.bounds
			found = true
			_basis_hits += 1
			break
	if not found:
		var vertices: PackedVector3Array = entry.vertices
		var low := relative*vertices[0]
		var high := low
		for point: Vector3 in vertices:
			var transformed := relative*point
			low = low.min(transformed); high = high.max(transformed)
		bounds = AABB(low,high-low)
		if entry.bases.size() >= MAX_BASIS_CACHE_PER_MESH: entry.bases.pop_front()
		entry.bases.append({"basis":relative,"bounds":bounds})
		_basis_evaluations += 1
	return {"bounds":AABB(bounds.position*magnitude+at.origin,bounds.size*magnitude),"finite":true}

func valid_normalization(value: Variant) -> bool:
	if not value is Array or value.size() != 16: return false
	for n: Variant in value:
		if not _number(n): return false
	if absf(float(value[3])) > EPS or absf(float(value[7])) > EPS or absf(float(value[11])) > EPS or absf(float(value[15]) - 1.0) > EPS: return false
	var basis := matrix_transform(value).basis
	var scale := basis.get_scale()
	if scale.x <= EPS or basis.determinant() <= 0: return false
	if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z): return false
	var unit := basis.scaled(Vector3.ONE / scale.x)
	return absf(unit.x.dot(unit.y)) < EPS and absf(unit.x.dot(unit.z)) < EPS and absf(unit.y.dot(unit.z)) < EPS

func matrix_transform(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[4], a[5], a[6]), Vector3(a[8], a[9], a[10])), Vector3(a[12], a[13], a[14]))

func valid_source_axes(up: String, front: String, measured_front: Variant = null) -> bool:
	if not up in AXES: return false
	if front == "measured_vector":
		if not _valid_vector(measured_front): return false
		var direction := vector(measured_front)
		return absf(direction.length() - 1.0) <= EPS and absf(direction.dot(axis_vector(up))) <= EPS
	# A vector accompanying a cardinal declaration is ambiguous, never silently ignored.
	return front in AXES and up.right(1) != front.right(1) and measured_front == null

func normalization_aligns_axes(value: Array, up: String, front: String, measured_front: Variant = null) -> bool:
	if not valid_normalization(value) or not valid_source_axes(up, front, measured_front): return false
	var alignment := matrix_transform(value).basis
	var direction := vector(measured_front) if front == "measured_vector" else axis_vector(front)
	return (alignment * axis_vector(up)).normalized().is_equal_approx(Vector3.UP) and (alignment * direction).normalized().is_equal_approx(Vector3.FORWARD)

func axis_vector(axis: String) -> Vector3:
	var result := Vector3.ZERO
	result["XYZ".find(axis.right(1))] = 1.0 if axis.begins_with("+") else -1.0
	return result

func transform_array(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, 0, t.basis.y.x, t.basis.y.y, t.basis.y.z, 0,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, 0, t.origin.x, t.origin.y, t.origin.z, 1]

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _valid_vector(value: Variant, positive := false) -> bool:
	if not value is Array or value.size() != 3: return false
	for n: Variant in value:
		if not _number(n) or (positive and float(n) <= 0): return false
	return true

func vector(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func box_record(box: AABB) -> Dictionary:
	return {"position_m": array(box.position), "size_m": array(box.size)}

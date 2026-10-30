extends "res://themes/performance_lod/exact_static_merge.gd"
## Optional v2: retain original local-space outline extrusion in a static cell.
const ORIGINAL_OUTLINE_PATH := "res://themes/halloween_07/outline.gdshader"
const ORIGINAL_OUTLINE_SHA256 := "98ad97dc101466526a5eb15df162d5089e60dc27a5539b6f3724feded39c40e4"
const OFFSET_OUTLINE = preload("res://themes/performance_lod/outline_world_offset.gdshader")
const OFFSET_OUTLINE_SHA256 := "2e36c6734f5606f07fe6aef466095c13d9a1638fbba896d419eca78e6d285457"
const MAX_OUTLINE_GEOMETRY_BYTES := 256 * 1024 * 1024
const EXTRUSION_VECTOR_TOLERANCE := 0.00001

var _outline_approval: Dictionary = {}
var _shared_material_cache: Dictionary = {}
var _created_material_resources := 0
var _cached_outline_geometry_abi := ""

func _init() -> void:
	_report["method"] = "exact_static_cell_material_and_outline_merge"
	_report["outline_source_sha256"] = ORIGINAL_OUTLINE_SHA256
	_report["outline_offset_sha256"] = OFFSET_OUTLINE_SHA256
	_report["max_expanded_bytes"] = MAX_OUTLINE_GEOMETRY_BYTES
	_report["custom0_policy"] = "RGB_FLOAT, three unnormalized float32 values per vertex: original instance basis * source NORMAL"
	_report["expanded_geometry_estimate"] = "Conservative CPU/GPU payload estimate includes 12-byte CUSTOM0 allowance for every accepted vertex, including unoutlined vertices"
	_report["outline_negative_determinant_batches"] = 0
	_report["cell_m"] = null
	_report["cell_dimensions_m"] = [128.0,96.0,128.0]
	_report["cell_policy"] = "Original H07 spatial bins; merge across shape keys within the original cell/material domain"
	_budget = {"used_bytes": 0, "limit_bytes": MAX_OUTLINE_GEOMETRY_BYTES}

func _cost_aware_selection() -> bool:
	return true

func _geometry_cache_abi() -> String:
	if _cached_outline_geometry_abi.is_empty():
		_cached_outline_geometry_abi = super._geometry_cache_abi() + "|outline-Bn-RGBf32/v1|source=" + ORIGINAL_OUTLINE_SHA256 + "|offset=" + OFFSET_OUTLINE_SHA256 + "|module=" + FileAccess.get_sha256("res://themes/performance_lod/exact_outline_merge.gd")
	return _cached_outline_geometry_abi

func _prepare_group_for_cache(group: Dictionary) -> void:
	var outlined: bool = group.material.next_pass != null
	var thickness := _thickness(group.material.next_pass) if outlined else 0.0
	for entry: Dictionary in group.entries:
		entry["outline_merged"] = outlined
		entry["outline_thickness"] = thickness

func _cache_group_policy(group: Dictionary) -> Dictionary:
	var outlined: bool = group.material.next_pass != null
	return {"outlined":outlined,"thickness":_thickness(group.material.next_pass) if outlined else 0.0,"source_outline":ORIGINAL_OUTLINE_SHA256,"offset_outline":OFFSET_OUTLINE_SHA256}

func _merge_cell_size() -> Vector3:
	return Vector3(128.0,96.0,128.0)

func _configure_output_node(node: MeshInstance3D, group: Dictionary) -> void:
	if group.material.next_pass == null: return
	var maximum := 0.0
	var thickness := absf(_thickness(group.material.next_pass))
	for entry: Dictionary in group.entries:
		var b: Basis=entry.pose.basis
		# Frobenius norm bounds ||B*n||, including shear; no outline vertex
		# may be culled merely because its extrusion leaves the base mesh AABB.
		maximum=maxf(maximum,sqrt(b.x.length_squared()+b.y.length_squared()+b.z.length_squared())*thickness*1.0002)
	node.extra_cull_margin=maximum
	node.set_meta("preserved_outline_cull_margin_m",maximum)

func use_shared_material_cache(cache: Dictionary) -> void:
	assert(_source_batches.is_empty(), "Set the shared material cache before collection")
	_shared_material_cache = cache

func _thickness(material: ShaderMaterial) -> float:
	var value: Variant = material.get_shader_parameter("thickness")
	return float(value) if value != null else 0.035

func _approved_material(material: Material, key: String) -> bool:
	if material == null or material.next_pass == null: return super._approved_material(material, key)
	if key.is_empty(): return false
	var ident := material.get_instance_id()
	if _outline_approval.has(ident): return _outline_approval[ident]
	var accepted := false
	if material is ShaderMaterial and material.next_pass is ShaderMaterial and material.next_pass.next_pass == null:
		var shader: Shader = (material as ShaderMaterial).shader
		var edge: ShaderMaterial = material.next_pass
		var edge_shader := edge.shader
		if shader != null and edge_shader != null:
			var main_hash := shader.code.sha256_text()
			var edge_hash := edge_shader.code.sha256_text()
			_report.observed_shader_hashes[main_hash] = shader.resource_path
			_report.observed_shader_hashes[edge_hash] = edge_shader.resource_path
			accepted = shader.resource_path == SHADER_PATH and main_hash == SHADER_SHA256 and edge_shader.resource_path == ORIGINAL_OUTLINE_PATH and edge_hash == ORIGINAL_OUTLINE_SHA256 and OFFSET_OUTLINE.code.sha256_text() == OFFSET_OUTLINE_SHA256 and is_finite(_thickness(edge))
	_outline_approval[ident] = accepted
	return accepted

func _mesh_data(mesh: Mesh) -> Dictionary:
	var data: Dictionary = super._mesh_data(mesh)
	if not data.is_empty() and not data.get("custom0_bytes_accounted", false):
		data["bytes"] = int(data.bytes) + int(data.vertices) * 12
		data["custom0_bytes_accounted"] = true
	return data

func try_add(mesh: Mesh, poses: Array, material: Material, key: String, tag: String, scene_id: String = "station") -> bool:
	if material != null and material.next_pass != null and _approved_material(material, key):
		# Preserve cull_front semantics conservatively. Mirrored instances must
		# retain their original MultiMesh path; a mixed batch is rejected whole.
		for pose: Transform3D in poses:
			if pose.basis.determinant() <= 0.0:
				_retained(poses, material)
				_report.outline_negative_determinant_batches += 1
				return _skip("outlined_nonpositive_determinant")
	return super.try_add(mesh, poses, material, key, tag, scene_id)

func _output_arrays(group: Dictionary) -> Array:
	var arrays: Array = super._output_arrays(group)
	if group.material.next_pass == null: return arrays
	_prepare_group_for_cache(group)
	var offsets := PackedFloat32Array()
	for entry: Dictionary in group.entries:
		var normals: PackedVector3Array = entry.data.arrays[Mesh.ARRAY_NORMAL]
		var pose: Transform3D = entry.pose
		for normal: Vector3 in normals:
			# This must not be normalized or inverse-transposed. Original shader
			# displacement is B * (source_NORMAL * thickness), including scale.
			var offset := pose.basis * normal
			offsets.append(offset.x); offsets.append(offset.y); offsets.append(offset.z)
	arrays[Mesh.ARRAY_CUSTOM0] = offsets
	return arrays

func _build_output_mesh(group: Dictionary) -> ArrayMesh:
	var arrays := _output_arrays(group)
	var flags := 0
	if group.material.next_pass != null:
		flags = Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh

func audit_output(mesh: ArrayMesh, origin: Vector3, entries: Array) -> Dictionary:
	var result: Dictionary = super.audit_output(mesh, origin, entries)
	result["outline_vertices"] = 0
	result["max_custom0_extrusion_error"] = 0.0
	result["max_outline_position_error_m"] = 0.0
	result["custom0_rgb_float_valid"] = true
	if entries.is_empty() or not entries[0].get("outline_merged", false): return result
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var format := mesh.surface_get_format(0)
	var custom: Variant = arrays[Mesh.ARRAY_CUSTOM0]
	result.custom0_rgb_float_valid = custom is PackedFloat32Array and custom.size() == vertices.size() * 3 and (format & Mesh.ARRAY_FORMAT_CUSTOM0) != 0 and ((format >> Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) & Mesh.ARRAY_FORMAT_CUSTOM_MASK) == Mesh.ARRAY_CUSTOM_RGB_FLOAT
	if not result.custom0_rgb_float_valid:
		result.passed = false
		return result
	var cursor := 0
	for entry: Dictionary in entries:
		var source: Array = entry.data.arrays
		var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
		var pose: Transform3D = entry.pose
		var thickness: float = entry.outline_thickness
		for i in source_vertices.size():
			var j := cursor + i
			var actual := Vector3(custom[j*3], custom[j*3+1], custom[j*3+2])
			var expected := pose.basis * source_normals[i]
			result.max_custom0_extrusion_error = maxf(result.max_custom0_extrusion_error, expected.distance_to(actual))
			var old_vertex := pose * (source_vertices[i] + source_normals[i] * thickness)
			var new_vertex := origin + vertices[j] + actual * thickness
			result.max_outline_position_error_m = maxf(result.max_outline_position_error_m, old_vertex.distance_to(new_vertex))
		cursor += source_vertices.size()
	result.outline_vertices = cursor
	result.passed = result.passed and float(result.max_custom0_extrusion_error) <= EXTRUSION_VECTOR_TOLERANCE and float(result.max_outline_position_error_m) <= POSITION_TOLERANCE_M
	return result

func _uniforms_equal(a: ShaderMaterial, b: ShaderMaterial) -> bool:
	if a.shader != b.shader: return false
	for uniform: Dictionary in a.shader.get_shader_uniform_list():
		var parameter: StringName = uniform.name
		var source: Variant = a.get_shader_parameter(parameter)
		var output: Variant = b.get_shader_parameter(parameter)
		if source is Resource:
			if output != source: return false
		elif var_to_bytes(source) != var_to_bytes(output):
			return false
	return true

func _render_material(source: Material) -> Material:
	if source.next_pass == null: return source
	var ident := source.get_instance_id()
	if _shared_material_cache.has(ident): return _shared_material_cache[ident].output
	var source_base := source as ShaderMaterial
	var source_edge := source.next_pass as ShaderMaterial
	var output := source_base.duplicate(false) as ShaderMaterial
	var edge := source_edge.duplicate(false) as ShaderMaterial
	output.shader = source_base.shader
	edge.shader = OFFSET_OUTLINE
	edge.set_shader_parameter("thickness", _thickness(source_edge))
	output.next_pass = edge
	_shared_material_cache[ident] = {"source": source, "source_edge": source.next_pass, "output": output, "edge": edge}
	_created_material_resources += 2
	return output

func _material_equivalent(output: Material, source: Material) -> bool:
	if source.next_pass == null: return super._material_equivalent(output, source)
	var ident := source.get_instance_id()
	if not _shared_material_cache.has(ident): return false
	var record: Dictionary = _shared_material_cache[ident]
	if not source is ShaderMaterial or not source.next_pass is ShaderMaterial or not output is ShaderMaterial or not output.next_pass is ShaderMaterial: return false
	var source_base := source as ShaderMaterial
	var source_edge := source.next_pass as ShaderMaterial
	var output_base := output as ShaderMaterial
	var output_edge := output.next_pass as ShaderMaterial
	return output == record.output and source == record.source and source.next_pass == record.source_edge and _uniforms_equal(source_base, output_base) and output_base.render_priority == source_base.render_priority and output_edge.render_priority == source_edge.render_priority and output_edge.shader == OFFSET_OUTLINE and output_edge.next_pass == null and _thickness(output_edge) == _thickness(source_edge) and source_edge.shader.resource_path == ORIGINAL_OUTLINE_PATH and source_edge.shader.code.sha256_text() == ORIGINAL_OUTLINE_SHA256

func flush(parent: Node3D, fallback: Callable) -> Dictionary:
	var result: Dictionary = super.flush(parent, fallback)
	result["material_resources_cloned"] = _created_material_resources
	result["material_or_texture_copies"] = _created_material_resources
	result["texture_copies_created"] = 0
	result["max_custom0_extrusion_error"] = 0.0
	result["max_outline_position_error_m"] = 0.0
	result["outline_vertices"] = 0
	for group: Dictionary in result.groups:
		var audit: Dictionary = group.audit
		result.outline_vertices += int(audit.get("outline_vertices", 0))
		result.max_custom0_extrusion_error = maxf(result.max_custom0_extrusion_error, float(audit.get("max_custom0_extrusion_error", 0.0)))
		result.max_outline_position_error_m = maxf(result.max_outline_position_error_m, float(audit.get("max_outline_position_error_m", 0.0)))
	return result

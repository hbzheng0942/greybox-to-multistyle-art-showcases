extends RefCounted
## Geometry/visible-attribute preserving batching for the pinned H07 paint shader.
## No face removal, visibility ranges, material copies or alternate silhouettes.

const CELL_M := 64.0
const MAX_EXPANDED_BYTES := 128 * 1024 * 1024
const POSITION_TOLERANCE_M := 0.001
# ArrayMesh repacks transformed normals into the renderer's octahedral format.
# L2 error 0.0002 bounds the angular change to approximately 0.0115 degrees.
const NORMAL_TOLERANCE := 0.0002
const SHADER_PATH := "res://themes/halloween_07/acid_cel.gdshader"
const SHADER_SHA256 := "159ae195076a21e8d0d679c145cfcc2f79a33654271884047bf6adfdbda64b7e"
const GLASS_SHADER_PATH := "res://themes/halloween_07/window_glass.gdshader"
const GLASS_SHADER_SHA256 := "a836c7e3f224c563c02cd5750ca2526c17c204248f16342043d8e01446dc0934"
const GLASS_MATERIAL_KEYS := ["glazing_lit", "glazing_dim", "glazing_dark"]
const MATERIAL_KEYS := ["window_frame", "window_lead", "glazing_lit", "glazing_dim", "glazing_dark", "ink"]
const ATTRIBUTES := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]

var _groups: Dictionary = {}
var _source_batches: Array = []
var _data_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _budget := {"used_bytes": 0, "limit_bytes": MAX_EXPANDED_BYTES}
var _geometry_cache: RefCounted
var _cached_geometry_abi := ""
var _report := {
	"schema": 1, "method": "exact_static_cell_material_merge", "cell_m": CELL_M,
	"source_batches": 0, "source_legacy_chunks": 0, "source_instances": 0,
	"input_tangent_vertices": 0,
	"candidate_geometry_bytes": 0, "fallback_legacy_chunks": 0,
	"cost_skipped_no_gain_groups": 0, "cost_skipped_budget_groups": 0,
	"cost_selected_saved_nodes": 0,
	"glass_shader_sha256": GLASS_SHADER_SHA256,
	"glass_source_batches": 0, "glass_nonpositive_determinant_batches": 0,
	"glass_scope": "Pinned opaque isotropic PBR glass from H07 default _make_batch only; no lightmap/capture, instance GI, instance uniform or custom MultiMesh data",
	"geometry_cache_hits":0,"geometry_cache_misses":0,"geometry_cache_invalid":0,
	"geometry_cache_writes":0,"geometry_cache_resource_bytes_read":0,
	"geometry_cache_new_blob_bytes":0,"geometry_cache_manifest_bytes_written":0,
	"geometry_cache_full_read_audits":0,"geometry_cache_write_failures":0,
	"merged_batches": 0, "merged_instances": 0, "fallback_instances": 0,
	"fallback_triangles": 0, "retained_outline_source_batches": 0,
	"retained_outline_instances": 0, "retained_outline_legacy_chunks": 0,
	"retained_original_source_batches": 0, "retained_original_instances": 0,
	"retained_original_legacy_chunks": 0,
	"triangles_before": 0, "triangles_after": 0, "vertices_after": 0,
	"expanded_geometry_bytes": 0, "max_expanded_bytes": MAX_EXPANDED_BYTES,
	"max_position_error_m": 0.0, "max_normal_error": 0.0,
	"max_uv_error": 0.0, "max_uv2_error": 0.0, "max_color_error": 0.0,
	"shared_original_materials": true, "all_source_triangles_retained": true,
	"visibility_distance_added": false, "material_or_texture_copies": 0,
	"skipped": {}, "groups": [], "errors": [], "passed": true,
	"shader_sha256": SHADER_SHA256,
	"observed_shader_hashes": {},
	"material_semantics_preserved": true,
	"normal_transform": "normalize(instance_basis * source_normal), matching Godot4.7.2 Forward+ MultiMesh under an identity parent",
	"normal_source_reference": "Godot4.7.2 scene_forward_clustered.glsl:238-242,317-322,409,416,427-430",
	"preserved_attributes": ["vertex_position", "triangle_indices", "normal", "UV", "UV2", "COLOR"],
	"tangent_policy": "Input tangents are not retained byte-for-byte. Godot rebuilds unused tangents; the pinned paint and isotropic glass shaders consume no TANGENT, BINORMAL, NORMAL_MAP or ANISOTROPY semantics.",
	"scope": "Static draw-node equivalence only. Actual pixels and performance require native same-view checks."
}

func set_geometry_cache(cache: RefCounted) -> void:
	assert(_source_batches.is_empty(), "Set the geometry cache before collection")
	assert(cache == null or (cache.has_method("lookup") and cache.has_method("store") and cache.has_method("invalidate")), "Use a compatible geometry-only cache")
	_geometry_cache = cache
	_report["geometry_cache_enabled"] = cache != null

func _geometry_cache_abi() -> String:
	if _cached_geometry_abi.is_empty():
		_cached_geometry_abi = "h07-static-Bn-f32-attrs/v1|base=" + FileAccess.get_sha256("res://themes/performance_lod/exact_static_merge.gd") + "|shader=" + SHADER_SHA256 + "|position=" + str(POSITION_TOLERANCE_M) + "|normal=" + str(NORMAL_TOLERANCE)
	return _cached_geometry_abi

func _prepare_group_for_cache(_group: Dictionary) -> void:
	pass

func _cache_group_policy(_group: Dictionary) -> Dictionary:
	return {"outlined":false}

func _cache_signature(group: Dictionary, abi: String) -> String:
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes([abi,group.origin,group.mask,_merge_cell_size(),_cache_group_policy(group)]))
	for entry: Dictionary in group.entries: digest.update(var_to_bytes([entry.data.fingerprint,entry.pose,entry.key,entry.tag]))
	return digest.finish().hex_encode()

func use_shared_budget(budget: Dictionary) -> void:
	assert(_source_batches.is_empty(), "Set the shared budget before collecting geometry")
	_budget = budget

func _cost_aware_selection() -> bool:
	return false

func _ordered_groups() -> Array:
	var ordered: Array = _groups.values()
	if not _cost_aware_selection(): return ordered
	for i in ordered.size(): ordered[i]["selection_order"] = i
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_density: float = float(a.source_ids.size()-1) / float(a.selection_bytes)
		var b_density: float = float(b.source_ids.size()-1) / float(b.selection_bytes)
		if a_density != b_density: return a_density > b_density
		return int(a.selection_order) < int(b.selection_order))
	return ordered

func _queue_cost_fallback(group: Dictionary, pending: Dictionary) -> void:
	for entry: Dictionary in group.entries:
		var source_id: int = entry.source_id
		if not pending.has(source_id): pending[source_id] = {}
		# Pose indices preserve original order and duplicate Transform values.
		pending[source_id][entry.source_pose_index] = true
		_report.fallback_instances += 1
		_report.fallback_triangles += int(entry.data.triangles)
	_report.fallback_legacy_chunks += group.source_ids.size()

func _emit_cost_fallbacks(pending: Dictionary, fallback: Callable) -> void:
	for source_id in _source_batches.size():
		if not pending.has(source_id): continue
		var source: Dictionary = _source_batches[source_id]
		var kept := []
		for pose_index in source.poses.size():
			if pending[source_id].has(pose_index): kept.append(source.poses[pose_index])
		fallback.call(source.mesh,kept,source.key,source.tag,source.scene)

func _merge_cell_size() -> Vector3:
	return Vector3.ONE * CELL_M

func _configure_output_node(_node: MeshInstance3D, _group: Dictionary) -> void:
	pass

func _hash_value(value: Variant) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _legacy_chunk_count(poses: Array) -> int:
	var cells := {}
	for pose: Transform3D in poses: cells[Vector3i(floori(pose.origin.x / 128.0), floori(pose.origin.y / 96.0), floori(pose.origin.z / 128.0))] = true
	return cells.size()

func _retained(poses: Array, material: Material) -> void:
	_report.retained_original_source_batches += 1
	_report.retained_original_instances += poses.size()
	_report.retained_original_legacy_chunks += _legacy_chunk_count(poses)
	if material != null and material.next_pass != null:
		_report.retained_outline_source_batches += 1
		_report.retained_outline_instances += poses.size()
		_report.retained_outline_legacy_chunks += _legacy_chunk_count(poses)

func _skip(reason: String) -> bool:
	_report.skipped[reason] = int(_report.skipped.get(reason, 0)) + 1
	return false

func _approved_material(material: Material, key: String) -> bool:
	if key not in MATERIAL_KEYS or material == null: return false
	if material is ShaderMaterial:
		var glass_shader: Shader = material.shader
		if glass_shader != null and glass_shader.resource_path == GLASS_SHADER_PATH:
			var glass_hash := glass_shader.code.sha256_text()
			_report.observed_shader_hashes[glass_hash] = glass_shader.resource_path
			# Default opaque/cull_back, isotropic GGX. No vertex displacement,
			# normal map, tangent-space anisotropy, alpha or local-space input.
			return key in GLASS_MATERIAL_KEYS and glass_hash == GLASS_SHADER_SHA256 and material.next_pass == null and material.render_priority == 0
	var ident := material.get_instance_id()
	if _material_cache.has(ident): return _material_cache[ident]
	var accepted := false
	if material is ShaderMaterial and material.next_pass == null:
		var shader: Shader = (material as ShaderMaterial).shader
		# The pinned shader derives paint from world positions/normals and optional
		# UVs. Unknown local-coordinate or vertex-displacing shaders are excluded.
		if shader != null:
			var actual_hash := shader.code.sha256_text()
			_report.observed_shader_hashes[actual_hash] = shader.resource_path
			accepted = shader.resource_path == SHADER_PATH and actual_hash == SHADER_SHA256 and not shader.code.contains("TANGENT") and not shader.code.contains("BINORMAL") and not shader.code.contains("NORMAL_MAP")
	_material_cache[ident] = accepted
	return accepted

func _mesh_data(mesh: Mesh) -> Dictionary:
	if mesh == null: return {}
	var ident := mesh.get_instance_id()
	if _data_cache.has(ident): return _data_cache[ident]
	var result: Dictionary = {}
	if mesh.get_surface_count() == 1:
		var triangles := true
		if mesh is ArrayMesh:
			triangles = mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES and mesh.get_blend_shape_count() == 0
		elif not mesh is BoxMesh:
			triangles = false
		if triangles:
			var arrays := mesh.surface_get_arrays(0)
			var vertices := PackedVector3Array(); var normals := PackedVector3Array()
			if arrays[Mesh.ARRAY_VERTEX] != null: vertices = arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_NORMAL] != null: normals = arrays[Mesh.ARRAY_NORMAL]
			var valid := not vertices.is_empty() and normals.size() == vertices.size()
			# This is reached only after the pinned-shader gate. Godot 4.7 may
			# synthesize tangent arrays even when the author supplied none. These
			# tangents have no visible semantics in this reviewed shader; omit the
			# input tangent array and let Godot rebuild it after static baking.
			# Skinning/custom data still requires its original rendering path.
			for slot in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
				if arrays[slot] != null and not arrays[slot].is_empty(): valid = false
			var tangent_vertices := 0
			if arrays[Mesh.ARRAY_TANGENT] != null and not arrays[Mesh.ARRAY_TANGENT].is_empty():
				valid = valid and arrays[Mesh.ARRAY_TANGENT].size() == vertices.size() * 4
				tangent_vertices = vertices.size()
			var mask := 0
			# Include a conservative 16-byte tangent allowance in the shared memory
			# budget even though the input tangent data is not copied.
			var stride := 40
			for slot in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				if arrays[slot] != null and not arrays[slot].is_empty():
					valid = valid and arrays[slot].size() == vertices.size()
					mask |= 1 << slot
					stride += 16 if slot == Mesh.ARRAY_COLOR else 8
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
			var index_count := indices.size() if not indices.is_empty() else vertices.size()
			valid = valid and index_count % 3 == 0
			for index: int in indices: valid = valid and index >= 0 and index < vertices.size()
			for i in vertices.size(): valid = valid and vertices[i].is_finite() and normals[i].is_finite() and normals[i].length_squared() > 0.000001
			if valid:
				result = {"arrays": arrays, "mask": mask, "vertices": vertices.size(), "tangent_vertices": tangent_vertices, "indices": index_count, "triangles": index_count / 3, "bytes": vertices.size() * stride + index_count * 4, "fingerprint": _hash_value(arrays)}
	_data_cache[ident] = result
	return result

func try_add(mesh: Mesh, poses: Array, material: Material, key: String, tag: String, scene_id: String = "station") -> bool:
	if not _approved_material(material, key):
		_retained(poses, material)
		return _skip("material_or_shader_not_reviewed")
	var is_glass: bool = (material as ShaderMaterial).shader.resource_path == GLASS_SHADER_PATH
	if is_glass:
		# An identity merged node cannot reproduce mirrored-instance cull_back
		# semantics merely by baking positions. Reject a mixed batch whole.
		for pose: Transform3D in poses:
			if pose.basis.determinant() <= 0.0:
				_retained(poses,material)
				_report.glass_nonpositive_determinant_batches += 1
				return _skip("glass_nonpositive_determinant")
		# Current window prisms have neither an alternate shadow mesh nor a
		# custom culling box; keep unfamiliar mesh render state on its old path.
		if mesh is ArrayMesh and (mesh.shadow_mesh != null or mesh.custom_aabb != AABB()):
			_retained(poses,material)
			return _skip("glass_special_mesh_render_state")
	var data := _mesh_data(mesh)
	if data.is_empty():
		_retained(poses, material)
		return _skip("mesh_attributes_not_reviewed")
	var estimate: int = int(data.bytes) * poses.size()
	var cost_aware := _cost_aware_selection()
	if not cost_aware and int(_budget.used_bytes) + estimate > int(_budget.limit_bytes):
		_retained(poses, material)
		return _skip("expanded_geometry_budget")
	for pose: Transform3D in poses:
		if not pose.is_finite() or absf(pose.basis.determinant()) < 0.000001:
			_retained(poses, material)
			return _skip("non_finite_or_singular_pose")
	var source_id := _source_batches.size()
	_source_batches.append({"mesh": mesh, "poses": poses, "key": key, "tag": tag, "scene": scene_id, "data": data})
	var old_cells := {}
	var source_pose_index := 0
	for pose: Transform3D in poses:
		var cell := Vector3i((pose.origin / _merge_cell_size()).floor())
		var token := str(cell) + "|" + str(material.get_instance_id()) + "|" + str(data.mask) + "|" + scene_id
		if not _groups.has(token):
			_groups[token] = {"origin": Vector3(cell) * _merge_cell_size(), "material": material, "key": key, "scene": scene_id, "mask": data.mask, "entries": []}
		var entry := {"mesh": mesh, "pose": pose, "key": key, "tag": tag, "data": data}
		if cost_aware:
			if not _groups[token].has("source_ids"):
				_groups[token]["source_ids"] = {}; _groups[token]["selection_bytes"] = 0
			_groups[token].source_ids[source_id] = true
			_groups[token].selection_bytes += int(data.bytes)
			entry["source_id"] = source_id; entry["source_pose_index"] = source_pose_index
		_groups[token].entries.append(entry)
		source_pose_index += 1
		old_cells[Vector3i(floori(pose.origin.x / 128.0), floori(pose.origin.y / 96.0), floori(pose.origin.z / 128.0))] = true
	_report.source_batches += 1
	if is_glass: _report.glass_source_batches += 1
	_report.source_legacy_chunks += old_cells.size()
	_report.source_instances += poses.size()
	_report.input_tangent_vertices += int(data.tangent_vertices) * poses.size()
	_report.triangles_before += int(data.triangles) * poses.size()
	if cost_aware:
		# Source arrays/poses are referenced here; no per-instance geometry is
		# expanded or charged until a profitable group passes its output audit.
		_report.candidate_geometry_bytes += estimate
	else:
		_report.expanded_geometry_bytes += estimate
		_budget.used_bytes += estimate
	return true

func _output_arrays(group: Dictionary) -> Array:
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var indices := PackedInt32Array()
	var colors := PackedColorArray(); var uv := PackedVector2Array(); var uv2 := PackedVector2Array()
	for entry: Dictionary in group.entries:
		var source: Array = entry.data.arrays
		var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
		var pose: Transform3D = entry.pose
		# Subtract the chunk origin before transforming source vertices. Output
		# geometry remains cell-local instead of embedding kilometer coordinates.
		pose.origin -= group.origin
		# Preserve this engine's original MultiMesh rendering, rather than apply
		# the physically correct inverse-transpose used for separate mesh nodes.
		# Forward+ composes model_normal_matrix with mat3(instance_matrix).
		var normal_basis := pose.basis
		var offset := vertices.size()
		for i in source_vertices.size():
			vertices.append(pose * source_vertices[i])
			normals.append((normal_basis * source_normals[i]).normalized())
		if source[Mesh.ARRAY_COLOR] != null: colors.append_array(source[Mesh.ARRAY_COLOR])
		if source[Mesh.ARRAY_TEX_UV] != null: uv.append_array(source[Mesh.ARRAY_TEX_UV])
		if source[Mesh.ARRAY_TEX_UV2] != null: uv2.append_array(source[Mesh.ARRAY_TEX_UV2])
		var source_indices := PackedInt32Array()
		if source[Mesh.ARRAY_INDEX] != null: source_indices = source[Mesh.ARRAY_INDEX]
		if source_indices.is_empty():
			for i in source_vertices.size(): indices.append(offset + i)
		else:
			for index: int in source_indices: indices.append(offset + index)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_INDEX] = indices
	if not colors.is_empty(): arrays[Mesh.ARRAY_COLOR] = colors
	if not uv.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uv
	if not uv2.is_empty(): arrays[Mesh.ARRAY_TEX_UV2] = uv2
	return arrays

## Reconstruct expectations from original source buffers and transforms. No
## retained duplicate world-vertex stream is needed for this executable audit.
func audit_output(mesh: ArrayMesh, origin: Vector3, entries: Array) -> Dictionary:
	var actual := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = actual[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = actual[Mesh.ARRAY_INDEX]
	var result := {"passed": true, "source_instances": entries.size(), "triangles_before": 0, "triangles_after": indices.size() / 3, "vertices": vertices.size(), "max_position_error_m": 0.0, "max_normal_error": 0.0, "max_uv_error": 0.0, "max_uv2_error": 0.0, "max_color_error": 0.0, "index_order_equal": true, "source_claim_sha256": "", "output_geometry_sha256": _hash_value(actual)}
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
	var vertex_offset := 0; var index_offset := 0
	for entry: Dictionary in entries:
		var source: Array = entry.data.arrays
		var source_vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
		var source_normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
		var pose: Transform3D = entry.pose
		var normal_basis := pose.basis
		digest.update(var_to_bytes([entry.data.fingerprint, pose, entry.key, entry.tag]))
		result.triangles_before += int(entry.data.triangles)
		for i in source_vertices.size():
			var j := vertex_offset + i
			result.max_position_error_m = maxf(result.max_position_error_m, (pose * source_vertices[i]).distance_to(origin + vertices[j]))
			result.max_normal_error = maxf(result.max_normal_error, (normal_basis * source_normals[i]).normalized().distance_to(normals[j]))
			if source[Mesh.ARRAY_TEX_UV] != null and not source[Mesh.ARRAY_TEX_UV].is_empty(): result.max_uv_error = maxf(result.max_uv_error, source[Mesh.ARRAY_TEX_UV][i].distance_to(actual[Mesh.ARRAY_TEX_UV][j]))
			if source[Mesh.ARRAY_TEX_UV2] != null and not source[Mesh.ARRAY_TEX_UV2].is_empty(): result.max_uv2_error = maxf(result.max_uv2_error, source[Mesh.ARRAY_TEX_UV2][i].distance_to(actual[Mesh.ARRAY_TEX_UV2][j]))
			if source[Mesh.ARRAY_COLOR] != null and not source[Mesh.ARRAY_COLOR].is_empty():
				var a: Color = source[Mesh.ARRAY_COLOR][i]; var b: Color = actual[Mesh.ARRAY_COLOR][j]
				result.max_color_error = maxf(result.max_color_error, maxf(maxf(absf(a.r-b.r), absf(a.g-b.g)), maxf(absf(a.b-b.b), absf(a.a-b.a))))
		var source_indices := PackedInt32Array()
		if source[Mesh.ARRAY_INDEX] != null: source_indices = source[Mesh.ARRAY_INDEX]
		for i in int(entry.data.indices):
			var expected := vertex_offset + (source_indices[i] if not source_indices.is_empty() else i)
			result.index_order_equal = result.index_order_equal and indices[index_offset+i] == expected
		vertex_offset += source_vertices.size(); index_offset += int(entry.data.indices)
	result.source_claim_sha256 = digest.finish().hex_encode()
	result.passed = vertex_offset == vertices.size() and index_offset == indices.size() and result.triangles_before == result.triangles_after and result.index_order_equal and float(result.max_position_error_m) <= POSITION_TOLERANCE_M and float(result.max_normal_error) <= NORMAL_TOLERANCE and result.max_uv_error == 0.0 and result.max_uv2_error == 0.0 and result.max_color_error == 0.0
	return result

func _build_output_mesh(group: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _output_arrays(group))
	return mesh

func _render_material(source: Material) -> Material:
	return source

func _material_equivalent(output: Material, source: Material) -> bool:
	return output == source

func flush(parent: Node3D, fallback: Callable) -> Dictionary:
	var cost_aware := _cost_aware_selection()
	if not cost_aware: _report.candidate_geometry_bytes = _report.expanded_geometry_bytes
	if cost_aware:
		_report["budget_selection_scope"] = "Per collector, descending (independent original source-cell calls - 1) / expanded bytes; world budget shared, collector construction order unchanged"
	var guard_reason := ""
	var version := Engine.get_version_info()
	if int(version.major) != 4 or int(version.minor) != 7 or int(version.patch) != 2: guard_reason = "Unreviewed engine version"
	elif parent.global_transform != Transform3D.IDENTITY: guard_reason = "Non-identity parent transform is outside the reviewed MultiMesh contract"
	elif DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != "forward_plus": guard_reason = "Unreviewed renderer"
	elif cost_aware and _merge_cell_size() != Vector3(128,96,128): guard_reason = "Cost selection requires the original MultiMesh spatial cells"
	_report["render_semantics_scope"] = "headless geometry contract only" if DisplayServer.get_name() == "headless" else "Godot4.7.2 Forward+ native"
	# Do not trade an existing shared instance batch for more static draw nodes.
	# Regions too sparse to benefit keep their exact original batch calls.
	if not guard_reason.is_empty() or (not cost_aware and _groups.size() >= int(_report.source_legacy_chunks)):
		for source: Dictionary in _source_batches:
			fallback.call(source.mesh, source.poses, source.key, source.tag, source.scene)
		_report.fallback_instances = _report.source_instances
		_report.fallback_triangles = _report.triangles_before
		_report.fallback_legacy_chunks = _report.source_legacy_chunks
		_budget.used_bytes -= int(_report.expanded_geometry_bytes)
		_report.expanded_geometry_bytes = 0
		_report["kept_original_reason"] = guard_reason if not guard_reason.is_empty() else "No reduction in static draw-node count"
		_groups.clear(); _source_batches.clear(); _data_cache.clear(); _material_cache.clear()
		return _report.duplicate(true)
	var group_index := 0
	var pending_fallbacks := {}
	# Both policies share this exact build/cache/audit/emission path.
	for group: Dictionary in _ordered_groups():
		if cost_aware:
			if group.source_ids.size() <= 1:
				_report.cost_skipped_no_gain_groups += 1
				_queue_cost_fallback(group,pending_fallbacks)
				group_index += 1
				continue
			if int(_budget.used_bytes) + int(group.selection_bytes) > int(_budget.limit_bytes):
				_report.cost_skipped_budget_groups += 1
				_queue_cost_fallback(group,pending_fallbacks)
				group_index += 1
				continue
		# Outline metadata is prepared on every path, including cache hits.
		_prepare_group_for_cache(group)
		var mesh: ArrayMesh
		var audit: Dictionary = {}
		var signature := ""; var abi := ""
		var hit := false
		if _geometry_cache != null:
			abi = _geometry_cache_abi(); signature = _cache_signature(group,abi)
			var cached: Dictionary = _geometry_cache.lookup(signature,abi)
			if cached.get("hit",false):
				mesh = cached.mesh
				if cached.get("verify_on_read",false):
					audit = audit_output(mesh,group.origin,group.entries)
					_report.geometry_cache_full_read_audits += 1
					audit["cache_full_audit_this_read"] = true
				else:
					audit = cached.audit
					audit["cache_full_audit_this_read"] = false
				hit = audit.get("passed",false)
				if hit:
					_report.geometry_cache_hits += 1
					_report.geometry_cache_resource_bytes_read += int(cached.get("resource_bytes",0))
				else:
					_geometry_cache.invalidate(signature)
					_report.geometry_cache_invalid += 1
			else:
				_report.geometry_cache_invalid += int(cached.get("invalid",false))
			if not hit: _report.geometry_cache_misses += 1
		if not hit:
			mesh = _build_output_mesh(group)
			audit = audit_output(mesh, group.origin, group.entries)
			audit["cache_full_audit_this_read"] = true
		audit["cache_hit"] = hit
		if _geometry_cache != null: audit["geometry_cache_signature"] = signature
		if _geometry_cache != null and not hit and audit.passed:
			var written: Dictionary = _geometry_cache.store(signature,abi,mesh,audit)
			_report.geometry_cache_writes += int(written.get("stored",false))
			_report.geometry_cache_write_failures += int(not written.get("stored",false))
			_report.geometry_cache_new_blob_bytes += int(written.get("new_canonical_blob_bytes",0))
			_report.geometry_cache_manifest_bytes_written += int(written.get("manifest_bytes_written",0))
		if not audit.passed:
			_report.errors.append("Group equivalence failed: " + str(group_index))
			if not _report.has("failed_group_audits"): _report["failed_group_audits"] = []
			if _report.failed_group_audits.size() < 8: _report.failed_group_audits.append({"group":group_index,"material":group.key,"audit":audit})
			if cost_aware:
				_queue_cost_fallback(group,pending_fallbacks)
			else:
				_report.fallback_instances += group.entries.size()
				_report.fallback_triangles += int(audit.triangles_before)
				for entry: Dictionary in group.entries:
					fallback.call(entry.mesh, [entry.pose], entry.key, entry.tag, group.scene)
					_budget.used_bytes -= int(entry.data.bytes)
					_report.expanded_geometry_bytes -= int(entry.data.bytes)
			group_index += 1
			continue
		var node := MeshInstance3D.new(); node.mesh = mesh; node.position = group.origin; node.material_override = _render_material(group.material)
		node.name = "ExactStatic_" + str(group.scene) + "_" + str(group.key) + "_" + str(group_index)
		var owner_id := str(parent.get_meta("instance_id", parent.name))
		node.set_meta("scene_id", group.scene); node.set_meta("asset_id", "h07_exact_static_" + str(group.key)); node.set_meta("instance_id", owner_id + "_" + node.name)
		node.set_meta("h07_exact_static_audit", audit)
		parent.add_child(node)
		_configure_output_node(node, group)
		_report.shared_original_materials = _report.shared_original_materials and node.material_override == group.material
		_report.material_semantics_preserved = _report.material_semantics_preserved and _material_equivalent(node.material_override, group.material)
		if cost_aware:
			_budget.used_bytes += int(group.selection_bytes)
			_report.expanded_geometry_bytes += int(group.selection_bytes)
			_report.cost_selected_saved_nodes += group.source_ids.size()-1
		_report.merged_batches += 1; _report.merged_instances += group.entries.size()
		_report.triangles_after += int(audit.triangles_after); _report.vertices_after += int(audit.vertices)
		for field: String in ["max_position_error_m", "max_normal_error", "max_uv_error", "max_uv2_error", "max_color_error"]: _report[field] = maxf(float(_report[field]), float(audit[field]))
		_report.groups.append({"scene": group.scene, "material": group.key, "origin": [group.origin.x, group.origin.y, group.origin.z], "audit": audit})
		group_index += 1
	if cost_aware:
		_emit_cost_fallbacks(pending_fallbacks,fallback)
		_report["static_draw_nodes_not_increased"] = int(_report.merged_batches) + int(_report.fallback_legacy_chunks) <= int(_report.source_legacy_chunks)
	_report.all_source_triangles_retained = int(_report.triangles_before) == int(_report.triangles_after) + int(_report.fallback_triangles)
	_report.passed = _report.errors.is_empty() and _report.material_semantics_preserved and _report.all_source_triangles_retained
	if cost_aware: _report.passed = _report.passed and _report.static_draw_nodes_not_increased and int(_budget.used_bytes) <= int(_budget.limit_bytes)
	_report["shared_budget_used_after_flush"] = _budget.used_bytes
	_groups.clear(); _source_batches.clear(); _data_cache.clear(); _material_cache.clear()
	return _report.duplicate(true)

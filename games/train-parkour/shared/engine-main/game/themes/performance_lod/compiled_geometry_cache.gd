extends RefCounted
## Optional task-owned cache. Stores geometry-only meshes, never scene/assets.
const SCHEMA := 1
const CACHE_ABI := "h07-geometry-only-res/v1"
# JSON numbers may decode as float. Accept only exact, finite integers; never
# coerce booleans, strings, arrays or dictionaries into numeric fields.
const MAX_SAFE_JSON_INTEGER := 9007199254740991.0
const MANIFEST_FIELDS := ["schema","cache_abi","source_signature","geometry_abi","engine","geometry_key","resource_sha256","resource_bytes","format","aabb","roundtrip_arrays_verified","audit","visual_acceptance"]
const BASE_AUDIT_FIELDS := ["passed","source_instances","triangles_before","triangles_after","vertices","max_position_error_m","max_normal_error","max_uv_error","max_uv2_error","max_color_error","index_order_equal","source_claim_sha256","output_geometry_sha256","cache_full_audit_this_read","cache_hit","geometry_cache_signature"]
const OUTLINE_AUDIT_FIELDS := ["outline_vertices","max_custom0_extrusion_error","max_outline_position_error_m","custom0_rgb_float_valid"]
# Read validation mirrors the existing passed-audit contract; geometry and ABI
# production are unchanged.
const AUDIT_ERROR_LIMITS := {"max_position_error_m":0.001,"max_normal_error":0.0002,"max_uv_error":0.0,"max_uv2_error":0.0,"max_color_error":0.0}
var enabled := false
var verify_on_read := false
var cache_root := ""
var _loaded: Dictionary = {}
var _trusted_blob_hashes: Dictionary = {}
var _manifest_index_ready := false
var _blob_candidates: Dictionary = {}
var _stats := {"hits":0,"misses":0,"rejections":{},"writes":0,"blob_reuses":0,"manifest_index_scans":0,"manifest_index_key_refreshes":0,"manifest_provenance_records":0,"resource_bytes_loaded":0,"new_canonical_blob_bytes":0,"temporary_bytes_written":0,"manifest_bytes_written":0,"write_failures":0}

func configure(root_path: String, verify: bool = false) -> bool:
	enabled = false; verify_on_read = verify; cache_root = ""; _loaded.clear(); _trusted_blob_hashes.clear()
	_manifest_index_ready = false; _blob_candidates.clear()
	if root_path.is_empty(): return false
	if not root_path.is_absolute_path() or root_path.begins_with("res://") or root_path.begins_with("user://"): return false
	cache_root = root_path.simplify_path().trim_suffix("/")
	for folder: String in [cache_root, cache_root.path_join("meshes"), cache_root.path_join("manifests"), cache_root.path_join("locks")]:
		if DirAccess.make_dir_recursive_absolute(folder) != OK: return false
	enabled = true
	return true

func _engine() -> String:
	var version := Engine.get_version_info()
	return "%s.%s.%s|%s|%s|%s" % [version.major,version.minor,version.patch,version.status,version.build,version.hash]

func _hash(value: Variant) -> String:
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(value))
	return digest.finish().hex_encode()

func _valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character: String in value:
		if not "0123456789abcdef".contains(character): return false
	return true

func _finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT: return false
	return is_finite(float(value))

func _nonnegative_integer(value: Variant) -> bool:
	if not _finite_number(value): return false
	var number := float(value)
	return number >= 0.0 and number <= MAX_SAFE_JSON_INTEGER and number == floor(number)

func _exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true

func _valid_shape_fields(record: Dictionary) -> bool:
	if not _nonnegative_integer(record.get("format")): return false
	var values: Variant = record.get("aabb")
	if not values is Array or values.size() != 6: return false
	for value: Variant in values:
		if not _finite_number(value): return false
	return float(values[3]) >= 0.0 and float(values[4]) >= 0.0 and float(values[5]) >= 0.0

func _valid_error(value: Variant, limit: float) -> bool:
	return _finite_number(value) and float(value) >= 0.0 and float(value) <= limit

func _valid_audit(value: Variant, signature: String, abi: String) -> bool:
	if not value is Dictionary: return false
	var audit: Dictionary = value
	var fields: Array = BASE_AUDIT_FIELDS.duplicate()
	var outlined := abi.contains("|outline-Bn-RGBf32/v1|")
	if outlined: fields.append_array(OUTLINE_AUDIT_FIELDS)
	if not _exact_fields(audit,fields): return false
	for field: String in ["passed","index_order_equal","cache_full_audit_this_read","cache_hit"]:
		if typeof(audit[field]) != TYPE_BOOL: return false
	if not audit.passed or not audit.index_order_equal or not audit.cache_full_audit_this_read or audit.cache_hit: return false
	for field: String in ["source_instances","triangles_before","triangles_after","vertices"]:
		if not _nonnegative_integer(audit[field]) or float(audit[field]) <= 0.0: return false
	if audit.triangles_before != audit.triangles_after: return false
	for field: String in AUDIT_ERROR_LIMITS:
		if not _valid_error(audit[field],float(AUDIT_ERROR_LIMITS[field])): return false
	for field: String in ["source_claim_sha256","output_geometry_sha256","geometry_cache_signature"]:
		if not _valid_hash(audit[field]): return false
	if audit.geometry_cache_signature != signature: return false
	if outlined:
		if not _nonnegative_integer(audit.outline_vertices): return false
		if audit.outline_vertices != 0 and audit.outline_vertices != audit.vertices: return false
		if typeof(audit.custom0_rgb_float_valid) != TYPE_BOOL or not audit.custom0_rgb_float_valid: return false
		if not _valid_error(audit.max_custom0_extrusion_error,0.00001) or not _valid_error(audit.max_outline_position_error_m,0.001): return false
	return true

func _valid_manifest(value: Variant) -> bool:
	if not value is Dictionary: return false
	var manifest: Dictionary = value
	if not _exact_fields(manifest,MANIFEST_FIELDS): return false
	for field: String in ["cache_abi","source_signature","geometry_abi","engine","geometry_key","resource_sha256"]:
		if typeof(manifest[field]) != TYPE_STRING or manifest[field].is_empty(): return false
	for field: String in ["source_signature","geometry_key","resource_sha256"]:
		if not _valid_hash(manifest[field]): return false
	if not _nonnegative_integer(manifest.schema) or not _nonnegative_integer(manifest.resource_bytes) or float(manifest.resource_bytes) <= 0.0 or not _valid_shape_fields(manifest): return false
	if typeof(manifest.roundtrip_arrays_verified) != TYPE_BOOL or not manifest.roundtrip_arrays_verified: return false
	if typeof(manifest.visual_acceptance) != TYPE_BOOL or manifest.visual_acceptance: return false
	if not _valid_audit(manifest.audit,manifest.source_signature,manifest.geometry_abi): return false
	return manifest.audit.output_geometry_sha256 == manifest.geometry_key

func _geometry_only(mesh: ArrayMesh) -> bool:
	if mesh == null or mesh.get_script() != null or mesh.shadow_mesh != null or mesh.get_surface_count() != 1 or mesh.get_blend_shape_count() != 0 or not mesh.get_meta_list().is_empty(): return false
	return mesh.surface_get_material(0) == null and mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES

func _length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var bytes := file.get_length(); file.close()
	return bytes

func _aabb(box: AABB) -> Array:
	return [box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z]

func _same_shape(mesh: ArrayMesh, record: Dictionary) -> bool:
	if not _geometry_only(mesh) or not _valid_shape_fields(record): return false
	if int(record.format) != mesh.surface_get_format(0): return false
	var values: Array = record.aabb
	var box := AABB(Vector3(values[0],values[1],values[2]), Vector3(values[3],values[4],values[5]))
	return mesh.get_aabb() == box

func _miss(reason: String, invalid: bool = false) -> Dictionary:
	_stats.misses += 1
	if invalid: _stats.rejections[reason] = int(_stats.rejections.get(reason,0)) + 1
	return {"hit":false,"reason":reason,"invalid":invalid}

func lookup(signature: String, abi: String) -> Dictionary:
	if not enabled: return _miss("disabled")
	if not _valid_hash(signature): return _miss("invalid_signature",true)
	var path := cache_root.path_join("manifests").path_join(signature+".json")
	if not FileAccess.file_exists(path): return _miss("missing_manifest")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return _miss("invalid_manifest",true)
	var data: Variant = parser.data
	if not _valid_manifest(data): return _miss("invalid_manifest_fields",true)
	var manifest: Dictionary = data
	if int(manifest.get("schema",0)) != SCHEMA or manifest.get("cache_abi","") != CACHE_ABI or manifest.get("engine","") != _engine() or manifest.get("geometry_abi","") != abi or manifest.get("source_signature","") != signature or not manifest.get("roundtrip_arrays_verified",false): return _miss("manifest_contract_mismatch",true)
	var audit: Dictionary = manifest.audit
	var geometry_key: String = manifest.geometry_key
	var resource_hash: String = manifest.resource_sha256
	if not audit is Dictionary or not audit.get("passed",false) or not _valid_hash(geometry_key) or not _valid_hash(resource_hash) or audit.get("output_geometry_sha256","") != geometry_key: return _miss("audit_binding_mismatch",true)
	var resource_path := cache_root.path_join("meshes").path_join(geometry_key+".res")
	if not FileAccess.file_exists(resource_path) or FileAccess.get_sha256(resource_path) != resource_hash: return _miss("resource_hash_mismatch",true)
	if not ResourceLoader.get_dependencies(resource_path).is_empty(): return _miss("resource_has_dependencies",true)
	var mesh: ArrayMesh
	if _loaded.has(geometry_key) and _loaded[geometry_key].sha256 == resource_hash:
		mesh = _loaded[geometry_key].mesh
	else:
		mesh = ResourceLoader.load(resource_path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if not _same_shape(mesh,manifest) or FileAccess.get_sha256(resource_path) != resource_hash: return _miss("resource_contract_or_read_race",true)
	if mesh.surface_get_array_len(0) != int(audit.vertices) or mesh.surface_get_array_index_len(0) != int(audit.triangles_after) * 3: return _miss("resource_audit_count_mismatch",true)
	_loaded[geometry_key] = {"mesh":mesh,"sha256":resource_hash}
	_trusted_blob_hashes[geometry_key] = resource_hash
	var bytes := _length(resource_path)
	_stats.hits += 1; _stats.resource_bytes_loaded += maxi(0,bytes)
	return {"hit":true,"mesh":mesh,"audit":audit.duplicate(true),"verify_on_read":verify_on_read,"resource_bytes":bytes,"geometry_key":geometry_key,"resource_sha256":resource_hash}

func _failure(reason: String) -> Dictionary:
	_stats.write_failures += 1
	return {"stored":false,"reason":reason,"new_canonical_blob_bytes":0,"temporary_bytes_written":0,"manifest_bytes_written":0}

func _remove_temp(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func _index_manifest_provenance(only_key: String = "") -> void:
	if only_key.is_empty():
		if _manifest_index_ready: return
		_manifest_index_ready = true
		_stats.manifest_index_scans += 1
	else:
		# Only a previously known key with a changed byte hash needs this rare
		# refresh. Drop stale evidence before deciding that its blob is damaged.
		_blob_candidates.erase(only_key)
		_stats.manifest_index_key_refreshes += 1
	var directory := cache_root.path_join("manifests")
	var engine := _engine()
	for filename: String in DirAccess.get_files_at(directory):
		if not filename.ends_with(".json") or not _valid_hash(filename.trim_suffix(".json")): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(directory.path_join(filename))) != OK: continue
		var value: Variant = parser.data
		if not _valid_manifest(value): continue
		var manifest: Dictionary = value
		if int(manifest.schema) != SCHEMA or manifest.cache_abi != CACHE_ABI or manifest.engine != engine or manifest.source_signature != filename.trim_suffix(".json"): continue
		# A different source/geometry ABI may still yield these exact arrays. The
		# old manifest supplies only byte provenance, not current-input approval.
		var key: String = manifest.geometry_key
		if not only_key.is_empty() and key != only_key: continue
		if not _blob_candidates.has(key): _blob_candidates[key] = {}
		_blob_candidates[key][manifest.resource_sha256] = true
		_stats.manifest_provenance_records += 1

func _existing_blob_status(path: String, key: String, shape: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path): return {"reuse":false,"replace":true}
	var fresh_index := not _manifest_index_ready
	if not _trusted_blob_hashes.has(key): _index_manifest_provenance()
	var existing_hash := FileAccess.get_sha256(path)
	if not _valid_hash(existing_hash): return {"reuse":false,"replace":false}
	var trusted: bool = _trusted_blob_hashes.get(key,"") == existing_hash
	var candidates: Dictionary = _blob_candidates.get(key,{})
	if not trusted and not candidates.has(existing_hash):
		if _trusted_blob_hashes.has(key) or not candidates.is_empty():
			if not _manifest_index_ready: _index_manifest_provenance()
			elif not fresh_index: _index_manifest_provenance(key)
			_trusted_blob_hashes.erase(key)
			candidates = _blob_candidates.get(key,{})
		if not candidates.has(existing_hash):
			# A fresh valid manifest for this key proves a SHA mismatch. With no
			# current provenance, keep unknown bytes rather than overwrite them.
			return {"reuse":false,"replace":not candidates.is_empty()}
	# Never parse an unproven blob. Even a proven byte hash must also match the
	# freshly audited geometry before its original serialized bytes are reused.
	if not ResourceLoader.get_dependencies(path).is_empty(): return {"reuse":false,"replace":true}
	var existing := ResourceLoader.load(path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if not _same_shape(existing,shape) or _hash(existing.surface_get_arrays(0)) != key or FileAccess.get_sha256(path) != existing_hash: return {"reuse":false,"replace":true}
	_trusted_blob_hashes[key] = existing_hash
	return {"reuse":true,"replace":false}

func store(signature: String, abi: String, mesh: ArrayMesh, audit: Dictionary) -> Dictionary:
	if not enabled: return _failure("disabled")
	if not _valid_hash(signature) or not _valid_audit(audit,signature,abi) or not _geometry_only(mesh): return _failure("unverified_or_non_geometry_input")
	var key: String = audit.output_geometry_sha256
	# An atomic directory provides one writer per immutable geometry blob.
	var lock := cache_root.path_join("locks").path_join(key+".lock")
	if DirAccess.make_dir_absolute(lock) != OK: return _failure("writer_busy")
	var result := _store_locked(signature,abi,key,mesh,audit)
	DirAccess.remove_absolute(lock)
	return result

func _store_locked(signature: String, abi: String, key: String, mesh: ArrayMesh, audit: Dictionary) -> Dictionary:
	var suffix := "."+str(OS.get_process_id())+"."+str(Time.get_ticks_usec())+".partial"
	var resource_path := cache_root.path_join("meshes").path_join(key+".res")
	var temporary := cache_root.path_join("meshes").path_join(key+suffix+".res")
	var save_error := ResourceSaver.save(mesh,temporary,ResourceSaver.FLAG_COMPRESS)
	if save_error != OK:
		_remove_temp(temporary)
		return _failure("resource_save_failed")
	var temporary_bytes := maxi(0,_length(temporary))
	_stats.temporary_bytes_written += temporary_bytes
	if not ResourceLoader.get_dependencies(temporary).is_empty():
		_remove_temp(temporary)
		return _failure("saved_resource_has_dependencies")
	var roundtrip := ResourceLoader.load(temporary,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	var shape := {"format":mesh.surface_get_format(0),"aabb":_aabb(mesh.get_aabb())}
	if not _same_shape(roundtrip,shape) or _hash(roundtrip.surface_get_arrays(0)) != key:
		_remove_temp(temporary)
		return _failure("resource_roundtrip_mismatch")
	# ResourceSaver's internal IDs may vary with the unique temporary path.
	# Preserve verified canonical bytes so older source manifests keep working.
	var existing_status := _existing_blob_status(resource_path,key,shape)
	var reuse: bool = existing_status.reuse
	var new_bytes := 0
	if reuse:
		_remove_temp(temporary)
	else:
		# A different Cache may have published a new key after our one-time
		# scan. With no provenance for that key, preserve its bytes and skip
		# this optional write instead of risking another manifest's integrity.
		# Known keys whose actual SHA no longer matches can still be repaired.
		if not existing_status.replace:
			_remove_temp(temporary)
			return _failure("unproven_existing_blob_preserved")
		if DirAccess.rename_absolute(temporary,resource_path) != OK:
			_remove_temp(temporary)
			return _failure("resource_publish_failed")
		new_bytes = maxi(0,_length(resource_path))
	var manifest := {"schema":SCHEMA,"cache_abi":CACHE_ABI,"source_signature":signature,"geometry_abi":abi,"engine":_engine(),"geometry_key":key,"resource_sha256":FileAccess.get_sha256(resource_path),"resource_bytes":_length(resource_path),"format":shape.format,"aabb":shape.aabb,"roundtrip_arrays_verified":true,"audit":audit.duplicate(true),"visual_acceptance":false}
	_trusted_blob_hashes[key] = manifest.resource_sha256
	var manifest_path := cache_root.path_join("manifests").path_join(signature+".json")
	var manifest_temp := cache_root.path_join("manifests").path_join(signature+suffix+".json")
	var stream := FileAccess.open(manifest_temp,FileAccess.WRITE)
	if stream == null: return _failure("manifest_write_failed")
	stream.store_string(JSON.stringify(manifest,"",true,true)+"\n");stream.flush();stream.close()
	var manifest_bytes := maxi(0,_length(manifest_temp))
	if DirAccess.rename_absolute(manifest_temp,manifest_path) != OK:
		_remove_temp(manifest_temp)
		return _failure("manifest_publish_failed")
	_stats.writes += 1; _stats.blob_reuses += int(reuse)
	_stats.new_canonical_blob_bytes += new_bytes; _stats.manifest_bytes_written += manifest_bytes
	return {"stored":true,"blob_reused":reuse,"new_canonical_blob_bytes":new_bytes,"temporary_bytes_written":temporary_bytes,"manifest_bytes_written":manifest_bytes}

func invalidate(signature: String) -> void:
	# Only the task-owned lookup manifest is retired. Immutable geometry may be
	# shared by other signatures, so this does not delete any resource blob.
	if enabled and _valid_hash(signature): _remove_temp(cache_root.path_join("manifests").path_join(signature+".json"))

func report() -> Dictionary:
	var result := _stats.duplicate(true)
	result["enabled"] = enabled; result["cache_root"] = cache_root; result["verify_on_read"] = verify_on_read
	result["cache_abi"] = CACHE_ABI; result["engine"] = _engine()
	result["bytes_scope"] = "Logical compressed-resource bytes considered per lookup/write; not physical I/O or APFS allocation"
	result["scope"] = "Task-owned geometry cache; no material/texture/scene duplication or visual acceptance"
	return result

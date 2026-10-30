extends RefCounted
## Candidate GLB preview. The raw GLB and its imported UV/material/texture resources
## stay intact. Only a parent transform fits the visual into a frozen gameplay box.

const IMPORTED_SHADER = preload("res://shaders/imported_model.gdshader")
const SupportSurface = preload("res://scripts/mesh_support.gd")

static func _normal_revision_mesh(source: ArrayMesh, revision: Dictionary, cache: Dictionary) -> ArrayMesh:
	if revision.is_empty():
		return source
	var key := "normal_mesh:%d:%s" % [source.get_instance_id(), JSON.stringify(revision).sha256_text()]
	if cache.has(key):
		return cache[key]
	var bounds: Array = revision["local_bounds"]
	var minimum := Vector3(bounds[0], bounds[1], bounds[2])
	var maximum := Vector3(bounds[3], bounds[4], bounds[5])
	var crease_cosine: float = cos(deg_to_rad(float(revision.get("crease_degrees", 35.0))))
	var weld: float = float(revision.get("weld_precision", 0.000001))
	var result := ArrayMesh.new()
	for blend_shape in range(source.get_blend_shape_count()):
		result.add_blend_shape(source.get_blend_shape_name(blend_shape))
	var changed: int = 0
	var retained: int = 0
	for surface in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var eligible := PackedByteArray()
		eligible.resize(vertices.size())
		var keys: Array[Vector3i] = []
		var blocked: Dictionary = {}
		var faces_at: Dictionary = {}
		var weighted_normals: Array[Vector3] = []
		var face_directions: Array[Vector3] = []
		var source_material: BaseMaterial3D = source.surface_get_material(surface) as BaseMaterial3D
		var image: Image = null
		if source_material != null and source_material.albedo_texture != null:
			image = source_material.albedo_texture.get_image()
			if image.is_compressed():
				image = image.duplicate()
				image.decompress()
		for i in range(vertices.size()):
			var p: Vector3 = vertices[i]
			var vertex_key := Vector3i(roundi(p.x / weld), roundi(p.y / weld), roundi(p.z / weld))
			keys.append(vertex_key)
			var inside: bool = p.x >= minimum.x and p.y >= minimum.y and p.z >= minimum.z and p.x <= maximum.x and p.y <= maximum.y and p.z <= maximum.z
			var excluded: Array = revision.get("exclude_local_bounds", [])
			if excluded.size() == 6 and p.x >= excluded[0] and p.y >= excluded[1] and p.z >= excluded[2] and p.x <= excluded[3] and p.y <= excluded[4] and p.z <= excluded[5]:
				inside = false
			var excluded_sphere: Array = revision.get("exclude_sphere", [])
			if excluded_sphere.size() == 4 and p.distance_to(Vector3(excluded_sphere[0], excluded_sphere[1], excluded_sphere[2])) < excluded_sphere[3]:
				inside = false
			if inside and bool(revision.get("protect_warm_material_edges", true)) and image != null and uvs.size() == vertices.size():
				var color: Color = image.get_pixel(clampi(roundi(uvs[i].x * (image.get_width() - 1)), 0, image.get_width() - 1), clampi(roundi(uvs[i].y * (image.get_height() - 1)), 0, image.get_height() - 1))
				inside = not (color.r - color.b > 0.07 and color.g - color.b > 0.03)
			eligible[i] = 1 if inside else 0
			if not inside:
				blocked[vertex_key] = true
		if normals.size() == vertices.size() and source.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES:
			for i in range(0, indices.size(), 3):
				var a: int = indices[i]; var b: int = indices[i + 1]; var c: int = indices[i + 2]
				var weighted: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
				# Keep the engine-imported orientation, including glTF winding conversion.
				if weighted.dot(normals[a] + normals[b] + normals[c]) < 0.0:
					weighted = -weighted
				var face_id: int = weighted_normals.size()
				weighted_normals.append(weighted)
				face_directions.append(weighted.normalized())
				if eligible[a] == 0 or eligible[b] == 0 or eligible[c] == 0:
					continue
				for vertex in [a, b, c]:
					var vertex_key: Vector3i = keys[vertex]
					if not faces_at.has(vertex_key): faces_at[vertex_key] = []
					faces_at[vertex_key].append(face_id)
			var adapted: PackedVector3Array = normals.duplicate()
			for i in range(vertices.size()):
				if eligible[i] == 0 or blocked.has(keys[i]) or not faces_at.has(keys[i]):
					retained += 1
					continue
				# Optional source-bound barrel field removes reconstructed triangular
				# shading from a designed smooth canopy. Alignment preserves end caps,
				# ribs and hard trim. Positions, UVs, topology and LODs remain exact.
				var field: Dictionary = revision.get("normal_field", {})
				if field.get("shape", "") == "parabolic_barrel":
					var p: Vector3 = vertices[i]
					var target := Vector3(2.0 * float(field["curvature"]) * (p.x - float(field.get("center_x", 0.0))), 1.0, 0.0).normalized()
					var alignment: float = normals[i].dot(target)
					var low: float = cos(deg_to_rad(float(field.get("alignment_limit_degrees", 45.0))))
					var high: float = cos(deg_to_rad(float(field.get("alignment_full_degrees", 25.0))))
					var blend: float = smoothstep(low, high, alignment) * float(revision.get("strength", 1.0))
					adapted[i] = normals[i].slerp(target, blend).normalized()
					if adapted[i].distance_squared_to(normals[i]) > 0.000001: changed += 1
					continue
				var sum := Vector3.ZERO
				var contributors: int = 0
				for face_id in faces_at[keys[i]]:
					if normals[i].dot(face_directions[face_id]) >= crease_cosine:
						sum += weighted_normals[face_id]
						contributors += 1
				if contributors > 1 and sum.length_squared() > 0.000000000001:
					adapted[i] = normals[i].slerp(sum.normalized(), float(revision.get("strength", 1.0))).normalized()
					if adapted[i].distance_squared_to(normals[i]) > 0.000001: changed += 1
			arrays[Mesh.ARRAY_NORMAL] = adapted
		var raw: Dictionary = RenderingServer.mesh_get_surface(source.get_rid(), surface)
		var lods: Dictionary = {}
		for lod in raw.get("lods", []):
			var bytes: PackedByteArray = lod["index_data"]
			var stride: int = 4 if vertices.size() > 65535 else 2
			var lod_indices := PackedInt32Array()
			lod_indices.resize(bytes.size() / stride)
			for i in range(lod_indices.size()):
				lod_indices[i] = bytes.decode_u32(i * stride) if stride == 4 else bytes.decode_u16(i * stride)
			lods[lod["edge_length"]] = lod_indices
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, source.surface_get_blend_shape_arrays(surface), lods)
		result.surface_set_material(surface, source.surface_get_material(surface))
		result.surface_set_name(surface, source.surface_get_name(surface))
	result.set_meta("normal_revision", revision.duplicate(true))
	result.set_meta("normal_revision_changed_vertices", changed)
	result.set_meta("normal_revision_retained_boundary_vertices", retained)
	cache[key] = result
	return result

static func _runtime_texture(source: Texture2D, profile: Dictionary, cache: Dictionary) -> Texture2D:
	var limit: int = int(profile.get("texture_max_size", 0))
	if limit not in [256,512,1024,2048] or maxi(source.get_width(),source.get_height()) <= limit:
		return source
	var key := "%d:%d" % [source.get_instance_id(),limit]
	if cache.has(key):
		return cache[key]
	var pixels: Image = source.get_image().duplicate()
	if pixels.is_compressed() and pixels.decompress() != OK:
		return source
	var ratio: float = float(limit)/maxi(pixels.get_width(),pixels.get_height())
	pixels.resize(maxi(1,roundi(pixels.get_width()*ratio)),maxi(1,roundi(pixels.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
	pixels.generate_mipmaps()
	var adapted := ImageTexture.create_from_image(pixels)
	cache[key] = adapted
	return adapted

static func _profile_texture(source: Texture2D, channel: String, profile: Dictionary, cache: Dictionary, owner: Node) -> Texture2D:
	var overrides: Dictionary = profile.get("texture_overrides", {})
	if not overrides.has(channel):
		return _runtime_texture(source, profile, cache) if source != null else null
	var override: Dictionary = overrides[channel]
	var path: String = str(override.get("path", ""))
	var expected_hash: String = str(override.get("sha256", ""))
	if path.is_empty() or not FileAccess.file_exists(path) or (not expected_hash.is_empty() and FileAccess.get_sha256(path) != expected_hash):
		var message := "Material revision texture missing or hash mismatch: " + path
		owner.set_meta("material_revision_error", message)
		push_error(message)
		return null
	var key := "override:" + path + ":" + expected_hash
	if not cache.has(key):
		var pixels := Image.load_from_file(path)
		if pixels == null or pixels.is_empty():
			owner.set_meta("material_revision_error", "Invalid material revision texture: " + path)
			push_error("Invalid material revision texture: " + path)
			return null
		pixels.generate_mipmaps()
		cache[key] = ImageTexture.create_from_image(pixels)
	return _runtime_texture(cache[key], profile, cache)

static func _apply_material_revision(derived: ShaderMaterial, profile: Dictionary) -> void:
	var interval: Array = profile.get("roughness_range", [0.0, 1.0])
	derived.set_shader_parameter("game_roughness_range", Vector2(float(interval[0]), float(interval[1])))
	var regions: Array = profile.get("material_regions", [])
	var rectangles := PackedVector4Array()
	var local_minimums := PackedVector4Array()
	var local_maximums := PackedVector4Array()
	var excluded_rectangles := PackedVector4Array()
	var excluded_minimums := PackedVector4Array()
	var excluded_maximums := PackedVector4Array()
	var excluded_spheres := PackedVector4Array()
	var colors := PackedColorArray()
	var responses := PackedVector4Array()
	var color_families := PackedInt32Array()
	for i in range(16):
		if i >= regions.size():
			rectangles.append(Vector4.ZERO)
			local_minimums.append(Vector4.ZERO)
			local_maximums.append(Vector4.ZERO)
			excluded_rectangles.append(Vector4(2, 2, 3, 3))
			excluded_minimums.append(Vector4.ZERO)
			excluded_maximums.append(Vector4.ZERO)
			excluded_spheres.append(Vector4.ZERO)
			colors.append(Color(0, 0, 0, 0))
			responses.append(Vector4.ZERO)
			color_families.append(0)
			continue
		var region: Dictionary = regions[i]
		var rect: Array = region.get("uv_rect", [0, 0, 1, 1])
		var color: Array = region["albedo_color"]
		var roughness: Array = region.get("roughness_range", interval)
		color_families.append(int(region.get("color_family", 0)))
		rectangles.append(Vector4(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3])))
		var local_box: Array = region.get("local_bounds", [])
		var excluded: Array = region.get("exclude_uv_rect", [2, 2, 3, 3])
		var excluded_box: Array = region.get("exclude_local_bounds", [])
		var excluded_sphere: Array = region.get("exclude_sphere", [0, 0, 0, 0])
		excluded_spheres.append(Vector4(float(excluded_sphere[0]), float(excluded_sphere[1]), float(excluded_sphere[2]), float(excluded_sphere[3])))
		excluded_minimums.append(Vector4(float(excluded_box[0]), float(excluded_box[1]), float(excluded_box[2]), 1.0) if excluded_box.size() == 6 else Vector4.ZERO)
		excluded_maximums.append(Vector4(float(excluded_box[3]), float(excluded_box[4]), float(excluded_box[5]), float(region.get("exclusion_feather", 0.0))) if excluded_box.size() == 6 else Vector4.ZERO)
		excluded_rectangles.append(Vector4(float(excluded[0]), float(excluded[1]), float(excluded[2]), float(excluded[3])))
		local_minimums.append(Vector4(float(local_box[0]), float(local_box[1]), float(local_box[2]), 1.0) if local_box.size() == 6 else Vector4.ZERO)
		local_maximums.append(Vector4(float(local_box[3]), float(local_box[4]), float(local_box[5]), 0.0) if local_box.size() == 6 else Vector4.ZERO)
		colors.append(Color(float(color[0]), float(color[1]), float(color[2]), float(region.get("strength", 1.0))))
		responses.append(Vector4(float(roughness[0]), float(roughness[1]),
			1.0 if region.get("protect_warm_trim", true) else 0.0, float(region.get("detail_contrast", 0.08))))
	derived.set_shader_parameter("material_region_count", mini(regions.size(), 16))
	derived.set_shader_parameter("material_region_rect", rectangles)
	derived.set_shader_parameter("material_region_local_min", local_minimums)
	derived.set_shader_parameter("material_region_local_max", local_maximums)
	derived.set_shader_parameter("material_region_exclude_uv", excluded_rectangles)
	derived.set_shader_parameter("material_region_exclude_local_min", excluded_minimums)
	derived.set_shader_parameter("material_region_exclude_local_max", excluded_maximums)
	derived.set_shader_parameter("material_region_exclude_sphere", excluded_spheres)
	derived.set_shader_parameter("material_region_color", colors)
	derived.set_shader_parameter("material_region_response", responses)
	derived.set_shader_parameter("material_region_color_family", color_families)
	derived.set_meta("material_revision", str(profile.get("material_revision", "source")))
	derived.set_meta("material_class", str(profile.get("material_class", "source")))
	derived.set_meta("material_revision_profile", profile.duplicate(true))

static func _runtime_materials(node: Node, materials: Array, profile: Dictionary = {}, texture_cache: Dictionary = {}) -> Error:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		if instance.mesh != null:
			if profile.has("normal_revision") and instance.mesh is ArrayMesh:
				instance.mesh = _normal_revision_mesh(instance.mesh, profile["normal_revision"], texture_cache)
			for surface in range(instance.mesh.get_surface_count()):
				var source: Material = instance.get_active_material(surface)
				if not source is BaseMaterial3D:
					continue
				var base: BaseMaterial3D = source
				var derived := ShaderMaterial.new()
				derived.shader = IMPORTED_SHADER
				var albedo := _profile_texture(base.albedo_texture, "albedo", profile, texture_cache, instance)
				if albedo != null:
					derived.set_shader_parameter("albedo_texture", albedo)
				derived.set_shader_parameter("has_albedo_texture", albedo != null)
				derived.set_shader_parameter("game_albedo_gain", float(profile.get("albedo_gain", 1.0)))
				derived.set_shader_parameter("game_roughness_floor", float(profile.get("roughness_floor", 0.0)))
				derived.set_shader_parameter("enable_hole_clip", bool(profile.get("enable_hole_clip", true)))
				derived.set_shader_parameter("albedo_tint", base.albedo_color)
				if profile.has("yellow_recolor"):
					var c: Array = profile["yellow_recolor"]
					derived.set_shader_parameter("recolor_yellow", true)
					derived.set_shader_parameter("yellow_target", Color(c[0],c[1],c[2],1))
				derived.set_shader_parameter("surface_roughness", base.roughness)
				derived.set_shader_parameter("surface_metallic", base.metallic)
				derived.set_shader_parameter("surface_specular", float(profile.get("specular", base.metallic_specular)))
				var metallic := _profile_texture(base.metallic_texture, "metallic", profile, texture_cache, instance)
				if metallic != null:
					derived.set_shader_parameter("metallic_texture", metallic)
					derived.set_shader_parameter("metallic_texture_channel", int(base.metallic_texture_channel))
					derived.set_shader_parameter("has_metallic_texture", true)
				var roughness := _profile_texture(base.roughness_texture, "roughness", profile, texture_cache, instance)
				if roughness != null:
					derived.set_shader_parameter("roughness_texture", roughness)
					derived.set_shader_parameter("roughness_texture_channel", int(base.roughness_texture_channel))
					derived.set_shader_parameter("has_roughness_texture", true)
				if instance.has_meta("material_revision_error"):
					return ERR_FILE_CORRUPT
				_apply_material_revision(derived, profile)
				instance.set_surface_override_material(surface, derived)
				materials.append(derived)
			# A surface override alone still serializes the original high-resolution
			# material on ArrayMesh. Strip those redundant references on a shared
			# runtime mesh copy, preserving the source mesh for subsequent instances.
			if int(profile.get("texture_max_size", 0)) > 0:
				var mesh_key := "runtime_mesh:%d" % instance.mesh.get_instance_id()
				if not texture_cache.has(mesh_key):
					var runtime_mesh: ArrayMesh = instance.mesh.duplicate() as ArrayMesh
					for surface in range(runtime_mesh.get_surface_count()):
						if instance.get_surface_override_material(surface) != null:
							runtime_mesh.surface_set_material(surface,StandardMaterial3D.new())
					texture_cache[mesh_key] = runtime_mesh
				instance.mesh = texture_cache[mesh_key]
	for child in node.get_children():
		var result := _runtime_materials(child, materials, profile, texture_cache)
		if result != OK:
			return result
	return OK

static func _scan(node: Node, parent_xf: Transform3D, info: Dictionary) -> void:
	var xf: Transform3D = parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node
		if instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				var vertices = arrays[Mesh.ARRAY_VERTEX]
				if vertices == null:
					continue
				var uv = arrays[Mesh.ARRAY_TEX_UV]
				if uv != null and (uv as PackedVector2Array).size() == (vertices as PackedVector3Array).size():
					info["uv_surfaces"] = int(info["uv_surfaces"]) + 1
				var material: Material = instance.get_active_material(surface)
				if material != null:
					info["material_surfaces"] = int(info["material_surfaces"]) + 1
					if material is BaseMaterial3D and (material as BaseMaterial3D).albedo_texture != null:
						info["textured_surfaces"] = int(info["textured_surfaces"]) + 1
				info["surfaces"] = int(info["surfaces"]) + 1
				var indices = arrays[Mesh.ARRAY_INDEX]
				var element_count: int = (indices as PackedInt32Array).size() if indices != null and (indices as PackedInt32Array).size() > 0 else (vertices as PackedVector3Array).size()
				info["triangles"] = int(info["triangles"]) + int(element_count / 3)
				for vertex in (vertices as PackedVector3Array):
					var point: Vector3 = xf * vertex
					info["min"] = (info["min"] as Vector3).min(point)
					info["max"] = (info["max"] as Vector3).max(point)
	for child in node.get_children():
		_scan(child, xf, info)

static func build(path: String, envelope: Vector3, theme_id: String, slot_id: String, archetype: String,
		support_height_from_base: float = 0.0) -> Node3D:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("Theme GLB path missing: " + path)
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error: Error = document.append_from_file(path, state)
	if error != OK:
		push_error("Theme GLB import failed: %s (%d)" % [path, error])
		return null
	var scene: Node = document.generate_scene(state)
	if scene == null or not scene is Node3D:
		push_error("Theme GLB has no 3D scene: " + path)
		return null
	var info: Dictionary = {}
	var scale_factor: float = 0.0
	var yaw_radians: float = 0.0
	var best_fill: float = -1.0
	# Test both footprint axes against this slot's actual frozen envelope. This is
	# recorded per source model, not a global 90-degree correction.
	for candidate_yaw in [0.0, PI * .5]:
		var candidate: Dictionary = {"min": Vector3.INF, "max": -Vector3.INF, "surfaces": 0,
			"uv_surfaces": 0, "material_surfaces": 0, "textured_surfaces": 0, "triangles": 0}
		_scan(scene, Transform3D(Basis(Vector3.UP, candidate_yaw), Vector3.ZERO), candidate)
		if int(candidate["surfaces"]) == 0:
			continue
		var candidate_size: Vector3 = (candidate["max"] as Vector3) - (candidate["min"] as Vector3)
		if candidate_size.x <= 0.0001 or candidate_size.y <= 0.0001 or candidate_size.z <= 0.0001:
			continue
		var candidate_scale: float = minf(envelope.x * .96 / candidate_size.x,
			minf(envelope.y * .96 / candidate_size.y, envelope.z * .96 / candidate_size.z))
		var fill: float = minf(candidate_size.x * candidate_scale / envelope.x,
			candidate_size.z * candidate_scale / envelope.z)
		if fill > best_fill:
			best_fill = fill
			info = candidate
			scale_factor = candidate_scale
			yaw_radians = candidate_yaw
	if info.is_empty() or int(info["surfaces"]) == 0:
		scene.free()
		push_error("Theme GLB has no mesh surfaces: " + path)
		return null
	var source_size: Vector3 = (info["max"] as Vector3) - (info["min"] as Vector3)
	if source_size.x <= 0.0001 or source_size.y <= 0.0001 or source_size.z <= 0.0001:
		scene.free()
		push_error("Theme GLB bounds are degenerate: " + path)
		return null
	# Lux3D does not promise gameplay-sized output. Preserve the raw GLB and apply a
	# small, recorded X/Z correction only where the height-limited uniform fit
	# leaves a role-specific footprint gap. Large shape changes still fail review.
	var target_fill: float = 0.80 if archetype in ["vehicle", "landmark"] else (0.75 if archetype == "wide_building" else 0.70)
	var max_axis_correction: float = 1.25 if archetype == "wide_building" else (1.10 if archetype == "landmark" else 1.15)
	var uniform_fill_x: float = source_size.x * scale_factor / envelope.x
	var uniform_fill_z: float = source_size.z * scale_factor / envelope.z
	var extra_x: float = minf(max_axis_correction, minf(.96 / uniform_fill_x, maxf(1.0, target_fill / uniform_fill_x)))
	var extra_z: float = minf(max_axis_correction, minf(.96 / uniform_fill_z, maxf(1.0, target_fill / uniform_fill_z)))
	var root := Node3D.new()
	root.name = "Visual"
	var fitted := Node3D.new()
	fitted.name = "SourceToEnvelope"
	var position := Vector3(-((info["min"] as Vector3).x + (info["max"] as Vector3).x) * .5 * scale_factor * extra_x,
		-envelope.y * .5 - (info["min"] as Vector3).y * scale_factor,
		-((info["min"] as Vector3).z + (info["max"] as Vector3).z) * .5 * scale_factor * extra_z)
	var world_fit: Basis = Basis.IDENTITY.scaled(Vector3(scale_factor * extra_x, scale_factor, scale_factor * extra_z))
	fitted.transform = Transform3D(world_fit * Basis(Vector3.UP, yaw_radians), position)
	root.add_child(fitted)
	fitted.add_child(scene)
	var extra_y: float = 1.0
	if archetype == "support_table" and support_height_from_base > 0.0:
		var samples: Array = [Vector2(-.4, -.19), Vector2(0, -.19), Vector2(.4, -.19),
			Vector2(-.4, .19), Vector2(0, .19), Vector2(.4, .19)]
		var expected_y: float = -envelope.y * .5 + support_height_from_base
		var preliminary: Dictionary = SupportSurface.measure(root, samples, expected_y)
		var heights: Array = preliminary["measured_y_local"]
		if not heights.has(null):
			var lowest: float = INF
			var highest: float = -INF
			var sum: float = 0.0
			for height in heights:
				lowest = minf(lowest, float(height))
				highest = maxf(highest, float(height))
				sum += float(height)
			var current_height: float = sum / heights.size() + envelope.y * .5
			var required: float = support_height_from_base / current_height if current_height > .1 else 0.0
			var max_by_envelope: float = envelope.y * .96 / (source_size.y * scale_factor)
			if highest - lowest <= .05 and required >= .90 and required <= 1.15:
				extra_y = clampf(required, .90, minf(1.15, max_by_envelope))
				if absf(extra_y - 1.0) > .0001:
					world_fit = Basis.IDENTITY.scaled(Vector3(scale_factor * extra_x,
						scale_factor * extra_y, scale_factor * extra_z))
					position.y = -envelope.y * .5 + (position.y + envelope.y * .5) * extra_y
					fitted.transform = Transform3D(world_fit * Basis(Vector3.UP, yaw_radians), position)
	var runtime_materials: Array = []
	if _runtime_materials(scene, runtime_materials) != OK:
		root.free()
		return null
	root.set_meta("asset_id", slot_id)
	root.set_meta("theme_id", theme_id)
	root.set_meta("status", "LUX3D_RAW_CANDIDATE")
	root.set_meta("source", "lux3d_raw_candidate")
	root.set_meta("triangles", int(info["triangles"]))
	root.set_meta("material_slots", int(info["surfaces"]))
	root.set_meta("raw_glb_path", path)
	root.set_meta("source_bounds", source_size)
	root.set_meta("source_to_envelope_scale", scale_factor)
	root.set_meta("source_to_envelope_extra_xz", Vector2(extra_x, extra_z))
	root.set_meta("source_to_envelope_extra_y", extra_y)
	root.set_meta("source_footprint_fill_xz", Vector2(uniform_fill_x * extra_x, uniform_fill_z * extra_z))
	root.set_meta("source_to_envelope_yaw_degrees", rad_to_deg(yaw_radians))
	root.set_meta("uv_surfaces", int(info["uv_surfaces"]))
	root.set_meta("textured_surfaces", int(info["textured_surfaces"]))
	root.set_meta("cutaway_materials", runtime_materials)
	return root

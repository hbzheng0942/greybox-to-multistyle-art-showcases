extends "res://../art/train-parkour/shared/tools/lux_calibration_world.gd"
## Incremental S8 assembly over the verified calibration. Never changes collision/gameplay.
## Geometry-only LODs reuse the single canonical source's PBR Material resources.
var source_templates: Dictionary = {}
var sample_templates: Dictionary = {}
var sample_specs: Dictionary = {}
var sample_seen: Dictionary = {}
var sample_layout_path := ""
var sample_layout_hash := ""
const FunctionalAssembly = preload("res://../art/train-parkour/shared/tools/lux_functional_assembly.gd")
const RouteDressing = preload("res://../art/train-parkour/shared/tools/lux_route_dressing.gd")

func build_style(session: Node3D, style_id: String) -> Node3D:
	var world := super.build_style(session, style_id)
	var before := _collision_count(session)
	source_templates.clear()
	sample_templates.clear()
	sample_specs.clear()
	sample_seen.clear()
	sample_layout_path = ""
	sample_layout_hash = ""
	var path := _sample_config_path()
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not config is Dictionary:
		errors.append("Missing S8 assembly descriptor: " + path)
	else:
		_apply_sample(world, config)
		for extra: Dictionary in config.get("additional_layouts", []):
			var extra_layout: Variant = _read_bound_json(extra)
			if extra_layout is Dictionary: _apply_layout(world, extra_layout)
		if config.has("functional"):
			var functional: Variant = _read_bound_json(config.functional)
			if functional is Dictionary:
				_load_sample_assets(functional.get("assets", []))
				FunctionalAssembly.new().build(session, world, self, functional)
				RouteDressing.new().build(session, world, self, functional)
		_apply_sample_lighting(session, world)
	for model: Node in source_templates.values(): model.free()
	for model: Node in sample_templates.values(): model.free()
	source_templates.clear()
	sample_templates.clear()
	var delta := _collision_count(session) - before
	if delta != 0: errors.append("Sample assembly changed collision count")
	var report := {"schema": 1, "stage": "S8_PARTIAL_SAMPLE_ASSEMBLY", "style_id": sid,
		"descriptor_path": ProjectSettings.globalize_path(path),
		"descriptor_sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "",
		"layout_path": sample_layout_path, "layout_sha256": sample_layout_hash,
		"assets": asset_reports, "instances": instance_reports, "new_collision_nodes": delta,
		"errors": errors.duplicate(), "warnings": warnings.duplicate(), "passed": errors.is_empty(),
		"scope": "Explicit measured sample additions plus original calibration; remaining route is S6 proxy",
		"limits": "AABB bounds are conservative; native visual/contact/route/performance review required. Not H4 acceptance."}
	world.set_meta("lux_sample_report", report)
	world.set_meta("proxy_geometry", _active_geometry(world.get_meta("proxy_geometry_before_calibration", {})))
	var combined: Dictionary = world.get_meta("construction_report", {}).duplicate(true)
	combined["stage"] = "S8_PARTIAL_SAMPLE_ASSEMBLY"
	var all_errors: Array = world.get_meta("proxy_construction_report", {}).get("errors", []).duplicate()
	all_errors.append_array(errors)
	combined["errors"] = all_errors
	combined["sample_asset_records"] = asset_reports.size()
	combined["sample_instance_records"] = instance_reports.size()
	combined["lux_functional"] = world.get_meta("lux_functional_report", {})
	combined["lux_route_dressing"] = world.get_meta("lux_route_dressing_report", {})
	combined["new_collision_nodes"] = delta
	combined["fidelity_acceptance"] = "Pending native sample review"
	world.set_meta("construction_report", combined)
	return world

func _sample_config_path() -> String:
	return CASE + "styles/" + sid + "/runtime/sample-assembly.json"

func _apply_sample_lighting(session: Node3D, world: Node3D) -> void:
	# The approved warehouse anchor has darker ambient space and warm practical pools.
	# Art-only environment overrides; the frozen route/camera remain unchanged.
	if sid != "odd-logistics": return
	for node: WorldEnvironment in session.find_children("*", "WorldEnvironment", true, false):
		var env := node.environment.duplicate() as Environment
		node.environment = env
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("222b29")
		sky_material.sky_horizon_color = Color("444a3d")
		sky_material.ground_bottom_color = Color("252c27")
		sky_material.ground_horizon_color = Color("444a3d")
		var sky := Sky.new()
		sky.sky_material = sky_material
		env.sky = sky
		env.ambient_light_color = Color("87978b")
		env.ambient_light_energy = 0.42
		env.fog_light_color = Color("5b624d")
		env.fog_density = 0.00065
		env.ssao_intensity = 1.7
		env.glow_intensity = 0.3
	for sun: DirectionalLight3D in session.find_children("*", "DirectionalLight3D", true, false):
		sun.light_color = Color("f3e9cb")
		sun.light_energy = 1.35
	var route: Node = session.lab.get_node("RouteRoot/MainRoute")
	var lights := 0
	for track_id: String in ["station_start", "station_carve"]:
		var track = route.tracks[track_id]
		for i in range(ceili(track.length / 105.0)):
			var along := minf(track.length - 5.0, 25.0 + i * 105.0)
			var pose: Transform3D = route.track_pose(track_id, along, 0)
			var light := OmniLight3D.new()
			light.name = "WarehousePractical_%s_%02d" % [track_id, i]
			light.light_color = Color("fff0c4")
			light.light_energy = 6.0
			light.omni_range = 72.0
			light.omni_attenuation = 1.2
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 180.0
			light.distance_fade_length = 90.0
			world.add_child(light)
			light.global_position = pose.origin + Vector3.UP * 28.0
			lights += 1
	world.set_meta("sample_lighting", {"art_only":true,"practical_lights":lights,
		"source_reference":"B2-scene-v2.png", "emitter_mesh_status":"Lux ceiling fixtures attached by functional assembly; native alignment review pending",
		"native_visual_acceptance":"pending"})

func _read_bound_json(binding: Dictionary) -> Variant:
	var path := _bound_path(binding, ".json")
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null

func _bound_path(binding: Dictionary, extension: String) -> String:
	var path := str(binding.get("path", ""))
	var digest := str(binding.get("sha256", ""))
	if path.is_empty() or path.is_absolute_path() or path.contains(":") or ".." in path.split("/") or not path.ends_with(extension):
		errors.append("Invalid sample resource path")
		return ""
	var absolute := ProjectSettings.globalize_path("res://../" + path)
	if digest.length() != 64 or not FileAccess.file_exists(absolute) or FileAccess.get_sha256(absolute) != digest:
		errors.append("Sample resource hash mismatch: " + path)
		return ""
	return absolute

func _apply_sample(world: Node3D, config: Dictionary) -> void:
	var layout: Variant = _read_bound_json(config.get("layout", {}))
	if not layout is Dictionary or str(layout.get("style_id", "")) != sid:
		errors.append("Invalid sample layout/style binding")
		return
	sample_layout_path = str(config.layout.path)
	sample_layout_hash = str(config.layout.sha256)
	_load_sample_assets(config.get("assets", []))
	_apply_layout(world, layout)

func _apply_layout(world: Node3D, layout: Dictionary) -> void:
	if str(layout.get("style_id", "")) != sid:
		errors.append("Layout/style mismatch")
		return
	for placement: Dictionary in layout.get("support_modules", []):
		_place_sample_model(world, placement, "far", "add")
	for part: Dictionary in layout.get("support_plinths", []): _place_structural_box(world, part)
	for part: Dictionary in layout.get("floor_caps", []): _place_structural_box(world, part)
	for part: Dictionary in layout.get("support_structures", []):
		if part.has("size_m") and (part.has("primitive") or part.has("geometry")): _place_structural_box(world, part)
	for part: Dictionary in layout.get("local_structures", []): _place_structural_box(world, part)
	for placement: Dictionary in layout.get("placements", []):
		var operation := str(placement.get("operation", "add"))
		if operation == "retain_existing": continue
		var level := "far" if str(placement.get("depth_band", "")) == "far" else "near"
		_place_sample_model(world, placement, level, operation)
	var removals: Array = layout.get("remove_proxy_instance_ids", []).duplicate()
	for replacement: Dictionary in layout.get("proxy_replacements", []):
		if replacement.get("action", "") == "hide_visual_only_after_parent_integration" and not replacement.get("frozen_geometry_or_collision", true):
			removals.append(str(replacement.source_proxy_instance_id))
	for old_id: String in removals:
		if old_id in replaced_ids: continue
		var matches: Array[Node3D] = []
		_find_instance(world, old_id, matches)
		if matches.size() != 1 or matches[0].get_parent() != world or not matches[0].is_visible_in_tree():
			errors.append("Layout removal lacks exact visible proxy: " + old_id)
			continue
		matches[0].visible = false
		replaced_ids.append(old_id)

func _load_sample_assets(assets: Array) -> void:
	for spec: Dictionary in assets:
		var ident := str(spec.get("id", ""))
		if sample_specs.has(ident):
			errors.append("Duplicate sample asset: " + ident)
			continue
		var original := load_asset(spec)
		if original == null: continue
		source_templates[ident] = original
		sample_specs[ident] = spec
		var manifest: Variant = _read_bound_json(spec.get("lod_manifest", {}))
		if not manifest is Dictionary or manifest.get("source", {}).get("sha256", "") != spec.source.sha256:
			errors.append("LOD manifest/source mismatch: " + ident)
			continue
		for level: Dictionary in manifest.get("levels", []):
			var name := str(level.get("id", ""))
			if not name in ["near", "far"] or level.get("visual_review", "") != "accepted_for_native_integration" or not level.get("roundtrip_verified", false):
				errors.append("Unsupported sample LOD: " + name)
				continue
			var model := _load_shared_material_lod(spec, original, level)
			if model != null: sample_templates[ident + ":" + name] = model

func _mesh_nodes(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null: found.append(node)
	for child: Node in node.get_children(): _mesh_nodes(child, found)

func _load_shared_material_lod(spec: Dictionary, original: Node3D, level: Dictionary) -> Node3D:
	var path := _bound_path(level, ".glb")
	if path.is_empty(): return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		errors.append("LOD parse failed: " + str(spec.id))
		return null
	var imported := doc.generate_scene(state)
	if imported == null: return null
	var source_meshes: Array[MeshInstance3D] = []
	var lod_meshes: Array[MeshInstance3D] = []
	_mesh_nodes(original, source_meshes)
	_mesh_nodes(imported, lod_meshes)
	if not forbidden_nodes(imported).is_empty() or source_meshes.size() != 1 or lod_meshes.size() != 1 or source_meshes[0].mesh.get_surface_count() != 1 or lod_meshes[0].mesh.get_surface_count() != 1:
		errors.append("LOD requires audited static single mesh/material: " + str(spec.id))
		imported.free()
		return null
	var slots: Variant = level.get("material_slots", [])
	if not slots is Array or slots.size() != 1 or int(slots[0].get("source_mesh_index", -1)) != 0 or int(slots[0].get("source_primitive_index", -1)) != 0:
		errors.append("LOD material mapping missing: " + str(spec.id))
		imported.free()
		return null
	var arrays := lod_meshes[0].mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_TEX_UV] == null or arrays[Mesh.ARRAY_TEX_UV].size() != arrays[Mesh.ARRAY_VERTEX].size():
		errors.append("LOD UV data missing: " + str(spec.id))
		imported.free()
		return null
	var material := source_meshes[0].get_active_material(0)
	if not material is BaseMaterial3D or material.albedo_texture == null:
		errors.append("Original PBR missing for LOD: " + str(spec.id))
		imported.free()
		return null
	lod_meshes[0].set_surface_override_material(0, material)
	var normalized := Node3D.new()
	normalized.transform = matrix_transform(spec.source_to_normalized)
	normalized.add_child(imported)
	var measured := measure(normalized)
	var original_measure := measure(original)
	var source_box: AABB = original_measure.bounds
	var lod_box: AABB = measured.bounds
	var tolerance := maxf(0.02, source_box.size.length() * 0.005)
	if (source_box.position - lod_box.position).length() > tolerance or (source_box.end - lod_box.end).length() > tolerance:
		errors.append("LOD changed source envelope: " + str(spec.id))
		normalized.free()
		return null
	asset_reports.append({"id": str(spec.id) + ":" + str(level.id), "role": "shared_material_lod", "source": spec.source,
		"lod": {"path": level.path, "sha256": level.sha256}, "triangles": level.get("actual_triangles", -1),
		"source_material_shared": lod_meshes[0].get_active_material(0) == material,
		"texture_copies_created": 0, "normalized_bounds": box_record(lod_box)})
	return normalized

func _claim_placement(p: Dictionary) -> bool:
	var ident := str(p.get("id", ""))
	if ident.is_empty() or sample_seen.has(ident) or not _valid_vector(p.get("position")) or not _number(p.get("yaw_radians")) or not str(p.get("space_id", "")) in ["N01", "N07", "N08"]:
		errors.append("Invalid/duplicate S8 sample placement: " + ident)
		return false
	sample_seen[ident] = true
	return true

func _place_sample_model(world: Node3D, p: Dictionary, level: String, operation: String) -> void:
	if not _claim_placement(p): return
	var ident := str(p.id)
	var asset_id := str(p.get("asset_id", ""))
	var key := asset_id + ":" + level
	if not sample_templates.has(key) or not _number(p.get("uniform_scale")) or float(p.uniform_scale) <= 0 or not operation in ["add", "replace_proxy"]:
		errors.append("Missing sample template/invalid operation: " + ident)
		return
	var old: Node3D = null
	var old_id := str(p.get("source_proxy_instance_id", ""))
	if operation == "replace_proxy":
		var matches: Array[Node3D] = []
		_find_instance(world, old_id, matches)
		if old_id.is_empty() or matches.size() != 1 or replaced_ids.has(old_id) or matches[0].get_parent() != world or not matches[0].is_visible_in_tree():
			errors.append("Sample replacement lacks exact visible proxy: " + ident)
			return
		old = matches[0]
	var mount := Node3D.new()
	mount.name = ident.validate_node_name()
	mount.add_child(sample_templates[key].duplicate())
	world.add_child(mount)
	mount.global_transform = Transform3D(Basis(Vector3.UP, float(p.yaw_radians)).scaled(Vector3.ONE * float(p.uniform_scale)), vector(p.position))
	_tag_tree(mount, ident, asset_id, str(p.get("scene_id", "station" if p.space_id == "N01" else "valley")))
	if not _record_sample_geometry(world, mount, p, asset_id, sample_specs[asset_id].source.sha256, level):
		mount.free()
		return
	if old != null:
		old.visible = false
		replaced_ids.append(old_id)

func _place_structural_box(world: Node3D, p: Dictionary) -> void:
	p = p.duplicate(true)
	if p.get("geometry", "") == "box_with_edge_bevel_trim":
		# Layout bottom-centre convention is converted once to the BoxMesh centre.
		p["primitive"] = "box"
		p["role"] = "submerged_foundation"
		if p.get("position_semantics", "") == "center XZ, bottom Y":
			p.position[1] += float(p.size_m[1]) * 0.5
	if not _claim_placement(p): return
	if str(p.get("primitive", "")) != "box" or not _valid_vector(p.get("size_m"), true):
		errors.append("Invalid structural cap/plinth")
		return
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = vector(p.size_m)
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.28, 0.20) if str(p.role) == "short_thick_support_plinth" else Color(0.34, 0.36, 0.24)
	material.roughness = 0.92
	if sid == "rain-eaten-city": material.albedo_color = Color("59615f")
	mesh.material_override = material
	mesh.name = str(p.id).validate_node_name()
	world.add_child(mesh)
	mesh.global_transform = Transform3D(Basis(Vector3.UP, float(p.yaw_radians)), vector(p.position))
	_tag_tree(mesh, str(p.id), "local_structural_connector", str(p.get("scene_id", "station" if p.space_id == "N01" else "valley")))
	if not _record_sample_geometry(world, mesh, p, "local_structural_connector", "", "structural_box"): mesh.free()

func _record_sample_geometry(world: Node3D, node: Node3D, p: Dictionary, asset_id: String, digest: String, level: String) -> bool:
	var measured := measure(node, world.global_transform)
	if not measured.finite or int(measured.mesh_count) == 0:
		errors.append("Invalid sample geometry: " + str(p.id))
		return false
	var declared: Variant = p.get("world_aabb_m")
	if not declared is Dictionary:
		errors.append("Missing reviewed placement envelope: " + str(p.id))
		return false
	var expected := AABB(vector(declared.min_m), vector(declared.max_m) - vector(declared.min_m))
	if not expected.grow(0.12).encloses(measured.bounds):
		errors.append("Native sample exceeds reviewed envelope: " + str(p.id))
		return false
	for i in measured.meshes.size():
		var row: Dictionary = measured.meshes[i]
		var box: Dictionary = row.bounds
		added_bounds.append({"id": str(p.id) + ":mesh:" + str(i), "style_id": sid, "space_id": p.space_id,
			"category": "background_mass", "center_m": array(vector(box.position_m) + vector(box.size_m) * 0.5), "size_m": box.size_m,
			"basis_columns": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "protected_route": false,
			"bounds_kind": row.get("bounds_kind", "conservative_mesh_aabb"), "mesh_path": row.path, "mesh_local_aabb": row.local_aabb,
			"mesh_to_world": row.transform, "source_asset_id": asset_id, "source_sha256": digest})
	instance_reports.append({"id": p.id, "asset_id": asset_id, "role": "environment", "space_id": p.space_id,
		"scene_id": str(p.get("scene_id", "station" if p.space_id == "N01" else "valley")), "source_proxy_instance_id": p.get("source_proxy_instance_id", ""),
		"lod": level, "position": p.position, "yaw_radians": p.yaw_radians,
		"uniform_scale": p.get("uniform_scale", 1.0), "bounds_world_m": box_record(measured.bounds),
		"source_to_normalized_applied_once": true, "native_ground_contact": "pending_visual_review"})
	return true

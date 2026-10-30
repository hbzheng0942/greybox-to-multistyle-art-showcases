extends "res://themes/paper_atlas/blockout_candidate.gd"
## Continuous N01-N07 presentation; all gameplay, route and camera sources are unchanged.
const ART_WORLD = preload("res://themes/paper_atlas/assets/canyon_art/world.glb")
const ART_PAPER = preload("res://themes/paper_atlas/canyon_paper.gdshader")
const MATERIAL_ADAPTER = preload("res://themes/paper_atlas/material_adapter.gd")
var material_adapter = MATERIAL_ADAPTER.new()
const TRANSPORT = preload("res://themes/paper_atlas/paper_transport.gd")
const ATMOSPHERE = preload("res://themes/paper_atlas/paper_atmosphere.gd")
var art_materials: Dictionary = {}
var generated_materials: Dictionary = {}
var generated_scenes: Dictionary = {}

func build(session: Node3D) -> Node3D:
	var result := super.build(session)
	# Replace the selected blockout canyon, retain shared six-node context and rails.
	result.get_child(result.get_child_count()-1).free()
	# Superseded decorative context only; actual frozen gameplay nodes stay intact.
	for mesh in result.find_children("*", "GeometryInstance3D", true, false):
		if str(mesh.name).begins_with("N01_context") or str(mesh.name).begins_with("N03_context") or str(mesh.name).begins_with("N04_context") or str(mesh.name).begins_with("N05_context") or str(mesh.name).begins_with("N06_context") or str(mesh.name).begins_with("N07_context"):
			mesh.visible = false
	for label in ["VerticalStationFrame", "CoilStation", "LoopRibs"]:
		var old_frame := session.get_node_or_null("ControllerLab/EnvironmentRoot/"+label) as GeometryInstance3D
		if old_frame != null: old_frame.visible = false
	var world: Node3D = ART_WORLD.instantiate()
	world.name = "N02ArtWorld"
	result.add_child(world)
	_art_register(world, "N02_art_geometry", false)
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://themes/paper_atlas/canyon_art_instances.json"))
	for item in spec.g1_instances:
		var source_path: String = "res://" + str(item.source).trim_prefix("game/")
		if not generated_scenes.has(source_path):
			generated_scenes[source_path] = load(source_path) as PackedScene
		var source := generated_scenes[source_path] as PackedScene
		if source == null:
			push_error("Missing canonical paper asset: " + source_path)
			continue
		var model: Node3D = source.instantiate()
		model.name = item.id
		result.add_child(model)
		model.position = Vector3(item.position_m[0],item.position_m[1],item.position_m[2])
		model.rotation.y = deg_to_rad(item.yaw_degrees)
		var shape: Array = item.get("shape_scale", [1.0,1.0,1.0])
		model.scale = Vector3(float(shape[0]),float(shape[1]),float(shape[2])) * item.uniform_scale
		_art_register(model, item.id, true, str(item.get("scene_id","canyon")))
		_art_asset_identity(model, str(item.asset_id), float(item.get("visibility_range_m", 800.0)))
	var lantern_count := 0
	var lantern_candidates: Array = spec.get("b3_environment", {}).get("lantern_candidates", [])
	# Keep lights tied to distinctive inhabited places before thinning the
	# repeated tunnel fixtures; every actual civic lamp keeps its local light.
	var selected_lights: Array = lantern_candidates.filter(func(row): return int(row.get("priority",0)) > 0)
	var repeated_lights: Array = lantern_candidates.filter(func(row): return int(row.get("priority",0)) == 0)
	var remaining := maxi(0,80-selected_lights.size())
	if remaining > 0:
		var stride := maxi(1,ceili(float(repeated_lights.size())/float(remaining)))
		for index in range(0,repeated_lights.size(),stride): selected_lights.append(repeated_lights[index])
	for item: Dictionary in selected_lights:
		var lantern := OmniLight3D.new()
		lantern.name = "PaperLantern_"+str(lantern_count)
		lantern.position = Vector3(item.position_m[0],item.position_m[1],item.position_m[2])
		lantern.light_color = Color(item.colour)
		lantern.light_energy = float(item.energy)
		lantern.omni_range = float(item.radius_m)
		lantern.shadow_enabled = false
		lantern.distance_fade_enabled = true
		lantern.distance_fade_begin = 60.0
		lantern.distance_fade_length = 25.0
		result.add_child(lantern)
		lantern_count += 1
	result.set_meta("tunnel_lantern_count",lantern_count)
	TRANSPORT.new().install(session,result)
	ATMOSPHERE.new().install(session,result,spec)
	var env: Node3D = session.get_node("ControllerLab/EnvironmentRoot")
	var sun := env.get_node("Sun") as DirectionalLight3D
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 620.0
	sun.shadow_blur = 1.6
	sun.shadow_opacity = 0.82
	sun.light_energy = 1.18
	sun.light_color = Color("fff1d9")
	sun.light_angular_distance = 1.6
	sun.rotation_degrees = Vector3(-42.0, -48.0, 0.0)
	var atmosphere := (env.get_node("WorldEnvironment") as WorldEnvironment).environment
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_sky_contribution = 0.30
	atmosphere.ambient_light_energy = 0.34
	atmosphere.ambient_light_color = Color("e5e4d6")
	atmosphere.ssao_enabled = true
	atmosphere.ssil_enabled = true
	atmosphere.ssao_radius = 4.0
	atmosphere.ssao_intensity = 2.0
	atmosphere.ssao_light_affect = 0.20
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_ACES
	atmosphere.tonemap_exposure = 1.02
	atmosphere.tonemap_white = 4.0
	atmosphere.fog_density = 0.00013
	atmosphere.glow_enabled = true
	atmosphere.glow_intensity = 0.34
	atmosphere.glow_hdr_threshold = 1.1
	atmosphere.fog_sky_affect = 0.12
	var sky_material := atmosphere.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = Color("58a2df")
	sky_material.sky_horizon_color = Color("7abde6")
	sky_material.ground_horizon_color = Color("7abde6")
	atmosphere.fog_light_color = Color("c4dce5")
	result.set_meta("art_stage","full_world_continuity_candidate_concept_review_pending")
	return result

func _art_asset_identity(node: Node, asset_id: String, visibility_range: float) -> void:
	node.set_meta("asset_id", asset_id)
	if node is MeshInstance3D:
		# Import-generated mesh LODs remain active. Range only removes remote source
		# detail, with broad procedural scenery preserving the valley silhouette.
		node.visibility_range_end = visibility_range
		node.visibility_range_end_margin = 60.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child in node.get_children():
		_art_asset_identity(child, asset_id, visibility_range)

func _art_register(node: Node, identity: String, textured: bool, scene_id := "canyon") -> void:
	var extras: Dictionary = node.get_meta("extras", {})
	scene_id = str(extras.get("scene_id",scene_id))
	node.set_meta("scene_id",scene_id)
	node.set_meta("asset_id","canyon_art")
	node.set_meta("instance_id",identity+":"+str(node.name))
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var source := node.mesh.surface_get_material(i) as BaseMaterial3D
			if source == null: continue
			if textured:
				if not generated_materials.has(source):
					# Preserve unsupported imported contributions instead of silently stripping them.
					generated_materials[source] = material_adapter.convert(source)
					var gaps: Array = material_adapter.unsupported(source)
					if not gaps.is_empty():
						push_warning("Paper material kept native: " + str(gaps))
				node.set_surface_override_material(i,generated_materials[source])
			else:
				var material_key: Variant = source
				var warm_fixture := str(node.name).begins_with("N05_lantern") or "nave_lantern_core" in str(node.name) or "rock_niche_lamp" in str(node.name)
				if warm_fixture: material_key = "lantern_"+str(source.get_instance_id())
				if not art_materials.has(material_key):
					var mat := ShaderMaterial.new()
					mat.shader = ART_PAPER
					mat.set_shader_parameter("tint",source.albedo_color)
					if warm_fixture:
						mat.set_shader_parameter("emission_energy",0.60)
					art_materials[material_key] = mat
				node.set_surface_override_material(i,art_materials[material_key])
	for child in node.get_children(): _art_register(child,identity,textured,scene_id)

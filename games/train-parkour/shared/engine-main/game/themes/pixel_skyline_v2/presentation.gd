extends RefCounted
## Independent V2 presentation. Gameplay, camera solids, poses and HUD stay frozen.

const PixelArtMaterials = preload("res://themes/pixel_skyline_v2/pixel_art_materials.gd")
const ContourPass = preload("res://themes/pixel_skyline_v2/contour_pass.gd")
const SKY_SHADER = preload("res://themes/pixel_skyline_v2/shaders/dusk_sky.gdshader")
const ROCK_SHADER = preload("res://themes/pixel_skyline_v2/shaders/continuous_rock.gdshader")
const WATER_SHADER = preload("res://themes/pixel_skyline_v2/shaders/water.gdshader")
const FALLING_WATER_SHADER = preload("res://themes/pixel_skyline_v2/shaders/falling_water.gdshader")
const SERVICE_SURFACE_SHADER = preload("res://themes/pixel_skyline_v2/shaders/service_surface.gdshader")
const HAZARD_SURFACE_SHADER = preload("res://themes/pixel_skyline_v2/shaders/hazard_surface.gdshader")
const TRAIN_SHADER = preload("res://themes/pixel_skyline_v2/shaders/train_livery.gdshader")
# The dynamic optional path allows descriptor validation before the authored
# export exists. input_roots fingerprints this complete directory once supplied.
const WORLD_DIRECTORY := "res://themes/pixel_skyline_v2/assets/"
const WORLD_FILENAME := "sample_world.glb"
const CartoonTrial = preload("res://themes/pixel_skyline_v2/cartoon_trial.gd")
const RouteFinish = preload("res://themes/pixel_skyline_v2/route_finish.gd")

# These are visual greybox batches explicitly authored by spatial_full_lab.gd.
# Keep Bed, Clamps, obstacle bodies and cues. Only the authored Power Tunnel
# replaces its rendered ContactStructure; original collision nodes remain frozen.
const REPLACED_ENVIRONMENT_BATCHES := [
	"StationGround", "StationPlatforms", "DistantPiers", "ValleyWalls",
	"ValleyFloor", "Riverbed", "FinalFloor", "FinalRidges", "HubBeacon",
]
const SAMPLE_TRACK_PREFIXES := ["station_", "canyon_", "rush_", "carve_", "wall_", "inverted_", "drop_", "rollout_", "cliff_", "upper_", "rescue_", "finish_", "landmark_return_", "loop_", "exit_", "grind_", "relay_", "high_", "tunnel_", "underpass_", "return_switchback_", "final_", "victory_"]
const SCENE_PREFIXES := {
	"station": "station", "terminal": "station", "canyon": "canyon",
	"energy_cut": "canyon", "inverted": "vertical", "loop": "coaster",
	"tunnel": "tunnel", "reservoir": "valley", "observatory": "finale",
}

var _materials: Dictionary = {}

func build(session: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "PixelSkylineV2"
	root.set_meta("scene_id", "station")
	root.set_meta("asset_id", "pixel_v2_sample_world")
	root.set_meta("instance_id", "pixel_v2_world")
	root.set_meta("build_state", "pending_authored_world")
	session.add_child(root)
	_build_palette()
	_apply_track_materials(session)
	_apply_train_materials(session)
	_apply_environment(session, root)
	ContourPass.attach(session.camera)
	var world := _load_authored_world()
	if world == null:
		push_warning("Pixel Skyline V2: authored sample_world.glb is pending or invalid; greybox decoration remains visible.")
		return root
	root.add_child(world)
	root.set_meta("cartoon_trial", CartoonTrial.install(world))
	root.set_meta("route_finish", RouteFinish.install_district(world))
	root.set_meta("g1_prepared_material_count", _prepare_imported_materials(world))
	var mesh_count := _register_geometry(world, world, "station", "pixel_v2_sample_world")
	if mesh_count == 0:
		root.remove_child(world)
		world.free()
		push_error("Pixel Skyline V2: authored world contains no renderable geometry.")
		return root
	root.set_meta("build_state", "authored_world_loaded")
	root.set_meta("authored_geometry_count", mesh_count)
	var light_count := _build_authored_lights(world)
	var expected_lights := 0
	for marker: Node in world.find_children("*", "Node3D", true, false):
		var extras: Dictionary = marker.get_meta("extras", {})
		if not str(marker.get_meta("art_light_color", extras.get("art_light_color", ""))).is_empty():
			expected_lights += 1
	var construction_errors: Array = []
	var finish_report: Dictionary = root.get_meta("route_finish", {})
	if finish_report.has("error"):
		construction_errors.append(finish_report.error)
		push_error("Route finish incomplete: " + str(finish_report.error))
	var cartoon_report: Dictionary = root.get_meta("cartoon_trial", {})
	if cartoon_report.has("error"):
		construction_errors.append(cartoon_report.error)
		push_error("Cartoon trial incomplete: " + str(cartoon_report.error))
	if light_count != expected_lights:
		construction_errors.append("Authored fixture light metadata failed to instantiate")
	root.set_meta("authored_light_count", light_count)
	root.set_meta("construction_report", {"errors": construction_errors,
		"authored_geometry_count": mesh_count, "authored_light_count": light_count,
		"source_light_anchor_count": expected_lights, "lighting_shadow_maps": 0,
		"route_finish": finish_report, "warning_finishes":session.get_meta("warning_finishes", {})})
	root.set_meta("visual_replacement_count", _hide_replaced_decorations(session, world))
	return root

func _build_authored_lights(world: Node3D) -> int:
	var count := 0
	for marker: Node in world.find_children("*", "Node3D", true, false):
		var extras: Dictionary = marker.get_meta("extras", {})
		var lamp_color := str(marker.get_meta("art_light_color", extras.get("art_light_color", "")))
		if lamp_color.is_empty():
			continue
		var lamp := OmniLight3D.new()
		lamp.name = "AuthoredFixtureLight"
		lamp.light_color = Color(lamp_color).lerp(Color("ff983c"), 0.35)
		# Source values are relative fixture intensity; calibrate to this filmic
		# scene exposure without changing the outdoor sun/ambient balance.
		lamp.light_energy = 8.0 * float(marker.get_meta("art_light_energy", extras.get("art_light_energy", 1.0)))
		lamp.omni_range = 1.0 * float(marker.get_meta("art_light_range_m", extras.get("art_light_range_m", 24.0)))
		lamp.omni_attenuation = 1.4
		lamp.shadow_enabled = false
		lamp.distance_fade_enabled = true
		lamp.distance_fade_begin = 110.0
		lamp.distance_fade_length = 50.0
		marker.add_child(lamp)
		count += 1
	return count

func _load_authored_world() -> Node3D:
	var path := WORLD_DIRECTORY + WORLD_FILENAME
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Pixel Skyline V2: authored world must import as PackedScene.")
		return null
	var instance := packed.instantiate()
	if not instance is Node3D or _contains_collision(instance):
		push_error("Pixel Skyline V2: authored world must be a Node3D with no collision nodes.")
		instance.free()
		return null
	var world := instance as Node3D
	if not world.transform.is_equal_approx(Transform3D.IDENTITY):
		push_error("Pixel Skyline V2: normalize the world export to an identity root transform; runtime does not repair DCC coordinates.")
		world.free()
		return null
	world.name = "AuthoredWorld"
	return world

func _contains_collision(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		return true
	for child: Node in node.get_children():
		if _contains_collision(child):
			return true
	return false

func _register_geometry(node: Node, world: Node3D, inherited_scene: String, inherited_asset: String) -> int:
	var extras: Dictionary = node.get_meta("extras", {})
	var scene_id := str(node.get_meta("scene_id", extras.get("scene_id", "")))
	if scene_id.is_empty():
		scene_id = _scene_from_name(str(node.name), inherited_scene)
	var asset_id := str(node.get_meta("asset_id", extras.get("asset_id", inherited_asset)))
	if asset_id.is_empty():
		asset_id = inherited_asset
	var count := 0
	if node is GeometryInstance3D:
		var instance_id := str(node.get_meta("instance_id", extras.get("instance_id", "")))
		if instance_id.is_empty():
			instance_id = "pixel_v2/" + str(world.get_path_to(node))
		node.set_meta("scene_id", scene_id)
		node.set_meta("asset_id", asset_id)
		node.set_meta("instance_id", instance_id)
		if asset_id == "far_skyline":
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		count = 1
	for child: Node in node.get_children():
		count += _register_geometry(child, world, scene_id, asset_id)
	return count

func _scene_from_name(node_name: String, fallback: String) -> String:
	var lower := node_name.to_lower()
	for prefix: String in SCENE_PREFIXES:
		if lower.begins_with(prefix):
			return SCENE_PREFIXES[prefix]
	return fallback

func _prepare_imported_materials(world: Node3D) -> int:
	# Exported G1_<asset> material names are the opt-in boundary. Duplicate each
	# resource once and keep every map, UV transform, alpha and normal channel.
	# Palette grouping and stepped illumination unify assets; rock/water stay world anchored.
	var prepared: Dictionary = {}
	var paving_materials: Dictionary = {}
	var nodes: Array[Node] = [world]
	nodes.append_array(world.find_children("*", "MeshInstance3D", true, false))
	for node: Node in nodes:
		if not node is MeshInstance3D:
			continue
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		for surface_index in mesh_node.mesh.get_surface_count():
			var source := mesh_node.get_active_material(surface_index) as BaseMaterial3D
			var family := source.resource_name.get_slice(".", 0) if source != null else ""
			if not CartoonTrial.expanded() and source != null: family = source.resource_name
			var cartoon_material := CartoonTrial.station_material(source, str(mesh_node.name))
			if cartoon_material != null:
				mesh_node.set_surface_override_material(surface_index, cartoon_material)
				continue
			if source != null and family in ["V2_concrete", "V2_reservoir_concrete", "V2_reservoir_paving"]:
				if not paving_materials.has(family):
					var paving := _service_surface("46536c", false)
					paving.set_shader_parameter("panel_size", Vector2(8.0, 12.0))
					paving_materials[family] = paving
				mesh_node.set_surface_override_material(surface_index, paving_materials[family])
				continue
			if source != null and family in ["V2_rock", "V2_rock_light", "V2_rock_dark"]:
				var stone := ShaderMaterial.new()
				stone.shader = ROCK_SHADER
				stone.set_shader_parameter("value", 0.26 if family == "V2_rock" else (0.30 if family == "V2_rock_light" else 0.20))
				stone.set_shader_parameter("broad_strata", CartoonTrial.expanded())
				mesh_node.set_surface_override_material(surface_index, stone)
				continue
			if source != null and family == "V2_reservoir_falling_water":
				var cascade := ShaderMaterial.new()
				cascade.shader = FALLING_WATER_SHADER
				mesh_node.set_surface_override_material(surface_index, cascade)
				continue
			if source != null and family == "V2_water":
				var water := ShaderMaterial.new()
				water.shader = WATER_SHADER
				water.set_shader_parameter("calm_groups", CartoonTrial.expanded())
				mesh_node.set_surface_override_material(surface_index, water)
				continue
			if source == null or not (family.begins_with("G1_") or family.begins_with("V2_atelier_") or family in ["V2_amber", "V2_cyan", "V2_dark", "V2_steel", "V2_trim", "V2_rail_alloy", "V2_rail_joint", "V2_rail_grate", "V2_rail_edge"]):
				continue
			var context := "district_finish" if CartoonTrial.expanded() and str(mesh_node.name).begins_with("district_") else ""
			var key := str(source.get_instance_id()) + context
			if not prepared.has(key):
				prepared[key] = PixelArtMaterials.adapt(source, context)
			# Set the instance override, never mutate a shared imported mesh/material.
			mesh_node.set_surface_override_material(surface_index, prepared[key])
	return prepared.size()

func _build_palette() -> void:
	_materials = {
		"deck": _material("28344d", 0.08),
		"steel": _material("536786", 0.12),
		"dark": _material("182236", 0.04),
		"cyan": _material("86deed", 0.08, "4ec8e3", 0.27),
		"gold": _material("ffd076", 0.08, "ffb954", 0.22),
		"rescue": _material("765b9a", 0.06),
		"rescue_cue": _material("c899ef", 0.04, "b187ed", 0.22),
		"hazard": _hazard_surface(),
		"contact": _service_surface("52617d", true),
		"deck_detail": _service_surface("36445e", false),
		"rescue_detail": _service_surface("69597f", false),
		"glass": _material("244659", 0.22, "1e6681", 0.13),
		"coral": _material("ed675e", 0.10),
	}
	if CartoonTrial.expanded():
		_materials.deck_detail = RouteFinish.surface(0, "3d5073", "91a9c6")
		_materials.rescue_detail = RouteFinish.surface(0, "695581", "b7a0d2")
		_materials.rail_cyan = RouteFinish.surface(1, "55b9d0", "b0ebf2")
		_materials.rail_gold = RouteFinish.surface(1, "e7a644", "ffe0a1")
		_materials.steel = RouteFinish.surface(2, "425576", "8ba2bf")
		_materials.hazard = RouteFinish.warning(0, Vector3.ONE)
		_materials.warning_plate = RouteFinish.warning(1, Vector3(3.5,.08,3.8))
		_materials.warning_sign = RouteFinish.warning(2, Vector3(2.6,1.8,.20))

func _hazard_surface() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HAZARD_SURFACE_SHADER
	return material

func _service_surface(color: String, industrial: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SERVICE_SURFACE_SHADER
	material.set_shader_parameter("base_color", Color(color))
	material.set_shader_parameter("industrial", industrial)
	material.set_shader_parameter("panel_size", Vector2(3.6, 5.4) if industrial else Vector2(2.2, 4.8))
	return material

func _material(color: String, metallic: float, emission_color: String = "000000", emission_energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.83
	material.metallic = metallic
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.emission_enabled = emission_energy > 0.0
	material.emission = Color(emission_color)
	material.emission_energy_multiplier = emission_energy
	return material

func _apply_track_materials(session: Node3D) -> void:
	var warning_finishes := {"cabinet":0, "approach":0, "sign":0}
	var presentation := session.get_node_or_null("ControllerLab/PresentationRoot")
	if presentation == null:
		push_error("Pixel Skyline V2: frozen PresentationRoot not found.")
		return
	for node: Node in presentation.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var label := str(node.name)
		var parent_name := str(node.get_parent().name)
		var is_rescue := parent_name.begins_with("rescue_")
		# Box obstacles keep their frozen silhouette and collision volume.
		# Runtime batch names carry numeric suffixes when several exist.
		if _is_frozen_obstacle(geometry, presentation):
			geometry.material_override = _materials.hazard
			warning_finishes.cabinet += 1
		if CartoonTrial.expanded():
			match RouteFinish.warning_role(geometry, presentation):
				1:
					geometry.material_override = _materials.warning_plate
					warning_finishes.approach += 1
				2:
					geometry.material_override = _materials.warning_sign
					warning_finishes.sign += 1
		match label:
			"Bed":
				geometry.material_override = _materials.rescue_detail if is_rescue else _materials.deck_detail
			"Rail":
				# Gold is a frozen single-lane/grind cue, cyan is the other rail family.
				geometry.material_override = _materials.gold if _is_gold_rail(geometry) else _materials.cyan
				if CartoonTrial.expanded():
					geometry.material_override = _materials.rail_gold if _is_gold_rail(geometry) else _materials.rail_cyan
			"Ties":
				geometry.material_override = _materials.dark
			"Clamps", "EdgeCurbs", "TrackPiers", "TunnelDecorFrames", "NearSpeedMarkers":
				geometry.material_override = _materials.steel
			"Pickets":
				geometry.material_override = _materials.rescue_cue if is_rescue else _materials.cyan
			"PulseArrows", "TunnelLamps", "CatchRunway", "CatchGate":
				geometry.material_override = _materials.cyan
			"ReleaseWindow", "GoldGrindCatch":
				geometry.material_override = _materials.gold
			"ContactStructure":
				geometry.material_override = _materials.contact
		# Warning red remains the obstacle identity. Advance plates and signs
		# have separate finishes; eject/receive cues and every mesh stay frozen.
	session.set_meta("warning_finishes", warning_finishes)

func _is_frozen_obstacle(node: GeometryInstance3D, presentation: Node) -> bool:
	# Godot renames repeated siblings, so use the exact frozen mesh/material
	# contract. Approach marks and signs have different primitive sizes.
	if not node is MultiMeshInstance3D or node.get_parent() != presentation:
		return false
	var batch := (node as MultiMeshInstance3D).multimesh
	if batch == null or not batch.mesh is BoxMesh or not (batch.mesh as BoxMesh).size.is_equal_approx(Vector3.ONE):
		return false
	var material := batch.mesh.surface_get_material(0) as BaseMaterial3D
	return material != null and (material.albedo_color.is_equal_approx(Color(1, 0.18, 0.11)) or material.albedo_color.is_equal_approx(Color(1, 0.22, 0.13)))

func _is_gold_rail(node: GeometryInstance3D) -> bool:
	if node is MultiMeshInstance3D:
		var batch := (node as MultiMeshInstance3D).multimesh
		if batch != null and batch.mesh != null and batch.mesh.get_surface_count() > 0:
			var material := batch.mesh.surface_get_material(0) as BaseMaterial3D
			if material != null:
				var color := material.albedo_color
				return color.r > 0.90 and color.g > 0.40 and color.b < 0.30
	return false

func _apply_train_materials(session: Node3D) -> void:
	var geometry := session.get_node_or_null("Actors/Train/VisualRoot/TrickPivot/Geometry")
	if geometry == null:
		push_error("Pixel Skyline V2: frozen train Geometry not found.")
		return
	var motorcar_path := WORLD_DIRECTORY + "train_motorcar.glb"
	if CartoonTrial.enabled():
		motorcar_path = WORLD_DIRECTORY + "cartoon_train.glb"
	if ResourceLoader.exists(motorcar_path, "PackedScene"):
		var packed := load(motorcar_path) as PackedScene
		var model := packed.instantiate() as Node3D if packed != null else null
		if model != null and model.transform.is_equal_approx(Transform3D.IDENTITY) and not _contains_collision(model):
			for child: Node in geometry.get_children():
				if child is MeshInstance3D:
					(child as MeshInstance3D).visible = false
			model.name = "PixelMotorcar"
			geometry.add_child(model)
			_prepare_imported_materials(model)
			_register_geometry(model, model, "station", "train_motorcar")
			if CartoonTrial.enabled():
				model.set_meta("source_kind", "authored_blender_geometry")
				model.set_meta("source_path", "art/source/pixel-skyline-v2/cartoon_atelier.blend")
			model.set_meta("decorative_only", true)
			return
		if model != null:
			model.free()
		push_error("Pixel V2 motorcar failed decorative identity/collision contract.")
	var livery := ShaderMaterial.new()
	livery.shader = TRAIN_SHADER
	for child: Node in geometry.get_children():
		if not child is MeshInstance3D:
			continue
		var node := child as MeshInstance3D
		var label := str(node.name)
		if label == "Body":
			node.material_override = livery
		elif label in ["FrontMarker", "RearWindow"] or label.contains("Window"):
			node.material_override = _materials.glass
		elif label.ends_with("Band"):
			node.material_override = _materials.cyan
		elif label == "RoofVent" or label.contains("Wheel"):
			node.material_override = _materials.dark

func _apply_environment(session: Node3D, root: Node3D) -> void:
	var world_environment := session.get_node_or_null("ControllerLab/EnvironmentRoot/WorldEnvironment") as WorldEnvironment
	if world_environment == null:
		push_error("Pixel Skyline V2: frozen WorldEnvironment not found.")
		return
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a0aed3")
	environment.ambient_light_energy = 0.44
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("8581ad")
	environment.fog_light_energy = 0.72
	environment.fog_density = 0.00017
	environment.fog_sky_affect = 0.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.32
	environment.glow_strength = 0.65
	environment.glow_hdr_threshold = 1.05
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for level in 7:
		environment.set_glow_level(level, 0.45 if level == 0 else (0.15 if level == 1 else 0.0))
	world_environment.environment = environment
	# These frozen structural supports remain visible/collidable; bring their
	# bright prototype material into the same steel family as the authored kit.
	var vertical_frame := session.get_node_or_null("ControllerLab/EnvironmentRoot/VerticalStationFrame") as GeometryInstance3D
	if vertical_frame != null:
		vertical_frame.material_override = _materials.steel
	var sun := session.get_node_or_null("ControllerLab/EnvironmentRoot/Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-24.0, -34.0, 0.0)
		sun.light_color = Color("ffba91")
		sun.light_energy = 1.32
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 420.0
	var fill := DirectionalLight3D.new()
	fill.name = "DuskBounce"
	fill.rotation_degrees = Vector3(-48.0, 145.0, 0.0)
	fill.light_color = Color("a6bfed")
	fill.light_energy = 0.23
	fill.shadow_enabled = false
	root.add_child(fill)

func _hide_replaced_decorations(session: Node3D, world: Node3D) -> int:
	var count := 0
	var has_tunnel := world.find_child("power_tunnel*", true, false) != null
	var has_coaster := world.find_child("coaster*", true, false) != null
	var has_observatory := world.find_child("observatory*", true, false) != null
	var environment := session.get_node_or_null("ControllerLab/EnvironmentRoot")
	if environment != null:
		for child: Node in environment.get_children():
			if not child is GeometryInstance3D:
				continue
			var replace := str(child.name) in REPLACED_ENVIRONMENT_BATCHES
			if has_observatory and str(child.name) == "HubBridge":
				(child as GeometryInstance3D).material_override = _materials.steel
			if has_observatory and str(child.name) == "TerminalStation":
				replace = true
			if has_coaster and str(child.name) in ["CoilStation", "LoopRibs"]:
				replace = true
			# The initial unlabelled broad plane is uniquely identified by its source
			# mesh and exact extent, not by a broad wildcard over EnvironmentRoot.
			if child is MeshInstance3D:
				var mesh := (child as MeshInstance3D).mesh
				if mesh is PlaneMesh and (mesh as PlaneMesh).size == Vector2(7000.0, 6000.0):
					replace = true
			if replace:
				(child as GeometryInstance3D).visible = false
				count += 1
	var presentation := session.get_node_or_null("ControllerLab/PresentationRoot")
	if presentation != null:
		for chunk: Node in presentation.get_children():
			var in_sample := false
			for prefix: String in SAMPLE_TRACK_PREFIXES:
				in_sample = in_sample or str(chunk.name).begins_with(prefix)
			if not in_sample:
				continue
			# The complete authored tunnel replaces only the old rendered shell.
			# Frozen StaticBody/shape nodes and all gameplay cues remain untouched.
			if (has_tunnel and str(chunk.name).begins_with("tunnel_")) or (has_observatory and str(chunk.name).begins_with("underpass_")):
				for part: String in ["ContactStructure", "TunnelDecorFrames"]:
					var shell := chunk.get_node_or_null(part) as GeometryInstance3D
					if shell != null:
						shell.visible = false
						count += 1
			var masses := chunk.get_node_or_null("NearMasses") as GeometryInstance3D
			if masses != null:
				masses.visible = false
				count += 1
	return count

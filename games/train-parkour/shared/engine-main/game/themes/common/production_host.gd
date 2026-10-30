extends Node
## Runtime-only presentation host. Never changes the frozen gameplay scripts.
var camera_profile := "comparison"
var pixel_scale := 0
var resource_root := "res://../"
var session: SpatialSession
var presentation: Node3D
var world_viewport: Viewport
var theme: Dictionary
var baseline_geometry: Dictionary = {}
var generated_geometry: Array[GeometryInstance3D] = []
var baseline_camera: Dictionary = {}
var builder: RefCounted

func resource_path(path: String) -> String:
	if path.begins_with("game/"): return "res://" + path.trim_prefix("game/")
	return resource_root + path

func create(description: Dictionary, build_visuals := true) -> Dictionary:
	theme = description
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	process_physics_priority = 1000
	get_window().content_scale_size = Vector2i(1440, 810)
	world_viewport = get_viewport()
	var render: Dictionary = theme.get("render_profile", {"mode": "native"})
	if render.get("mode", "native") == "pixel":
		var container = SubViewportContainer.new()
		container.name = "PixelDisplay"
		container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.stretch = true
		container.stretch_shrink = pixel_scale if pixel_scale > 0 else int(render.get("divisor", 3))
		add_child(container)
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var viewport = SubViewport.new()
		viewport.name = "WorldViewport"
		viewport.own_world_3d = true
		viewport.handle_input_locally = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		viewport.use_taa = false
		container.add_child(viewport)
		world_viewport = viewport
	session = load(resource_path(theme.application_scene)).instantiate()
	world_viewport.add_child(session) if world_viewport != get_viewport() else add_child(session)
	# Reparent only after _ready caches HUD; frozen scripts never resolve its path again.
	if world_viewport != get_viewport():
		session.get_node("HUD").reparent(self)
		session.hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	baseline_camera = camera_values()
	for node in session.find_children("*", "GeometryInstance3D", true, false): baseline_geometry[node.get_instance_id()] = {"path": str(session.get_path_to(node)), "visible": node.is_visible_in_tree()}
	if build_visuals:
		build_presentation()
		apply_camera_profile()
	return {"session": session, "presentation": presentation, "world_viewport": world_viewport}

func build_presentation() -> Node3D:
	if theme.has("presentation_script"):
		builder = load(resource_path(theme.presentation_script)).new()
		presentation = builder.build(session)
		assert(presentation != null and session.is_ancestor_of(presentation), "Presentation must be attached under session")
	else:
		presentation = Node3D.new()
		presentation.name = "ThemeWorld"
		session.add_child(presentation)
	refresh_geometry()
	return presentation

func refresh_geometry() -> void:
	generated_geometry.clear()
	for node in session.find_children("*", "GeometryInstance3D", true, false):
		if not baseline_geometry.has(node.get_instance_id()): generated_geometry.append(node)

func registration(node: Node) -> Dictionary:
	var result = {}
	var current = node
	while current != null and current != session:
		for key in ["instance_id", "asset_id", "scene_id"]:
			if not result.has(key) and current.has_meta(key): result[key] = current.get_meta(key)
		current = current.get_parent()
	return result

func invalid_geometry() -> Array:
	refresh_geometry()
	var invalid = []
	for node in generated_geometry:
		var info = registration(node)
		if info.size() != 3 or not info.values().all(func(value): return value is String and not value.is_empty()) or not node.global_transform.is_finite(): invalid.append(str(session.get_path_to(node)))
	return invalid

func camera_values() -> Dictionary:
	var camera = session.camera
	return {"fov": camera.fov, "h_offset": camera.h_offset, "v_offset": camera.v_offset,
		"projection": camera.projection, "near": camera.near, "keep_aspect": camera.keep_aspect}

func selected_camera() -> Dictionary:
	return theme.get("camera_profiles", {}).get(camera_profile, {}) if camera_profile == "play" else {}

func apply_camera_profile() -> void:
	if session == null: return
	for field in selected_camera(): session.camera.set(field, selected_camera()[field])

func camera_profile_valid() -> bool:
	var camera = session.camera
	if world_viewport.get_camera_3d() != camera or session.train.get_viewport() != world_viewport: return false
	if camera.projection != baseline_camera.projection or camera.near != baseline_camera.near or camera.keep_aspect != baseline_camera.keep_aspect: return false
	for field in selected_camera():
		if not is_equal_approx(float(camera.get(field)), float(selected_camera()[field])): return false
	return true

func _process(_delta: float) -> void:
	apply_camera_profile()

func _physics_process(_delta: float) -> void:
	apply_camera_profile()

func replacements() -> Array:
	var result = []
	for node in session.find_children("*", "GeometryInstance3D", true, false):
		var prior: Dictionary = baseline_geometry.get(node.get_instance_id(), {})
		if prior.get("visible", false) and not node.is_visible_in_tree():
			result.append({"id": "baseline:" + prior.path, "action": "hidden", "path": prior.path})
	return result

func evidence() -> Dictionary:
	var render: Dictionary = theme.get("render_profile", {"mode": "native"}).duplicate()
	if render.get("mode") == "pixel" and pixel_scale > 0: render["divisor"] = pixel_scale
	return {"visual_replacements": replacements(), "camera_profile": camera_profile, "camera_settings": selected_camera(),
		"render_profile": render,
		"internal_resolution": [world_viewport.get_visible_rect().size.x, world_viewport.get_visible_rect().size.y],
		"camera_matches_input_viewport": world_viewport.get_camera_3d() == session.camera,
		"hud_resolution": [session.hud.size.x, session.hud.size.y]}

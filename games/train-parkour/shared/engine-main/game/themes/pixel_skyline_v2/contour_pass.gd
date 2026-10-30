extends RefCounted
## Decorative camera child; never changes camera properties or gameplay meshes.
const SHADER = preload("res://themes/pixel_skyline_v2/shaders/contour.gdshader")
const MODES := ["off", "contour", "contact", "bold"]

static func attach(camera: Camera3D) -> MeshInstance3D:
	var overlay := MeshInstance3D.new()
	overlay.name = "PixelContour"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	overlay.mesh = quad
	overlay.position.z = -1.0
	overlay.extra_cull_margin = 16.0
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.set_meta("scene_id", "station")
	overlay.set_meta("asset_id", "pixel_contour_overlay")
	overlay.set_meta("instance_id", "pixel_v2/contour")
	overlay.set_meta("decorative_only", true)
	overlay.set_meta("screen_space_effect", true)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = 127
	overlay.material_override = material
	camera.add_child(overlay)
	var mode := str(ProjectSettings.get_setting("showcase/art_ink", "off"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--art-ink="):
			mode = arg.trim_prefix("--art-ink=")
	set_mode(overlay, mode)
	return overlay

static func set_mode(overlay: MeshInstance3D, mode: String) -> void:
	if not mode in MODES:
		push_error("Unknown art-ink mode: " + mode)
		mode = "off"
	overlay.visible = mode != "off"
	overlay.set_meta("ink_mode", mode)
	var material := overlay.material_override as ShaderMaterial
	var bold := mode == "bold"
	material.set_shader_parameter("contact_strength", 0.70 if mode == "contact" else 0.0)
	material.set_shader_parameter("contour_width", 2 if bold else 1)
	material.set_shader_parameter("contour_strength", 0.96 if bold else 0.86)
	material.set_shader_parameter("crease_strength", 0.16 if bold else 0.23)
	material.set_shader_parameter("ink_color", Color("080d19") if bold else Color(0.060, 0.078, 0.140))

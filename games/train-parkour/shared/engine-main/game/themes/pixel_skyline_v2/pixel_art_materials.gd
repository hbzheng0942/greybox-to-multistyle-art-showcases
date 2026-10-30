extends RefCounted
## Shared art material adapter. Source resources and mesh/UV geometry are immutable.
## Textured palettes are opt-in by G1 semantic name; authored colours use mode 3.

const ASSET_SHADER = preload("res://themes/pixel_skyline_v2/shaders/atelier_asset.gdshader")
static var _shader_variants: Dictionary = {}

static func adapt(source: BaseMaterial3D, semantic_id: String = "") -> ShaderMaterial:
	if source == null:
		return null
	var identity := (semantic_id + " " + source.resource_name).to_lower()
	var material := ShaderMaterial.new()
	material.shader = _shader_for(source)
	material.resource_name = "Atelier_" + source.resource_name
	material.render_priority = source.render_priority
	material.next_pass = source.next_pass
	var train := identity.contains("train") or identity.contains("motorcar")
	var rock := identity.contains("basalt") or identity.contains("rock") or identity.contains("mountain_city")
	var authored := identity.contains("v2_atelier_") or source.albedo_texture == null
	var expanded := "--art-shape=continuous" in OS.get_cmdline_user_args()
	var cartoon := identity.contains("cartoon") or (expanded and not authored and _has_window_carrier(identity))
	var mode := 3 if authored else (1 if train else (2 if rock else 0))
	material.set_shader_parameter("palette_mode", mode)
	material.set_shader_parameter("train_window_accent", identity.contains("train_motorcar"))
	material.set_shader_parameter("palette_strength", 1.0 if authored or train else 0.90)
	material.set_shader_parameter("ambient_floor", 0.60 if train else 0.40)
	material.set_shader_parameter("direct_strength", 0.76 if train else 0.80)
	material.set_shader_parameter("albedo_tint", source.albedo_color)
	material.set_shader_parameter("uv_scale", source.uv1_scale)
	material.set_shader_parameter("uv_offset", source.uv1_offset)
	material.set_shader_parameter("uv2_scale", source.uv2_scale)
	material.set_shader_parameter("uv2_offset", source.uv2_offset)
	material.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
	material.set_shader_parameter("vertex_color_is_srgb", source.vertex_color_is_srgb)
	material.set_shader_parameter("double_sided", source.cull_mode == BaseMaterial3D.CULL_DISABLED)
	material.set_shader_parameter("source_alpha_mode", source.transparency)
	material.set_shader_parameter("source_alpha_scissor", source.alpha_scissor_threshold)
	material.set_shader_parameter("source_alpha_hash_scale", source.alpha_hash_scale)
	if source.albedo_texture != null:
		material.set_shader_parameter("has_albedo_texture", true)
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		# Keep rectangular atlas proportions. One sample per 4-8 source texels
		# clusters generated detail without erasing windows or train paint boundaries.
		var atlas := Vector2(source.albedo_texture.get_width(), source.albedo_texture.get_height())
		var longest := maxf(atlas.x, atlas.y)
		var max_cells := 384.0 if train else 512.0
		material.set_shader_parameter("texture_cells", atlas * minf(1.0, max_cells / maxf(longest, 1.0)))
	if source.normal_enabled and source.normal_texture != null:
		material.set_shader_parameter("has_normal_texture", true)
		material.set_shader_parameter("normal_texture", source.normal_texture)
		material.set_shader_parameter("normal_strength", clampf(source.normal_scale * 0.18, 0.0, 0.25))
	if source.emission_enabled:
		material.set_shader_parameter("authored_emission", source.emission)
		material.set_shader_parameter("authored_emission_energy", source.emission_energy_multiplier)
		material.set_shader_parameter("emission_add", source.emission_operator == BaseMaterial3D.EMISSION_OP_ADD)
		material.set_shader_parameter("emission_on_uv2", source.emission_on_uv2)
		if source.emission_texture != null:
			material.set_shader_parameter("has_emission_texture", true)
			material.set_shader_parameter("emission_texture", source.emission_texture)
	if not train and not authored and _has_window_carrier(identity):
		material.set_shader_parameter("window_emission", 1.10)
	# Keep added casing accents subordinate to frozen gameplay rails.
	if identity.contains("atelier_rail_cyan"):
		material.set_shader_parameter("albedo_tint", Color("298ba4"))
		material.set_shader_parameter("authored_emission", Color("298ba4"))
		material.set_shader_parameter("authored_emission_energy", 0.16)
	if identity.contains("atelier_lamp_core") or identity.contains("atelier_tunnel_amber_core"):
		material.set_shader_parameter("albedo_tint", Color("ffd79b"))
		material.set_shader_parameter("authored_emission", Color("ffc35e"))
		material.set_shader_parameter("authored_emission_energy", 0.85)
	if identity.contains("atelier_amber") or identity.contains("atelier_tunnel_amber"):
		if not identity.contains("core"):
			material.set_shader_parameter("albedo_tint", Color("f28b32"))
			material.set_shader_parameter("authored_emission", Color("ff932e"))
			material.set_shader_parameter("authored_emission_energy", 0.75)
	if identity.contains("atelier_tunnel_warm_edge") or identity.contains("atelier_warm_side"):
		material.set_shader_parameter("albedo_tint", Color("c47838"))
		material.set_shader_parameter("authored_emission", Color("e29140"))
		material.set_shader_parameter("authored_emission_energy", 0.18)
	if identity.ends_with("v2_atelier_tunnel_panel") or identity.ends_with("v2_atelier_tunnel_panel_lit"):
		material.set_shader_parameter("surface_detail_role", 1)
	if identity.ends_with("v2_atelier_district_stone"):
		material.set_shader_parameter("surface_detail_role", 4)
	if identity.contains("atelier_tunnel_"):
		if identity.ends_with("void") or identity.ends_with("backing"):
			material.set_shader_parameter("ambient_floor", 0.22)
		elif identity.ends_with("panel") or identity.ends_with("floor"):
			material.set_shader_parameter("ambient_floor", 0.32)
	if expanded and authored and identity.contains("atelier_district_stone"):
		material.set_shader_parameter("albedo_tint", Color("354b78"))
		material.set_shader_parameter("surface_detail_role", 0)
	if expanded and identity.contains("district_finish"):
		# Floor belts carry the facade hierarchy; window trim stays subordinate.
		var colors := {"V2_atelier_slate":"435a83", "V2_atelier_edge":"7692b5",
			"V2_atelier_masonry":"56688b", "V2_atelier_metal":"233650",
			"V2_atelier_recess":"111e36", "V2_atelier_finish_darkglass":"234560",
			"V2_atelier_finish_window":"f5b659", "V2_atelier_finish_glint":"ffe5a3"}
		var family := source.resource_name.get_slice(".",0)
		if colors.has(family): material.set_shader_parameter("albedo_tint", Color(colors[family]))
		if family in ["V2_atelier_finish_window", "V2_atelier_finish_glint"]:
			material.set_shader_parameter("authored_emission", Color("ffc15f"))
			material.set_shader_parameter("authored_emission_energy", .58 if family.ends_with("window") else .85)
	if expanded and not authored:
		material.set_shader_parameter("has_normal_texture", false)
	if cartoon:
		# The new G1 input already carries the art palette. Keep those authored
		# groups, suppress normal-map grain and use larger painted clusters.
		material.set_shader_parameter("palette_mode", 3 if authored else 4)
		material.set_shader_parameter("snap_planar_normals", not authored)
		material.set_shader_parameter("has_normal_texture", false)
		material.set_shader_parameter("train_window_accent", false)
		material.set_shader_parameter("ambient_floor", 0.48 if train else 0.34)
		material.set_shader_parameter("direct_strength", 0.85)
		if source.albedo_texture != null:
			var atlas := Vector2(source.albedo_texture.get_width(), source.albedo_texture.get_height())
			material.set_shader_parameter("texture_cells", atlas * minf(1.0, 384.0 / maxf(atlas.x, atlas.y)))
			material.set_shader_parameter("window_emission", 0.65)
			material.set_shader_parameter("ink", Color("101c38"))
			material.set_shader_parameter("shadow", Color("253b67"))
			material.set_shader_parameter("middle", Color("46679c"))
			material.set_shader_parameter("face", Color("809dd1"))
			material.set_shader_parameter("edge", Color("abc3eb"))
	return material

static func solid(color: Color, role: String = "steel", emission: Color = Color.BLACK, energy: float = 0.0) -> ShaderMaterial:
	var source := StandardMaterial3D.new()
	source.resource_name = "V2_atelier_" + role
	source.albedo_color = color
	if energy > 0.0:
		source.emission_enabled = true
		source.emission = emission
		source.emission_energy_multiplier = energy
	return adapt(source, role)

static func _has_window_carrier(identity: String) -> bool:
	# Never infer glowing paint on machinery, pylons, rail furnishings or rock.
	for carrier in ["observatory", "powerhouse", "mountain_city", "skybridge", "skyline_tower", "hydro_service_house", "waterfront_service_quarter"]:
		if identity.contains(carrier):
			return true
	return false

static func _shader_for(source: BaseMaterial3D) -> Shader:
	var key := "%d:%d:%d:%d:%d" % [source.cull_mode, source.transparency, source.blend_mode, source.depth_draw_mode, int(source.texture_repeat)]
	if _shader_variants.has(key):
		return _shader_variants[key]
	var code := ASSET_SHADER.code
	var cull := "cull_back"
	if source.cull_mode == BaseMaterial3D.CULL_DISABLED:
		cull = "cull_disabled"
	elif source.cull_mode == BaseMaterial3D.CULL_FRONT:
		cull = "cull_front"
	code = code.replace("render_mode cull_back", "render_mode " + cull)
	var extra_modes := ""
	if source.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		extra_modes += ", blend_add"
	elif source.blend_mode == BaseMaterial3D.BLEND_MODE_SUB:
		extra_modes += ", blend_sub"
	elif source.blend_mode == BaseMaterial3D.BLEND_MODE_MUL:
		extra_modes += ", blend_mul"
	if source.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS:
		extra_modes += ", depth_draw_always"
	elif source.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED:
		extra_modes += ", depth_draw_never"
	var alpha := ""
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		# Continuous alpha sampling preserves foliage/window silhouettes instead of
		# moving the cutout boundary onto the coarse painted-colour UV cells.
		alpha = "float coverage = albedo_tint.a;\n    if (has_albedo_texture) { coverage *= textureGrad(albedo_texture, source_uv, dx, dy).a; }\n    if (use_vertex_color) { coverage *= COLOR.a; }\n    ALPHA = coverage;"
		if source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			alpha += "\n    ALPHA_SCISSOR_THRESHOLD = source_alpha_scissor;"
		elif source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH:
			alpha += "\n    ALPHA_HASH_SCALE = source_alpha_hash_scale;"
		elif source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			extra_modes += ", depth_prepass_alpha"
	code = code.replace("ambient_light_disabled;", "ambient_light_disabled" + extra_modes + ";")
	code = code.replace("// ATELIER_ALPHA_BODY", alpha)
	if not source.texture_repeat:
		code = code.replace("repeat_enable", "repeat_disable")
	var variant := Shader.new()
	variant.code = code
	_shader_variants[key] = variant
	return variant

extends RefCounted
## Narrow opaque UV0 paper adapter. Unsupported contributions retain imported material.
var shader: Shader
var parity_linear_shader: Shader
func _init() -> void:
	var path := OS.get_environment("PAPER_MATERIAL_SHADER")
	shader = load(path if not path.is_empty() else "res://themes/paper_atlas/textured_paper.gdshader")
func unsupported(source: Material) -> Array:
	var reasons := []
	if not source is StandardMaterial3D: return ["non_standard_material"]
	var s := source as StandardMaterial3D
	if s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: reasons.append("alpha")
	if s.cull_mode != BaseMaterial3D.CULL_BACK: reasons.append("cull")
	if s.uv1_scale != Vector3.ONE or s.uv1_offset != Vector3.ZERO or s.uv1_triplanar: reasons.append("uv_transform")
	if s.vertex_color_use_as_albedo: reasons.append("vertex_colour")
	if s.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and s.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC: reasons.append("sampler_filter")
	if not s.texture_repeat: reasons.append("sampler_repeat")
	if s.ao_enabled and s.ao_texture != null: reasons.append("ao")
	if s.emission_enabled and (s.emission_texture != null or s.emission.get_luminance() > 0.00001): reasons.append("emission")
	if s.normal_enabled and s.normal_texture != null: reasons.append("normal")
	if s.heightmap_enabled or s.clearcoat_enabled or s.anisotropy_enabled or s.subsurf_scatter_enabled or s.rim_enabled or s.backlight_enabled or s.detail_enabled: reasons.append("advanced_material_feature")
	if s.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL: reasons.append("shading_mode")
	return reasons
func channel(index: int) -> Vector4:
	if index==0: return Vector4(1,0,0,0)
	if index==1: return Vector4(0,1,0,0)
	if index==2: return Vector4(0,0,1,0)
	if index==3: return Vector4(0,0,0,1)
	return Vector4(0.3333333,0.3333333,0.3333333,0)
func convert(source: Material, paper_amount: float=1.0) -> Material:
	if not unsupported(source).is_empty(): return source
	var s := source as StandardMaterial3D
	var m := ShaderMaterial.new()
	m.shader = shader
	# Preserve imported sampler semantics in calibration; R8 paper finish keeps anisotropic filtering.
	if paper_amount == 0.0 and s.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		if parity_linear_shader == null:
			parity_linear_shader = Shader.new()
			parity_linear_shader.code = shader.code.replace("filter_linear_mipmap_anisotropic", "filter_linear_mipmap")
		m.shader = parity_linear_shader
	m.set_shader_parameter("tint",s.albedo_color)
	m.set_shader_parameter("has_albedo",s.albedo_texture != null)
	m.set_shader_parameter("source_albedo",s.albedo_texture)
	m.set_shader_parameter("source_roughness",s.roughness)
	m.set_shader_parameter("source_metallic",s.metallic)
	m.set_shader_parameter("source_specular",s.metallic_specular)
	m.set_shader_parameter("has_roughness",s.roughness_texture != null)
	m.set_shader_parameter("has_metallic",s.metallic_texture != null)
	m.set_shader_parameter("roughness_map",s.roughness_texture)
	m.set_shader_parameter("metallic_map",s.metallic_texture)
	m.set_shader_parameter("roughness_channel",channel(s.roughness_texture_channel))
	m.set_shader_parameter("metallic_channel",channel(s.metallic_texture_channel))
	m.set_shader_parameter("paper_amount",paper_amount)
	return m
func audit(source: Material) -> Dictionary:
	var result := {"unsupported":unsupported(source),"class":source.get_class()}
	if source is StandardMaterial3D:
		result.merge({"roughness":source.roughness,"metallic":source.metallic,"roughness_channel":source.roughness_texture_channel,"metallic_channel":source.metallic_texture_channel,"has_albedo":source.albedo_texture!=null,"has_roughness":source.roughness_texture!=null,"has_metallic":source.metallic_texture!=null,"cull":source.cull_mode,"texture_filter":source.texture_filter,"tint":[source.albedo_color.r,source.albedo_color.g,source.albedo_color.b,source.albedo_color.a]})
	return result

extends RefCounted
## A01 material layers, Compatibility / StandardMaterial3D only.
## Canonical GLBs and source textures are immutable. Runtime overrides remain
## StandardMaterial3D so the existing player/held-object alpha fallback works.
const TEXTURES = preload("res://styles/A01/runtime/modules/8ae8b471957da1a2-surface_texture_source.gd")
const REVISION := "satin-cloth-materials-03"
# These are the complete first-native tuning controls (not hidden exposure).
var parameters: Dictionary = {
	"navy": Color("4b5b74"), "cream": Color("dccbad"),
	"canvas": {"patch_m":.32,"rough_min":.60,"rough_max":.76,"specular":.46,"normal":1.0},
	"wall": {"patch_m":.32,"rough_min":.48,"rough_max":.66,"specular":.50,"normal":1.1},
	"coated": {"patch_m":.40,"rough_min":.26,"rough_max":.40,"specular":.60,"normal":.75},
	"floor": {"patch_m":1.8,"rough_min":.28,"rough_max":.42,"specular":.65,"normal":1.0,"tint":Color(.96,.94,.96)},
	"mammoth_canvas": {"rough_min":.80,"rough_max":.94,"specular":.22,"detail":.22,"tint":Color(.96,.97,1.0)},
	"character_fabric": {"rough_min":.74,"rough_max":.91,"specular":.24,"detail":.16,"tint":Color(1,1,1)},
	"sewn_short_pile": {"rough_min":.83,"rough_max":.97,"specular":.20,"detail":.12,"tint":Color(1,1,1)},
	"soft_collectible": {"rough_min":.73,"rough_max":.91,"specular":.24,"detail":.15,"tint":Color(1,1,1)},
	"ceramic_glaze": {"rough_min":.24,"rough_max":.42,"specular":.48,"detail":0.0,"tint":Color(1,1,1)},
	"mineral": {"rough_min":.64,"rough_max":.88,"specular":.28,"detail":0.0,"tint":Color(1,1,1)},
	"ivory_exhibit": {"rough_min":.68,"rough_max":.86,"specular":.30,"detail":.08,"tint":Color(1,1,1)}
}
var _materials: Dictionary = {}
var _instance_materials: Dictionary = {}
var _range_cache: Dictionary = {}

func material(color: Color, fabric: bool = true) -> StandardMaterial3D:
	var coated := fabric and color.r > color.b*1.8 and color.r > color.g*1.25
	return _authored(color, "coated" if coated else ("canvas" if fabric else "solid"))

func floor_material(color: Color) -> StandardMaterial3D:
	return _authored(color,"floor")

func wall_material(color: Color) -> StandardMaterial3D:
	return _authored(color,"wall")

func parameter_report() -> Dictionary:
	return {"revision":REVISION,"parameters":parameters.duplicate(true),"texture_size":256,"authored_mapping":"world triplanar; physical texture patch in metres","import_detail_mapping":"original UV1; no UV/tangent replacement","import_roughness":"bounded 256px data-only remap, original reference retained in material metadata","source_assets_immutable":true}

func _authored(color: Color, family: String) -> StandardMaterial3D:
	var key := family+":"+color.to_html(true)
	if _materials.has(key):return _materials[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "A01_"+family
	m.albedo_color = _palette_color(color) if family in ["canvas","wall"] else color
	if family=="floor":m.albedo_color*=parameters.floor.tint
	m.metallic = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if family == "solid":
		m.roughness = .59
		m.metallic_specular = .30
	else:
		var p: Dictionary = parameters[family]
		var texture_family := "canvas" if family in ["canvas","wall"] else family
		var maps: Dictionary = TEXTURES.maps(texture_family,float(p.patch_m))
		m.albedo_texture = maps.albedo
		m.normal_enabled = true
		m.normal_texture = maps.normal
		m.normal_scale = float(p.normal)
		m.roughness = 1.0
		m.roughness_texture = _range_texture(maps.roughness,BaseMaterial3D.TEXTURE_CHANNEL_RED,float(p.rough_min),float(p.rough_max),1.0)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.metallic_specular = float(p.specular)
		# Authored architecture is static. World scale prevents every enlarged
		# soft primitive from enlarging the fabric grain into woodgrain blocks.
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / float(p.patch_m)
	_materials[key] = m
	return m

func _palette_color(c: Color) -> Color:
	# Semantic palette calibration, not a global light/exposure compensation.
	if c.r < .32 and c.b > .15 and c.b > c.r*1.4:
		var navy: Color = parameters.navy
		return Color(navy.r,navy.g,navy.b,c.a)
	if absf(c.r-Color("e5d7b6").r)<.06 and absf(c.g-Color("e5d7b6").g)<.06 and absf(c.b-Color("e5d7b6").b)<.06:
		var cream: Color = parameters.cream
		return Color(cream.r,cream.g,cream.b,c.a)
	return c

func _import_family(id: String) -> String:
	if id.begins_with("mammoth_"):return "mammoth_canvas"
	if id=="dog_player" or id.begins_with("visitor_"):return "character_fabric"
	if id.begins_with("specimen_") or id=="wall_specimen_head":return "sewn_short_pile"
	if id in ["prop_specimen","prop_souvenir"]:return "soft_collectible"
	if id.begins_with("prop_vase") or id=="prop_plate":return "ceramic_glaze"
	if id.begins_with("prop_rock") or id=="prop_bust":return "mineral"
	if id=="prop_bone":return "ivory_exhibit"
	return ""

func apply_imported(root: Node3D, asset_id: String) -> Dictionary:
	var family := _import_family(asset_id)
	var result := {"revision":REVISION,"asset_id":asset_id,"family":family,"surfaces":0,"materials_created":0,"cache_hits":0,"unsupported_materials":0,"detail_existing_preserved":0,"source_albedo_normal_preserved":true,"source_texture_bytes_unchanged":true,"mesh_uv_tangents_unchanged":true,"roughness_runtime_remapped":true,"source_roughness_reference_retained":true}
	if root==null or family.is_empty():
		result.status = "skipped"
		return result
	var root_id := root.get_instance_id()
	if not _instance_materials.has(root_id):_instance_materials[root_id]={}
	var profile: Dictionary = parameters[family]
	result["roughness_range"] = [profile.rough_min,profile.rough_max]
	_apply_node(root,family,profile,_instance_materials[root_id],result)
	result.status = "applied" if result.unsupported_materials==0 else "partial_unsupported_material"
	return result

func _apply_node(node: Node, family: String, p: Dictionary, cache: Dictionary, report: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		for surface in range(node.mesh.get_surface_count()):
			var source: Material = node.get_active_material(surface)
			if not source is StandardMaterial3D:
				report.unsupported_materials+=1
				continue
			if source.get_meta("a01_palette_revision","")==REVISION and source.get_meta("a01_palette_family","")==family:
				report.cache_hits+=1
				report.surfaces+=1
				continue
			var key := str(source.get_instance_id())+":"+family
			var adjusted: StandardMaterial3D
			if cache.has(key):
				adjusted=cache[key]
				report.cache_hits+=1
			else:
				adjusted=source.duplicate(false) as StandardMaterial3D
				adjusted.metallic=0.0
				adjusted.roughness=1.0
				adjusted.roughness_texture=_range_texture(source.roughness_texture,source.roughness_texture_channel,float(p.rough_min),float(p.rough_max),source.roughness)
				adjusted.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
				adjusted.set_meta("a01_original_roughness_texture",source.roughness_texture)
				adjusted.metallic_specular=float(p.specular)
				adjusted.albedo_color=source.albedo_color*(p.tint as Color)
				adjusted.clearcoat_enabled=false
				adjusted.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				adjusted.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
				if float(p.detail)>0.0 and not source.detail_enabled:
					var detail: Dictionary=TEXTURES.detail(family,float(p.detail))
					adjusted.detail_enabled=true
					adjusted.detail_uv_layer=BaseMaterial3D.DETAIL_UV_1
					adjusted.detail_blend_mode=BaseMaterial3D.BLEND_MODE_MUL
					adjusted.detail_albedo=detail.albedo
					adjusted.detail_normal=source.normal_texture if source.normal_texture!=null else TEXTURES.neutral_normal()
					# Same original UV1 normal in both inputs: no second tiled
					# normal carrier across an atlas of unrelated surface charts.
					# Original UV1/normal basis is preserved. UV2 triplanar would
					# overwrite imported tangents in the engine's standard shader.
				elif source.detail_enabled:
					report.detail_existing_preserved+=1
				adjusted.set_meta("a01_palette_family",family)
				adjusted.set_meta("a01_palette_revision",REVISION)
				adjusted.set_meta("a01_source_material_id",source.get_instance_id())
				cache[key]=adjusted
				report.materials_created+=1
			if node.material_override!=null:node.material_override=adjusted
			else:node.set_surface_override_material(surface,adjusted)
			report.surfaces+=1
	for child in node.get_children():_apply_node(child,family,p,cache,report)

func _range_texture(source: Texture2D, channel: int, lower: float, upper: float, factor: float) -> Texture2D:
	var key := str(source.get_instance_id() if source!=null else 0)+":"+str(channel)+":"+str(lower)+":"+str(upper)+":"+str(factor)
	if _range_cache.has(key):return _range_cache[key]
	var im: Image = source.get_image() if source!=null else null
	if im!=null and im.is_compressed():
		if im.decompress()!=OK:im=null
	if im!=null and not im.is_empty():im.resize(mini(im.get_width(),256),mini(im.get_height(),256),Image.INTERPOLATE_LANCZOS)
	else:
		im=Image.create(1,1,false,Image.FORMAT_RGBA8)
		im.fill(Color(.65,.65,.65,.65))
	var out := Image.create(im.get_width(),im.get_height(),false,Image.FORMAT_R8)
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c:=im.get_pixel(x,y)
			var value:=c.r
			match channel:
				BaseMaterial3D.TEXTURE_CHANNEL_GREEN:value=c.g
				BaseMaterial3D.TEXTURE_CHANNEL_BLUE:value=c.b
				BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:value=c.a
				BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:value=(c.r+c.g+c.b)/3.0
			value=lerpf(lower,upper,clampf(value*factor,0.0,1.0))
			out.set_pixel(x,y,Color(value,value,value))
	out.generate_mipmaps()
	var texture:=ImageTexture.create_from_image(out)
	_range_cache[key]=texture
	return texture

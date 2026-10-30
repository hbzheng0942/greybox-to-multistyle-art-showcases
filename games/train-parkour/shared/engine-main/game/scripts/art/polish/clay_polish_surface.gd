extends "res://scripts/art/refinement/clay_surface.gd"
const PALETTE={"cream":"eccb9e","peach":"ec865f","teal":"398c87","lavender":"a892c5","dark":"244262","orange":"f18847","floor":"9982af","rail":"b6a6ce","sleeper":"725c88","red":"d94b38","gold":"d6a352","sage":"729966"}
func _init() -> void:
 shader=preload("res://materials/clay-polish/handmade.gdshader")
func material(key: String,color: String="",glow: float=0.0,tile: bool=false) -> ShaderMaterial:
 var resolved: String=str(PALETTE.get(key,"")) if color.is_empty() else color
 var result:=super.material(key,resolved,glow,tile)
 result.set_shader_parameter("stone",key=="lavender")
 result.set_shader_parameter("relief",.044 if key=="lavender" else .016 if not tile else .010)
 var glaze:=key in ["teal","orange","red","rail","gold"]
 result.set_shader_parameter("roughness_value",.40 if glaze else .79)
 result.set_shader_parameter("coat",.24 if glaze else 0.0)
 result.set_shader_parameter("metal",.60 if key=="gold" else .18 if key=="rail" else 0.0)
 return result
func converted(old: Material) -> Material:
 var result: Material=super.converted(old)
 if old is StandardMaterial3D and result is ShaderMaterial:
  var name: String=old.resource_name.to_lower()
  for pair in [["terracotta","peach"],["cream","cream"],["teal","teal"],["lavender","lavender"],["indigo","dark"],["safetyred","red"],["orangecabin","orange"],["ochre","gold"]]:
   if pair[0] in name:
    result.set_shader_parameter("clay_color",Color(PALETTE[pair[1]]))
  var glazed: bool="teal" in name or "orangecabin" in name or "glass" in name or "indigo" in name
  result.set_shader_parameter("roughness_value",.24 if "indigo" in name or "glass" in name else .38 if glazed else .77)
  result.set_shader_parameter("coat",.38 if glazed else 0.)
  result.set_shader_parameter("relief",.004 if glazed else .020)
  if "ochre" in name or "brass" in name:
   result.set_shader_parameter("metal",.68);result.set_shader_parameter("roughness_value",.32)
  if "globe" in name or "signal" in name:result.set_shader_parameter("emission_value",.6)
  if old.albedo_texture!=null:result.set_shader_parameter("relief",.006)
  # Preserve imported PBR data before applying the shared clay micro-surface.
  # Packed glTF roughness is G, metallic B; other imported channels are legal too.
  result.set_shader_parameter("source_uv_scale",Vector2(old.uv1_scale.x,old.uv1_scale.y))
  result.set_shader_parameter("source_uv_offset",Vector2(old.uv1_offset.x,old.uv1_offset.y))
  if old.albedo_texture!=null:
   result.set_shader_parameter("clay_color",old.albedo_color)
   result.set_shader_parameter("pigment_variation",.18)
  if old.roughness_texture!=null:
   result.set_shader_parameter("mapped_roughness",true)
   result.set_shader_parameter("roughness_map",old.roughness_texture)
   result.set_shader_parameter("roughness_channel",_channel(old.roughness_texture_channel))
   result.set_shader_parameter("roughness_value",old.roughness)
  if old.metallic_texture!=null:
   result.set_shader_parameter("mapped_metal",true)
   result.set_shader_parameter("metal_map",old.metallic_texture)
   result.set_shader_parameter("metal_channel",_channel(old.metallic_texture_channel))
   result.set_shader_parameter("metal",old.metallic)
  if old.normal_enabled and old.normal_texture!=null:
   result.set_shader_parameter("mapped_normal",true)
   result.set_shader_parameter("normal_map",old.normal_texture)
   result.set_shader_parameter("normal_strength",old.normal_scale)
  if old.ao_enabled and old.ao_texture!=null:
   result.set_shader_parameter("baked_contact",true);result.set_shader_parameter("contact_map",old.ao_texture)
   result.set_shader_parameter("contact_channel",_channel(old.ao_texture_channel))
   result.set_shader_parameter("contact_uv2",old.ao_on_uv2)

 return result

func _channel(channel: int) -> Vector4:
 var channels: Array[Vector4]=[Vector4(1,0,0,0),Vector4(0,1,0,0),Vector4(0,0,1,0),Vector4(0,0,0,1),Vector4(.333333,.333333,.333333,0)]
 return channels[clampi(channel,0,4)]

shader_type spatial;
render_mode diffuse_burley;
#include "res://themes/paper_atlas/paper_surface.gdshaderinc"
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D source_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo = false;
// Data textures remain linear; imported packed MR uses G roughness / B metalness.
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metallic_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_roughness = false;
uniform bool has_metallic = false;
uniform vec4 roughness_channel = vec4(0,1,0,0);
uniform vec4 metallic_channel = vec4(0,0,1,0);
uniform float source_roughness = 1.0;
uniform float source_metallic = 0.0;
uniform float source_specular = 0.5;
uniform float paper_amount : hint_range(0,1) = 1.0;
void vertex(){paper_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 relief=paper_relief(paper_world);
 vec3 colour=tint.rgb;
 if(has_albedo){colour*=texture(source_albedo,UV).rgb;}
 ALBEDO=colour*(1.0+relief.x*0.65*paper_amount);
 NORMAL=paper_normal(VERTEX,NORMAL,relief.y*0.6*paper_amount);
 float rough=source_roughness;
 float metal=source_metallic;
 if(has_roughness){rough*=dot(texture(roughness_map,UV),roughness_channel);}
 if(has_metallic){metal*=dot(texture(metallic_map,UV),metallic_channel);}
 // Existing R8 paper finish is an explicit artistic override, not parity.
 ROUGHNESS=mix(rough,0.96,paper_amount);
 METALLIC=mix(metal,0.0,paper_amount);
 SPECULAR=mix(source_specular,0.10,paper_amount);
}

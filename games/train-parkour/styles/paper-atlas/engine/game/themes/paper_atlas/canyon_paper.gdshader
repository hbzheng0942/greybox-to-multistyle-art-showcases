shader_type spatial;
render_mode diffuse_burley;
#include "res://themes/paper_atlas/paper_surface.gdshaderinc"
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 emission_tint : source_color = vec4(1.0, 0.55, 0.18, 1.0);
uniform float emission_energy = 0.0;
void vertex(){paper_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 relief=paper_relief(paper_world);
 ALBEDO=tint.rgb*(1.0+relief.x);
 NORMAL=paper_normal(VERTEX,NORMAL,relief.y);
 ROUGHNESS=0.96;SPECULAR=0.10;
 EMISSION=emission_tint.rgb*emission_energy;
}

shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx;
uniform vec4 water_color : source_color = vec4(.08,.50,.58,1.0);
uniform bool falling = false;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float a=sin(world_pos.x*.032+TIME*.6)*sin(world_pos.z*.027-TIME*.4);
 float b=sin(world_pos.x*.09+world_pos.z*.05-TIME*.7);
 float wave=pow(max(0.0,a*.65+b*.35),8.0);
 if(falling){wave=pow(max(0.0,sin(UV.x*97.0+sin(UV.y*11.0-TIME*3.0)*.7)),9.0);}
 ALBEDO=mix(water_color.rgb,vec3(.80,.92,.87),wave*.12);ROUGHNESS=.80;SPECULAR=.20;METALLIC=0.0;
 NORMAL=normalize(NORMAL+vec3(cos(world_pos.x*.032+TIME*.6)*.07,sin(world_pos.z*.027-TIME*.4)*.06,0));
}

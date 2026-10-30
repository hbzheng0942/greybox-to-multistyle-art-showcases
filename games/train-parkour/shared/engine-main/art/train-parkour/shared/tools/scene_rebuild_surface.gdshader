shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(0.28,0.29,0.23,1.0);
uniform float metalness = 0.1;
uniform bool floor_surface = false;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=floor_surface?world_pos.xz:UV*vec2(14.0,9.0);
 vec2 cells=floor(p*1.4);
 float tone=fract(sin(dot(cells,vec2(13.71,47.17)))*43758.5453);
 float coarse=step(0.78,tone)*0.055-step(tone,0.13)*0.04;
 vec2 panel=abs(fract(p/5.0)-0.5);
 float seam=step(0.492,max(panel.x,panel.y));
 ALBEDO=base_color.rgb*(0.92+coarse)-vec3(seam*0.045);
 ROUGHNESS=0.86; METALLIC=metalness;
}

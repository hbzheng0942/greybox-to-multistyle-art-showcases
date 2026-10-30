shader_type spatial;
uniform float review_time = -1.0;
render_mode unshaded,cull_disabled;
uniform vec2 water_corner=vec2(-9.0,8.0);
uniform vec2 land_half_size=vec2(22.0,18.0);
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 vec2 p=world_position.xz;
 // No hidden water plane inside the hole cavity under dry land.
 bool in_rectangle=abs(p.x)<=land_half_size.x && abs(p.y)<=land_half_size.y;
 bool in_inlet=p.x<water_corner.x && p.y>water_corner.y;
 if(in_rectangle && !in_inlet){discard;}
 float wave=sin(p.x*1.8+p.y*.52+(review_time >= 0.0 ? review_time : TIME)*.9)*sin(p.y*2.1-(review_time >= 0.0 ? review_time : TIME)*.65);
 float line=smoothstep(.75,.95,wave);
 ALBEDO=mix(vec3(.07,.29,.39),vec3(.23,.56,.63),.35+wave*.14+line*.15);
}

shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 clay_color : source_color = vec4(0.8,0.6,0.45,1.0);
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
uniform sampler2D source_albedo : source_color, filter_linear_mipmap;
uniform bool textured = false;
uniform bool remap_texture = false;
uniform float roughness_value = 0.84;
uniform float relief = 0.08;
uniform float emission_value = 0.0;
uniform float tiled = 0.0;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
float handmade(vec3 p,vec3 weights){
 return texture(grain,p.yz*.045).r*weights.x+texture(grain,p.xz*.045).r*weights.y+texture(grain,p.xy*.045).r*weights.z;
}
void fragment(){
 vec3 wn=normalize(world_normal);vec3 weights=pow(abs(wn),vec3(5.0));weights/=max(dot(weights,vec3(1.0)),.0001);
 float h=handmade(world_pos,weights);float fine=handmade(world_pos*3.2,weights);
 float seams=0.0;
 if(tiled>0.5){vec2 q=UV/vec2(2.2,3.2);q.x+=mod(floor(q.y),2.0)*.5;vec2 edge=min(fract(q),1.0-fract(q));seams=1.0-smoothstep(.007,.021,min(edge.x,edge.y));}
 float height=(h*.8+fine*.2)*relief-seams*.016;
 vec3 dx=dFdx(world_pos);vec3 dy=dFdy(world_pos);vec3 r1=cross(dy,wn);vec3 r2=cross(wn,dx);float det=dot(dx,r1);
 vec3 gradient=sign(det)*(dFdx(height)*r1+dFdy(height)*r2);
 vec3 perturbed=normalize(max(abs(det),.00001)*wn-gradient);
 NORMAL=normalize(mat3(VIEW_MATRIX)*perturbed);
 vec3 base=clay_color.rgb;if(textured){vec3 sample_color=texture(source_albedo,UV).rgb;
 if(remap_texture){base*=mix(.85,1.08,dot(sample_color,vec3(.33)));}else{base*=pow(sample_color,vec3(.8));}}
 ALBEDO=base*mix(.97,1.015,h)*mix(.995,1.005,fine)*(1.0-seams*.16);
 ROUGHNESS=clamp(roughness_value+(h-.5)*.14,.2,.98);SPECULAR=.28;METALLIC=0.0;
 AO=1.0-seams*.15;AO_LIGHT_AFFECT=.35;EMISSION=clay_color.rgb*emission_value;
}

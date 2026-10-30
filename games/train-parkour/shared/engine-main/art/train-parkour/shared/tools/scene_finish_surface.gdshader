shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.5,0.5,0.4,1.0);
uniform bool floor_surface = false;
uniform bool safety_stripes = false;
uniform sampler2D cardboard_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured_cardboard=false;
uniform float metalness = 0.1;
varying vec3 wp;
varying vec3 wn;
float cell(vec3 p) { return fract(sin(dot(floor(p),vec3(17.17,71.31,43.57)))*43758.5453); }
void vertex() { wp = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
 float broad=cell(wp*0.22), paint=cell(wp*0.52), fleck=cell(wp*1.7);
 vec3 c=base_color.rgb*(0.84+0.22*broad+0.1*paint);
 if(safety_stripes) {
  float stripe=step(0.5,fract((wp.y+wp.x+wp.z)*0.28));
  c=mix(vec3(0.047,0.054,0.044),base_color.rgb,stripe);
 }
 float worn=step(0.87,paint)*step(0.45,fleck);
 c=mix(c,vec3(0.29,0.30,0.25),worn*(floor_surface ? 0.25 : (length(base_color.rgb)<0.45 ? 0.06 : 0.22)));
 if(floor_surface) {
  vec2 seams=abs(fract(wp.xz/6.0)-0.5);
  float seam=max(step(0.493,seams.x),step(0.493,seams.y));
  c*=1.0-seam*0.32;
  float stain=step(0.82,cell(vec3(wp.x*0.1,0.0,wp.z*0.1)));
  c*=1.0-stain*0.16;
 }
 if(textured_cardboard) {
  vec3 n=pow(abs(wn),vec3(6.0));n/=max(dot(n,vec3(1.0)),0.0001);
  vec3 paper=texture(cardboard_tex,wp.yz/7.0).rgb*n.x+texture(cardboard_tex,wp.xz/7.0).rgb*n.y+texture(cardboard_tex,wp.xy/7.0).rgb*n.z;
  float luma=dot(paper,vec3(0.2126,0.7152,0.0722));
  c=mix(vec3(luma),paper,0.55)*1.45*(0.8+base_color.g*0.5);
 }
 ALBEDO=c; ROUGHNESS=0.85; METALLIC=metalness;
}

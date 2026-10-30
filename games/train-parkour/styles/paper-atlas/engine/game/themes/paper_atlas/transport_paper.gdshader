shader_type spatial;
render_mode diffuse_burley;
varying vec3 paper_position;
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }
float pulp(vec3 p) {
 vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { paper_position=VERTEX; }
void fragment() {
 float pixel=length(fwidth(paper_position));
 // Suppress fine paper grain before it becomes a high-speed crawling pattern.
 float fiber=(pulp(paper_position*24.0)-0.5)*0.045/(1.0+pixel*80.0);
 float broad=(pulp(paper_position*1.8)-0.5)*0.038/(1.0+pixel*6.0);
 ALBEDO=COLOR.rgb*(1.0+fiber+broad);
 ROUGHNESS=COLOR.a;
 SPECULAR=0.10;
}

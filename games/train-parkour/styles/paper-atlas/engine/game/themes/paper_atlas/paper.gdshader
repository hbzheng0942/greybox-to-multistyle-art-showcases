shader_type spatial;
render_mode diffuse_burley;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 paper_position;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float grain(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
 mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { paper_position=VERTEX; }
void fragment() {
 float fade=1.0/(1.0+length(fwidth(paper_position*5.0))*2.0);
 float fiber=(grain(paper_position*5.0)-0.5)*0.055*fade;
 ALBEDO=tint.rgb*(1.0+fiber); ROUGHNESS=0.97; SPECULAR=0.12;
}

shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
// Geological masses use a small cool palette instead of fine normal noise.
uniform vec3 rock_shadow : source_color = vec3(0.21,0.24,0.38);
uniform vec3 rock_body : source_color = vec3(0.27,0.30,0.46);
uniform vec3 rock_facet : source_color = vec3(0.32,0.34,0.50);
uniform vec3 rock_edge : source_color = vec3(0.38,0.37,0.50);
uniform float value = 0.26;
uniform bool broad_strata = false;
varying vec3 world_position;
varying vec3 world_normal;
float hash3(vec3 p) { p=fract(p*.1031);p+=dot(p,p.yzx+33.33);return fract((p.x+p.y)*p.z); }
void vertex() {
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 vec3 q=floor(world_position/.65)*.65;
 float stratum=floor((q.y+q.x*.095+q.z*.075)/4.8);
 vec3 block=floor(vec3(q.x/7.5+stratum*.37,stratum,q.z/8.0));
 float grain=hash3(block);
 vec3 color=mix(rock_shadow,rock_body,step(.22,grain));
 color=mix(color,rock_facet,step(.70,grain));
 float ledge=step(.80,fract((q.y+q.x*.095+q.z*.075)/4.8));
 color=mix(color,rock_edge,ledge*.33*step(.46,grain));
 float face=dot(world_normal,normalize(vec3(-.5,.6,.35)));
 color*=mix(.75,1.12,step(.15,face));
 if(broad_strata){
  // Geological layers stay large; no micro checkerwork on the distant slopes.
  float layer=floor((world_position.y+world_position.x*.06+world_position.z*.025)/15.0);
  float mass=hash3(vec3(floor(world_position.x/36.),layer,floor(world_position.z/42.)));
  color=mix(rock_shadow,rock_body,step(.28,mass));
  color=mix(color,rock_facet,step(.82,mass));
  color*=vec3(.70,.86,1.0)*mix(.96,1.02,smoothstep(-.15,.45,face));
 }
 ALBEDO=color*clamp(value/.26,.65,1.3);
 ROUGHNESS=1.0;SPECULAR=0.0;
 EMISSION=ALBEDO*vec3(.30,.31,.46);
}
void light() {
 float ndl=max(dot(NORMAL,LIGHT),0.0);
 float bands=floor(ndl*3.0+.35)/3.0;
 if(broad_strata){bands=.35+.16*smoothstep(.15,.65,ndl);}
 DIFFUSE_LIGHT+=LIGHT_COLOR*ATTENUATION*(.10+.70*bands);
}

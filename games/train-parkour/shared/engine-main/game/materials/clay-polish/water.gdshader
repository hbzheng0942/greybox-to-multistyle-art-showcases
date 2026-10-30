shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform bool falling = false;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 vec2 p=falling?vec2(UV.x*13.,UV.y*24.+TIME*.75):wp.xz*.12+vec2(TIME*.035,TIME*.020);
 float a=noise(p),b=noise(p*2.7-vec2(TIME*.05,0));
 float foam=smoothstep(.81,.98,a*.6+b*.47)*.22;
 vec3 teal=mix(vec3(.013,.115,.165),vec3(.032,.235,.27),a*.7+b*.3);
 if(falling){
  teal=mix(teal,vec3(.10,.42,.45),.45);
  foam=max(smoothstep(.65,.94,a+b*.22),pow(UV.y,10.)*.85);
 }
 ALBEDO=mix(teal,vec3(.69,.84,.78),foam);
 float h=(a*.6+b*.2)*.055;
 vec3 n=normalize(wn),dx=dFdx(wp),dy=dFdy(wp);
 vec3 r1=cross(dy,n),r2=cross(n,dx);float det=dot(dx,r1);
 vec3 bump=normalize(max(abs(det),.000001)*n-sign(det)*(dFdx(h)*r1+dFdy(h)*r2));
 NORMAL=normalize(mat3(VIEW_MATRIX)*bump);
 ROUGHNESS=.46;SPECULAR=.32;METALLIC=0.;
}
